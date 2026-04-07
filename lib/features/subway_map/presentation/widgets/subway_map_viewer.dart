import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/entities/connection.dart';
import '../../../../domain/entities/route_result.dart';
import '../../../../domain/entities/station.dart';
import '../../../../domain/usecases/search_route.dart';
import '../../../route_search/utils/direction_resolver.dart';
import '../providers/live_train_provider.dart';
import '../providers/subway_map_providers.dart';
import 'svg_web_view.dart';

/// 지하철 노선도 뷰어.
///
/// WebView 기반 SVG 렌더링으로 원본 SVG의 한국어 텍스트와 CSS를 완전히 지원한다.
/// 출발+도착 모두 선택 시 경로를 탐색하여 경유 노선을 강조하고,
/// 출발역으로 카메라를 부드럽게 이동한다.
class SubwayMapViewer extends ConsumerStatefulWidget {
  final List<Station> stations;
  final List<Connection> connections;

  const SubwayMapViewer({
    super.key,
    required this.stations,
    required this.connections,
  });

  @override
  ConsumerState<SubwayMapViewer> createState() => _SubwayMapViewerState();
}

class _SubwayMapViewerState extends ConsumerState<SubwayMapViewer> {
  Set<String> _highlightedLineIds = const {};
  Set<String> _routeStationIds = const {};
  ({double x, double y})? _panTarget;
  ({double x, double y})? _toolbarTarget;
  RouteResult? _fastestRoute;
  RouteResult? _leastTransferRoute;
  String _activeRouteMode = 'fastest';
  int _computeRevision = 0;
  List<LiveTrain> _liveTrains = const [];

  @override
  void initState() {
    super.initState();
    _maybeComputeHighlightedLines();
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod 공식 패턴: build 내 ref.listen은 중복 구독 자동 방지
    ref.listen(selectedStationsProvider, (prev, next) {
      _onSelectedStationsChanged(next);
    });

    // 실시간 열차 데이터: AsyncLoading 중 리빌드를 방지하여 맵 깜빡임 제거
    ref.listen(liveTrainsProvider, (prev, next) {
      final trains = next.valueOrNull;
      if (trains != null && !identical(trains, _liveTrains)) {
        setState(() => _liveTrains = trains);
      }
    });
    // 초기 데이터 동기화 (화면 복귀 시 이미 캐시된 데이터 반영)
    final cachedTrains = ref.read(liveTrainsProvider).valueOrNull;
    if (cachedTrains != null) {
      _liveTrains = cachedTrains;
    }

    return SvgWebView(
      stations: widget.stations,
      connections: widget.connections,
      routeStationIds: _routeStationIds,
      highlightedLineIds: _highlightedLineIds,
      panTarget: _panTarget,
      routeToolbarTarget: _toolbarTarget,
      hasTwoRoutes: _leastTransferRoute != null &&
          _fastestRoute != null &&
          _leastTransferRoute != _fastestRoute,
      onRouteToolbarSelect: _handleRouteToolbarSelect,
      liveTrains: _liveTrains,
    );
  }

  void _onSelectedStationsChanged(SelectedStations selected) {
    if (!selected.isComplete) {
      _fastestRoute = null;
      _leastTransferRoute = null;
      _activeRouteMode = 'fastest';
      ref.read(activeRouteFilterProvider.notifier).state = null;
      if (_highlightedLineIds.isNotEmpty ||
          _routeStationIds.isNotEmpty ||
          _toolbarTarget != null ||
          _liveTrains.isNotEmpty) {
        setState(() {
          _highlightedLineIds = const {};
          _routeStationIds = const {};
          _panTarget = null;
          _toolbarTarget = null;
          _liveTrains = const [];
        });
      }
      return;
    }
    _computeHighlightedLines(selected);
  }

  void _maybeComputeHighlightedLines() {
    final selected = ref.read(selectedStationsProvider);
    if (selected.isComplete) {
      _computeHighlightedLines(selected);
    }
  }

  Future<void> _computeHighlightedLines(SelectedStations selected) async {
    final revision = ++_computeRevision;
    final repo = ref.read(stationRepositoryProvider);
    final useCase = SearchRoute(stationRepository: repo);

    try {
      final (:fastest, :leastTransfer) = await useCase.executeAll(
        selected.departure!.id,
        selected.arrival!.id,
      );

      if (!mounted || revision != _computeRevision) return;

      _fastestRoute = fastest;
      _leastTransferRoute = leastTransfer;
      _activeRouteMode = 'fastest';

      final lineIds = _getLineIdsForMode(_activeRouteMode);
      _updateRouteFilter(_activeRouteMode);

      setState(() {
        _highlightedLineIds = lineIds;
        _routeStationIds = _getRouteStationIdsForMode(_activeRouteMode);
        _panTarget = (
          x: selected.departure!.svgX,
          y: selected.departure!.svgY,
        );
        _toolbarTarget = (
          x: selected.departure!.svgX,
          y: selected.departure!.svgY,
        );
      });
    } catch (_) {
      if (!mounted || revision != _computeRevision) return;
      _fastestRoute = null;
      _leastTransferRoute = null;
      ref.read(activeRouteFilterProvider.notifier).state = null;
      setState(() {
        _highlightedLineIds = const {};
        _routeStationIds = const {};
        _panTarget = null;
        _toolbarTarget = null;
      });
    }
  }

  /// 활성 경로의 첫 번째 유효 세그먼트 방향 정보를 프로바이더에 설정한다.
  void _updateRouteFilter(String mode) {
    final route = _routeForMode(mode);
    if (route == null || route.segments.isEmpty) {
      ref.read(activeRouteFilterProvider.notifier).state = null;
      return;
    }
    final validSeg = findFirstDirectionalSegment(route);
    if (validSeg == null) {
      ref.read(activeRouteFilterProvider.notifier).state = null;
      return;
    }
    ref.read(activeRouteFilterProvider.notifier).state = ActiveRouteFilter(
      lineId: validSeg.lineId,
      isDown: isDownDirection(validSeg),
    );
  }

  RouteResult? _routeForMode(String mode) =>
      mode == 'leastTransfer' ? _leastTransferRoute : _fastestRoute;

  Set<String> _getLineIdsForMode(String mode) {
    final route = _routeForMode(mode);
    if (route == null) return const {};
    return {for (final seg in route.segments) seg.lineId};
  }

  Set<String> _getRouteStationIdsForMode(String mode) {
    final route = _routeForMode(mode);
    if (route == null) return const {};
    return {
      for (final seg in route.segments)
        for (final station in seg.stations) station.id,
    };
  }

  void _handleRouteToolbarSelect(String mode) {
    if (mode == 'cancel') {
      ref.read(selectedStationsProvider.notifier).clear();
      return;
    }

    if (mode == 'result') {
      if (_fastestRoute != null) {
        final selected = ref.read(selectedStationsProvider);
        context.go('/route-result', extra: (
          fastest: _fastestRoute!,
          leastTransfer: _leastTransferRoute,
          departureStationName: selected.departure!.name,
        ));
      }
      return;
    }

    if (mode == _activeRouteMode) return;
    _activeRouteMode = mode;
    _updateRouteFilter(mode);
    setState(() {
      _highlightedLineIds = _getLineIdsForMode(mode);
      _routeStationIds = _getRouteStationIdsForMode(mode);
    });
  }
}
