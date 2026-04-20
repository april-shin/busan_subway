import '../domain/entities/station.dart';
import '../domain/entities/connection.dart';
import '../domain/entities/express_skip_edge.dart';
import 'models/graph_edge.dart';
import 'models/graph_node.dart';
import 'subway_graph.dart';

/// 그래프 빌더.
///
/// 기본 그래프 구성:
/// - 모든 역에 대해 `{stationId}_{lineId}` 형식의 노드 추가
/// - 인접 역 사이에 양방향 완행 edge 추가 (`Connection`)
/// - 같은 이름의 환승역 사이에 양방향 환승 edge 추가
///
/// 급행 모델링(선택적, [expressSkipEdges]가 비어있지 않으면 활성화):
/// - 급행 정차역에 `{stationId}_{lineId}E` 가상 노드 추가
/// - 급행 정차역 인접 쌍 사이에 양방향 급행 edge 추가 (lineId=`{line}E`)
/// - 같은 역의 완행↔급행 노드 사이에 양방향 모드 전환 edge 추가
///   (lineId=`{line}M`, isTransfer=true, weight=배차간격/2)
///
/// 환승 대기 시간 반영(선택적, [headwaySeconds]가 비어있지 않으면 활성화):
/// - 환승 edge 가중치에 도착 노선 배차간격/2 추가 (방향별 비대칭)
class GraphBuilder {
  /// 환승 시간 fallback (transferTimes에 키가 없을 때).
  static const int _defaultTransferSeconds = 180;

  /// 배차간격 fallback (headwaySeconds에 노선이 없을 때).
  static const int _defaultHeadwaySeconds = 180;

  SubwayGraph build({
    required List<Station> stations,
    required List<Connection> connections,
    required Map<String, int> transferTimes,
    List<ExpressSkipEdge> expressSkipEdges = const [],
    Map<String, int> headwaySeconds = const {},
  }) {
    final graph = SubwayGraph();

    _addStationNodes(graph, stations);
    _addConnectionEdges(graph, connections);
    _addExpressNodes(graph, stations, expressSkipEdges);
    _addExpressSkipEdges(graph, expressSkipEdges);
    _addModeSwitchEdges(graph, expressSkipEdges, headwaySeconds);
    _addTransferEdges(graph, stations, transferTimes, headwaySeconds);

    return graph;
  }

  void _addStationNodes(SubwayGraph graph, List<Station> stations) {
    for (final station in stations) {
      final nodeId = '${station.id}_${station.lineId}';
      graph.addNode(GraphNode(
        id: nodeId,
        stationName: station.name,
        lineId: station.lineId,
      ));
    }
  }

