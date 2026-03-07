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

    test('findShortestPath with transferPenalty avoids transfer', () {
      // 그래프: A_1 → B_1 → B_2(환승) → E_2 = 450초 (환승 1회)
      // transferPenalty가 있으면 환승 비용이 커져서 같은 경로를 반환하지만
      // 페널티는 totalTimeSeconds에 포함되지 않음
      final graph = _buildSimpleGraph();
      final finder = ShortestPathFinder(graph: graph);

      final result = finder.findShortestPath('A_1', 'E_2', transferPenalty: 100000);

      expect(result, isNotNull);
      // 경로는 동일 (다른 경로가 없으므로)
      expect(result!.nodeIds, ['A_1', 'B_1', 'B_2', 'D_2', 'E_2']);
      // totalTimeSeconds는 실제 시간만 반영 (페널티 미포함)
      expect(result.totalTimeSeconds, 450);
    });

    test('findMinTransferPathBetweenStations prefers fewer transfers', () {
      // 그래프:
      //  A_1 --60s-- B_1 --60s-- C_1 --60s-- D_1 (직행, 환승 0회, 180초)
      //  A_1 --60s-- B_1 → B_2(환승 120s) → D_2 --30s-- D_1(환승 120s) (환승 2회, 330초)
      // findShortestPath: 180초 직행 선택
      // findMinTransferPath: 180초 직행 선택 (환승도 적고 시간도 적으므로)
      final graph = SubwayGraph();

      graph.addNode(GraphNode(id: 'A_1', stationName: 'A역', lineId: '1'));
      graph.addNode(GraphNode(id: 'B_1', stationName: 'B역', lineId: '1'));
      graph.addNode(GraphNode(id: 'C_1', stationName: 'C역', lineId: '1'));
      graph.addNode(GraphNode(id: 'D_1', stationName: 'D역', lineId: '1'));
      graph.addNode(GraphNode(id: 'B_2', stationName: 'B역', lineId: '2'));
      graph.addNode(GraphNode(id: 'D_2', stationName: 'D역', lineId: '2'));

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'A_1', toNodeId: 'B_1', lineId: '1', weightSeconds: 60,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'B_1', toNodeId: 'C_1', lineId: '1', weightSeconds: 60,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'C_1', toNodeId: 'D_1', lineId: '1', weightSeconds: 60,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'B_1', toNodeId: 'B_2', lineId: 'transfer',
        weightSeconds: 120, isTransfer: true,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'B_2', toNodeId: 'D_2', lineId: '2', weightSeconds: 30,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'D_2', toNodeId: 'D_1', lineId: 'transfer',
        weightSeconds: 120, isTransfer: true,
      ));

      final finder = ShortestPathFinder(graph: graph);

      final results = finder.findMinTransferPathBetweenStations('A역', 'D역');

      expect(results, isNotEmpty);
      // 환승 0회 직행 경로가 선택됨
      final best = results.first;
      final transferCount = best.edges.where((e) => e.isTransfer).length;
      expect(transferCount, 0);
      expect(best.totalTimeSeconds, 180);
    });

    test('findMinTransferPathBetweenStations chooses less transfers over faster', () {
      // A_1 --200s-- D_1 (직행, 환승 0회, 200초 — 느리지만 환승 없음)
      // A_1 --30s-- B_1 → B_2(환승 60s) → D_2 --30s-- D_1(환승 60s) (환승 2회, 180초)
      final graph = SubwayGraph();

      graph.addNode(GraphNode(id: 'A_1', stationName: 'A역', lineId: '1'));
      graph.addNode(GraphNode(id: 'D_1', stationName: 'D역', lineId: '1'));
      graph.addNode(GraphNode(id: 'B_1', stationName: 'B역', lineId: '1'));
      graph.addNode(GraphNode(id: 'B_2', stationName: 'B역', lineId: '2'));
      graph.addNode(GraphNode(id: 'D_2', stationName: 'D역', lineId: '2'));

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'A_1', toNodeId: 'D_1', lineId: '1', weightSeconds: 200,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'A_1', toNodeId: 'B_1', lineId: '1', weightSeconds: 30,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'B_1', toNodeId: 'B_2', lineId: 'transfer',
        weightSeconds: 60, isTransfer: true,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'B_2', toNodeId: 'D_2', lineId: '2', weightSeconds: 30,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'D_2', toNodeId: 'D_1', lineId: 'transfer',
        weightSeconds: 60, isTransfer: true,
      ));

      final finder = ShortestPathFinder(graph: graph);

      // 최단시간: A_1→B_1→B_2→D_2 (30+60+30=120초, 환승 1회)
      final fastest = finder.findShortestPathBetweenStations('A역', 'D역');
      expect(fastest.first.totalTimeSeconds, 120);

      // 최소환승: 직행 경로 (200초, 환승 0회)
      final minTransfer = finder.findMinTransferPathBetweenStations('A역', 'D역');
      expect(minTransfer, isNotEmpty);
      final best = minTransfer.first;
      final transferCount = best.edges.where((e) => e.isTransfer).length;
      expect(transferCount, 0);
      expect(best.totalTimeSeconds, 200);
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
