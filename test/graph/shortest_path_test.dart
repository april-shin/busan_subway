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
      // 이동시간 210 + 정차시간 30 (중간역 B_1 × 30초)
      expect(result.totalTimeSeconds, 240);
      expect(result.totalDwellTimeSeconds, 30);
      expect(result.edges.length, 2);
    });

    test('finds path with transfer', () {
      final graph = _buildSimpleGraph();
      final finder = ShortestPathFinder(graph: graph);

      final result = finder.findShortestPath('A_1', 'E_2');

      expect(result, isNotNull);
      expect(result!.nodeIds, ['A_1', 'B_1', 'B_2', 'D_2', 'E_2']);
      // 이동시간 450 + 정차시간 30 (중간역 D_2 × 30초, B_1/B_2는 환승 인접)
      expect(result.totalTimeSeconds, 480);
      expect(result.totalDwellTimeSeconds, 30);
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
      // 이동시간 450 + 정차시간 30
      expect(results.first.totalTimeSeconds, 480);
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
      // totalTimeSeconds는 실제 시간만 반영 (페널티 미포함) + 정차시간 30
      expect(result.totalTimeSeconds, 480);
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
      // 이동시간 180 + 정차시간 60 (중간역 B_1, C_1 × 30초)
      expect(best.totalTimeSeconds, 240);
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

    test('급행 모델 — 완행 + 모드 전환 + 급행 + 모드 전환 경로 자동 선택', () {
      // 9호선 시뮬레이션:
      //  - 완행: A_9 - B_9 - C_9 - D_9 - E_9 (각 60초, 총 240초)
      //  - 급행: B_9E - E_9E (90초 직통, B/E만 정차)
      //  - 모드 전환: B_9 ↔ B_9E (50초), E_9 ↔ E_9E (50초)
      // 출발 A → 도착 E.
      // 경로 옵션:
      //   1) 완행 단독: A→B→C→D→E = 240초
      //   2) 완행+급행: A→B→B_9E→E_9E→E = 60 + 50 + 90 + 50 = 250초 (느림)
      //   가중치를 조정해서 급행이 빠른 경우를 만든다.
      // 각 완행 edge를 100초로 변경하면:
      //   1) 완행 단독: 100*4 = 400초
      //   2) 완행+급행: 100 + 50 + 90 + 50 = 290초 → 급행 선택
      final graph = SubwayGraph();

      for (final id in ['A_9', 'B_9', 'C_9', 'D_9', 'E_9']) {
        graph.addNode(GraphNode(id: id, stationName: id[0], lineId: '9'));
      }
      for (final id in ['B_9E', 'E_9E']) {
        graph.addNode(GraphNode(id: id, stationName: id[0], lineId: '9E'));
      }
      // 완행 edge
      void addLocal(String from, String to) {
        graph.addBidirectionalEdge(GraphEdge(
          fromNodeId: from, toNodeId: to, lineId: '9', weightSeconds: 100,
        ));
      }
      addLocal('A_9', 'B_9');
      addLocal('B_9', 'C_9');
      addLocal('C_9', 'D_9');
      addLocal('D_9', 'E_9');
      // 급행 edge
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'B_9E', toNodeId: 'E_9E', lineId: '9E',
        weightSeconds: 90,
      ));
      // 모드 전환 edge
      void addMode(String local, String express) {
        graph.addBidirectionalEdge(GraphEdge(
          fromNodeId: local, toNodeId: express, lineId: '9M',
          weightSeconds: 50, isTransfer: true,
        ));
      }
      addMode('B_9', 'B_9E');
      addMode('E_9', 'E_9E');

      final finder = ShortestPathFinder(graph: graph);
      final result = finder.findShortestPath('A_9', 'E_9');

      expect(result, isNotNull);
      // 급행 경로가 선택돼야 함. (정차시간 dwell은 환승 인접 노드 제외)
      // 경로 노드: A_9 → B_9 → B_9E → E_9E → E_9
      // 환승 인접 노드: B_9, B_9E (모드 전환1), E_9E, E_9 (모드 전환2)
      // → 중간 dwell 없음. 총 시간 = 100+50+90+50 = 290초
      expect(result!.nodeIds, ['A_9', 'B_9', 'B_9E', 'E_9E', 'E_9']);
      expect(result.totalTimeSeconds, 290);
    });

    test('findShortestPathBetweenStations: nodeFilter로 급행만 허용 시 급행 노드 사용', () {
      // 그래프:
      //   A_9 (완행) ← 급행 미정차
      //   B_9 / B_9E (급행 정차)
      //   E_9 / E_9E (급행 정차)
      // - 시작: A역(완행 노드만 보유) → 도착: E역(완행+급행 보유)
      // - nodeFilter: id.endsWith('E')
      //   → 시작 후보 비어있음 → 결과 비어있어야 함.
      final graph = SubwayGraph();
      for (final id in ['A_9', 'B_9', 'C_9', 'D_9', 'E_9']) {
        graph.addNode(GraphNode(id: id, stationName: id[0], lineId: '9'));
      }
      for (final id in ['B_9E', 'E_9E']) {
        graph.addNode(GraphNode(id: id, stationName: id[0], lineId: '9E'));
      }
      void addLocal(String from, String to) {
        graph.addBidirectionalEdge(GraphEdge(
          fromNodeId: from, toNodeId: to, lineId: '9', weightSeconds: 60,
        ));
      }
      addLocal('A_9', 'B_9');
      addLocal('B_9', 'C_9');
      addLocal('C_9', 'D_9');
      addLocal('D_9', 'E_9');
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'B_9E', toNodeId: 'E_9E', lineId: '9E',
        weightSeconds: 90,
      ));

      final finder = ShortestPathFinder(graph: graph);

      // 급행만 허용: A역에 급행 노드가 없으므로 결과 없음
      final expressOnly = finder.findShortestPathBetweenStations(
        'A', 'E',
        nodeFilter: (id) => id.endsWith('E'),
      );
      expect(expressOnly, isEmpty);

      // 완행만 허용: 정상 결과
      final localOnly = finder.findShortestPathBetweenStations(
        'A', 'E',
        nodeFilter: (id) => !id.endsWith('E'),
      );
      expect(localOnly, isNotEmpty);
      // A_9 → B_9 → C_9 → D_9 → E_9 (완행 4 edge × 60초 + 중간 dwell 3 × 30초)
      expect(localOnly.first.totalTimeSeconds, 60 * 4 + 30 * 3);

      // B역(급행 정차) → E역(급행 정차) — 급행만 허용 시 결과 있음
      final bToEExpress = finder.findShortestPathBetweenStations(
        'B', 'E',
        nodeFilter: (id) => id.endsWith('E'),
      );
      expect(bToEExpress, isNotEmpty);
      expect(bToEExpress.first.nodeIds, ['B_9E', 'E_9E']);
      expect(bToEExpress.first.totalTimeSeconds, 90);
    });

    test('findMinTransferPathBetweenStations: nodeFilter도 동일하게 적용', () {
      // 동일 시나리오 — 환승 페널티 적용 변형도 nodeFilter를 존중해야 한다.
      final graph = SubwayGraph();
      graph.addNode(GraphNode(id: 'X_1', stationName: 'X', lineId: '1'));
      graph.addNode(GraphNode(id: 'Y_1', stationName: 'Y', lineId: '1'));
      graph.addNode(GraphNode(id: 'Y_1E', stationName: 'Y', lineId: '1E'));
      graph.addNode(GraphNode(id: 'Z_1E', stationName: 'Z', lineId: '1E'));

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'X_1', toNodeId: 'Y_1', lineId: '1', weightSeconds: 60,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'Y_1E', toNodeId: 'Z_1E', lineId: '1E', weightSeconds: 50,
      ));

      final finder = ShortestPathFinder(graph: graph);

      // X역엔 급행 노드가 없으므로 급행만 허용 시 결과 없음
      final expressOnly = finder.findMinTransferPathBetweenStations(
        'X', 'Z',
        nodeFilter: (id) => id.endsWith('E'),
      );
      expect(expressOnly, isEmpty);
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
      // 이동시간 80 + 정차시간 30 (중간역 C × 30초)
      expect(result!.totalTimeSeconds, 110);
      expect(result.nodeIds, ['A', 'C', 'B']);
    });
  });
}
