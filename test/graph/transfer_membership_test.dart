@Tags(['integration'])
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/graph/shortest_path.dart';
import 'package:seoul_subway/graph/subway_graph.dart';

/// 노선 소속 보강(신설동/성신여대입구/보문/김포공항/신내) 회귀 테스트.
///
/// 실제 assets/json 데이터를 로드해 그래프를 구성하고, 보강된 환승이
/// (1) Station 레코드로 존재하고 (2) 환승 edge 로 그래프에 반영되며
/// (3) 실제 최단경로 탐색으로 통과 가능한지 검증한다.
void main() {
  late List<Station> stations;
  late List<Connection> connections;
  late Map<String, int> transferTimes;
  late SubwayGraph graph;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final stationsJson =
        await rootBundle.loadString('assets/json/stations.json');
    stations = (jsonDecode(stationsJson) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();

    final connectionsJson =
        await rootBundle.loadString('assets/json/connections.json');
    connections = (jsonDecode(connectionsJson) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();

    final transferJson =
        await rootBundle.loadString('assets/json/transfer_times.json');
    transferTimes = (jsonDecode(transferJson) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));

    graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );
  });

  // 보강된 (name, lineId) Station 레코드가 존재해야 한다.
  final requiredVariants = <(String, String)>[
    ('신설동', '1'), ('신설동', '2'), ('신설동', '우이신설'),
    ('성신여대입구', '4'), ('성신여대입구', '우이신설'),
    ('보문', '6'), ('보문', '우이신설'),
    ('김포공항', '5'), ('김포공항', '9'), ('김포공항', '공항철도'),
    ('김포공항', '김포골드'), ('김포공항', '서해'),
    ('신내', '6'), ('신내', '경춘'),
  ];

  test('보강된 모든 (역명, 노선) Station 레코드가 존재한다', () {
    for (final (name, line) in requiredVariants) {
      final found = stations.any(
        (s) => s.name == name && s.lineId == line && s.isTransfer,
      );
      expect(found, isTrue,
          reason: '$name($line) Station 레코드(isTransfer=true) 누락');
    }
  });

  // 그래프에 환승 edge 로 반영되어야 하는 노선쌍.
  final requiredTransfers = <(String, String, String)>[
    ('신설동', '1', '우이신설'),
    ('신설동', '2', '우이신설'),
    ('신설동', '1', '2'),
    ('성신여대입구', '4', '우이신설'),
    ('보문', '6', '우이신설'),
    ('신내', '6', '경춘'),
    ('김포공항', '5', '김포골드'),
    ('김포공항', '공항철도', '서해'),
  ];

  bool hasTransferEdge(String fromNode, String toNode) {
    return graph
        .getNeighbors(fromNode)
        .any((e) => e.toNodeId == toNode && e.isTransfer);
  }

  test('보강된 환승쌍이 그래프에 transfer edge 로 존재한다', () {
    String node(String name, String line) {
      final s = stations.firstWhere((s) => s.name == name && s.lineId == line);
      return '${s.id}_${s.lineId}';
    }

    for (final (name, a, b) in requiredTransfers) {
      final na = node(name, a);
      final nb = node(name, b);
      expect(hasTransferEdge(na, nb), isTrue,
          reason: '$name: $a↔$b 환승 edge 없음 ($na→$nb)');
      expect(hasTransferEdge(nb, na), isTrue,
          reason: '$name: $b↔$a 환승 edge 없음 ($nb→$na)');
    }
  });

  test('보강 환승을 통과하는 실제 최단경로가 존재한다', () {
    final finder = ShortestPathFinder(graph: graph);

    String node(String name, String line) {
      final s = stations.firstWhere((s) => s.name == name && s.lineId == line);
      return '${s.id}_${s.lineId}';
    }

    // 각 케이스: 환승을 강제하는 출발/도착 (서로 다른 노선의 인접 종착권 역)
    final cases = <(String, String, String, String, String)>[
      // 신내(6↔경춘): 봉화산(6) → 갈매(경춘) 은 신내 환승을 반드시 경유
      ('봉화산', '6', '갈매', '경춘', '신내'),
      // 성신여대입구(4↔우이신설): 한성대입구(4) → 정릉(우이신설)
      ('한성대입구', '4', '정릉', '우이신설', '성신여대입구'),
      // 보문(6↔우이신설): 안암(6) → 정릉(우이신설)
      ('안암', '6', '정릉', '우이신설', '보문'),
      // 김포공항(9↔김포골드): 개화(9) → 고촌(김포골드)
      ('개화', '9', '고촌', '김포골드', '김포공항'),
      // 김포공항(5↔서해): 방화(5) → 원종(서해)
      ('방화', '5', '원종', '서해', '김포공항'),
      // 신설동(1↔우이신설): 제기동(1) → 정릉(우이신설)
      ('제기동', '1', '정릉', '우이신설', '신설동'),
    ];

    for (final (fromName, fromLine, toName, toLine, via) in cases) {
      final result = finder.findShortestPath(
        node(fromName, fromLine),
        node(toName, toLine),
      );
      expect(result, isNotNull,
          reason: '$fromName($fromLine) → $toName($toLine) 경로 없음 (via $via)');

      // 경유 노드에 via 역이 포함되는지 확인
      final nodeNames = result!.nodeIds.map((id) {
        final s = stations.firstWhere(
          (s) => '${s.id}_${s.lineId}' == id || '${s.id}_${s.lineId}E' == id,
          orElse: () => const Station(
              id: '?', name: '?', lineId: '?', latitude: 0, longitude: 0),
        );
        return s.name;
      }).toSet();
      expect(nodeNames.contains(via), isTrue,
          reason: '$fromName → $toName 경로가 $via 를 경유하지 않음: $nodeNames');
    }
  });
}
