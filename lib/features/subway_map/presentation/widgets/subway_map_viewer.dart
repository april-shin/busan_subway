import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/upstream_stations.dart';
import '../../../../domain/entities/connection.dart';
import '../../../../domain/entities/route_result.dart';
import '../../../../domain/entities/station.dart';
import '../../../../domain/usecases/search_route.dart';
import '../../../route_search/presentation/providers/recent_search_provider.dart';
import '../../../route_search/presentation/providers/timetable_providers.dart';
import '../../../route_search/utils/departure_time_calculator.dart'
    show baseLineId;
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

  /// 역 이름 라벨을 밝게 유지할 역 이름 집합. 강조 노선에 속한 역이라도
  /// 이 집합에 없으면 흐리게 처리한다. (라벨은 `data-station` 이름으로 매칭)
  ///
  /// 구성:
  ///  - 경로에 포함된 모든 역(급행 미정차역 포함)
  ///  - 출발 노선에서 출발역 **상류**(출발역으로 열차가 들어오는 쪽) 역들
  ///
  /// 출발역 상류를 유지해야 출발역으로 다가오는 실시간 열차의 위치를 파악할 수
  /// 있다. 반대로 출발 노선이라도 경로가 노선을 벗어난 뒤 이어지는 **하류**
  /// 구간은 경로 밖이므로 이 집합에서 제외되어 흐려진다.
  Set<String> _highlightLabelNames = const {};
  ({double x, double y})? _panTarget;
  ({double x, double y})? _toolbarTarget;
  RouteResult? _fastestRoute;
  RouteResult? _leastTransferRoute;
  // 결과 화면 진입 시 모드 트레이드오프 비교를 위해 함께 전달한다.
  RouteResult? _fastestExpressRoute;
  RouteResult? _fastestLocalRoute;
  String _activeRouteMode = 'fastest';
  int _computeRevision = 0;
  List<LiveTrain> _liveTrains = const [];

  /// 급행 가상 edge 의 미정차역 인덱스.
  ///
  /// key: `'$fromStationId-$toStationId'` (양방향 모두 등록)
  /// value: 두 정차역 사이에서 SVG 상으로는 경로가 지나가지만 급행이 정차하지 않는 역 ID 들.
  ///
  /// 하이라이트 시 급행 세그먼트(`*E`)의 인접 정차역 사이에 미정차역을
  /// `routeStationIds` 에 함께 추가해, `connections` 기반으로 그려지는
  /// SVG 경로가 끊기지 않도록 한다.
  Map<String, List<String>> _expressSkippedIndex = const {};

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
      final trains = next.value;
      if (trains != null && !identical(trains, _liveTrains)) {
        setState(() => _liveTrains = trains);
      }
    });
    // 초기 데이터 동기화 (화면 복귀 시 이미 캐시된 데이터 반영)
    final cachedTrains = ref.read(liveTrainsProvider).value;
    if (cachedTrains != null) {
      _liveTrains = cachedTrains;
    }

    return SvgWebView(
      stations: widget.stations,
      connections: widget.connections,
      routeStationIds: _routeStationIds,
      highlightedLineIds: _highlightedLineIds,
      highlightLabelNames: _highlightLabelNames,
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
      _fastestExpressRoute = null;
      _fastestLocalRoute = null;
      _activeRouteMode = 'fastest';
      ref.read(activeRouteFilterProvider.notifier).state = null;
      if (_highlightedLineIds.isNotEmpty ||
          _routeStationIds.isNotEmpty ||
          _toolbarTarget != null ||
          _liveTrains.isNotEmpty) {
        setState(() {
          _highlightedLineIds = const {};
          _routeStationIds = const {};
          _highlightLabelNames = const {};
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
    final timetableSource = ref.read(timetableDataSourceProvider);
    final useCase = SearchRoute(
      stationRepository: repo,
      timetableDataSource: timetableSource,
    );

    try {
      final (
        :fastest,
        :leastTransfer,
        :fastestExpress,
        :fastestLocal,
      ) = await useCase.executeAll(
        selected.departure!.id,
        selected.arrival!.id,
        viaStationIds: selected.waypointStationIds,
        // 급행 운행 시간대 게이트 기준 시각 (`ExpressServiceWindow` 참조).
        at: DateTime.now(),
      );

      // 급행 미정차역 인덱스 갱신 (없으면 빈 맵). 하이라이트 누락 방지용.
      final expressEdges = await repo.getExpressSkipEdges();
      final skippedIndex = <String, List<String>>{};
      for (final e in expressEdges) {
        skippedIndex['${e.fromStationId}-${e.toStationId}'] =
            e.skippedStationIds;
        skippedIndex['${e.toStationId}-${e.fromStationId}'] =
            e.skippedStationIds;
      }

      if (!mounted || revision != _computeRevision) return;

      // 최근 검색 이력 기록(fire-and-forget): 출발+도착이 모두 선택돼 경로가
      // 실제로 계산된 시점에 1건을 저장한다. 무경로(fastest=null)는 남기지
      // 않는다. 홈검색·지도탭·picker·이력탭 모든 진입경로가 이 지점으로 수렴.
      if (fastest != null) {
        ref.read(recentSearchProvider.notifier).record(
              selected.departure!.id,
              selected.arrival!.id,
            );
      }

      _expressSkippedIndex = skippedIndex;
      _fastestRoute = fastest;
      _leastTransferRoute = leastTransfer;
      _fastestExpressRoute = fastestExpress;
      _fastestLocalRoute = fastestLocal;
      _activeRouteMode = 'fastest';

      final lineIds = _getLineIdsForMode(_activeRouteMode);
      _updateRouteFilter(_activeRouteMode);

      setState(() {
        _highlightedLineIds = lineIds;
        _routeStationIds = _getRouteStationIdsForMode(_activeRouteMode);
        _highlightLabelNames = _getHighlightLabelNamesForMode(_activeRouteMode);
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
      _fastestExpressRoute = null;
      _fastestLocalRoute = null;
      ref.read(activeRouteFilterProvider.notifier).state = null;
      setState(() {
        _highlightedLineIds = const {};
        _routeStationIds = const {};
        _highlightLabelNames = const {};
        _panTarget = null;
        _toolbarTarget = null;
      });
    }
  }

  /// 활성 경로의 첫 번째 유효 세그먼트 방향 정보를 프로바이더에 설정한다.
  ///
  /// 가상 급행 노선(`9E`)은 실시간 도착정보 API(`subwayId → '9'`)와 매칭이 안 되므로
  /// `baseLineId`로 정규화한다. (방향 판정은 가상 노선이든 base든 동일)
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
      lineId: baseLineId(validSeg.lineId),
      isDown: isDownDirection(validSeg),
      // 지선 필터용 탑승 구간 역 목록. 급행 세그먼트는 정차역만 담고 있지만
      // 판정이 "부분수열" 규칙이라 그대로 넘겨도 안전하다
      // (`trainPathCoversRoute` 참조).
      routeStationIds: [for (final s in validSeg.stations) s.id],
    );
  }

  RouteResult? _routeForMode(String mode) =>
      mode == 'leastTransfer' ? _leastTransferRoute : _fastestRoute;

  /// SVG 지도 노선 하이라이트용 lineId 집합.
  ///
  /// 가상 급행(`9E`/`1E` 등)은 SVG 원본에 정의돼 있지 않으므로 base 노선 ID(`9`/`1`)로
  /// 변환해 SVG 색상이 정상 적용되도록 한다.
  Set<String> _getLineIdsForMode(String mode) {
    final route = _routeForMode(mode);
    if (route == null) return const {};
    return {for (final seg in route.segments) baseLineId(seg.lineId)};
  }

  Set<String> _getRouteStationIdsForMode(String mode) {
    final route = _routeForMode(mode);
    if (route == null) return const {};
    final ids = <String>{};
    for (final seg in route.segments) {
      final segStations = seg.stations;
      for (final s in segStations) {
        ids.add(s.id);
      }
      // 급행 세그먼트(`*E`)는 정차역만 stations 에 포함된다.
      // SVG 하이라이트는 base `connections` 기반으로 인접 두 역이 모두
      // routeSet 에 있을 때만 그려지므로, 미정차역(`skippedStationIds`)을
      // 함께 추가해 경로가 끊이지 않도록 한다. (예: 9호선 급행 고속터미널→당산)
      if (!seg.lineId.endsWith('E')) continue;
      for (var i = 0; i + 1 < segStations.length; i++) {
        final key = '${segStations[i].id}-${segStations[i + 1].id}';
        final skipped = _expressSkippedIndex[key];
        if (skipped != null) ids.addAll(skipped);
      }
    }
    return ids;
  }

  /// 역 이름 라벨을 밝게 유지할 역 이름 집합(`_highlightLabelNames` 참조).
  ///
  /// = 경로에 포함된 모든 역 이름 ∪ 출발 노선의 출발역 상류 역 이름.
  Set<String> _getHighlightLabelNamesForMode(String mode) {
    final routeIds = _getRouteStationIdsForMode(mode);
    if (routeIds.isEmpty) return const {};

    final idToName = {for (final s in widget.stations) s.id: s.name};

    final names = <String>{};
    for (final id in routeIds) {
      final n = idToName[id];
      if (n != null) names.add(n);
    }
    for (final id in _getDepartureUpstreamStationIds(mode)) {
      final n = idToName[id];
      if (n != null) names.add(n);
    }
    return names;
  }

  /// 출발 노선에서 출발역 **상류**(출발역으로 열차가 들어오는 쪽) 역 ID 집합.
  /// 상세 알고리즘·경계 처리는 [departureUpstreamStationIds] 참조.
  Set<String> _getDepartureUpstreamStationIds(String mode) {
    final route = _routeForMode(mode);
    if (route == null || route.segments.isEmpty) return const {};
    final firstSeg = route.segments.first;
    final segStations = firstSeg.stations;
    // 최소 2개 역이 있어야 진행 방향을 정할 수 있다.
    if (segStations.length < 2) return const {};

    return departureUpstreamStationIds(
      connections: widget.connections,
      lineId: baseLineId(firstSeg.lineId),
      departureId: segStations.first.id,
      routeNextId: segStations[1].id,
      routeStationIds: _getRouteStationIdsForMode(mode),
    );
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
          fastestExpress: _fastestExpressRoute,
          fastestLocal: _fastestLocalRoute,
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
      _highlightLabelNames = _getHighlightLabelNamesForMode(mode);
    });
  }
}
