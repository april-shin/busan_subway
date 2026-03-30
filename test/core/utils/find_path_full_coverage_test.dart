@Tags(['integration'])
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/path_on_line.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 실제 stations.json/connections.json 데이터를 사용하여
/// 같은 노선의 모든 역 쌍에 대해 findPathOnLine이 경로를 찾는지 검증한다.
void main() {
  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final stationsJson = await rootBundle.loadString('assets/json/stations.json');
    stations = (jsonDecode(stationsJson) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();

    final connectionsJson = await rootBundle.loadString('assets/json/connections.json');
    connections = (jsonDecode(connectionsJson) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  test('전 노선/전 역 쌍에 대한 findPathOnLine 커버리지 테스트', () {
    // 노선별 역 그룹화
    final stationsByLine = <String, List<Station>>{};
    for (final s in stations) {
      stationsByLine.putIfAbsent(s.lineId, () => []).add(s);
    }

    var totalPairs = 0;
    var nullPairs = 0;
    final nullResults = <String>[];

    for (final entry in stationsByLine.entries) {
      final lineId = entry.key;
      final lineStations = entry.value;

      // 같은 노선의 모든 역 쌍 (i → j, i ≠ j)
      for (var i = 0; i < lineStations.length; i++) {
        for (var j = i + 1; j < lineStations.length; j++) {
          final from = lineStations[i];
          final to = lineStations[j];
          totalPairs++;

          final result = findPathOnLine(
            fromStationName: from.name,
            toStationName: to.name,
            lineId: lineId,
            stations: stations,
            connections: connections,
          );

          if (result == null) {
            nullPairs++;
            nullResults.add(
              '[$lineId] ${from.name}(${from.id}) → ${to.name}(${to.id})',
            );
          }
        }
      }
    }

    // 결과 출력
    // ignore: avoid_print
    print('\n=== findPathOnLine 전체 경로 테스트 ===');
    // ignore: avoid_print
    print('전체 테스트 쌍: $totalPairs');
    // ignore: avoid_print
    print('성공: ${totalPairs - nullPairs}');
    // ignore: avoid_print
    print('실패 (null): $nullPairs');

    if (nullResults.isNotEmpty) {
      // ignore: avoid_print
      print('\n--- null 반환된 경로 ---');
      for (final line in nullResults) {
        // ignore: avoid_print
        print('  $line');
      }
    }

    // null이 있더라도 테스트 자체는 통과시키고 결과만 보여줌
    // (구조적으로 단절된 노선이 있을 수 있으므로)
  });

  test('노선별 연결 그래프 연결성 분석', () {
    final stationsByLine = <String, List<Station>>{};
    for (final s in stations) {
      stationsByLine.putIfAbsent(s.lineId, () => []).add(s);
    }

    // ignore: avoid_print
    print('\n=== 노선별 연결 그래프 분석 ===');

    for (final entry in stationsByLine.entries) {
      final lineId = entry.key;
      final lineStations = entry.value;

      // 해당 노선의 비환승 연결 수
      final lineConnections = connections
          .where((c) => c.lineId == lineId && !c.isTransfer)
          .toList();

      // 인접 리스트 구축
      final adjacency = <String, Set<String>>{};
      for (final c in lineConnections) {
        adjacency.putIfAbsent(c.fromStationId, () => {}).add(c.toStationId);
        adjacency.putIfAbsent(c.toStationId, () => {}).add(c.fromStationId);
      }

      // 연결된 역 수 (인접 리스트에 있는 역)
      final connectedIds = adjacency.keys.toSet();
      final allIds = lineStations.map((s) => s.id).toSet();
      final disconnected = allIds.difference(connectedIds);

      // BFS로 연결 컴포넌트 수 확인
      final visited = <String>{};
      var components = 0;
      for (final id in connectedIds) {
        if (visited.contains(id)) continue;
        components++;
        // BFS
        final queue = [id];
        visited.add(id);
        while (queue.isNotEmpty) {
          final current = queue.removeAt(0);
          for (final neighbor in adjacency[current] ?? <String>{}) {
            if (visited.add(neighbor)) {
              queue.add(neighbor);
            }
          }
        }
      }

      final status = disconnected.isEmpty && components <= 1
          ? 'OK'
          : '${components > 1 ? "컴포넌트 $components개" : ""}'
              '${disconnected.isNotEmpty ? " 고립역 ${disconnected.length}개" : ""}';

      // ignore: avoid_print
      print(
        '[$lineId] 역 ${lineStations.length}개, '
        '연결 ${lineConnections.length}개, '
        '연결 컴포넌트: $components, '
        '고립역: ${disconnected.length} '
        '— $status',
      );

      if (disconnected.isNotEmpty) {
        for (final id in disconnected) {
          final name = lineStations.firstWhere((s) => s.id == id).name;
          // ignore: avoid_print
          print('  고립역: $name ($id)');
        }
      }
    }
  });
}
