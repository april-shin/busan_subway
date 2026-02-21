import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/graph/subway_graph.dart';
import 'package:seoul_subway/graph/models/graph_node.dart';
import 'package:seoul_subway/graph/models/graph_edge.dart';

void main() {
  late SubwayGraph graph;

  setUp(() {
    graph = SubwayGraph();
  });

  group('SubwayGraph', () {
    test('addNode adds a node to the graph', () {
      final node = GraphNode(id: 'A_1', stationName: '강남', lineId: '2');
      graph.addNode(node);

      expect(graph.nodeCount, 1);
      expect(graph.containsNode('A_1'), true);
      expect(graph.getNode('A_1'), node);
    });

    test('addEdge adds a directed edge', () {
      graph.addNode(GraphNode(id: 'A_1', stationName: '강남', lineId: '2'));
      graph.addNode(GraphNode(id: 'B_1', stationName: '역삼', lineId: '2'));

      graph.addEdge(GraphEdge(
        fromNodeId: 'A_1',
        toNodeId: 'B_1',
        lineId: '2',
        weightSeconds: 90,
      ));

      expect(graph.getNeighbors('A_1').length, 1);
      expect(graph.getNeighbors('B_1').length, 0);
    });

    test('addBidirectionalEdge adds edges in both directions', () {
      graph.addNode(GraphNode(id: 'A_1', stationName: '강남', lineId: '2'));
      graph.addNode(GraphNode(id: 'B_1', stationName: '역삼', lineId: '2'));

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'A_1',
        toNodeId: 'B_1',
        lineId: '2',
        weightSeconds: 90,
      ));

      expect(graph.getNeighbors('A_1').length, 1);
      expect(graph.getNeighbors('B_1').length, 1);
      expect(graph.edgeCount, 2);
    });

    test('getNeighbors returns empty list for unknown node', () {
      expect(graph.getNeighbors('unknown'), isEmpty);
    });

    test('containsNode returns false for non-existent node', () {
      expect(graph.containsNode('unknown'), false);
    });

    test('getNodeIdsForStation returns all nodes for a station name', () {
      graph.addNode(GraphNode(id: '214_2', stationName: '교대', lineId: '2'));
      graph.addNode(GraphNode(id: '320_3', stationName: '교대', lineId: '3'));

      final nodeIds = graph.getNodeIdsForStation('교대');
      expect(nodeIds.length, 2);
      expect(nodeIds, containsAll(['214_2', '320_3']));
    });

    test('getNodeIdsForStation returns empty for unknown station', () {
      expect(graph.getNodeIdsForStation('없는역'), isEmpty);
    });
  });
}
