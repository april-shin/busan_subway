// 경강선(판교~여주) 독립 노선 회귀 가드.
//
// 2026-07-30 까지 경강선은 별개 노선이 아니라 lineId='경춘' 의 C25~C33(삼동~여주)
// 으로 접혀 있었고, 실제 정차역인 판교·성남·이매 3역은 아예 빠져 있었다. 그 상태의
// 증상:
//   1) 삼동~여주 9개 역이 **경로 탐색에서 완전히 도달 불가**. 유일한 연결 시도였던
//      이매(B19)↔삼동(C25) 수기 환승 connection 은 `GraphBuilder._addConnectionEdges`
//      가 `isTransfer` 라 건너뛰고, 환승 edge 는 `_addTransferEdges` 가 **역명 일치**
//      로만 만들기 때문에(이매≠삼동) 어떤 edge 도 생성되지 않았다.
//   2) UI 가 이천·여주 등을 경춘선 초록(#0C8E72)·"경춘선" 으로 표시.
//   3) `subwayIdToLineId['1081']` 이 '에버라인' 으로 잘못 매핑돼 경강선 실시간
//      도착·열차위치가 에버라인으로 흘러갔다(1081 은 경강선. 실측 근거는
//      `subway_id_mapping.dart` 주석 참조).
//
// 방향 규칙: 앱 일반규칙(ID 증가 = 하행)이 API 라벨과 일치한다 —
// `realtimeStationArrival` 이천 응답에서 "여주행"=하행, "판교행"=상행.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/constants/line_colors.dart';
import 'package:seoul_subway/core/constants/subway_id_mapping.dart';
import 'package:seoul_subway/core/utils/headway_estimator.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/local/timetable_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/graph/shortest_path.dart';

