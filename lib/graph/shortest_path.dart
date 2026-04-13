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

  PathResult? findShortestPath(
    String fromNodeId,
    String toNodeId, {
    int transferPenalty = 0,
  }) {
    if (!graph.containsNode(fromNodeId) || !graph.containsNode(toNodeId)) {
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

    path.reversed;
    edges.reversed;

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

  List<PathResult> findShortestPathBetweenStations(
    String fromStationName,
    String toStationName,
  ) {
    final fromNodeIds = graph.getNodeIdsForStation(fromStationName);
    final toNodeIds = graph.getNodeIdsForStation(toStationName);

    if (fromNodeIds.isEmpty || toNodeIds.isEmpty) return [];

    final results = <PathResult>[];

    for (final fromId in fromNodeIds) {
      for (final toId in toNodeIds) {
        final result = findShortestPath(fromId, toId);
        if (result != null) results.add(result);
      }
    }

    results.sort((a, b) => a.totalTimeSeconds.compareTo(b.totalTimeSeconds));
    return results;
  }

  /// 환승 횟수를 최소화한 경로를 반환한다.
  /// 환승 엣지에 큰 페널티를 부여하여 환승을 피하도록 유도하고,
  /// 동일 환승 횟수 내에서는 시간이 짧은 경로를 선택한다.
  List<PathResult> findMinTransferPathBetweenStations(
    String fromStationName,
    String toStationName,
  ) {
    final fromNodeIds = graph.getNodeIdsForStation(fromStationName);
    final toNodeIds = graph.getNodeIdsForStation(toStationName);

    if (fromNodeIds.isEmpty || toNodeIds.isEmpty) return [];

    final results = <PathResult>[];

    for (final fromId in fromNodeIds) {
      for (final toId in toNodeIds) {
        final result = findShortestPath(
          fromId,
          toId,
          transferPenalty: _transferPenalty,
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
