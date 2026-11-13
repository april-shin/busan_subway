@Tags(['integration'])
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/graph/graph_builder.dart';
import 'package:busan_subway/graph/shortest_path.dart';
import 'package:busan_subway/graph/subway_graph.dart';

/// 환승 소속·환승시간 키 완비 검증 (부산).
///
/// 실제 assets/json 데이터를 로드해
/// (1) `isTransfer` 역의 `transferLines` 가 자기 노선을 포함하고 소속 노선마다 실제
///     Station 레코드가 있으며(이름이 달라도 connections 의 환승 연결로 이어짐),
/// (2) 같은 이름 환승 쌍마다 `transfer_times.json` 키(`{역명}_{노선1}_{노선2}`)가 있고
///     모르는(고아) 키가 없으며,
/// (3) 환승을 강제하는 실제 최단경로가 존재하는지 확인한다.
void main() {
  late List<Station> stations;
  late List<Connection> connections;
  late Map<String, int> transferTimes;
  late SubwayGraph graph;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    stations = (jsonDecode(
            await rootBundle.loadString('assets/json/stations.json')) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    connections = (jsonDecode(
            await rootBundle.loadString('assets/json/connections.json')) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
    transferTimes = (jsonDecode(
            await rootBundle.loadString('assets/json/transfer_times.json'))
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));

    graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );
  });

  String node(String name, String line) {
    final s = stations.firstWhere((s) => s.name == name && s.lineId == line);
    return '${s.id}_${s.lineId}';
  }

  test('isTransfer 역의 transferLines 는 자기 노선을 포함하고 2개 이상이다', () {
    final transferStations = stations.where((s) => s.isTransfer).toList();
    expect(transferStations, hasLength(24), reason: '환승 레코드 24건(12쌍)');
    for (final s in transferStations) {
      expect(s.transferLines, contains(s.lineId), reason: '${s.name}(${s.lineId})');
      expect(s.transferLines.length, greaterThanOrEqualTo(2),
          reason: '${s.name}(${s.lineId})');
    }
  });

  test('비환승 역은 transferLines 가 자기 노선 하나뿐이다', () {
    for (final s in stations.where((s) => !s.isTransfer)) {
      expect(s.transferLines, [s.lineId], reason: '${s.name}(${s.lineId})');
    }
  });

  test('transferLines 의 각 노선에 대응하는 환승 레코드가 있다 (이름이 달라도)', () {
    final byId = {for (final s in stations) s.id: s};
    for (final s in stations.where((s) => s.isTransfer)) {
      for (final line in s.transferLines.where((l) => l != s.lineId)) {
        final sameName = stations.any(
            (o) => o.name == s.name && o.lineId == line && o.isTransfer);
        // 이름이 다른 환승(벡스코)은 connections 의 isTransfer 연결로 이어진다.
        final viaConnection = connections.any((c) =>
            c.isTransfer &&
            c.fromStationId == s.id &&
            byId[c.toStationId]?.lineId == line);
        expect(sameName || viaConnection, isTrue,
            reason: '${s.name}(${s.lineId}) 의 환승 노선 $line 레코드 없음');
      }
    }
  });

  test('같은 이름 환승 쌍마다 transfer_times 키가 있고 양수다', () {
    final byName = <String, List<Station>>{};
    for (final s in stations.where((s) => s.isTransfer)) {
      byName.putIfAbsent(s.name, () => []).add(s);
    }
    var pairs = 0;
    for (final entry in byName.entries) {
      final v = entry.value;
      for (var i = 0; i < v.length; i++) {
        for (var j = i + 1; j < v.length; j++) {
          pairs++;
          final k1 = '${entry.key}_${v[i].lineId}_${v[j].lineId}';
          final k2 = '${entry.key}_${v[j].lineId}_${v[i].lineId}';
          final t = transferTimes[k1] ?? transferTimes[k2];
          expect(t, isNotNull, reason: '환승시간 키 없음: $k1');
          expect(t!, greaterThan(0), reason: k1);
        }
      }
    }
    expect(pairs, 11);
    expect(transferTimes, hasLength(11), reason: '고아 키 없음 — 쌍 수와 키 수가 같아야 한다');
  });

  test('transfer_times 의 모든 키는 실제 환승 쌍에 대응한다', () {
    for (final key in transferTimes.keys) {
      final parts = key.split('_');
      expect(parts, hasLength(3), reason: key);
      final (name, a, b) = (parts[0], parts[1], parts[2]);
      final ok = stations.any((s) => s.name == name && s.lineId == a && s.isTransfer) &&
          stations.any((s) => s.name == name && s.lineId == b && s.isTransfer);
      expect(ok, isTrue, reason: '$key 에 해당하는 환승 레코드 없음');
    }
  });

  test('환승 edge 의 도보시간은 transfer_times 값이다 (서면 1↔2 = 360)', () {
    final e = graph
        .getNeighbors(node('서면', '1'))
        .firstWhere((e) => e.toNodeId == node('서면', '2'));
    expect(e.transferWalkSeconds, transferTimes['서면_1_2']);
    expect(e.transferWalkSeconds, 360);
  });

  test('환승을 강제하는 실제 최단경로가 환승역을 경유한다', () {
    final finder = ShortestPathFinder(graph: graph);

    // (출발, 출발노선, 도착, 도착노선, 경유 환승역)
    final cases = <(String, String, String, String, String)>[
      ('다대포해수욕장', '1', '장산', '2', '서면'),
      ('노포', '1', '태화강', '동해', '교대'),
      ('양산', '2', '대저', '3', '덕천'),
      ('안평', '4', '수영', '3', '미남'),
      ('가야대', '부산김해', '구포', '3', '대저'),
      ('센텀시티', '2', '일광', '동해', '벡스코'),
    ];

    for (final (fromName, fromLine, toName, toLine, via) in cases) {
      final result = finder.findShortestPath(
        node(fromName, fromLine),
        node(toName, toLine),
      );
      expect(result, isNotNull,
          reason: '$fromName($fromLine) → $toName($toLine) 경로 없음 (via $via)');
      final names = result!.nodeIds
          .map((id) => graph.getNode(id)?.stationName ?? id)
          .toList();
      expect(names.any((n) => n == via || n.startsWith(via)), isTrue,
          reason: '$fromName → $toName 경로가 $via 를 경유하지 않음: $names');
    }
  });
}