  void _addConnectionEdges(SubwayGraph graph, List<Connection> connections) {
    for (final connection in connections) {
      if (connection.isTransfer) continue;

      final fromNodeId = '${connection.fromStationId}_${connection.lineId}';
      final toNodeId = '${connection.toStationId}_${connection.lineId}';

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: fromNodeId,
        toNodeId: toNodeId,
        lineId: connection.lineId,
        weightSeconds: connection.travelTimeSeconds,
        expressWeightSeconds: connection.expressTimeSeconds,
      ));
    }
  }

  /// 급행 정차역에 `{stationId}_{lineId}E` 가상 노드를 추가한다.
  ///
  /// stationName은 기존 [Station] 데이터를 참조하여 동일하게 사용한다.
  /// lineId는 `{baseLineId}E` (예: `9E`).
  ///
  /// 이미 추가된 노드(중복 등장)는 [SubwayGraph.addNode]가 idempotent하므로
  /// 재할당되어 안전하다.
  void _addExpressNodes(
    SubwayGraph graph,
    List<Station> stations,
    List<ExpressSkipEdge> expressSkipEdges,
  ) {
    if (expressSkipEdges.isEmpty) return;

    // (stationId, lineId) → Station 빠른 조회용
    final stationLookup = <String, Station>{
      for (final s in stations) '${s.id}_${s.lineId}': s,
    };

    final addedNodes = <String>{};
    for (final edge in expressSkipEdges) {
      _addExpressNodeIfNeeded(
        graph: graph,
        stationLookup: stationLookup,
        baseLineId: edge.lineId,
        stationId: edge.fromStationId,
        addedNodes: addedNodes,
      );
      _addExpressNodeIfNeeded(
        graph: graph,
        stationLookup: stationLookup,
        baseLineId: edge.lineId,
        stationId: edge.toStationId,
        addedNodes: addedNodes,
      );
    }
  }

  void _addExpressNodeIfNeeded({
    required SubwayGraph graph,
    required Map<String, Station> stationLookup,
    required String baseLineId,
    required String stationId,
    required Set<String> addedNodes,
  }) {
    final expressLineId = '${baseLineId}E';
    final expressNodeId = '${stationId}_$expressLineId';
    if (!addedNodes.add(expressNodeId)) return;

    final baseStation = stationLookup['${stationId}_$baseLineId'];
    if (baseStation == null) return; // 기존 역 데이터에 없으면 스킵
    graph.addNode(GraphNode(
      id: expressNodeId,
      stationName: baseStation.name,
      lineId: expressLineId,
    ));
  }

  /// 급행 정차역 사이에 양방향 급행 edge를 추가한다.
  /// lineId는 `{baseLineId}E`.
  void _addExpressSkipEdges(
    SubwayGraph graph,
    List<ExpressSkipEdge> expressSkipEdges,
  ) {
    for (final e in expressSkipEdges) {
      final expressLineId = '${e.lineId}E';
      final fromNodeId = '${e.fromStationId}_$expressLineId';
      final toNodeId = '${e.toStationId}_$expressLineId';

      // 두 노드가 그래프에 모두 등록되어 있어야 의미가 있다.
      if (!graph.containsNode(fromNodeId) || !graph.containsNode(toNodeId)) {
        continue;
      }

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: fromNodeId,
        toNodeId: toNodeId,
        lineId: expressLineId,
        weightSeconds: e.seconds,
      ));
    }
  }

  /// 같은 역의 완행 노드 ↔ 급행 노드 사이에 양방향 모드 전환 edge를 추가한다.
  ///
  /// - lineId: `{baseLineId}M`
  /// - isTransfer: true (세그먼트 경계로 인식되어 환승 대기시간이 표시됨)
  /// - weightSeconds: 해당 노선 배차간격 / 2 (없으면 기본 90초)
  void _addModeSwitchEdges(
    SubwayGraph graph,
    List<ExpressSkipEdge> expressSkipEdges,
    Map<String, int> headwaySeconds,
  ) {
    if (expressSkipEdges.isEmpty) return;

    // 모드 전환 edge가 필요한 (stationId, baseLineId) 집합
    final modeSwitchTargets = <_ModeSwitchKey>{};
    for (final e in expressSkipEdges) {
      modeSwitchTargets.add(_ModeSwitchKey(e.fromStationId, e.lineId));
      modeSwitchTargets.add(_ModeSwitchKey(e.toStationId, e.lineId));
    }

    for (final key in modeSwitchTargets) {
      final localNodeId = '${key.stationId}_${key.baseLineId}';
      final expressNodeId = '${key.stationId}_${key.baseLineId}E';
      if (!graph.containsNode(localNodeId) ||
          !graph.containsNode(expressNodeId)) {
        continue;
      }

      // 9호선은 같은 플랫폼에서 급행↔완행 환승이 가능하여 모드 전환 대기 0초.
      // (사용자 정책: "9호선 급행 환승시간은 0분")
      final waitSeconds = key.baseLineId == '9'
          ? 0
          : (headwaySeconds[key.baseLineId] ?? _defaultHeadwaySeconds) ~/ 2;
      final modeLineId = '${key.baseLineId}M';

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: localNodeId,
        toNodeId: expressNodeId,
        lineId: modeLineId,
        weightSeconds: waitSeconds,
        isTransfer: true,
      ));
    }
  }

  /// 같은 이름의 환승역 사이에 양방향 환승 edge를 추가한다.
  ///
  /// 환승 대기 시간(배차간격/2)을 도착 노선별로 반영하기 위해
  /// 양방향 edge를 **개별 addEdge**로 분리한다 (비대칭).
  void _addTransferEdges(
    SubwayGraph graph,
    List<Station> stations,
    Map<String, int> transferTimes,
    Map<String, int> headwaySeconds,
  ) {
    final transferStations = <String, List<Station>>{};

    for (final station in stations) {
      if (station.isTransfer) {
        transferStations.putIfAbsent(station.name, () => []).add(station);
      }
    }

    for (final entry in transferStations.entries) {
      final stationName = entry.key;
      final stationVariants = entry.value;

      for (var i = 0; i < stationVariants.length; i++) {
        for (var j = i + 1; j < stationVariants.length; j++) {
          final from = stationVariants[i];
          final to = stationVariants[j];

          final fromNodeId = '${from.id}_${from.lineId}';
          final toNodeId = '${to.id}_${to.lineId}';

          final transferKey = '${stationName}_${from.lineId}_${to.lineId}';
          final reverseKey = '${stationName}_${to.lineId}_${from.lineId}';

          final transferTime = transferTimes[transferKey] ??
              transferTimes[reverseKey] ??
              _defaultTransferSeconds;

          // headwaySeconds가 비어있을 때는 환승 대기 시간을 추가하지 않는다
          // (레거시 호환). 호출자가 명시적으로 맵을 전달하면 도착 노선
          // 기준으로 비대칭하게 배차간격/2를 추가한다.
          final addHeadway = headwaySeconds.isNotEmpty;
          final fromWait = addHeadway
              ? (headwaySeconds[from.lineId] ?? _defaultHeadwaySeconds) ~/ 2
              : 0;
          final toWait = addHeadway
              ? (headwaySeconds[to.lineId] ?? _defaultHeadwaySeconds) ~/ 2
              : 0;

          // from→to: 도착 노선 = to → to의 배차간격/2 추가
          graph.addEdge(GraphEdge(
            fromNodeId: fromNodeId,
            toNodeId: toNodeId,
            lineId: 'transfer',
            weightSeconds: transferTime + toWait,
            isTransfer: true,
          ));
          // to→from: 도착 노선 = from → from의 배차간격/2 추가
          graph.addEdge(GraphEdge(
            fromNodeId: toNodeId,
            toNodeId: fromNodeId,
            lineId: 'transfer',
            weightSeconds: transferTime + fromWait,
            isTransfer: true,
          ));
        }
      }
    }
  }
}

/// 모드 전환 edge 추가 시 중복 제거용 키.
class _ModeSwitchKey {
  final String stationId;
  final String baseLineId;

  const _ModeSwitchKey(this.stationId, this.baseLineId);

  @override
  bool operator ==(Object other) =>
      other is _ModeSwitchKey &&
      other.stationId == stationId &&
      other.baseLineId == baseLineId;

  @override
  int get hashCode => Object.hash(stationId, baseLineId);
}
