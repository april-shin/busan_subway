import 'dart:math' as math;

import '../entities/route_result.dart';
import '../entities/station.dart';
import '../entities/transfer_guide.dart';
import '../repositories/station_repository.dart';
import '../../data/local/timetable_data_source.dart';
import '../../graph/graph_builder.dart';
import '../../graph/models/graph_edge.dart';
import '../../graph/shortest_path.dart';
import '../../graph/subway_graph.dart';
import '../../core/constants/dwell_time.dart';
import '../../core/constants/line_colors.dart';
import '../../core/utils/headway_estimator.dart';
import '../../core/utils/line_direction.dart';
import '../../core/utils/transfer_guide_key.dart';

class SearchRoute {
  final StationRepository _stationRepository;

  /// 노선별 평균 배차간격을 계산하기 위한 시간표 데이터소스(옵셔널).
  ///
  /// null이면 환승 대기시간/모드 전환 가중치는 기본값(180초/90초)으로 폴백한다.
  final TimetableDataSource? _timetableDataSource;

  SearchRoute({
    required StationRepository stationRepository,
    TimetableDataSource? timetableDataSource,
  })  : _stationRepository = stationRepository,
        _timetableDataSource = timetableDataSource;

  /// [at] — 급행 운행 시간대 게이트의 기준 시각(`GraphBuilder.build` 의 `at`).
  ///
  /// 넘기지 않으면 게이트가 없다. 1호선 B급행처럼 하루 몇 편성뿐인 계통이
  /// 시각과 무관하게 최단경로로 뽑히는 것을 막으려면 화면에서 조회 시각을
  /// 넘겨야 한다. 자세한 배경은 `ExpressServiceWindow` 문서 참조.
  Future<RouteResult?> execute(
    String fromStationId,
    String toStationId, {
    DateTime? at,
  }) async {
    final stations = await _stationRepository.getAllStations();
    final connections = await _stationRepository.getAllConnections();
    final transferTimes = await _stationRepository.getTransferTimes();
    final transferGuides = await _stationRepository.getTransferGuides();
    final expressSkipEdges = await _stationRepository.getExpressSkipEdges();
    final headwaySeconds = await _loadHeadwayMap();

    final graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
      expressSkipEdges: expressSkipEdges,
      headwaySeconds: headwaySeconds,
      at: at,
    );

    final stationMap = {for (final s in stations) s.id: s};

    final fromStation = stationMap[fromStationId];
    final toStation = stationMap[toStationId];
    if (fromStation == null || toStation == null) return null;

    final finder = ShortestPathFinder(graph: graph);
    final results = finder.findShortestPathBetweenStations(
      fromStation.name,
      toStation.name,
    );

    if (results.isEmpty) return null;

