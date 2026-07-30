// GTX-A 서울역~수서 미개통 구간 회귀 가드.
//
// GTX-A 는 삼성역 미완공으로 **두 구간이 분리 운행**된다.
//   - 북부: 운정중앙(G01) ↔ 서울역(G05)  — 전 열차 서울역 종착
//   - 남부: 수서(G06) ↔ 동탄(G09)        — 전 열차 수서 종착
// 근거(2026-07-30 실측):
//   - 실시간 도착 API: 서울역의 GTX 열차는 bstatnNm 이 "운정중앙" 또는 "서울역"뿐,
//     수서의 GTX 열차는 "수서" 또는 "동탄"뿐. 두 구간을 관통하는 열차가 없다.
//   - line_schedules.json: 서울역(G05) 하행·수서(G06) 상행 시간표가 null,
//     북부 141편/일 vs 남부 60편/일로 편성 자체가 분리.
//
// 자동 생성된 인접 연결(G05→G06)이 남아 있으면 존재하지 않는 열차로 서울역~수서를
// 5분에 관통하는 경로가 최단으로 뽑힌다(회귀 당시 연신내→수서 10.5분, 실제 3호선 70분).
// 삼성역 개통 시에는 이 테스트와 tool/generate_station_data.dart 의 제거 로직을 함께
// 되돌리고 삼성역을 GTX-A 역 목록에 추가한다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/path_on_line.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/local/timetable_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/usecases/search_route.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
    final connectionsJson =
        await rootBundle.loadString('assets/json/connections.json');
    connections = (jsonDecode(connectionsJson) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();

    final stationsJson =
        await rootBundle.loadString('assets/json/stations.json');
    stations = (jsonDecode(stationsJson) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  test('connections.json 에 서울역(G05)↔수서(G06) GTX-A 연결이 없다', () {
    final gap = connections.where((c) =>
        c.lineId == 'GTX-A' &&
        ((c.fromStationId == 'G05' && c.toStationId == 'G06') ||
            (c.fromStationId == 'G06' && c.toStationId == 'G05')));
    expect(gap, isEmpty, reason: 'GTX-A 서울역~수서는 미개통 구간이다');
  });

  test('GTX-A 는 서울역/수서를 경계로 두 컴포넌트로 분리되고, 각 구간 내부는 온전히 연결된다', () {
    final adjacency = <String, Set<String>>{};
    for (final c in connections) {
      if (c.lineId != 'GTX-A' || c.isTransfer) continue;
      adjacency.putIfAbsent(c.fromStationId, () => {}).add(c.toStationId);
      adjacency.putIfAbsent(c.toStationId, () => {}).add(c.fromStationId);
    }

    Set<String> componentOf(String start) {
      final visited = {start};
      final queue = [start];
      while (queue.isNotEmpty) {
        for (final n in adjacency[queue.removeAt(0)] ?? const <String>{}) {
          if (visited.add(n)) queue.add(n);
        }
      }
      return visited;
    }

    expect(componentOf('G01'), {'G01', 'G02', 'G03', 'G04', 'G05'});
    expect(componentOf('G09'), {'G06', 'G07', 'G08', 'G09'});
  });

  test('실시간 열차 경로 탐색(findPathOnLine)이 미개통 구간을 관통하지 않는다', () {
    // 미개통 구간을 넘는 조회는 null (지도 위 유령 열차 방지).
    for (final pair in [
      ('서울역', '수서'),
      ('연신내', '동탄'),
      ('킨텍스', '성남'),
    ]) {
      expect(
        findPathOnLine(
          fromStationName: pair.$1,
          toStationName: pair.$2,
          lineId: 'GTX-A',
          stations: stations,
          connections: connections,
        ),
        isNull,
        reason: '${pair.$1}→${pair.$2} 는 GTX-A 미개통 구간을 지난다',
      );
    }

    // 각 구간 내부 조회는 정상 동작해야 한다.
    for (final pair in [
      ('운정중앙', '서울역'),
      ('수서', '동탄'),
    ]) {
      expect(
        findPathOnLine(
          fromStationName: pair.$1,
          toStationName: pair.$2,
          lineId: 'GTX-A',
          stations: stations,
          connections: connections,
        ),
        isNotNull,
        reason: '${pair.$1}→${pair.$2} 는 개통 구간이다',
      );
    }
  });

  test('경로 검색이 GTX-A 로 서울역~수서를 관통하지 않는다', () async {
    final repo = StationRepositoryImpl(localDataSource: LocalDataSource());
    final search = SearchRoute(
      stationRepository: repo,
      timetableDataSource: TimetableDataSource(),
    );

    // 회귀 당시 GTX-A 단독 세그먼트로 뽑혔던 조합들.
    for (final pair in [('G05', 'G06'), ('G04', 'G09'), ('G02', 'G07')]) {
      final result = await search.execute(pair.$1, pair.$2);
      expect(result, isNotNull);

      for (final seg in result!.segments) {
        if (seg.lineId != 'GTX-A') continue;
        final ids = seg.stations.map((s) => s.id).toList();
        for (var i = 0; i < ids.length - 1; i++) {
          final edge = {ids[i], ids[i + 1]};
          expect(edge, isNot({'G05', 'G06'}),
              reason: '${pair.$1}→${pair.$2} 경로가 미개통 구간(서울역~수서)을 사용했다');
        }
      }
    }
  });
}
