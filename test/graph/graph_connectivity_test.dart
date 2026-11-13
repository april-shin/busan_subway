@Tags(['integration'])
library;

import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/graph/graph_builder.dart';
import 'package:busan_subway/graph/shortest_path.dart';
import 'package:busan_subway/graph/subway_graph.dart';

/// 부산 그래프 연결성 회귀 가드.
///
/// 환승 edge 는 (a) 같은 이름의 `isTransfer` 역끼리(`_addTransferEdges`)와 (b) 이름이
/// 다른 `isTransfer` 연결(`_addCrossNameTransferEdges` — `벡스코(시립미술관)` 2호선 ↔
/// `벡스코` 동해선)로 만들어진다. 한 곳이라도 빠지면 노선이 통째로 고립된다.
/// 동명이역(좌천 1호선/동해선, 동해선 동래)은 환승이 아니므로 edge 가 **없어야** 한다.
///
/// 이 테스트가 깨지면: 새 노선·역을 추가했는데 기존 망과 이어지는 환승이 빠졌거나,
/// 동명이역을 실수로 환승으로 묶었다.
void main() {
  late List<Station> stations;
  late SubwayGraph graph;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    stations =
        (jsonDecode(await rootBundle.loadString('assets/json/stations.json'))
                as List)
            .map((e) => Station.fromJson(e as Map<String, dynamic>))
            .toList();
    final connections =
        (jsonDecode(await rootBundle.loadString('assets/json/connections.json'))
                as List)
            .map((e) => Connection.fromJson(e as Map<String, dynamic>))
            .toList();
    final transferTimes =
        (jsonDecode(
                  await rootBundle.loadString(
                    'assets/json/transfer_times.json',
                  ),
                )
                as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int));

    graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );
  });

  String nodeOf(String name, String lineId) {
    final s = stations.firstWhere(
      (s) => s.name == name && s.lineId == lineId,
      orElse: () => fail('역 없음: $name($lineId)'),
    );
    return '${s.id}_${s.lineId}';
  }

  /// [start] 에서 BFS 로 도달 가능한 노드 집합.
  /// reverse=false 는 "start 에서 갈 수 있는 곳", true 는 "start 로 올 수 있는 곳".
  Set<String> reach(String start, {required bool reverse}) {
    final incoming = <String, List<String>>{};
    if (reverse) {
      for (final id in graph.nodes.keys) {
        for (final e in graph.getNeighbors(id)) {
          incoming.putIfAbsent(e.toNodeId, () => []).add(id);
        }
      }
    }
    final seen = <String>{start};
    final queue = Queue<String>()..add(start);
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      final next = reverse
          ? (incoming[cur] ?? const <String>[])
          : graph.getNeighbors(cur).map((e) => e.toNodeId);
      for (final n in next) {
        if (seen.add(n)) queue.add(n);
      }
    }
    return seen;
  }

  String describe(Iterable<String> nodeIds) => nodeIds
      .map((id) {
        final n = graph.getNode(id);
        return n == null ? id : '${n.stationName}(${n.lineId})';
      })
      .join(', ');

  List<String> labelsOf(PathResult r) => r.nodeIds.map((id) {
    final n = graph.getNode(id)!;
    return '${n.stationName}(${n.lineId})';
  }).toList();

  bool hasTransfer(String a, String b) =>
      graph.getNeighbors(a).any((e) => e.toNodeId == b && e.isTransfer);

  group('고립 컴포넌트 0', () {
    test('노드 수는 stations.json 레코드 수와 같고 고립 노드(이웃 0)가 없다', () {
      expect(graph.nodes.length, stations.length);
      final isolated = [
        for (final id in graph.nodes.keys)
          if (graph.getNeighbors(id).isEmpty) id,
      ];
      expect(isolated, isEmpty, reason: describe(isolated));
    });

    test('서면(1호선)에서 stations.json 의 모든 역 노드에 도달한다', () {
      final reachable = reach(nodeOf('서면', '1'), reverse: false);
      final missing = [
        for (final s in stations)
          if (!reachable.contains('${s.id}_${s.lineId}')) '${s.id}_${s.lineId}',
      ];
      expect(
        missing,
        isEmpty,
        reason: '서면에서 도달 불가한 역 ${missing.length}개 — 환승 누락. '
            '노선 단위로 빠졌다면 그 노선과 기존 망을 잇는 환승을 확인하라:\n'
            '${describe(missing)}',
      );
    });

    test('모든 역 노드에서 서면(1호선)으로 돌아올 수 있다 (단방향 막다른 길 없음)', () {
      final canReach = reach(nodeOf('서면', '1'), reverse: true);
      final stuck = [
        for (final s in stations)
          if (!canReach.contains('${s.id}_${s.lineId}')) '${s.id}_${s.lineId}',
      ];
      expect(stuck, isEmpty,
          reason: '서면으로 못 돌아오는 역 ${stuck.length}개:\n${describe(stuck)}');
    });

    test('노선 내부(비환승) edge 만으로 각 노선이 한 덩어리다', () {
      final byLine = <String, List<Station>>{};
      for (final s in stations) {
        byLine.putIfAbsent(s.lineId, () => []).add(s);
      }
      expect(byLine.keys,
          unorderedEquals(['1', '2', '3', '4', '동해', '부산김해']));
      for (final entry in byLine.entries) {
        final ids = {for (final s in entry.value) '${s.id}_${s.lineId}'};
        final seen = <String>{ids.first};
        final q = Queue<String>()..add(ids.first);
        while (q.isNotEmpty) {
          for (final e in graph.getNeighbors(q.removeFirst())) {
            if (!e.isTransfer && ids.contains(e.toNodeId) && seen.add(e.toNodeId)) {
              q.add(e.toNodeId);
            }
          }
        }
        expect(seen, ids, reason: '${entry.key}호선 내부가 끊김');
      }
    });
  });

  group('환승 edge', () {
    test('같은 이름 환승역 11곳은 양방향 환승 edge 가 있다', () {
      const pairs = <(String, String, String)>[
        ('서면', '1', '2'),
        ('연산', '1', '3'),
        ('교대', '1', '동해'),
        ('동래', '1', '4'),
        ('부전', '1', '동해'),
        ('수영', '2', '3'),
        ('사상', '2', '부산김해'),
        ('덕천', '2', '3'),
        ('거제', '3', '동해'),
        ('미남', '3', '4'),
        ('대저', '3', '부산김해'),
      ];
      for (final (name, a, b) in pairs) {
        expect(hasTransfer(nodeOf(name, a), nodeOf(name, b)), isTrue,
            reason: '$name $a→$b 환승 edge 없음');
        expect(hasTransfer(nodeOf(name, b), nodeOf(name, a)), isTrue,
            reason: '$name $b→$a 환승 edge 없음');
      }
    });

    test('이름이 다른 환승(벡스코(시립미술관) 2호선 ↔ 벡스코 동해선)도 양방향 edge 가 있다', () {
      final a = nodeOf('벡스코(시립미술관)', '2');
      final b = nodeOf('벡스코', '동해');
      expect(hasTransfer(a, b), isTrue);
      expect(hasTransfer(b, a), isTrue);
      final edge = graph.getNeighbors(a).firstWhere((e) => e.toNodeId == b);
      expect(edge.transferWalkSeconds, 360,
          reason: 'connections.json 환승 연결의 travelTimeSeconds 가 도보시간');
    });

    test('동명이역(좌천 1호선/동해선, 동해선 동래)은 환승 edge 로 묶이지 않는다', () {
      expect(hasTransfer(nodeOf('좌천', '1'), nodeOf('좌천', '동해')), isFalse);
      expect(hasTransfer(nodeOf('좌천', '동해'), nodeOf('좌천', '1')), isFalse);
      for (final other in ['1', '4']) {
        expect(hasTransfer(nodeOf('동래', other), nodeOf('동래', '동해')), isFalse,
            reason: '동래 $other↔동해');
        expect(hasTransfer(nodeOf('동래', '동해'), nodeOf('동래', other)), isFalse,
            reason: '동래 동해↔$other');
      }
    });

    test('환승 edge 의 총 쌍 수: 같은 이름 11 + 이름 다른 1 = 12 쌍(양방향 24 edge)', () {
      var transferEdges = 0;
      for (final id in graph.nodes.keys) {
        transferEdges += graph.getNeighbors(id).where((e) => e.isTransfer).length;
      }
      expect(transferEdges, 24);
    });
  });

  group('대표 경로 탐색', () {
    test('벡스코 환승 경유: 센텀시티(2호선) → 센텀(동해선)은 벡스코에서 환승 1회', () {
      final result = ShortestPathFinder(graph: graph).findShortestPath(
        nodeOf('센텀시티', '2'),
        nodeOf('센텀', '동해'),
      );
      expect(result, isNotNull);
      expect(result!.edges.where((e) => e.isTransfer).length, 1);
      expect(
        labelsOf(result),
        containsAllInOrder(['벡스코(시립미술관)(2)', '벡스코(동해)', '센텀(동해)']),
        reason: describe(result.nodeIds),
      );
    });

    test('1호선 다대포해수욕장 → 김해 가야대는 서면(1→2)·사상(2→부산김해) 환승 2회', () {
      final result = ShortestPathFinder(graph: graph).findShortestPath(
        nodeOf('다대포해수욕장', '1'),
        nodeOf('가야대', '부산김해'),
      );
      expect(result, isNotNull);
      expect(result!.edges.where((e) => e.isTransfer).length, 2,
          reason: describe(result.nodeIds));
      expect(labelsOf(result),
          containsAllInOrder(['서면(1)', '서면(2)', '사상(2)', '사상(부산김해)']),
          reason: describe(result.nodeIds));
    });

    test('같은 노선 안에서는 환승 0회 (1호선 다대포해수욕장 → 노포)', () {
      final result = ShortestPathFinder(graph: graph).findShortestPath(
        nodeOf('다대포해수욕장', '1'),
        nodeOf('노포', '1'),
      );
      expect(result, isNotNull);
      expect(result!.edges.where((e) => e.isTransfer), isEmpty);
      expect(result.nodeIds.length, 40);
    });
  });
}
