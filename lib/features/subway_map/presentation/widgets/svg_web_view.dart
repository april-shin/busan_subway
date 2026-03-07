import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/connection.dart';
import '../../../../domain/entities/station.dart';
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
  final ({double x, double y})? panTarget;
  final ({double x, double y})? routeToolbarTarget;
  final bool hasTwoRoutes;
  final void Function(String mode)? onRouteToolbarSelect;

  const SvgWebView({
    super.key,
    required this.stations,
    required this.connections,
    this.routeStationIds = const {},
    this.highlightedLineIds = const {},
    this.panTarget,
    this.routeToolbarTarget,
    this.hasTwoRoutes = false,
    this.onRouteToolbarSelect,
  });

  @override
  ConsumerState<SvgWebView> createState() => _SvgWebViewState();
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
    _runJs("window.highlightLines(${_jsString(json)})");
  }

  void _clearLineHighlight() {
    if (!_isReady) return;
    _runJs("window.clearLineHighlight()");
  }

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

    // 노선 강조 변경 감지
    if (widget.highlightedLineIds != oldWidget.highlightedLineIds) {
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