/// 경강선 정차역 — 판교(GG01) → 여주(GG12) 순서.
const _gyeonggangOrder = [
  ('GG01', '판교'),
  ('GG02', '성남'),
  ('GG03', '이매'),
  ('GG04', '삼동'),
  ('GG05', '경기광주'),
  ('GG06', '초월'),
  ('GG07', '곤지암'),
  ('GG08', '신둔도예촌'),
  ('GG09', '이천'),
  ('GG10', '부발'),
  ('GG11', '세종대왕릉'),
  ('GG12', '여주'),
];

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

  test('경강선 12개역이 판교~여주 순서로 등록되어 있다', () {
    final line = lines.firstWhere((l) => l['id'] == '경강');
    expect(line['name'], '경강선');
    expect(line['stationIds'],
        _gyeonggangOrder.map((e) => e.$1).toList());

    final byId = {for (final s in stations) s.id: s};
    for (final (id, name) in _gyeonggangOrder) {
      expect(byId[id]?.name, name, reason: '$id 는 $name 이어야 한다');
      expect(byId[id]?.lineId, '경강');
    }
  });

  test('경춘선에는 경강선 역이 섞여 있지 않다 (청량리~춘천 24역)', () {
    final line = lines.firstWhere((l) => l['id'] == '경춘');
    expect(line['stationIds'],
        [for (var i = 1; i <= 24; i++) 'C${i.toString().padLeft(2, '0')}']);

    // 구 매핑의 잔재(C25~C33)가 어떤 데이터에도 남아 있지 않아야 한다.
    for (var i = 25; i <= 33; i++) {
      final legacyId = 'C$i';
      expect(stations.where((s) => s.id == legacyId), isEmpty,
          reason: '$legacyId 는 경강선으로 이전됐다');
      expect(
        connections.where((c) =>
            c.fromStationId == legacyId || c.toStationId == legacyId),
        isEmpty,
        reason: '$legacyId 를 참조하는 연결이 남아 있다',
      );
    }
  });

  test('경강선 전 구간이 하나로 연결되어 있다', () {
    final adjacency = <String, Set<String>>{};
    for (final c in connections) {
      if (c.lineId != '경강' || c.isTransfer) continue;
      adjacency.putIfAbsent(c.fromStationId, () => {}).add(c.toStationId);
      adjacency.putIfAbsent(c.toStationId, () => {}).add(c.fromStationId);
    }
    final visited = {'GG01'};
    final queue = ['GG01'];
    while (queue.isNotEmpty) {
      for (final n in adjacency[queue.removeAt(0)] ?? const <String>{}) {
        if (visited.add(n)) queue.add(n);
      }
    }
    expect(visited, _gyeonggangOrder.map((e) => e.$1).toSet());
  });

  test('경강선 소요시간이 getTrainSch 실측값이다', () {
    // `다음역 trainArvlTm − 현재역 trainDptreTm` (dwell 제외 = 앱 규약).
    // 평일 상·하행 전 편성(n=61, 부발 이후 46)에서 상하행 대칭·편차 0.
    // 회귀 당시엔 생성기의 좌표거리 추정값(전 구간 300초)이 들어 있었다.
    const expected = {
      ('GG01', 'GG02'): 120, // 판교→성남
      ('GG02', 'GG03'): 90, //  성남→이매
      ('GG03', 'GG04'): 300, // 이매→삼동
      ('GG04', 'GG05'): 240, // 삼동→경기광주
      ('GG05', 'GG06'): 240, // 경기광주→초월
      ('GG06', 'GG07'): 240, // 초월→곤지암
      ('GG07', 'GG08'): 300, // 곤지암→신둔도예촌
      ('GG08', 'GG09'): 330, // 신둔도예촌→이천
      ('GG09', 'GG10'): 210, // 이천→부발
      ('GG10', 'GG11'): 360, // 부발→세종대왕릉
      ('GG11', 'GG12'): 270, // 세종대왕릉→여주
    };
    final actual = {
      for (final c in connections)
        if (c.lineId == '경강' && !c.isTransfer)
          (c.fromStationId, c.toStationId): c.travelTimeSeconds,
    };
    expect(actual, expected);
    expect(actual.values.reduce((a, b) => a + b), 2700,
        reason: '판교→여주 주행 합계는 45분이다');
  });

  test('판교·성남·이매는 경강선 환승역이다', () {
    // 환승 edge 는 역명 일치로 생성되므로, 양쪽 노드가 모두 isTransfer 여야 한다.
    const pairs = [
      ('GG01', 'D08', 'SB'),
      ('GG02', 'G07', 'GTX-A'),
      ('GG03', 'B19', '수인분당'),
    ];
    final byId = {for (final s in stations) s.id: s};
    for (final (ggId, otherId, otherLine) in pairs) {
      final gg = byId[ggId]!;
      final other = byId[otherId]!;
      expect(gg.name, other.name, reason: '$ggId 와 $otherId 는 같은 역명이어야 한다');
      expect(gg.isTransfer, isTrue);
      expect(other.isTransfer, isTrue);
      expect(gg.transferLines, containsAll(['경강', otherLine]));
      expect(other.transferLines, containsAll(['경강', otherLine]));
    }
  });

  test('경강선 방향 규칙: ID 증가 = 하행(여주 방면)', () {
    // API 라벨 기준 — "여주행"=하행, "판교행"=상행.
    expect(isDownBetween('GG01', 'GG12', '경강'), isTrue);
    expect(isDownBetween('GG09', 'GG10', '경강'), isTrue);
    expect(isDownBetween('GG10', 'GG09', '경강'), isFalse);
    expect(isDownBetween('GG12', 'GG01', '경강'), isFalse);
  });

  test('실시간 API subwayId 1081 은 경강선이다', () {
    expect(subwayIdToLineId['1081'], '경강');
    expect(subwayIdToLineId.values, isNot(contains('에버라인')),
        reason: '에버라인은 서울 실시간 API 미제공 노선이다');
  });

  test('경강선 색·이름이 등록되어 있다', () {
    expect(lineNames['경강'], '경강선');
    // SVG data-line="KK" stroke 색과 동일해야 지도와 UI 색이 일치한다.
    expect(lineColorFor('경강').toARGB32(), 0xFF004EA7);
    expect(lineColorFor('경강'), isNot(lineColorFor('경춘')));
  });

  test('경강선 시간표가 별도 노선으로 분리되어 있다', () async {
    final schedules = await TimetableDataSource().loadSchedules();
    expect(schedules.containsKey('경강'), isTrue);

    // stationDepartures 는 방향별 맵이다(weekday=상행, weekdayDown=하행).
    // 상행 종점 판교(GG01)와 하행 종점 여주(GG12)는 각각 해당 방향 출발이 없다.
    final up = schedules['경강']!.weekday.stationDepartures;
    final down = schedules['경강']!.weekdayDown?.stationDepartures;
    expect(up, isNotNull);
    expect(down, isNotNull);
    for (final (id, name) in _gyeonggangOrder) {
      if (id != 'GG01') {
        expect(up!.containsKey(id), isTrue, reason: '$name($id) 상행 시간표 누락');
      }
      if (id != 'GG12') {
        expect(down!.containsKey(id), isTrue, reason: '$name($id) 하행 시간표 누락');
      }
    }
    expect(up!.containsKey('GG01'), isFalse, reason: '판교는 상행 종점이다');
    expect(down!.containsKey('GG12'), isFalse, reason: '여주는 하행 종점이다');

    // 경춘선 시간표에 경강선 역 ID 가 남아 있지 않아야 한다.
    expect(
      schedules['경춘']!.weekday.stationDepartures?.keys
              .where((k) => k.startsWith('GG')) ??
          const <String>[],
      isEmpty,
    );

    // 배차간격이 폴백(3분)이 아닌 실제 값으로 산출되어야 환승 대기시간이 맞는다.
    final headways = buildHeadwayMap(schedules);
    expect(headways['경강'], greaterThan(600),
        reason: '경강선 평시 배차는 20분 내외다');
  });

  test('경강선이 경로 탐색으로 도달 가능하다', () async {
    final repo = StationRepositoryImpl(localDataSource: LocalDataSource());
    final graph = GraphBuilder().build(
      stations: await repo.getAllStations(),
      connections: await repo.getAllConnections(),
      transferTimes: await repo.getTransferTimes(),
      expressSkipEdges: await repo.getExpressSkipEdges(),
      headwaySeconds:
          buildHeadwayMap(await TimetableDataSource().loadSchedules()),
    );
    final finder = ShortestPathFinder(graph: graph);

    // 회귀 당시 이 조합들이 모두 "도달 불가" 였다.
    for (final name in ['삼동', '이천', '여주', '경기광주']) {
      final result = finder.findShortestPathMulti(
        graph.getNodeIdsForStation('강남').toSet(),
        graph.getNodeIdsForStation(name).toSet(),
      );
      expect(result, isNotNull, reason: '강남 → $name 경로를 찾지 못했다');
    }
  });
}
