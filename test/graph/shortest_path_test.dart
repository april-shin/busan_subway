import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/graph/subway_graph.dart';
import 'package:busan_subway/graph/shortest_path.dart';
import 'package:busan_subway/graph/models/graph_node.dart';
import 'package:busan_subway/graph/models/graph_edge.dart';

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

  group('findShortestPathVia — 경유역', () {
    test('stops 2개면 findShortestPathMulti 와 동일한 결과', () {
      final finder = ShortestPathFinder(graph: _buildSimpleGraph());

      final via = finder.findShortestPathVia([
        {'A_1'},
        {'E_2'},
      ]);
      final multi = finder.findShortestPathMulti({'A_1'}, {'E_2'});

      expect(via, isNotNull);
      expect(via!.nodeIds, multi!.nodeIds);
      expect(via.totalTimeSeconds, multi.totalTimeSeconds);
      expect(via.totalDwellTimeSeconds, multi.totalDwellTimeSeconds);
    });

    test('경로상 경유역은 직행과 동일한 경로/시간을 만든다', () {
      final finder = ShortestPathFinder(graph: _buildSimpleGraph());

      // A→C 최단경로는 A-B-C. B 를 경유로 지정해도 같아야 한다.
      final direct = finder.findShortestPathMulti({'A_1'}, {'C_1'});
      final via = finder.findShortestPathVia([
        {'A_1'},
        {'B_1'},
        {'C_1'},
      ]);

      expect(via, isNotNull);
      expect(via!.nodeIds, ['A_1', 'B_1', 'C_1']);
      expect(via.totalTimeSeconds, direct!.totalTimeSeconds);
      expect(via.edges.length, 2);
    });

    test('우회 경유역을 실제로 지나며 시간이 늘어난다', () {
      final finder = ShortestPathFinder(graph: _buildSimpleGraph());

      // A→C 직행(A-B-C, 240초) 대신 D(2호선) 를 경유하도록 강제.
      final via = finder.findShortestPathVia([
        {'A_1'},
        {'D_2'},
        {'C_1'},
      ]);

      expect(via, isNotNull);
      expect(via!.nodeIds, contains('D_2'));
      expect(via.nodeIds, ['A_1', 'B_1', 'B_2', 'D_2', 'B_2', 'B_1', 'C_1']);
      // 이동 90+180+90+90+180+120 = 750. 정차는 환승 인접 노드를 뺀 중간 노드만.
      expect(via.totalTimeSeconds, greaterThan(240));
      expect(
        via.edges.where((e) => e.isTransfer).length,
        2,
        reason: 'B역에서 1→2호선, 2→1호선 환승을 각각 한 번씩 지난다',
      );
    });

    test('경유역이 환승역이면 다음 구간이 필요한 노선으로 환승 edge 를 포함한다', () {
      final finder = ShortestPathFinder(graph: _buildSimpleGraph());

      // 경유역 B 는 1·2호선 환승역 — 두 노드를 모두 후보로 준다.
      final via = finder.findShortestPathVia([
        {'A_1'},
        {'B_1', 'B_2'},
        {'E_2'},
      ]);

      expect(via, isNotNull);
      expect(via!.nodeIds, ['A_1', 'B_1', 'B_2', 'D_2', 'E_2']);
      expect(via.edges.where((e) => e.isTransfer).length, 1);
    });

    test('경유역이 직전 정차역과 같으면 0-edge 구간으로 무시된다', () {
      final finder = ShortestPathFinder(graph: _buildSimpleGraph());

      final via = finder.findShortestPathVia([
        {'A_1'},
        {'A_1'},
        {'C_1'},
      ]);

      expect(via, isNotNull);
      expect(via!.nodeIds, ['A_1', 'B_1', 'C_1']);
      expect(via.totalTimeSeconds, 240);
    });

    test('어느 구간이라도 경로가 없으면 null', () {
      final graph = _buildSimpleGraph();
      graph.addNode(GraphNode(id: 'Z_9', stationName: 'Z역', lineId: '9'));
      final finder = ShortestPathFinder(graph: graph);

      expect(
        finder.findShortestPathVia([
          {'A_1'},
          {'Z_9'},
          {'C_1'},
        ]),
        isNull,
      );
    });

    test('stops 가 2개 미만이면 null', () {
      final finder = ShortestPathFinder(graph: _buildSimpleGraph());

      expect(finder.findShortestPathVia([]), isNull);
      expect(finder.findShortestPathVia([{'A_1'}]), isNull);
    });

    test('경유역 플랫폼 선택이 뒤 구간까지 고려된다 (그리디 금지 회귀 가드)', () {
      // 경유역 W 에 두 플랫폼(W_1/W_2)이 있고, 서로 환승이 비싼(500s) 구조.
      //   S→W_1 = 10   (가장 싸게 W 에 닿는 플랫폼)
      //   S→W_2 = 30   (T역 환승을 거쳐 조금 더 비쌈)
      //   W_1→E = 600  (또는 W_1→W_2 환승 500 + 10 = 510)
      //   W_2→E = 10
      // 앞 구간만 보는 그리디는 W_1(10) 에 고정돼 총 520 이 되지만,
      // 최적은 W_2 를 골라 이동 40 + 경유역 W 정차 30 = 70 이다.
      final graph = SubwayGraph();
      for (final n in [
        ['S_1', 'S역', '1'],
        ['T_1', 'T역', '1'],
        ['T_2', 'T역', '2'],
        ['W_1', 'W역', '1'],
        ['W_2', 'W역', '2'],
        ['E_1', 'E역', '1'],
        ['E_2', 'E역', '2'],
      ]) {
        graph.addNode(GraphNode(id: n[0], stationName: n[1], lineId: n[2]));
      }
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'S_1', toNodeId: 'W_1', lineId: '1', weightSeconds: 10,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'S_1', toNodeId: 'T_1', lineId: '1', weightSeconds: 5,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'T_1', toNodeId: 'T_2', lineId: 'transfer',
        weightSeconds: 20, isTransfer: true,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'T_2', toNodeId: 'W_2', lineId: '2', weightSeconds: 5,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'W_1', toNodeId: 'W_2', lineId: 'transfer',
        weightSeconds: 500, isTransfer: true,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'W_1', toNodeId: 'E_1', lineId: '1', weightSeconds: 600,
      ));
      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: 'W_2', toNodeId: 'E_2', lineId: '2', weightSeconds: 10,
      ));

      final via = ShortestPathFinder(graph: graph).findShortestPathVia([
        {'S_1'},
        {'W_1', 'W_2'},
        {'E_1', 'E_2'},
      ]);

      expect(via, isNotNull);
      expect(
        via!.nodeIds,
        ['S_1', 'T_1', 'T_2', 'W_2', 'E_2'],
        reason: 'W 를 2호선 플랫폼으로 잡는 것이 전체 최적 — 그리디면 '
            "['S_1','W_1','W_2','E_2'] 로 520초가 된다",
      );
      // 이동 40 + 경유역 W_2 정차 30. 그리디 경로는 520(환승 인접 노드라 정차 0).
      expect(via.totalTimeSeconds, 70);
    });

    test('nodeFilter 가 모든 구간에 적용된다', () {
      final finder = ShortestPathFinder(graph: _buildSimpleGraph());

      // 2호선 노드를 전부 금지하면 D 경유는 불가능.
      expect(
        finder.findShortestPathVia(
          [
            {'A_1'},
            {'D_2'},
            {'C_1'},
          ],
          nodeFilter: (id) => id.endsWith('_1'),
        ),
        isNull,
      );
    });
  });
}
