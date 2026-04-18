import 'dart:math' as math;

import '../entities/route_result.dart';
import '../entities/station.dart';
import '../entities/transfer_guide.dart';
import '../repositories/station_repository.dart';
import '../../graph/graph_builder.dart';
import '../../graph/shortest_path.dart';
import '../../core/constants/dwell_time.dart';
import '../../core/constants/line_colors.dart';
import '../../core/utils/line_direction.dart';
import '../../core/utils/transfer_guide_key.dart';

class SearchRoute {
  final StationRepository _stationRepository;

  SearchRoute({required StationRepository stationRepository})
      : _stationRepository = stationRepository;

  Future<RouteResult?> execute(String fromStationId, String toStationId) async {
    final stations = await _stationRepository.getAllStations();
    final connections = await _stationRepository.getAllConnections();
    final transferTimes = await _stationRepository.getTransferTimes();
    final transferGuides = await _stationRepository.getTransferGuides();

    final graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
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

  /// 최단시간 경로와 최소환승 경로를 동시에 반환한다.
  /// 두 경로가 동일하면 leastTransfer는 null.
  Future<({RouteResult? fastest, RouteResult? leastTransfer})> executeAll(
    String fromStationId,
    String toStationId,
  ) async {
    final stations = await _stationRepository.getAllStations();
    final connections = await _stationRepository.getAllConnections();
    final transferTimes = await _stationRepository.getTransferTimes();
    final transferGuides = await _stationRepository.getTransferGuides();

    final graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );

    final stationMap = {for (final s in stations) s.id: s};

    final fromStation = stationMap[fromStationId];
    final toStation = stationMap[toStationId];
    if (fromStation == null || toStation == null) {
      return (fastest: null, leastTransfer: null);
    }

    final finder = ShortestPathFinder(graph: graph);

    final fastestResults = finder.findShortestPathBetweenStations(
      fromStation.name,
      toStation.name,
    );
    final minTransferResults = finder.findMinTransferPathBetweenStations(
      fromStation.name,
      toStation.name,
    );

    final fastest = fastestResults.isEmpty
        ? null
        : _buildRouteResult(fastestResults.first, stationMap, transferGuides);
    final leastTransfer = minTransferResults.isEmpty
        ? null
        : _buildRouteResult(
            minTransferResults.first, stationMap, transferGuides);

    // 두 경로가 동일하면 leastTransfer를 null로 반환
    final isSame = fastest != null &&
        leastTransfer != null &&
        fastest.totalTimeSeconds == leastTransfer.totalTimeSeconds &&
        fastest.transferCount == leastTransfer.transferCount;

    return (
      fastest: fastest,
      leastTransfer: isSame ? null : leastTransfer,
    );
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
      transferCount: built.segments.length - 1,
      stationCount: built.segments
              .fold(0, (sum, seg) => sum + seg.stations.length) -
          (built.segments.length - 1),
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

        // 환승 가이드 매칭 (이전 세그먼트 방향 + 다음 노선 기준)
        final nextLineId = (i + 1 < path.edges.length)
            ? path.edges[i + 1].lineId
            : null;
        transferGuidesList.add(_resolveTransferGuide(
          completedSegment: completedSegment,
          stationName: station?.name,
          nextLineId: nextLineId,
          guides: transferGuides,
        ));

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
