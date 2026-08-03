@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/graph/shortest_path.dart';
import 'package:seoul_subway/graph/subway_graph.dart';

/// 서해선 보수(누락 8역 신설·엣지 보수) 최단경로 회귀 테스트.
///
/// 실제 assets/json 데이터로 그래프를 구성해
/// (1) 김포공항→능곡 1구간 직결 (제보 재현),
/// (2) 일산→원시 전 구간 주파,
/// (3) 신설 환승역(소사 1↔서해 등)의 환승 edge 성립
/// 을 검증한다. 패턴은 `transfer_membership_test.dart` 를 따른다.
void main() {
  late List<Station> stations;
  late SubwayGraph graph;
  late ShortestPathFinder finder;

  String node(String name, String line) {
    final s = stations.firstWhere((s) => s.name == name && s.lineId == line);
    return '${s.id}_${s.lineId}';
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    stations = ((jsonDecode(
                await rootBundle.loadString('assets/json/stations.json')))
            as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();

    final connections = ((jsonDecode(
                await rootBundle.loadString('assets/json/connections.json')))
            as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();

    final transferTimes = (jsonDecode(await rootBundle
            .loadString('assets/json/transfer_times.json'))
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));

    graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );
    finder = ShortestPathFinder(graph: graph);
  });

  test('김포공항 → 능곡 은 서해선 1구간 직결이다 (제보 재현 가드)', () {
    final result = finder.findShortestPath(
      node('김포공항', '서해'),
      node('능곡', '서해'),
    );
    expect(result, isNotNull, reason: '김포공항(서해) → 능곡(서해) 경로 없음');
    expect(result!.nodeIds, ['H12_서해', 'H17_서해'],
        reason: '중간역 없는 1구간 직결이어야 한다');
  });

  test('일산 → 원시 전 구간이 서해선 20역으로 주파된다', () {
    final result = finder.findShortestPath(
      node('일산', '서해'),
      node('원시', '서해'),
    );
    expect(result, isNotNull, reason: '일산(서해) → 원시(서해) 경로 없음');
    // 전 구간이 서해선 위에 있어야 한다 (환승으로 새는 쪽이 더 느리다).
    expect(result!.nodeIds.length, 20);
    expect(result.nodeIds.every((id) => id.endsWith('_서해')), isTrue,
        reason: '경로가 서해선을 벗어났다: ${result.nodeIds}');
    // 신설·기존 구간 이음매가 모두 포함되는지 대표 역으로 확인.
    for (final expected in ['H16_서해', 'H12_서해', 'H19_서해', 'H20_서해']) {
      expect(result.nodeIds, contains(expected),
          reason: '경로에 $expected (대곡/김포공항/소사/초지) 가 없다');
    }
  });

  test('신설 환승역의 환승 edge 가 양방향으로 성립한다', () {
    bool hasTransferEdge(String fromNode, String toNode) => graph
        .getNeighbors(fromNode)
        .any((e) => e.toNodeId == toNode && e.isTransfer);

    const pairs = <(String, String, String)>[
      ('소사', '1', '서해'),
      ('부천종합운동장', '7', '서해'),
      ('초지', '4', '서해'),
      ('초지', '수인분당', '서해'),
      ('능곡', '경의중앙', '서해'),
      ('백마', '경의중앙', '서해'),
      ('풍산', '경의중앙', '서해'),
      ('일산', '경의중앙', '서해'),
      ('대곡', '3', '서해'),
      ('대곡', '경의중앙', '서해'),
      ('대곡', 'GTX-A', '서해'),
    ];
    for (final (name, a, b) in pairs) {
      final na = node(name, a);
      final nb = node(name, b);
      expect(hasTransferEdge(na, nb), isTrue,
          reason: '$name: $a↔$b 환승 edge 없음 ($na→$nb)');
      expect(hasTransferEdge(nb, na), isTrue,
          reason: '$name: $b↔$a 환승 edge 없음 ($nb→$na)');
    }
  });

  test('소사 1호선 → 서해선 환승 경로가 성립한다', () {
    // 부천(1) → 시흥대야(서해) 는 소사 1↔서해 환승을 반드시 경유한다.
    final result = finder.findShortestPath(
      node('부천', '1'),
      node('시흥대야', '서해'),
    );
    expect(result, isNotNull, reason: '부천(1) → 시흥대야(서해) 경로 없음');
    expect(result!.nodeIds, contains('148_1'),
        reason: '경로가 소사(1호선) 를 경유하지 않는다');
    expect(result.nodeIds, contains('H19_서해'),
        reason: '경로가 소사(서해선) 를 경유하지 않는다');
  });
}
