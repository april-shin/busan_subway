import 'package:collection/collection.dart';

import '../core/constants/dwell_time.dart';
import 'models/graph_edge.dart';
import 'subway_graph.dart';

class PathResult {
  final List<String> nodeIds;
  final List<GraphEdge> edges;
  final int totalTimeSeconds;
  final int totalDwellTimeSeconds;

  const PathResult({
    required this.nodeIds,
    required this.edges,
    required this.totalTimeSeconds,
    this.totalDwellTimeSeconds = 0,
  });
}

class ShortestPathFinder {
  final SubwayGraph graph;

  const ShortestPathFinder({required this.graph});

  /// Dijkstra 단일 출발-도착 최단 경로.
  ///
  /// [nodeFilter]가 주어지면 출발/도착/탐색 중간 노드 모두 필터를 통과해야 방문된다.
  /// 즉 필터 false인 노드는 그래프에서 제외된 것처럼 동작한다.
  /// 이 옵션은 "급행 단독(`_E` 노드만)" 또는 "완행 단독(base 노드만)" 경로 비교용이다.
  PathResult? findShortestPath(
    String fromNodeId,
    String toNodeId, {
    int transferPenalty = 0,
    bool Function(String nodeId)? nodeFilter,
  }) {
    if (!graph.containsNode(fromNodeId) || !graph.containsNode(toNodeId)) {
      return null;
    }
    if (nodeFilter != null &&
        (!nodeFilter(fromNodeId) || !nodeFilter(toNodeId))) {
      return null;
    }

    if (fromNodeId == toNodeId) {
      return PathResult(
        nodeIds: [fromNodeId],
        edges: [],
        totalTimeSeconds: 0,
      );
    }

    final distances = <String, int>{};
    final previous = <String, String?>{};
    final previousEdge = <String, GraphEdge?>{};
    final visited = <String>{};

    final queue = PriorityQueue<_QueueEntry>(
      (a, b) => a.distance.compareTo(b.distance),
    );

    for (final nodeId in graph.nodes.keys) {
      distances[nodeId] = _infinity;
      previous[nodeId] = null;
      previousEdge[nodeId] = null;
    }

    distances[fromNodeId] = 0;
    queue.add(_QueueEntry(nodeId: fromNodeId, distance: 0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();

      if (visited.contains(current.nodeId)) continue;
      visited.add(current.nodeId);

      if (current.nodeId == toNodeId) break;

      for (final edge in graph.getNeighbors(current.nodeId)) {
        if (visited.contains(edge.toNodeId)) continue;
        if (nodeFilter != null && !nodeFilter(edge.toNodeId)) continue;

        final penalty = (transferPenalty > 0 && edge.isTransfer)
            ? transferPenalty
            : 0;
        final newDistance =
            distances[current.nodeId]! + edge.weightSeconds + penalty;

        if (newDistance < distances[edge.toNodeId]!) {
          distances[edge.toNodeId] = newDistance;
          previous[edge.toNodeId] = current.nodeId;
          previousEdge[edge.toNodeId] = edge;
          queue.add(_QueueEntry(nodeId: edge.toNodeId, distance: newDistance));
        }
      }
    }

    if (distances[toNodeId] == _infinity) return null;

    final path = <String>[];
    final edges = <GraphEdge>[];
    String? current = toNodeId;

    while (current != null) {
      path.add(current);
      final edge = previousEdge[current];
      if (edge != null) edges.add(edge);
      current = previous[current];
    }

    final reversedEdges = edges.reversed.toList();
    final reversedPath = path.reversed.toList();
    final travelTime =
        reversedEdges.fold(0, (sum, edge) => sum + edge.weightSeconds);

    // 중간 노드 정차시간 계산 (출발역·도착역 제외, 환승 인접 노드 제외)
    final transferAdjacentNodes = <int>{};
    for (var i = 0; i < reversedEdges.length; i++) {
      if (reversedEdges[i].isTransfer) {
        transferAdjacentNodes.add(i); // 환승 직전 노드
        transferAdjacentNodes.add(i + 1); // 환승 직후 노드
      }
    }
    var dwellCount = 0;
    for (var i = 1; i < reversedPath.length - 1; i++) {
      if (!transferAdjacentNodes.contains(i)) {
        dwellCount++;
      }
    }
    final dwellTime = dwellCount * dwellTimeSeconds;

    return PathResult(
      nodeIds: reversedPath,
      edges: reversedEdges,
      totalTimeSeconds: travelTime + dwellTime,
      totalDwellTimeSeconds: dwellTime,
    );
  }

  /// 두 역 사이의 최단 경로(들)를 반환한다.
  ///
  /// [nodeFilter]가 주어지면 시작/도착 후보 노드뿐 아니라 Dijkstra가 방문하는
  /// **모든 노드**를 필터링한다. 즉 필터 false인 노드는 그래프에서 제외된 것처럼
  /// 동작한다. "급행 단독(_E 노드만)" 또는 "완행 단독(base 노드만)" 경로 비교용이다.
  ///
  /// 예) `nodeFilter: (id) => id.endsWith('E')` — 가상 급행 노선(`{base}E`) 노드만 사용.
  ///     시작역 또는 도착역에 `_E` 노드가 없으면 결과는 빈 리스트.
  List<PathResult> findShortestPathBetweenStations(
    String fromStationName,
    String toStationName, {
    bool Function(String nodeId)? nodeFilter,
  }) {
    final fromNodeIds = graph
        .getNodeIdsForStation(fromStationName)
        .where((id) => nodeFilter == null || nodeFilter(id))
        .toList();
    final toNodeIds = graph
        .getNodeIdsForStation(toStationName)
        .where((id) => nodeFilter == null || nodeFilter(id))
        .toList();

    if (fromNodeIds.isEmpty || toNodeIds.isEmpty) return [];

    final results = <PathResult>[];

    for (final fromId in fromNodeIds) {
      for (final toId in toNodeIds) {
        final result = findShortestPath(
          fromId,
          toId,
          nodeFilter: nodeFilter,
        );
        if (result != null) results.add(result);
      }
    }

    results.sort((a, b) => a.totalTimeSeconds.compareTo(b.totalTimeSeconds));
    return results;
  }

  /// 환승 횟수를 최소화한 경로를 반환한다.
  /// 환승 엣지에 큰 페널티를 부여하여 환승을 피하도록 유도하고,
  /// 동일 환승 횟수 내에서는 시간이 짧은 경로를 선택한다.
  ///
  /// [nodeFilter] 동작은 [findShortestPathBetweenStations]와 동일.
  List<PathResult> findMinTransferPathBetweenStations(
    String fromStationName,
    String toStationName, {
    bool Function(String nodeId)? nodeFilter,
  }) {
    final fromNodeIds = graph
        .getNodeIdsForStation(fromStationName)
        .where((id) => nodeFilter == null || nodeFilter(id))
        .toList();
    final toNodeIds = graph
        .getNodeIdsForStation(toStationName)
        .where((id) => nodeFilter == null || nodeFilter(id))
        .toList();

    if (fromNodeIds.isEmpty || toNodeIds.isEmpty) return [];

    final results = <PathResult>[];

    for (final fromId in fromNodeIds) {
      for (final toId in toNodeIds) {
        final result = findShortestPath(
          fromId,
          toId,
          transferPenalty: _transferPenalty,
          nodeFilter: nodeFilter,
        );
        if (result != null) results.add(result);
      }
    }

    results.sort((a, b) {
      final transferA =
          a.edges.where((e) => e.isTransfer).length;
      final transferB =
          b.edges.where((e) => e.isTransfer).length;
      final cmp = transferA.compareTo(transferB);
      if (cmp != 0) return cmp;
      return a.totalTimeSeconds.compareTo(b.totalTimeSeconds);
    });
    return results;
  }

  static const int _transferPenalty = 100000;
  static const int _infinity = 999999999;
}

class _QueueEntry {
  final String nodeId;
  final int distance;

  const _QueueEntry({required this.nodeId, required this.distance});
}