    return _buildRouteResult(results.first, stationMap, transferGuides);
  }

  /// 4가지 경로 후보를 동시에 반환한다.
  ///
  /// - [fastest]: 전체 그래프 기준 최단시간 (완행/급행 자유 선택, 자동 환승 포함)
  /// - [leastTransfer]: 환승 페널티가 큰 Dijkstra 결과. fastest와 같으면 null.
  /// - [fastestExpress]: 최단시간 경로가 급행(`{base}E`) edge 를 하나라도 쓰면
  ///   그 경로(`fastest`)를 그대로 재사용. 급행을 안 쓰면 null.
  /// - [fastestLocal]: `fastestExpress`가 있을 때, 그 경로가 지나간 base 노선들의
  ///   완행 버전(급행 노드 금지 + 동일 base 노선 제한). 해당 완행 경로가 없으면 null.
  ///
  /// `fastestExpress` / `fastestLocal`은 UI에서 "급행/완행 모드 트레이드오프"를
  /// 비교 가능한지 판정하는 데 사용된다(둘 다 non-null + 시간이 다를 때만 탭 표시).
  /// 노선 공유 여부와 무관하게 일반화되어, 신논현→마곡나루(9호선 단독)뿐 아니라
  /// 총신대입구→마곡나루(4호선→9호선 환승 후 급행)처럼 환승이 낀 경로에서도
  /// 같은 경로의 완행 대안을 함께 보여준다. 자세한 판정 근거는 본문 주석 참조.
  ///
  /// [at] 은 [execute] 와 같은 급행 운행 시간대 게이트 기준 시각이다.
  ///
  /// [viaStationIds] 는 출발→도착 사이에 **지정된 순서대로** 반드시 지나야 하는
  /// 경유역 ID 목록이다. 비어 있으면(기본값) 경유 없는 기존 동작과 완전히 동일하다.
  /// 4가지 후보 모두 같은 경유 제약을 받는다.
  Future<
      ({
        RouteResult? fastest,
        RouteResult? leastTransfer,
        RouteResult? fastestExpress,
        RouteResult? fastestLocal,
      })> executeAll(
    String fromStationId,
    String toStationId, {
    List<String> viaStationIds = const [],
    DateTime? at,
  }) async {
    final stations = await _stationRepository.getAllStations();
    final connections = await _stationRepository.getAllConnections();
    final transferTimes = await _stationRepository.getTransferTimes();
    final transferGuides = await _stationRepository.getTransferGuides();
    final expressSkipEdges = await _stationRepository.getExpressSkipEdges();
    final headwaySeconds = await _loadHeadwayMap();

    final graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
      expressSkipEdges: expressSkipEdges,
      headwaySeconds: headwaySeconds,
      at: at,
    );

    final stationMap = {for (final s in stations) s.id: s};

    final fromStation = stationMap[fromStationId];
    final toStation = stationMap[toStationId];
    if (fromStation == null || toStation == null) {
      return (
        fastest: null,
        leastTransfer: null,
        fastestExpress: null,
        fastestLocal: null,
      );
    }

    final finder = ShortestPathFinder(graph: graph);

    // 정차 순서: 출발 → 경유역들(지정 순서) → 도착. 경유가 없으면 [출발, 도착].
    final stops = _buildStops(
      fromStation: fromStation,
      toStation: toStation,
      viaStationIds: viaStationIds,
      stationMap: stationMap,
    );
    final stopNodeIds = [
      for (final stop in stops) _nodeIdsForStation(graph, stop),
    ];

    final fastestPath = finder.findShortestPathVia(stopNodeIds);
    // 환승 페널티가 큰 Dijkstra로 최소환승 경로 산출 (shortest_path.dart의
    // _transferPenalty=100000 과 동일 수치를 사용).
    final minTransferPath = finder.findShortestPathVia(
      stopNodeIds,
      transferPenalty: 100000,
    );
    final fastest = fastestPath == null
        ? null
        : _buildRouteResult(fastestPath, stationMap, transferGuides);
    final leastTransfer = minTransferPath == null
        ? null
        : _buildRouteResult(minTransferPath, stationMap, transferGuides);

    // 급행/완행 비교("모드 트레이드오프")는 노선 공유 여부와 무관하게, 최단시간
    // 경로(`fastestPath`) 자체가 급행(`{lineId}E`) edge 를 하나라도 쓰는지로
    // 일반화하여 판정한다.
    //
    // 기존에는 출발·도착이 "공유하는 급행 지원 노선"(sharedExpressLine)이 있을
    // 때만 비교했기 때문에, 총신대입구(4,7호선)→마곡나루(9,공항철도)처럼 서로
    // 다른 노선에서 환승해 9호선 급행을 타는 경로는 완행 대안이 계산되지
    // 않았다(교집합이 없어 sharedExpressLine == null). 이 경우도 "경로 어딘가에서
    // 급행을 탔다"는 사실만으로 완행 대안을 보여줘야 사용자가 비교할 수 있다.
    //
    // 판정은 정규화(swap) 이전의 `fastestPath`(순수 시간최단 PathResult) 기준으로
    // 한다. `finalFastest`는 leastTransfer 와 swap 될 수 있어 "시간최단 경로가
    // 급행을 썼는가"라는 질문과 맞지 않기 때문이다.
    final expressUsed = fastestPath != null &&
        fastestPath.edges.any((e) => e.lineId.endsWith('E'));

    RouteResult? fastestExpress;
    RouteResult? fastestLocal;
    if (expressUsed) {
      // 완행 대안은 "급행을 피해 아무렇게나 찾은 최단경로"가 아니라, fastest 가
      // 실제로 지나간 그 노선들의 완행 버전이어야 한다. 그렇지 않으면 예를 들어
      // 총신대입구(4호선)→마곡나루(9호선 급행) 경로의 완행 대안이 "4호선→서울역
      // →공항철도"처럼 전혀 다른 노선으로 우회해버려, 사용자가 화면에서 본
      // 경로와 무관한 대안이 나온다.
      //
      // 그래서 nodeFilter 를 두 조건의 AND 로 구성한다:
      //   1) 급행 가상 노드(`{base}E`) 금지 — 완행이어야 하므로.
      //   2) fastest 경로가 실제 이동에 사용한 base 노선(환승/모드전환 edge 제외)
      //      의 노드만 허용 — "같은 경로의 완행 버전"을 보장.
      final fastestBaseLines = fastestPath.edges
          .where((e) => !e.isTransfer && !e.lineId.endsWith('M'))
          .map((e) => _stripExpressSuffix(e.lineId))
          .toSet();
      final localPath = finder.findShortestPathVia(
        stopNodeIds,
        nodeFilter: (id) =>
            !_isExpressNode(id) && fastestBaseLines.contains(id.split('_').last),
      );

      fastestExpress = fastest;
      fastestLocal = localPath == null
          ? null
          : _buildRouteResult(localPath, stationMap, transferGuides);
    }

    // fastest / leastTransfer 결과를 사용자 관점에서 정상화한다.
    //
    // 정의상 fastest는 "시간이 더 짧은 쪽", leastTransfer는 "시간은 더 길지만
    // 환승이 더 적은 쪽"이어야 한다. 그러나 `findShortestPathBetweenStations`은
    // 환승 페널티를 비용에 포함하므로, 같은 노선 내 급행/완행 혼합처럼 환승이
    // 1개 더 들어가면서도 시간이 짧은 경로가 fastest로 잡히고, 환승이 0인
    // 단일 노선 경로가 leastTransfer로 잡히면 사용자 관점에선
    // "최단시간이 최소환승보다 오래 걸린다"는 모순이 화면에 노출된다.
    //
    // 그래서 두 결과를 비교해 다음을 보장한다:
    //   1) 시간 정상화: leastTransfer 가 더 빠르면 swap.
    //   2) dominate 컷: 정상화 후 fastest 가 환승까지 같거나 적으면
    //      leastTransfer 는 의미가 없으므로 null. (이렇게 되면 화면이
    //      single 또는 modeTradeoff 분기로 자연스럽게 넘어가, 9호선 같은
    //      급행/완행 케이스에서 "급행/완행" 탭이 뜬다.)
    RouteResult? finalFastest = fastest;
    RouteResult? finalLeastTransfer = leastTransfer;
    if (finalFastest != null && finalLeastTransfer != null) {
      if (finalLeastTransfer.totalTimeSeconds < finalFastest.totalTimeSeconds) {
        final tmp = finalFastest;
        finalFastest = finalLeastTransfer;
        finalLeastTransfer = tmp;
      }
      if (finalFastest.transferCount <= finalLeastTransfer.transferCount) {
        finalLeastTransfer = null;
      }
    }

    return (
      fastest: finalFastest,
      leastTransfer: finalLeastTransfer,
      fastestExpress: fastestExpress,
      fastestLocal: fastestLocal,
    );
  }

  /// 출발 → 경유역들 → 도착 순서의 정차역 목록을 만든다.
  ///
  /// 정규화 규칙(경로 계산이 무의미한 입력을 제거):
  ///   - [stationMap] 에 없는 경유역 ID 는 무시한다.
  ///   - 직전 정차역과 **같은 역 이름**인 경유역은 무시한다(연속 중복, 출발역과
  ///     동일한 첫 경유역 등). 같은 역을 다시 지나라는 제약은 경로를 바꾸지 않는다.
  ///   - 마지막 경유역이 도착역과 같은 역이면 도착역 레코드로 교체한다. 사용자가
  ///     고른 도착역 레코드가 최종 정차역으로 남아야 노드 후보 집합이 도착역
  ///     기준으로 잡힌다.
  static List<Station> _buildStops({
    required Station fromStation,
    required Station toStation,
    required List<String> viaStationIds,
    required Map<String, Station> stationMap,
  }) {
    final stops = <Station>[fromStation];
    for (final id in viaStationIds) {
      final via = stationMap[id];
      if (via == null || via.name == stops.last.name) continue;
      stops.add(via);
    }
    if (stops.length > 1 && stops.last.name == toStation.name) {
      stops[stops.length - 1] = toStation;
    } else {
      stops.add(toStation);
    }
    return stops;
  }

  /// 사용자가 선택한 [station] 에 대응하는 그래프 노드 후보 집합.
  ///
  /// 환승역은 같은 물리 역이므로 소속 모든 노선 노드를 "거리 0" 의
  /// multi-source/sink 후보로 간주한다. 이렇게 해야 종합운동장(2·9호선) ↔
  /// 동작(4·9호선) 조회에서 9호선 단독 경로가 환승 0 으로 올바르게 잡힌다.
  ///
  /// 동명이역(예: 5호선 "양평" vs 경의중앙선 "양평")을 피하기 위해 선택된 Station 의
  /// `lineId + transferLines` 에 포함된 노선만 허용한다.
  ///
  /// 가상 급행 노드(`{base}E`)도 함께 포함해야 한다. 그렇지 않으면 정차역이 급행
  /// 정차역이어도 `_base → 9M edge → _E` 모드 전환이 앞뒤 세그먼트 경계에 삽입되어
  /// "종합운동장에서 환승 시작" 같은 부자연스러운 경로가 나온다.
  static Set<String> _nodeIdsForStation(SubwayGraph graph, Station station) {
    final lineIds = <String>{station.lineId, ...station.transferLines};
    final allowedSuffixes = <String>{
      for (final base in lineIds) ...['_$base', '_${base}E'],
    };
    // graph 에 실제로 존재하는 동명 노드(base + 가상 급행) 를 모두 후보로 편입.
    return graph
        .getNodeIdsForStation(station.name)
        .where((id) => allowedSuffixes.any(id.endsWith))
        .toSet();
  }

  /// 노선별 평균 배차간격(초) 맵을 로드한다.
  ///
  /// [_timetableDataSource]가 null이거나 로드에 실패하면 빈 맵을 반환한다.
  /// (그래프 빌더가 누락된 노선에 대해 기본값으로 폴백한다.)
  Future<Map<String, int>> _loadHeadwayMap() async {
    final source = _timetableDataSource;
    if (source == null) return const <String, int>{};
    try {
      final schedules = await source.loadSchedules();
      return buildHeadwayMap(schedules);
    } catch (_) {
      return const <String, int>{};
    }
  }

  RouteResult _buildRouteResult(
    PathResult path,
    Map<String, Station> stationMap,
    Map<String, TransferGuide> transferGuides,
  ) {
    final built = _buildSegments(path, stationMap, transferGuides);

    return RouteResult(
      segments: built.segments,
      totalTimeSeconds: path.totalTimeSeconds,
      // 모드 전환(완행↔급행)도 사용자 관점에선 다른 열차로 갈아타는 것이므로
      // 일반 환승과 동일하게 카운트한다.
      transferCount: built.segments.length - 1,
      // "N개역" 표시는 거쳐간 정거장 수(hop)이다. 세그먼트별
      // (stations.length - 1) 의 합 — 환승역 자체는 hop 으로 세지 않는다.
      // 예) 사당→방배 단일 세그먼트 [사당, 방배] → 1개역.
      stationCount: built.segments.fold(
        0,
        (sum, seg) =>
            sum + (seg.stations.isEmpty ? 0 : seg.stations.length - 1),
      ),
      transferDurations: built.transferDurations,
      transferWalkDurations: built.transferWalkDurations,
      transferGuides: built.transferGuides,
    );
  }

  ({
    List<RouteSegment> segments,
    List<int> transferDurations,
    List<int> transferWalkDurations,
    List<TransferGuide?> transferGuides,
  }) _buildSegments(
    PathResult path,
    Map<String, Station> stationMap,
    Map<String, TransferGuide> transferGuides,
  ) {
    if (path.edges.isEmpty) {
      return (
        segments: <RouteSegment>[],
        transferDurations: <int>[],
        transferWalkDurations: <int>[],
        transferGuides: <TransferGuide?>[],
      );
    }

    final segments = <RouteSegment>[];
    final transferDurations = <int>[];
    // 환승 라벨용 도보시간(초). transferDurations(도보+대기)와 항상 나란히
    // 같은 길이로 채워진다. 라우팅/총시간 계산에는 쓰이지 않는다.
    final transferWalkDurations = <int>[];
    final transferGuidesList = <TransferGuide?>[];
    var currentLineId = path.edges.first.lineId;
    var currentStations = <Station>[];
    var currentDurationSeconds = 0;

    for (var i = 0; i < path.edges.length; i++) {
      final edge = path.edges[i];

      if (edge.isTransfer) {
        // 환승역을 이전 세그먼트의 마지막 역으로 추가
        final fromNodeId = edge.fromNodeId;
        final stationId = fromNodeId.split('_').first;
        final station = stationMap[stationId];
        if (_shouldAppend(currentStations, station)) {
          currentStations.add(station!);
        }

        RouteSegment? completedSegment;
        if (currentStations.isNotEmpty) {
          // 중간 역 정차시간 추가 (첫 역·마지막 역 제외)
          final intermediateCount =
              math.max(0, currentStations.length - 2);
          final dwellSum = intermediateCount * dwellTimeSeconds;
          currentDurationSeconds += dwellSum;
          completedSegment = _createSegment(
            currentLineId,
            currentStations,
            currentDurationSeconds,
          );
          segments.add(completedSegment);
        }
        transferDurations.add(edge.weightSeconds);
        // 라벨용 도보시간을 나란히 수집(대기 제외). 불변식: transferDurations,
        // transferWalkDurations, transferGuidesList 세 리스트는 항상 같은 길이.
        transferWalkDurations.add(edge.transferWalkSeconds);

        // 환승 가이드 매칭 (이전 세그먼트 방향 + 다음 노선/방향 기준).
        // 단, 모드 전환(`{line}M`)은 같은 역의 완행↔급행 전환이라 환승 가이드 의미 없음.
        //
        // 다음 세그먼트는 이 시점에 아직 조립되지 않았으므로, 환승 직후 첫 주행
        // edge(`path.edges[i + 1]`)를 미리 들여다봐(lookahead) 목적 노선의 방향을
        // 산출한다. 산출 불가면 null → 폴백(4-tuple) 키만 사용한다.
        final nextEdge =
            (i + 1 < path.edges.length) ? path.edges[i + 1] : null;
        final nextLineId = nextEdge?.lineId;
        final isModeSwitch = edge.lineId.endsWith('M');
        transferGuidesList.add(
          isModeSwitch
              ? null
              : _resolveTransferGuide(
                  completedSegment: completedSegment,
                  stationName: station?.name,
                  nextLineId: nextLineId,
                  destIsDown: _resolveDestinationDirection(nextEdge),
                  guides: transferGuides,
                ),
        );

        currentStations = [];
        currentDurationSeconds = 0;
        if (i + 1 < path.edges.length) {
          currentLineId = path.edges[i + 1].lineId;
        }
        continue;
      }

      if (edge.lineId != currentLineId && currentStations.isNotEmpty) {
        final intermediateCount2 =
            math.max(0, currentStations.length - 2);
        final dwellSum2 = intermediateCount2 * dwellTimeSeconds;
        currentDurationSeconds += dwellSum2;
        segments.add(_createSegment(
          currentLineId,
          currentStations,
          currentDurationSeconds,
        ));
        currentStations = [];
        currentDurationSeconds = 0;
        currentLineId = edge.lineId;
      }

      final fromNodeId = edge.fromNodeId;
      final stationId = fromNodeId.split('_').first;
      final station = stationMap[stationId];
      if (_shouldAppend(currentStations, station)) {
        currentStations.add(station!);
      }

      currentDurationSeconds += edge.weightSeconds;

      if (i == path.edges.length - 1) {
        final toNodeId = edge.toNodeId;
        final toStationId = toNodeId.split('_').first;
        final toStation = stationMap[toStationId];
        if (toStation != null) {
          currentStations.add(toStation);
        }
      }
    }

    if (currentStations.isNotEmpty) {
      // 마지막 세그먼트: 중간 역 정차시간 추가 (첫 역·마지막 역 제외)
      final lastIntermediateCount =
          math.max(0, currentStations.length - 2);
      final lastDwellSum = lastIntermediateCount * dwellTimeSeconds;
      currentDurationSeconds += lastDwellSum;
      segments.add(_createSegment(
        currentLineId,
        currentStations,
        currentDurationSeconds,
      ));
    }

    return (
      segments: List.unmodifiable(segments),
      transferDurations: List.unmodifiable(transferDurations),
      transferWalkDurations: List.unmodifiable(transferWalkDurations),
      transferGuides: List.unmodifiable(transferGuidesList),
    );
  }

  /// [station] 을 세그먼트의 역 목록에 이어붙여야 하는지.
  ///
  /// **바로 앞 역과 같을 때만** 건너뛴다. 같은 물리 역의 노선별 노드를 연속으로
  /// 지나는 경우(환승 edge 전후, 완행↔급행 모드 전환)에 역이 두 번 들어가는 것을
  /// 막는 것이 이 중복 제거의 목적이다.
  ///
  /// 목록 전체를 검사하지 않는 이유: 경유역 지정으로 되돌아오는 경로(A→…→D→…→B)나
  /// 2호선 순환 구간에서는 같은 역을 **떨어진 위치에서** 다시 지나는 것이 정상이다.
  /// 전체 검사로 지우면 그 재방문이 역 목록·정거장 수에서 사라진다.
  static bool _shouldAppend(List<Station> stations, Station? station) {
    if (station == null) return false;
    return stations.isEmpty || stations.last != station;
  }

  /// 환승 가이드 키를 조립하여 매칭되는 가이드를 반환한다.
  ///
  /// 이전 세그먼트의 마지막 두 역으로 도착 방향(up/down)을 판정하고,
  /// `{역명}_{이전노선}_{도착방향}_{다음노선}_{목적방향}` 구체 키를 먼저,
  /// 없으면 `{역명}_{이전노선}_{도착방향}_{다음노선}` 폴백 키를 조회한다
  /// ([lookupTransferGuide]).
  ///
  /// [destIsDown] 이 null 이면(다음 주행 edge 없음·모드 전환 등) 폴백 키만 쓴다.
  ///
  /// 매칭 실패, 방향 판정 불가(역 수 부족), 세그먼트 없음 → null.
  TransferGuide? _resolveTransferGuide({
    required RouteSegment? completedSegment,
    required String? stationName,
    required String? nextLineId,
    required bool? destIsDown,
    required Map<String, TransferGuide> guides,
  }) {
    if (completedSegment == null ||
        stationName == null ||
        nextLineId == null) {
      return null;
    }
    if (completedSegment.stations.length < 2) return null;

    final prevLineId = completedSegment.lineId;
    final fromId = completedSegment
        .stations[completedSegment.stations.length - 2]
        .id;
    final toId = completedSegment.stations.last.id;
    final isDown = isDownBetween(fromId, toId, prevLineId);
    // 가상 급행 노선(`{base}E`) 은 실제 환승 가이드 키가 base 노선 ID 로 등록되어
    // 있다. 급행·완행에서 내려도 하차 문 방향/객차 번호는 동일하므로 `1E → 1`
    // 처럼 정규화하여 조회.
    return lookupTransferGuide<TransferGuide>(
      guides,
      stationName: stationName,
      arrivalLineId: _stripExpressSuffix(prevLineId),
      isDown: isDown,
      destinationLineId: _stripExpressSuffix(nextLineId),
      destIsDown: destIsDown,
    );
  }

  /// 환승 직후 첫 주행 edge 로 **목적 노선의 진행 방향**(하행 여부)을 산출한다.
  ///
  /// 반환 null = "방향을 알 수 없음" → 호출부는 폴백(4-tuple) 키만 쓴다. null 이
  /// 되는 경우:
  ///   - 다음 edge 가 없다(환승이 경로의 마지막 edge — 비정상이지만 방어).
  ///   - 다음 edge 가 또 환승 edge 다(연속 환승 — 목적 노선 주행이 아직 없음).
  ///   - 다음 edge 가 모드 전환(`{base}M`) 이다(같은 역 완행↔급행 전환).
  ///   - 노드 ID 에서 역 ID 를 못 뽑거나 두 역이 같다.
  ///   - 역 ID 에 후행 숫자가 없어 `isDownBetween` 이 방향을 판정할 수 없다.
  ///
  /// 마지막 항목이 중요하다: `isDownBetween` 은 숫자 ID 추출 실패 시 안전한
  /// 기본값 `false`(= up) 를 반환하므로, 그대로 쓰면 "모름"이 "up" 으로 둔갑해
  /// 존재하지도 않는 근거로 `..._up` 구체 키를 조회하게 된다(계약 위반). 그래서
  /// `canResolveDirection` 으로 **먼저** 거른다. 현재 번들 데이터로는 도달 불가한
  /// 경로지만, 계약을 코드로 못박아 데이터 확장 시 조용히 어긋나지 않게 한다.
  ///
  /// 가이드는 부가 정보이므로 산출 실패가 경로 검색 자체를 깨뜨려선 안 된다.
  /// 예외는 삼켜 null 로 처리한다.
  bool? _resolveDestinationDirection(GraphEdge? nextEdge) {
    if (nextEdge == null) return null;
    if (nextEdge.isTransfer) return null;

    final lineId = nextEdge.lineId;
    if (lineId.endsWith('M')) return null;

    try {
      // 노드 ID 포맷은 `{stationId}_{lineId}` 이고 stationId 에는 `_` 가 없다
      // (`_buildSegments` 의 `split('_').first` 와 같은 전제).
      final fromId = nextEdge.fromNodeId.split('_').first;
      final toId = nextEdge.toNodeId.split('_').first;
      if (fromId.isEmpty || toId.isEmpty || fromId == toId) return null;
      if (!canResolveDirection(fromId) || !canResolveDirection(toId)) {
        return null;
      }
      // 급행 접미사는 키 조립과 동일하게 정규화한다. `isDownBetween` 자체도 내부
      // 정규화를 하지만, 방향 산출과 키 조립이 같은 규칙을 쓴다는 것을 명시.
      return isDownBetween(fromId, toId, _stripExpressSuffix(lineId));
    } catch (_) {
      return null;
    }
  }

  /// 가상 급행 노선 ID(`{base}E`)에서 `E` 접미사 제거. 그 외는 그대로.
  /// `baseLineId` 유틸이 features 레이어에 있어 domain 에서 직접 참조하지 않도록
  /// private 헬퍼로 복제. 규칙이 단순하여 중복 허용.
  String _stripExpressSuffix(String lineId) =>
      lineId.endsWith('E') ? lineId.substring(0, lineId.length - 1) : lineId;

  /// 노드 ID(`{stationId}_{lineId}`)가 가상 급행 노선(`{base}E`) 노드인지 판정.
  ///
  /// lineId 부분(마지막 `_` 뒤)이 `E`로 끝나면 급행 가상 노드. 예:
  /// `905_9E` → true(급행), `905_9` → false(완행).
  bool _isExpressNode(String nodeId) => nodeId.split('_').last.endsWith('E');

  RouteSegment _createSegment(
    String lineId,
    List<Station> stations,
    int durationSeconds,
  ) {
    final lineName = lineNames[lineId] ?? lineId;
    final lastStation = stations.isNotEmpty ? stations.last.name : '';

    return RouteSegment(
      lineId: lineId,
      lineName: lineName,
      stations: List.unmodifiable(stations),
      durationSeconds: durationSeconds,
      direction: '$lastStation 방면',
    );
  }
}
