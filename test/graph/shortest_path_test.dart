import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/graph/subway_graph.dart';
import 'package:seoul_subway/graph/shortest_path.dart';
import 'package:seoul_subway/graph/models/graph_node.dart';
import 'package:seoul_subway/graph/models/graph_edge.dart';

SubwayGraph _buildSimpleGraph() {
  //  A --90s-- B --120s-- C
  //            |
  //          180s (transfer)
  //            |
  //            D --90s-- E
  final graph = SubwayGraph();

  graph.addNode(GraphNode(id: 'A_1', stationName: 'A역', lineId: '1'));
  graph.addNode(GraphNode(id: 'B_1', stationName: 'B역', lineId: '1'));
  graph.addNode(GraphNode(id: 'C_1', stationName: 'C역', lineId: '1'));
  graph.addNode(GraphNode(id: 'B_2', stationName: 'B역', lineId: '2'));
  graph.addNode(GraphNode(id: 'D_2', stationName: 'D역', lineId: '2'));
  graph.addNode(GraphNode(id: 'E_2', stationName: 'E역', lineId: '2'));

  graph.addBidirectionalEdge(GraphEdge(
    fromNodeId: 'A_1', toNodeId: 'B_1', lineId: '1', weightSeconds: 90,
  ));
  graph.addBidirectionalEdge(GraphEdge(
    fromNodeId: 'B_1', toNodeId: 'C_1', lineId: '1', weightSeconds: 120,
  ));
  graph.addBidirectionalEdge(GraphEdge(
    fromNodeId: 'B_1', toNodeId: 'B_2', lineId: 'transfer',
    weightSeconds: 180, isTransfer: true,
  ));
  graph.addBidirectionalEdge(GraphEdge(
    fromNodeId: 'B_2', toNodeId: 'D_2', lineId: '2', weightSeconds: 90,
  ));
  graph.addBidirectionalEdge(GraphEdge(
    fromNodeId: 'D_2', toNodeId: 'E_2', lineId: '2', weightSeconds: 90,
  ));

  return graph;
}

void main() {
  group('ShortestPathFinder', () {
    test('finds direct path on same line', () {
      final graph = _buildSimpleGraph();
      final finder = ShortestPathFinder(graph: graph);

      final result = finder.findShortestPath('A_1', 'C_1');

      expect(result, isNotNull);
      expect(result!.nodeIds, ['A_1', 'B_1', 'C_1']);
      expect(result.totalTimeSeconds, 210); // 90 + 120
      expect(result.edges.length, 2);
    });

    test('finds path with transfer', () {
      final graph = _buildSimpleGraph();
      final finder = ShortestPathFinder(graph: graph);

      final result = finder.findShortestPath('A_1', 'E_2');

      expect(result, isNotNull);
      expect(result!.nodeIds, ['A_1', 'B_1', 'B_2', 'D_2', 'E_2']);
      expect(result.totalTimeSeconds, 450); // 90 + 180 + 90 + 90
    });

    test('returns null for non-existent node', () {
      final graph = _buildSimpleGraph();
      final finder = ShortestPathFinder(graph: graph);

      expect(finder.findShortestPath('A_1', 'unknown'), isNull);
      expect(finder.findShortestPath('unknown', 'A_1'), isNull);
    });

    test('returns zero-cost path for same node', () {
      final graph = _buildSimpleGraph();
      final finder = ShortestPathFinder(graph: graph);

      final result = finder.findShortestPath('A_1', 'A_1');

      expect(result, isNotNull);
      expect(result!.totalTimeSeconds, 0);
      expect(result.nodeIds, ['A_1']);
    });

    test('returns null for unreachable node', () {
      final graph = SubwayGraph();
      graph.addNode(GraphNode(id: 'X', stationName: 'X역', lineId: '1'));
      graph.addNode(GraphNode(id: 'Y', stationName: 'Y역', lineId: '1'));

      final finder = ShortestPathFinder(graph: graph);
      expect(finder.findShortestPath('X', 'Y'), isNull);
    });

    test('findShortestPathBetweenStations finds best path across lines', () {
      final graph = _buildSimpleGraph();
      final finder = ShortestPathFinder(graph: graph);

      final results = finder.findShortestPathBetweenStations('A역', 'E역');

      expect(results, isNotEmpty);
      expect(results.first.totalTimeSeconds, 450);
    });

    test('findShortestPathBetweenStations returns empty for unknown station', () {
      final graph = _buildSimpleGraph();
      final finder = ShortestPathFinder(graph: graph);

      expect(finder.findShortestPathBetweenStations('없는역', 'A역'), isEmpty);
    });

    test('chooses shorter path when multiple exist', () {
      final graph = SubwayGraph();

      // A --100s-- B (direct)
      // A --50s-- C --30s-- B (indirect, shorter)
      graph.addNode(GraphNode(id: 'A', stationName: 'A역', lineId: '1'));
      graph.addNode(GraphNode(id: 'B', stationName: 'B역', lineId: '1'));
      graph.addNode(GraphNode(id: 'C', stationName: 'C역', lineId: '1'));

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'A', toNodeId: 'B', lineId: '1', weightSeconds: 100,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'A', toNodeId: 'C', lineId: '1', weightSeconds: 50,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'C', toNodeId: 'B', lineId: '1', weightSeconds: 30,
      ));

      final finder = ShortestPathFinder(graph: graph);
      final result = finder.findShortestPath('A', 'B');

      expect(result, isNotNull);
      expect(result!.totalTimeSeconds, 80); // 50 + 30 via C
      expect(result.nodeIds, ['A', 'C', 'B']);
    });
  });
}
