// 전 노선 방향 판정 단조성 가드.
//
// `isDownDirection` 은 세그먼트의 **첫 두 역**으로 방향을 정한다. 부산 노선은 전부
// 지선·순환 없는 단순 선형이고 "역 ID 증가 = 하행" 한 규칙이다. 따라서 어느 역에서든
// 같은 방향 이웃은 최대 1개여야 하고(분기역 예외 없음), lines.json 의 stationIds
// 순서와 isDownBetween 이 어긋나서는 안 된다.
//
// 새 역·연장 구간을 추가했을 때 이 테스트가 깨지면 역 번호가 물리 순서와 어긋났거나
// 분기가 생긴 것이다 — 번호 체계를 먼저 점검한다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/line_direction.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;
  late List<Map<String, dynamic>> lines;

  setUpAll(() async {
    stations = (jsonDecode(
                await rootBundle.loadString('assets/json/stations.json'))
            as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    connections = (jsonDecode(
                await rootBundle.loadString('assets/json/connections.json'))
            as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
    lines = (jsonDecode(await rootBundle.loadString('assets/json/lines.json'))
            as List)
        .cast<Map<String, dynamic>>();
  });

  test('모든 노선에서 인접역 방향 판정이 단조다 (같은 방향 이웃은 최대 1개)', () {
    final names = {for (final s in stations) '${s.lineId}|${s.id}': s.name};

    final adjacency = <String, Map<String, List<String>>>{};
    for (final c in connections) {
      if (c.isTransfer) continue;
      final line = adjacency.putIfAbsent(c.lineId, () => {});
      line.putIfAbsent(c.fromStationId, () => []).add(c.toStationId);
      line.putIfAbsent(c.toStationId, () => []).add(c.fromStationId);
    }

    final violations = <String>[];
    for (final entry in adjacency.entries) {
      final lineId = entry.key;
      for (final node in entry.value.entries) {
        final stationId = node.key;
        final down = <String>[];
        final up = <String>[];
        for (final other in node.value) {
          (isDownBetween(stationId, other, lineId) ? down : up).add(other);
        }
        if (down.length < 2 && up.length < 2) continue;
        String label(String id) => '$id(${names['$lineId|$id'] ?? '?'})';
        final side = down.length >= 2 ? down : up;
        violations.add(
          '[$lineId] ${label(stationId)} 의 같은 방향 이웃이 '
          '${side.map(label).join(', ')} 로 둘 이상이다',
        );
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('lines.json stationIds 체인을 따라 하행이 일관되고 역방향은 상행이다', () {
    expect(lines, isNotEmpty);
    for (final l in lines) {
      final lineId = l['id'] as String;
      final ids = (l['stationIds'] as List).cast<String>();
      for (var i = 0; i + 1 < ids.length; i++) {
        expect(isDownBetween(ids[i], ids[i + 1], lineId), isTrue,
            reason: '[$lineId] ${ids[i]} → ${ids[i + 1]} 은 하행이어야 한다');
        expect(isDownBetween(ids[i + 1], ids[i], lineId), isFalse,
            reason: '[$lineId] ${ids[i + 1]} → ${ids[i]} 은 상행이어야 한다');
      }
    }
  });

  test('가상 급행 노선({base}E) 은 base 규칙으로 정규화된다', () {
    expect(isDownBetween('305', '306', '3E'), isTrue);
    expect(isDownBetween('306', '305', '3E'), isFalse);
  });
}
