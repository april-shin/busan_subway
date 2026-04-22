import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../entities/route_result.dart';
import '../entities/station.dart';
import '../entities/transfer_guide.dart';
import '../repositories/station_repository.dart';
import '../../data/local/timetable_data_source.dart';
import '../../graph/graph_builder.dart';
import '../../graph/shortest_path.dart';
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

  Future<RouteResult?> execute(String fromStationId, String toStationId) async {
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
  /// - [fastestExpress]: 시작/도착 후보를 가상 급행 노선(`{base}E`) 노드로 한정.
  ///   해당 역 모두에 급행 정차할 때만 결과가 있음. 둘 중 하나라도 급행 미정차면 null.
  /// - [fastestLocal]: 시작/도착 후보를 base(완행) 노드로 한정. 항상 가능.
  ///
  /// `fastestExpress` / `fastestLocal`은 UI에서 "급행/완행 모드 트레이드오프"를
  /// 비교 가능한지 판정하는 데 사용된다. 예) 신논현→마곡나루는 둘 다 환승 0회지만
  /// 시간이 다르므로 두 경로를 탭으로 비교한다.
  Future<
      ({
        RouteResult? fastest,
        RouteResult? leastTransfer,
        RouteResult? fastestExpress,
        RouteResult? fastestLocal,
      })> executeAll(
    String fromStationId,
    String toStationId,
  ) async {
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

    // 환승역은 같은 물리 역이므로 출발/도착이 환승역이면 소속 모든 노선 노드를
    // "거리 0" 의 multi-source/sink 로 간주한다. 이렇게 해야 종합운동장(2·9호선)
    // ↔ 동작(4·9호선) 조회에서 9호선 단독 경로가 환승 0 으로 올바르게 잡힌다.
    //
    // 동명이역(예: 5호선 "양평" vs 경의중앙선 "양평")을 피하기 위해 사용자가
    // 선택한 Station 의 `lineId + transferLines` 에 포함된 노선만 허용한다.
    //
    // 가상 급행 노드(`{base}E`)도 함께 포함해야 한다. 그렇지 않으면 출발/도착이
    // 급행 정차역이어도 `_base → 9M edge → _E` 모드 전환이 첫/마지막 세그먼트에
    // 삽입되어 "종합운동장에서 환승 시작" 같은 부자연스러운 경로가 나온다.
    final fromLineIds = <String>{
      fromStation.lineId,
      ...fromStation.transferLines,
    };
    final toLineIds = <String>{
      toStation.lineId,
      ...toStation.transferLines,
    };
    final allowedFromNodeSuffixes = <String>{
      for (final base in fromLineIds) ...['_$base', '_${base}E'],
    };
    final allowedToNodeSuffixes = <String>{
      for (final base in toLineIds) ...['_$base', '_${base}E'],
    };
    // graph 에 실제로 존재하는 동명 노드(base + 가상 급행) 를 모두 후보로 편입.
    final fromNodeIds = graph
        .getNodeIdsForStation(fromStation.name)
        .where((id) => allowedFromNodeSuffixes.any(id.endsWith))
        .toSet();
    final toNodeIds = graph
        .getNodeIdsForStation(toStation.name)
        .where((id) => allowedToNodeSuffixes.any(id.endsWith))
        .toSet();

    final fastestPath = finder.findShortestPathMulti(fromNodeIds, toNodeIds);
    // 환승 페널티가 큰 Dijkstra로 최소환승 경로 산출 (shortest_path.dart의
    // _transferPenalty=100000 과 동일 수치를 사용).
    final minTransferPath = finder.findShortestPathMulti(
      fromNodeIds,
      toNodeIds,
      transferPenalty: 100000,
    );
    final fastest = fastestPath == null
        ? null
        : _buildRouteResult(fastestPath, stationMap, transferGuides);
    final leastTransfer = minTransferPath == null
        ? null
        : _buildRouteResult(minTransferPath, stationMap, transferGuides);

    // 급행 지원 노선 lineId 집합 (expressSkipEdges 기반)
    final expressLines = <String>{
      for (final e in expressSkipEdges) e.lineId,
    };

    // 출발/도착이 공유하는 노선 중 "급행 지원" 노선을 찾는다.
    //
    // 환승역(예: 종합운동장 218_2 ↔ 930_9)은 `transferLines`에 소속된 모든 노선을
    // 포함하고 있다. Station Picker는 환승역을 단일 항목으로 표시하면서 대표
    // Station 하나만 저장하므로(`lineId` 하나), 단순 `fromStation.lineId ==
    // toStation.lineId` 비교로는 "종합운동장(2호선 대표) → 여의도(5호선 대표)"
    // 같은 환승역 간 조회에서 9호선 급행/완행 비교가 실패한다.
    //
    // 그래서 `lineId + transferLines` 합집합의 교집합에서 급행 지원 노선을 찾아
    // 그 노선 기준으로 fastestExpress/fastestLocal 을 계산한다.
    // 교집합 중 급행 지원이 여러 개면 첫 원소(안정적)를 사용.
    final fromLines = <String>{
      fromStation.lineId,
      ...fromStation.transferLines,
    };
    final toLines = <String>{
      toStation.lineId,
      ...toStation.transferLines,
    };
    final sharedExpressLine = fromLines
        .intersection(toLines)
        .firstWhereOrNull(expressLines.contains);

    // `fastestExpress` — 공유 급행 지원 노선 안에서 "급행(`_E`) edge를 1개 이상
    // 거치는 최소시간 경로". 공유 노선이 없거나 급행 edge 가 포함된 경로가 없으면 null.
    //
    // multi-source/sink 로 호출해야 출발/도착이 급행 정차역일 때 `_E` 노드에서
    // 바로 시작/종료되어 "출발역에서 9M 모드 전환"이라는 부자연스러운 첫 환승이 사라진다.
    RouteResult? fastestExpress;
    if (sharedExpressLine != null) {
      final lineId = sharedExpressLine;
      bool expressNodeFilter(String id) =>
          id.endsWith('_$lineId') ||
          id.endsWith('_${lineId}E') ||
          id.endsWith('_${lineId}M');
      // 출발/도착 후보를 base + _E 노드로 한정.
      final expressFromIds = graph
          .getNodeIdsForStation(fromStation.name)
          .where((id) =>
              id.endsWith('_$lineId') || id.endsWith('_${lineId}E'))
          .toSet();
      final expressToIds = graph
          .getNodeIdsForStation(toStation.name)
          .where((id) =>
              id.endsWith('_$lineId') || id.endsWith('_${lineId}E'))
          .toSet();
      final path = finder.findShortestPathMulti(
        expressFromIds,
        expressToIds,
        nodeFilter: expressNodeFilter,
      );
      // 급행 구간(`{lineId}E` edge)이 1개 이상 포함된 경로만 "급행"으로 인정.
      if (path != null &&
          path.edges.any((e) => e.lineId == '${lineId}E')) {
        fastestExpress = _buildRouteResult(path, stationMap, transferGuides);
      }
    }

    // `fastestLocal` — 공유 급행 지원 노선의 완행(`_{lineId}` 노드만) 단독 경로.
    // 조건 미충족 시 null.
    RouteResult? fastestLocal;
    if (sharedExpressLine != null) {
      final localLineId = sharedExpressLine;
      bool localNodeFilter(String id) => id.endsWith('_$localLineId');
      final localFromIds = graph
          .getNodeIdsForStation(fromStation.name)
          .where(localNodeFilter)
          .toSet();
      final localToIds = graph
          .getNodeIdsForStation(toStation.name)
          .where(localNodeFilter)
          .toSet();
      final path = finder.findShortestPathMulti(
        localFromIds,
        localToIds,
        transferPenalty: 100000,
        nodeFilter: localNodeFilter,
      );
      fastestLocal = path == null
          ? null
          : _buildRouteResult(path, stationMap, transferGuides);
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
      transferGuides: built.transferGuides,
      totalExpressTimeSeconds: _computeTotalExpress(
        segments: built.segments,
        transferDurations: built.transferDurations,
      ),
    );
  }

  /// 전 경로 급행 환산 총 시간을 계산한다.
  ///
  /// - 어떤 세그먼트라도 `expressDurationSeconds`가 non-null이면 결과는 non-null.
  ///   해당 세그먼트는 급행 시간을, 그렇지 않은 세그먼트는 완행(`durationSeconds`) 시간을 합산한다.
  /// - 모든 세그먼트가 null이면 결과도 null (급행 적용 가능 구간 없음).
  /// - 환승 시간은 동일하게 합산된다.
  int? _computeTotalExpress({
    required List<RouteSegment> segments,
    required List<int> transferDurations,
  }) {
    final hasAnyExpress =
        segments.any((s) => s.expressDurationSeconds != null);
    if (!hasAnyExpress) return null;

    var total = 0;
    for (final seg in segments) {
      total += seg.expressDurationSeconds ?? seg.durationSeconds;
    }
    for (final t in transferDurations) {
      total += t;
    }
    return total;
  }

  ({
    List<RouteSegment> segments,
    List<int> transferDurations,
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
        transferGuides: <TransferGuide?>[],
      );
    }

    final segments = <RouteSegment>[];
    final transferDurations = <int>[];
    final transferGuidesList = <TransferGuide?>[];
    var currentLineId = path.edges.first.lineId;
    var currentStations = <Station>[];
    var currentDurationSeconds = 0;
    // 급행 환산 시간 누적값 — 항상 매 edge를 `expressWeightSeconds ?? weightSeconds`로 합산.
    // 세그먼트 내 `expressWeightSeconds`가 **하나라도** 등장하면 `hasExpressInSegment=true`로
    // 표시되어, 세그먼트 종료 시 이 누적값이 채택된다. 모두 null이면 세그먼트의
    // expressDurationSeconds는 null로 남는다.
    var currentExpressAccumulated = 0;
    var hasExpressInSegment = false;

    for (var i = 0; i < path.edges.length; i++) {
      final edge = path.edges[i];

      if (edge.isTransfer) {
        // 환승역을 이전 세그먼트의 마지막 역으로 추가
        final fromNodeId = edge.fromNodeId;
        final stationId = fromNodeId.split('_').first;
        final station = stationMap[stationId];
        if (station != null && !currentStations.contains(station)) {
          currentStations.add(station);
        }

        RouteSegment? completedSegment;
        if (currentStations.isNotEmpty) {
          // 중간 역 정차시간 추가 (첫 역·마지막 역 제외)
          final intermediateCount =
              math.max(0, currentStations.length - 2);
          final dwellSum = intermediateCount * dwellTimeSeconds;
          currentDurationSeconds += dwellSum;
          // 급행 시간도 동일한 dwell 가산 (단순화 가정).
          currentExpressAccumulated += dwellSum;
          completedSegment = _createSegment(
            currentLineId,
            currentStations,
            currentDurationSeconds,
            expressDurationSeconds:
                hasExpressInSegment ? currentExpressAccumulated : null,
          );
          segments.add(completedSegment);
        }
        transferDurations.add(edge.weightSeconds);

        // 환승 가이드 매칭 (이전 세그먼트 방향 + 다음 노선 기준).
        // 단, 모드 전환(`{line}M`)은 같은 역의 완행↔급행 전환이라 환승 가이드 의미 없음.
        final nextLineId = (i + 1 < path.edges.length)
            ? path.edges[i + 1].lineId
            : null;
        final isModeSwitch = edge.lineId.endsWith('M');
        transferGuidesList.add(
          isModeSwitch
              ? null
              : _resolveTransferGuide(
                  completedSegment: completedSegment,
                  stationName: station?.name,
                  nextLineId: nextLineId,
                  guides: transferGuides,
                ),
        );

        currentStations = [];
        currentDurationSeconds = 0;
        currentExpressAccumulated = 0;
        hasExpressInSegment = false;
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
        currentExpressAccumulated += dwellSum2;
        segments.add(_createSegment(
          currentLineId,
          currentStations,
          currentDurationSeconds,
          expressDurationSeconds:
              hasExpressInSegment ? currentExpressAccumulated : null,
        ));
        currentStations = [];
        currentDurationSeconds = 0;
        currentExpressAccumulated = 0;
        hasExpressInSegment = false;
        currentLineId = edge.lineId;
      }

      final fromNodeId = edge.fromNodeId;
      final stationId = fromNodeId.split('_').first;
      final station = stationMap[stationId];
      if (station != null && !currentStations.contains(station)) {
        currentStations.add(station);
      }

      currentDurationSeconds += edge.weightSeconds;
      // 급행 시간 누적 전략 (순서 의존성 버그 방지):
      //   - 매 edge마다 항상 `expressWeightSeconds ?? weightSeconds`를 누적한다.
      //   - `expressWeightSeconds`가 non-null인 edge가 하나라도 있으면 세그먼트는
      //     "급행 운영 구간 포함"으로 표시되고, 세그먼트 종료 시 누적값이 채택된다.
      //   - 모든 edge가 null이면 hasExpressInSegment=false → expressDurationSeconds=null.
      // 이 방식으로 "첫 N개 완행 + 뒤 M개 급행" 순서에서도 앞쪽 completed 시간이 누락되지 않는다.
      final expressOrLocal = edge.expressWeightSeconds ?? edge.weightSeconds;
      currentExpressAccumulated += expressOrLocal;
      if (edge.expressWeightSeconds != null) {
        hasExpressInSegment = true;
      }

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
      currentExpressAccumulated += lastDwellSum;
      segments.add(_createSegment(
        currentLineId,
        currentStations,
        currentDurationSeconds,
        expressDurationSeconds:
            hasExpressInSegment ? currentExpressAccumulated : null,
      ));
    }

    return (
      segments: List.unmodifiable(segments),
      transferDurations: List.unmodifiable(transferDurations),
      transferGuides: List.unmodifiable(transferGuidesList),
    );
  }

  /// 환승 가이드 키를 조립하여 매칭되는 가이드를 반환한다.
  ///
  /// 이전 세그먼트의 마지막 두 역으로 방향(up/down)을 판정하고,
  /// `{역명}_{이전노선}_{방향}_{다음노선}` 포맷으로 조회한다.
  ///
  /// 매칭 실패, 방향 판정 불가(역 수 부족), 세그먼트 없음 → null.
  TransferGuide? _resolveTransferGuide({
    required RouteSegment? completedSegment,
    required String? stationName,
    required String? nextLineId,
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
    final key = buildTransferGuideKey(
      stationName: stationName,
      arrivalLineId: prevLineId,
      isDown: isDown,
      destinationLineId: nextLineId,
    );
    return guides[key];
  }

  RouteSegment _createSegment(
    String lineId,
    List<Station> stations,
    int durationSeconds, {
    int? expressDurationSeconds,
  }) {
    final lineName = lineNames[lineId] ?? lineId;
    final lastStation = stations.isNotEmpty ? stations.last.name : '';

    return RouteSegment(
      lineId: lineId,
      lineName: lineName,
      stations: List.unmodifiable(stations),
      durationSeconds: durationSeconds,
      direction: '$lastStation 방면',
      expressDurationSeconds: expressDurationSeconds,
    );
  }
}
