import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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

class _SvgWebViewState extends ConsumerState<SvgWebView>
    with WidgetsBindingObserver {
  static const _mapAsset = 'assets/html/map.html';

  /// 복구 재로드 사이 최소 간격. 로드 직후 프로세스가 다시 죽는 상황(메모리
  /// 부족 지속)에서 종료 → 재로드 → 종료가 쉼 없이 반복되는 것을 막는다. 이
  /// 간격 안의 요청은 버리지 않고 남은 시간만큼 미뤘다가 다시 시도한다.
  static const _minReloadInterval = Duration(seconds: 3);

  /// 연속 재로드 상한. 넘으면 멈추고 다음 포그라운드 복귀 때 다시 시도한다.
  static const _maxReloadAttempts = 3;

  /// 마지막 재로드 뒤 이만큼 무사했으면 연속 횟수를 새로 센다.
  static const _reloadAttemptsResetAfter = Duration(minutes: 1);

  /// 포그라운드 복귀 시점에 로드가 이만큼 넘게 끝나지 않고 있으면 실패로 보고
  /// 다시 로드한다(타이머가 아니라 복귀 때만 검사한다).
  static const _loadWatchdog = Duration(seconds: 10);

  /// 포그라운드 복귀 시 페이지 생존 점검의 1회 응답 대기 상한.
  static const _aliveCheckTimeout = Duration(seconds: 3);

  late final WebViewController _controller;
  late final Map<String, Station> _stationMap;
  bool _isReady = false;

  // 복구 재로드 상태.
  DateTime _lastLoadAt = DateTime.now();
  int _reloadAttempts = 0;
  Timer? _reloadTimer;
  bool _aliveCheckRunning = false;

  /// 백그라운드에서 종료 알림을 받아 포그라운드 복귀까지 재로드를 미룬 상태.
  bool _reloadPending = false;

  /// 지금 진행 중인 로드가 복구 재로드인지. `_onPageLoaded` 가 소비한다.
  bool _recovering = false;

  /// 복구 재로드를 시작할 때 화면에 있던(= 죽은 페이지에 이미 그렸던) 열차 목록.
  List<LiveTrain>? _trainsAtReload;

  // JS 에 마지막으로 넘긴 오른쪽 safe area 폭. 펼친 iPhone Duo 에서만 0 이
  // 아니다(지도가 세로 상태바 띠까지 깔림 — home_screen.dart).
  double _safeRight = 0;

  // JS 에 마지막으로 넘긴 위쪽 safe 경계(홈 검색 카드 아래쪽 y). 값의 출처는
  // [mapSafeTopProvider] 이고 `ref.listen` 으로만 읽어 위젯을 리빌드하지 않는다.
  double _safeTop = 0;

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
          onWebResourceError: _onWebResourceError,
        ),
      )
      ..loadFlutterAsset(_mapAsset);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloadTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // 웹 콘텐츠 프로세스 종료 복구
  // ============================================================
  //
  // 앱이 백그라운드에 있는 동안 OS 가 메모리 회수를 위해 WebView 의 웹 콘텐츠
  // 프로세스만 따로 죽일 수 있다(iOS WKWebView 에서 흔하다). Flutter 쪽은
  // 살아 있으므로 앱은 그대로 복귀하지만 WebView 는 배경색만 남은 빈 화면이
  // 되고, 스스로 복구되지 않는다. 지도를 다시 로드하면 `_onPageLoaded` 가
  // 경로·마커·열차를 현재 위젯 상태로 복원한다(줌/팬 위치는 잃는다).

  /// iOS 는 프로세스 종료를 이 콜백으로 알린다.
  void _onWebResourceError(WebResourceError error) {
    if (error.errorType != WebResourceErrorType.webContentProcessTerminated) {
      return;
    }
    _reloadMapWhenForeground();
  }

  /// 포그라운드면 바로 재로드하고, 아니면 사용자가 돌아올 때까지 미룬다.
  /// 백그라운드에서는 다시 띄워도 메모리 압박으로 곧 또 죽기 쉽다.
  void _reloadMapWhenForeground() {
    // 죽은 페이지로 JS 를 보내지 않는다.
    _isReady = false;
    // lifecycleState 가 null 이면 아직 통지 전 — 전면으로 본다.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _reloadPending = true;
      return;
    }
    _reloadMap();
  }

  /// 포그라운드로 돌아올 때마다 지도를 점검한다 — 미뤄 둔 재로드를 실행하고,
  /// 종료 콜백이 오지 않은 경우에 대비해 페이지가 살아 있는지 직접 물어본다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _reloadAttempts = 0;
    if (_reloadPending) {
      _reloadMap();
    } else {
      _reloadMapIfDead();
    }
  }

  Future<void> _reloadMapIfDead() async {
    if (!_isReady) {
      // 로드 중. 정상이면 onPageFinished 가 마무리하지만, 로드가 실패했거나
      // 재시도 상한에 걸려 멈춘 상태면 여기서 다시 시작한다.
      final stalled = _reloadTimer == null &&
          DateTime.now().difference(_lastLoadAt) > _loadWatchdog;
      if (stalled) _reloadMap();
      return;
    }
    if (_aliveCheckRunning) return;
    _aliveCheckRunning = true;
    final loadAtStart = _lastLoadAt;
    var alive = false;
    try {
      // 복귀 직후 응답이 한 번 늦었다고 멀쩡한 페이지를 재로드하면 줌·위치를
      // 잃는다. 두 번 연속 실패해야 죽은 것으로 본다.
      for (var attempt = 0; attempt < 2 && !alive; attempt++) {
        try {
          final result = await _controller
              .runJavaScriptReturningResult('window.showTrains ? 1 : 0')
              .timeout(_aliveCheckTimeout);
          alive = result is num ? result == 1 : '$result' == '1';
          // 응답은 왔는데 지도가 없다 = 빈 페이지. 다시 물어볼 필요가 없다.
          if (!alive) break;
        } catch (_) {
          // 타임아웃·실행 오류 — 한 번 더 물어본다.
        }
      }
    } finally {
      _aliveCheckRunning = false;
    }
    // 대기 중에 종료 콜백이 먼저 처리했으면(재로드 중이거나 이미 끝났으면)
    // 겹치지 않는다.
    if (!mounted || alive || !_isReady || _lastLoadAt != loadAtStart) return;
    _reloadMap();
  }

  void _reloadMap() {
    if (!mounted) return;
    _reloadTimer?.cancel();
    _reloadTimer = null;

    final now = DateTime.now();
    final sinceLast = now.difference(_lastLoadAt);
    if (sinceLast > _reloadAttemptsResetAfter) _reloadAttempts = 0;
    // 상한에 걸리면 멈춘다. _isReady=false 로 남으므로 다음 포그라운드 복귀의
    // 워치독 분기가 다시 시작한다.
    if (_reloadAttempts >= _maxReloadAttempts) {
      _isReady = false;
      return;
    }
    if (sinceLast < _minReloadInterval) {
      _isReady = false;
      _reloadTimer = Timer(_minReloadInterval - sinceLast, () {
        _reloadTimer = null;
        if (mounted) _reloadMapWhenForeground();
      });
      return;
    }

    _lastLoadAt = now;
    _reloadAttempts++;
    _reloadPending = false;
    _recovering = true;
    // 연속 재로드에서는 처음 죽었을 때의 목록을 유지한다.
    _trainsAtReload ??= widget.liveTrains;
    _isReady = false;
    // 툴팁은 새 페이지에 복원하지 않으므로 탭 상태도 함께 비운다.
    ref.read(tappedStationProvider.notifier).state = null;
    _controller.loadFlutterAsset(_mapAsset).catchError((Object e) {
      if (kDebugMode) {
        debugPrint('지도 재로드 오류: $e');
      }
    });
  }

  void _onPageLoaded() {
    final recovering = _recovering;
    _recovering = false;
    _isReady = true;
    if (_safeRight != 0) _runJs('window.setSafeRight($_safeRight)');
    // 재로드(복구)된 새 페이지는 JS 상태가 초기화돼 있으므로 현재 값을 다시 보낸다.
    _safeTop = ref.read(mapSafeTopProvider);
    if (_safeTop != 0) _runJs('window.setSafeTop($_safeTop)');
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

    // 기존 선택된 역 마커 복원 (출발/경유/도착)
    _setSelectionMarkers(ref.read(selectedStationsProvider));

    // 초기 열차 데이터 표시.
    // 복구 재로드에서는 죽기 전에 이미 그렸던 목록을 다시 넣지 않고 다음
    // refresh(15초 이내)에 맡긴다. 새 페이지는 도착 확정 기억(`arrivedTrains`)이
    // 비어 있어, 백그라운드 이전의 낡은 목록을 넣으면 이미 도착 처리된 열차가
    // 다시 그려져 도착 알림이 중복된다. 로드 중에 새 목록이 왔으면 그건 넣는다.
    final staleTrains = _trainsAtReload;
    _trainsAtReload = null;
    if (widget.liveTrains.isNotEmpty &&
        !identical(widget.liveTrains, staleTrains)) {
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
    //
    // 콜드 스타트에는 panTarget 이 항상 null 이다. null 이 아닌 채 여기 오는
    // 것은 복구 재로드(또는 경로 계산이 페이지 로드보다 먼저 끝난 경우)이며,
    // 그때는 didUpdateWidget 이 팬할 기회가 없었으므로 경로로 즉시 맞춘다.
    // 경로가 없어도 복구 중이고 출발역이 골라져 있으면 그 역으로 되돌린다
    // (출발역 선택 때 포커싱했던 자리).
    final panTarget = widget.panTarget;
    final departure =
        recovering ? ref.read(selectedStationsProvider).departure : null;
    if (panTarget != null) {
      _panTo(panTarget.x, panTarget.y, durationMs: 0);
    } else if (departure != null) {
      _panTo(departure.svgX, departure.svgY, durationMs: 0);
    } else {
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
        case 'addWaypoint':
          final stationId = data['stationId'];
          if (stationId is! String) return;
          _handleAddWaypoint(stationId);
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

  /// 지도 툴팁의 "경유" 액션. 상한을 넘으면 상태를 바꾸지 않고 스낵바로 알린다.
  ///
  /// 마커는 `selectedStationsProvider` 리스너가 전체를 다시 그리므로 여기서
  /// 개별 `_setMarker` 를 호출하지 않는다.
  void _handleAddWaypoint(String stationId) {
    final station = _findStation(stationId);
    if (station == null) return;

    final added =
        ref.read(selectedStationsProvider.notifier).addWaypoint(station);
    ref.read(tappedStationProvider.notifier).state = null;
    if (added || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('경유역은 최대 $maxWaypoints개까지 추가할 수 있습니다'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleViewArrivalInfo(String stationName) {
    // 툴팁은 직전에 탭한 역에 붙어 있으므로 tappedStation 이 곧 조회 대상이다.
    // 동명이역(양평 등) 구분을 위해 그 Station ID 를 함께 넘긴다. 역명이
    // 어긋나거나 비어 있으면 ID 없이 역명만으로 진행한다(기존 동작).
    final tapped = ref.read(tappedStationProvider);
    final station =
        tapped != null && tapped.name == stationName ? tapped : null;

    // 로컬 데이터에 존재하는 역명인지 검증
    if (station == null && !widget.stations.any((s) => s.name == stationName)) {
      return;
    }

    ref.read(tappedStationProvider.notifier).state = null;
    if (!mounted) return;

    final query = station == null ? '' : '?stationId=${station.id}';
    context.go('/arrivals/$stationName$query');
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

  /// 허용된 마커 타입만 JS 로 넘긴다(문자열이 JS 리터럴에 그대로 들어가므로
  /// 화이트리스트로 주입 위험을 차단). `window.setMarker` 계약과 동일한 집합.
  static final RegExp _markerTypePattern =
      RegExp(r'^(departure|arrival|waypoint-\d+)$');

  void _setMarker(String type, double svgX, double svgY) {
    if (!_isReady) return;
    if (!_markerTypePattern.hasMatch(type)) return;
    _runJs("window.setMarker('$type', $svgX, $svgY)");
  }

  /// 현재 선택(출발/경유/도착)의 마커를 모두 다시 그린다.
  void _setSelectionMarkers(SelectedStations selected) {
    if (selected.departure != null) {
      _setMarker(
        'departure',
        selected.departure!.svgX,
        selected.departure!.svgY,
      );
    }
    // 빈 칸(아직 역 미선택)은 찍을 좌표가 없으므로 건너뛴다. 인덱스는 칸 기준을
    // 유지해 같은 칸이 항상 같은 마커 id 를 갖게 한다.
    for (var i = 0; i < selected.waypoints.length; i++) {
      final w = selected.waypoints[i];
      if (w == null) continue;
      _setMarker('waypoint-$i', w.svgX, w.svgY);
    }
    if (selected.arrival != null) {
      _setMarker('arrival', selected.arrival!.svgX, selected.arrival!.svgY);
    }
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

  /// 열차 목록과 함께 이 목록이 속한 **활성 경로 스코프**(노선+방향)를 넘긴다.
  ///
  /// JS 는 스코프가 바뀌면 이전 스코프의 열차를 즉시 제거한다. 이 값이 없으면
  /// JS 가 "경로 변경으로 사라진 열차" 와 "API jitter 로 한 cycle 누락된 열차" 를
  /// 구분할 수 없어, 도착역만 바꿔 경로 노선이 달라진 뒤에도 이전 노선 열차가
  /// 흐려진 지도 위에 수십 초~2분간 남는다. (window.showTrains 계약)
  void _showTrains(List<LiveTrain> trains) {
    if (!_isReady) return;
    final json = jsonEncode([for (final t in trains) t.toJson()]);
    _runJs(
      "window.showTrains(${_jsString(json)}, ${_jsString(_routeScopeKey())})",
    );
  }

  /// 활성 경로 필터를 JS 로 넘길 스코프 키로 직렬화한다.
  /// 필터가 없으면 빈 문자열 — JS 는 빈 스코프에선 스코프 기반 제거를 하지 않는다.
  String _routeScopeKey() {
    final filter = ref.read(activeRouteFilterProvider);
    if (filter == null) return '';
    return '${filter.lineId}|${filter.isDown ? 'down' : 'up'}';
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
    // 오른쪽 safe area 를 JS 툴팁·경로 툴바 배치에 반영한다. 다른 기기에서는
    // 앱 루트가 이미 소비해 0 이라 아무것도 보내지 않는다.
    final safeRight = MediaQuery.paddingOf(context).right;
    if (safeRight != _safeRight) {
      _safeRight = safeRight;
      if (_isReady) _runJs('window.setSafeRight($safeRight)');
    }

    // 홈 검색 카드 높이 변화를 JS 에 전달(툴바가 카드 밑으로 들어가지 않게).
    // 값이 실제로 바뀔 때만 호출하며, 로드 전이면 _onPageLoaded 가 현재 값을 보낸다.
    ref.listen(mapSafeTopProvider, (prev, next) {
      if (next == _safeTop) return;
      _safeTop = next;
      if (_isReady) _runJs('window.setSafeTop($next)');
    });

    // selectedStationsProvider 변경 시 마커 업데이트
    // (Riverpod 공식 패턴: build 내 ref.listen은 부작용 실행용으로 허용)
    ref.listen(selectedStationsProvider, (prev, next) {
      if (!_isReady) return;
      _clearMarkers();
      _setSelectionMarkers(next);

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

    return WebViewWidget.fromPlatformCreationParams(
      params: _webViewWidgetParams(),
    );
  }

  /// 플랫폼별 WebViewWidget 생성 파라미터.
  ///
  /// Android 는 Hybrid Composition 으로 렌더링한다. 기본 모드(TLHC)는
  /// WebView 를 SurfaceTexture 텍스처로 복사해 합성하는데, 지도 팬 중에는
  /// 매 프레임 콘텐츠가 무효화(transform/viewBox 갱신)되어 텍스처 프레임
  /// 전달이 끊기면 화면이 점멸하듯 맵이 지워지는 현상이 발생한다
  /// (SurfaceTexture 렌더링 한계 — flutter/flutter#104889, #116954).
  /// Hybrid Composition 은 실제 Android View 를 직접 합성하므로 텍스처
  /// 복사 단계가 없어 점멸이 없다. iOS(WKWebView)는 기존 기본 동작 유지.
  ///
  /// 트레이드오프: Android 10(API 29) 미만에서는 Hybrid Composition 이
  /// 래스터 스레드를 플랫폼 스레드에 병합해 팬 프레임레이트 비용이 있으나,
  /// 점멸(맵 소실)이 더 심각한 결함이므로 전 버전 무조건 적용한다.
  PlatformWebViewWidgetCreationParams _webViewWidgetParams() {
    PlatformWebViewWidgetCreationParams params =
        PlatformWebViewWidgetCreationParams(controller: _controller.platform);
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewWidgetCreationParams
          .fromPlatformWebViewWidgetCreationParams(
        params,
        displayWithHybridComposition: true,
      );
    }
    return params;
  }
}
