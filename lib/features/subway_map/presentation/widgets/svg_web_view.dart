import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/connection.dart';
import '../../../../domain/entities/station.dart';
import '../../../settings/presentation/providers/home_station_provider.dart';
import '../providers/live_train_provider.dart';
import '../providers/subway_map_providers.dart';

/// WebView 기반 지하철 노선도 뷰어.
///
/// 원본 SVG를 HTML로 렌더링하고, JavaScriptChannel을 통해
/// Flutter와 양방향 통신한다.
class SvgWebView extends ConsumerStatefulWidget {
  final List<Station> stations;
  final List<Connection> connections;
  final Set<String> routeStationIds;
  final Set<String> highlightedLineIds;

  /// 역 이름 라벨을 밝게 유지할 역 이름 집합(경로 역 ∪ 출발역 상류 역).
  /// 강조 노선에 속한 역이라도 이 집합에 없으면 흐리게 처리한다.
  final Set<String> highlightLabelNames;
  final ({double x, double y})? panTarget;
  final ({double x, double y})? routeToolbarTarget;
  final bool hasTwoRoutes;
  final void Function(String mode)? onRouteToolbarSelect;
  final List<LiveTrain> liveTrains;

  const SvgWebView({
    super.key,
    required this.stations,
    required this.connections,
    this.routeStationIds = const {},
    this.highlightedLineIds = const {},
    this.highlightLabelNames = const {},
    this.panTarget,
    this.routeToolbarTarget,
    this.hasTwoRoutes = false,
    this.onRouteToolbarSelect,
    this.liveTrains = const [],
  });

  @override
  ConsumerState<SvgWebView> createState() => _SvgWebViewState();

  /// 선택 상태가 [prev]→[next] 로 바뀔 때 지도를 출발역으로 포커싱해야
  /// 하는지 판정한다.
  ///
  /// - `next.departure != null`: 포커싱 대상(출발역)이 있어야 한다.
  /// - `next.arrival == null`: 도착역까지 선택돼 경로가 완성되면 SubwayMapViewer
  ///   의 panTarget 파이프라인이 출발역으로 팬하므로, 도착역이 아직 없을
  ///   때만 팬해 중복 발동을 피한다.
  /// - `prev?.arrival == null`: 도착역을 해제하는 (출발,도착)→(출발,null)
  ///   전이에서 출발역이 그대로여도 원치 않는 재팬이 일어나지 않게 막는다.
  ///   반대로 같은 출발역을 다시 선택하는 경우엔 선택 행위마다 포커싱된다.
  @visibleForTesting
  static bool shouldPanToDeparture(
    SelectedStations? prev,
    SelectedStations next,
  ) {
    return next.departure != null &&
        next.arrival == null &&
        prev?.arrival == null;
  }
}

