import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/graph/subway_graph.dart';
import 'package:busan_subway/graph/models/graph_node.dart';
import 'package:busan_subway/graph/models/graph_edge.dart';

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

    test('addBidirectionalEdge propagates lineId and weight to reverse edge',
        () {
      // 급행은 가상 노선 `{base}E` 의 별도 edge 로 표현되므로, 역방향에도
      // lineId/weight 가 그대로 전달돼야 양방향 경로가 같은 급행 edge 를 쓴다.
      graph.addNode(GraphNode(id: 'A_9E', stationName: '언주', lineId: '9E'));
      graph.addNode(GraphNode(id: 'B_9E', stationName: '신논현', lineId: '9E'));

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'A_9E',
        toNodeId: 'B_9E',
        lineId: '9E',
        weightSeconds: 80,
      ));

      final forward = graph.getNeighbors('A_9E').first;
      final reverse = graph.getNeighbors('B_9E').first;
      expect(forward.weightSeconds, 80);
      expect(reverse.weightSeconds, 80,
          reason: '역방향 edge에도 같은 가중치가 전달돼야 함');
      expect(reverse.lineId, '9E');
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
