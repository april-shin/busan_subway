import 'package:collection/collection.dart';

import 'models/graph_edge.dart';
import 'subway_graph.dart';

class PathResult {
  final List<String> nodeIds;
  final List<GraphEdge> edges;
  final int totalTimeSeconds;

  const PathResult({
    required this.nodeIds,
    required this.edges,
    required this.totalTimeSeconds,
  });
}

class ShortestPathFinder {
  final SubwayGraph graph;

  const ShortestPathFinder({required this.graph});

  PathResult? findShortestPath(String fromNodeId, String toNodeId) {
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

        final newDistance = distances[current.nodeId]! + edge.weightSeconds;

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

    return PathResult(
      nodeIds: path.reversed.toList(),
      edges: edges.reversed.toList(),
      totalTimeSeconds: distances[toNodeId]!,
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

  static const int _infinity = 999999999;
}

class _QueueEntry {
  final String nodeId;
  final int distance;

  const _QueueEntry({required this.nodeId, required this.distance});
}