class _SvgWebViewState extends ConsumerState<SvgWebView> {
  late final WebViewController _controller;
  late final Map<String, Station> _stationMap;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _stationMap = {for (final s in widget.stations) s.id: s};
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF5F5F5))
      ..addJavaScriptChannel(
        'StationChannel',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onPageLoaded(),
        ),
      )
      ..loadFlutterAsset('assets/html/map.html');
  }

  void _onPageLoaded() {
    _isReady = true;
    _injectStationData();

    if (widget.routeStationIds.isNotEmpty) {
      _highlightRoute(widget.routeStationIds);
    }

    if (widget.highlightedLineIds.isNotEmpty) {
      _highlightLines(widget.highlightedLineIds);
    }

    if (widget.routeToolbarTarget != null) {
      _showRouteToolbar(
        widget.routeToolbarTarget!.x,
        widget.routeToolbarTarget!.y,
        widget.hasTwoRoutes,
      );
    }

    // 기존 선택된 역 마커 복원
    final selected = ref.read(selectedStationsProvider);
    if (selected.departure != null) {
      _setMarker('departure', selected.departure!.svgX, selected.departure!.svgY);
    }
    if (selected.arrival != null) {
      _setMarker('arrival', selected.arrival!.svgX, selected.arrival!.svgY);
    }

    // 초기 열차 데이터 표시
    if (widget.liveTrains.isNotEmpty) {
      _showTrains(widget.liveTrains);
    }

    // 홈 역 초기 팬. 사용자가 설정한 역이 있다면 서울역 대신 그 역이
    // 화면 중앙에 오도록 즉시 이동한다(애니메이션 없음). 설정 없으면
    // map.html 의 INITIAL_CENTER_X/Y (서울역) 기본값을 그대로 유지.
    // 활성 경로가 있으면 그쪽 팬을 우선한다 (경로 진입 UX 우선).
    //
    // 앱 콜드 스타트 시 map.html 은 static asset 이라 수십 ms 만에 로드되지만
    // `homeStationProvider` 는 SharedPreferences 초기화(첫 접근 100~300ms)를
    // 기다려야 값이 나온다. 그래서 `valueOrNull` 로 동기 스냅샷을 찍으면 첫
    // 실행에서 항상 null → 서울역이 뜨는 회귀가 있었다. `.future` 로 로드
    // 완료를 기다린 뒤 pan.
    if (widget.panTarget == null) {
      _panToHomeStationAsync();
    }
  }

  /// 홈 역 로드 후 지도 중앙 이동. 실패/설정 없음은 조용히 넘긴다.
  Future<void> _panToHomeStationAsync() async {
    try {
      final home = await ref.read(homeStationProvider.future);
      if (!mounted || home == null) return;
      _panTo(home.svgX, home.svgY, durationMs: 0);
    } catch (_) {
      // provider 실패 시 서울역 기본값 유지.
    }
  }

  void _injectStationData() {
    final stationsJson = jsonEncode(
      widget.stations
          .map((s) => {
                'id': s.id,
                'name': s.name,
                'lineId': s.lineId,
                'svgX': s.svgX,
                'svgY': s.svgY,
                'isTransfer': s.isTransfer,
                'transferLines': s.transferLines,
              })
          .toList(),
    );

    final connectionsJson = jsonEncode(
      widget.connections
          .map((c) => {
                'fromStationId': c.fromStationId,
                'toStationId': c.toStationId,
                'lineId': c.lineId,
                'isTransfer': c.isTransfer,
              })
          .toList(),
    );

    final colorsJson = jsonEncode(
      lineColors.map(
        (key, color) =>
            MapEntry(key, '#${color.toARGB32().toRadixString(16).substring(2)}'),
      ),
    );

    final namesJson = jsonEncode(lineNames);

    _runJs(
      "window.initStations("
      "${_jsString(stationsJson)}, "
      "${_jsString(connectionsJson)}, "
      "${_jsString(colorsJson)}, "
      "${_jsString(namesJson)}"
      ")",
    );
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message);
      if (data is! Map<String, dynamic>) return;

      final action = data['action'];
      if (action is! String) return;

      switch (action) {
        case 'stationTapped':
          final stationId = data['stationId'];
          if (stationId is! String) return;
          _handleStationTapped(stationId);
        case 'setDeparture':
          final stationId = data['stationId'];
          if (stationId is! String) return;
          _handleSetDeparture(stationId);
        case 'setArrival':
          final stationId = data['stationId'];
          if (stationId is! String) return;
          _handleSetArrival(stationId);
        case 'viewArrivalInfo':
          final stationName = data['stationName'];
          if (stationName is! String) return;
          _handleViewArrivalInfo(stationName);
        case 'routeToolbarSelect':
          final mode = data['mode'];
          if (mode is! String) return;
          widget.onRouteToolbarSelect?.call(mode);
        case 'trainArrived':
          final destination = data['destination'];
          if (destination is String && destination.isNotEmpty && mounted) {
            HapticFeedback.mediumImpact();
            final messenger = ScaffoldMessenger.of(context);
            messenger.clearSnackBars();
            messenger.showSnackBar(
              SnackBar(
                content: Text('$destination행 열차가 도착했습니다'),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        case 'dismiss':
          ref.read(tappedStationProvider.notifier).state = null;
      }
    } on FormatException {
      // 잘못된 JSON 무시
    }
  }

  Station? _findStation(String stationId) {
    return _stationMap[stationId];
  }

  void _handleStationTapped(String stationId) {
    final station = _findStation(stationId);
    if (station == null) return;

    ref.read(tappedStationProvider.notifier).state = station;
    _showTooltip(station);
  }

  void _handleSetDeparture(String stationId) {
    final station = _findStation(stationId);
    if (station == null) return;

    ref.read(selectedStationsProvider.notifier).setDeparture(station);
    ref.read(tappedStationProvider.notifier).state = null;
    _setMarker('departure', station.svgX, station.svgY);
  }

  void _handleSetArrival(String stationId) {
    final station = _findStation(stationId);
    if (station == null) return;

    ref.read(selectedStationsProvider.notifier).setArrival(station);
    ref.read(tappedStationProvider.notifier).state = null;
    _setMarker('arrival', station.svgX, station.svgY);
  }

  void _handleViewArrivalInfo(String stationName) {
    // 로컬 데이터에 존재하는 역명인지 검증
    final exists = widget.stations.any((s) => s.name == stationName);
    if (!exists) return;

    ref.read(tappedStationProvider.notifier).state = null;
    if (mounted) {
      context.go('/arrivals/$stationName');
    }
  }

  // ============================================================
  // Flutter → JS 호출
  // ============================================================

  void _highlightRoute(Set<String> routeStationIds) {
    if (!_isReady) return;
    final json = jsonEncode(routeStationIds.toList());
    _runJs("window.highlightRoute(${_jsString(json)})");
  }

  void _clearRoute() {
    if (!_isReady) return;
    _runJs("window.clearRoute()");
  }

  void _setMarker(String type, double svgX, double svgY) {
    if (!_isReady) return;
    if (type != 'departure' && type != 'arrival') return;
    _runJs("window.setMarker('$type', $svgX, $svgY)");
  }

  void _clearMarkers() {
    if (!_isReady) return;
    _runJs("window.clearMarkers()");
  }

  void _showTooltip(Station station) {
    if (!_isReady) return;
    final json = jsonEncode({
      'id': station.id,
      'name': station.name,
      'lineId': station.lineId,
      'svgX': station.svgX,
      'svgY': station.svgY,
      'isTransfer': station.isTransfer,
      'transferLines': station.transferLines,
    });
    _runJs("window.showTooltip(${_jsString(json)})");
  }

  void _highlightLines(Set<String> lineIds) {
    if (!_isReady) return;
    final json = jsonEncode(lineIds.toList());
    final keepNamesJson = jsonEncode(widget.highlightLabelNames.toList());
    _runJs(
      "window.highlightLines(${_jsString(json)}, ${_jsString(keepNamesJson)})",
    );
  }

  void _clearLineHighlight() {
    if (!_isReady) return;
    _runJs("window.clearLineHighlight()");
  }

  /// 지도를 [svgX], [svgY] 가 화면 중앙에 오도록 이동한다(줌 레벨 유지).
  ///
  /// [durationMs] 가 0 이하이면 애니메이션 없이 즉시 스냅한다(홈역 초기 팬).
  /// 그 외엔 easeInOut 애니메이션. (window.panTo 계약 — build_map_html.dart)
  void _panTo(double svgX, double svgY, {int durationMs = 400}) {
    if (!_isReady) return;
    _runJs("window.panTo($svgX, $svgY, $durationMs)");
  }

  void _showRouteToolbar(double svgX, double svgY, bool hasTwoRoutes) {
    if (!_isReady) return;
    _runJs(
      "window.showRouteToolbar($svgX, $svgY, ${hasTwoRoutes ? 'true' : 'false'})",
    );
  }

  void _hideRouteToolbar() {
    if (!_isReady) return;
    _runJs("window.hideRouteToolbar()");
  }

  void _showTrains(List<LiveTrain> trains) {
    if (!_isReady) return;
    final json = jsonEncode([for (final t in trains) t.toJson()]);
    _runJs("window.showTrains(${_jsString(json)})");
  }

  void _clearTrains() {
    if (!_isReady) return;
    _runJs("window.clearTrains()");
  }

  void _hideTooltip() {
    if (!_isReady) return;
    _runJs("window.hideTooltip()");
  }

  void _runJs(String script) {
    _controller.runJavaScript(script).catchError((Object e) {
      if (kDebugMode) {
        debugPrint('JS 실행 오류: $e');
      }
    });
  }

  /// JSON 문자열을 JS 문자열 리터럴로 감싸는 헬퍼.
  static String _jsString(String value) {
    final escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\u2028', '\\u2028')
        .replaceAll('\u2029', '\\u2029');
    return "'$escaped'";
  }

  // ============================================================
  // 위젯 업데이트 감지
  // ============================================================

  @override
  void didUpdateWidget(covariant SvgWebView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_isReady) return;

    // 경로 하이라이트 변경 감지
    if (widget.routeStationIds != oldWidget.routeStationIds) {
      if (widget.routeStationIds.isEmpty) {
        _clearRoute();
      } else {
        _highlightRoute(widget.routeStationIds);
      }
    }

    // 노선 강조 변경 감지. 노선 집합이 같아도 유지할 역 이름 집합
    // (highlightLabelNames)이 달라지는 모드 전환에서도 라벨 하이라이트를 다시
    // 계산해야 하므로 함께 비교한다.
    if (widget.highlightedLineIds != oldWidget.highlightedLineIds ||
        widget.highlightLabelNames != oldWidget.highlightLabelNames) {
      if (widget.highlightedLineIds.isEmpty) {
        _clearLineHighlight();
      } else {
        _highlightLines(widget.highlightedLineIds);
      }
    }

    // 카메라 이동 감지
    if (widget.panTarget != oldWidget.panTarget && widget.panTarget != null) {
      _panTo(widget.panTarget!.x, widget.panTarget!.y);
    }

    // 툴바 표시/숨김
    if (widget.routeToolbarTarget != oldWidget.routeToolbarTarget ||
        widget.hasTwoRoutes != oldWidget.hasTwoRoutes) {
      if (widget.routeToolbarTarget == null) {
        _hideRouteToolbar();
      } else {
        _showRouteToolbar(
          widget.routeToolbarTarget!.x,
          widget.routeToolbarTarget!.y,
          widget.hasTwoRoutes,
        );
      }
    }

    // 실시간 열차 데이터 변경 감지
    if (!identical(widget.liveTrains, oldWidget.liveTrains)) {
      if (widget.liveTrains.isEmpty) {
        _clearTrains();
      } else {
        _showTrains(widget.liveTrains);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // selectedStationsProvider 변경 시 마커 업데이트
    // (Riverpod 공식 패턴: build 내 ref.listen은 부작용 실행용으로 허용)
    ref.listen(selectedStationsProvider, (prev, next) {
      if (!_isReady) return;
      _clearMarkers();
      if (next.departure != null) {
        _setMarker('departure', next.departure!.svgX, next.departure!.svgY);
      }
      if (next.arrival != null) {
        _setMarker('arrival', next.arrival!.svgX, next.arrival!.svgY);
      }

      // 출발역을 선택하면 지도를 그 역으로 부드럽게 포커싱한다.
      // 판정 규칙은 SvgWebView.shouldPanToDeparture 참고.
      if (SvgWebView.shouldPanToDeparture(prev, next)) {
        _panTo(next.departure!.svgX, next.departure!.svgY);
      }
    });

    // tappedStation 변경 시 툴팁 제어
    ref.listen(tappedStationProvider, (prev, next) {
      if (!_isReady) return;
      if (next == null) {
        _hideTooltip();
      }
    });

    return WebViewWidget(controller: _controller);
  }
}
