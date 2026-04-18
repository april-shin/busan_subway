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

    test('addBidirectionalEdge propagates expressWeightSeconds to reverse edge',
        () {
      // 역방향 edge에 급행 시간이 누락되면 해당 방향 경로의 급행 토글이
      // 사라지는 회귀 방지.
      graph.addNode(GraphNode(id: 'A_9', stationName: '언주', lineId: '9'));
      graph.addNode(GraphNode(id: 'B_9', stationName: '신논현', lineId: '9'));

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'A_9',
        toNodeId: 'B_9',
        lineId: '9',
        weightSeconds: 120,
        expressWeightSeconds: 80,
      ));

      final forward = graph.getNeighbors('A_9').first;
      final reverse = graph.getNeighbors('B_9').first;
      expect(forward.expressWeightSeconds, 80);
      expect(reverse.expressWeightSeconds, 80,
          reason: '역방향 edge에도 급행 시간이 전달돼야 함');
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
