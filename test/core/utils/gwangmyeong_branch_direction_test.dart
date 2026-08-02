// 1호선 광명 지선(`1A1`) 방향 판정 회귀 가드.
//
// 광명은 금천구청(166)에서 분기하는 단일역 dead-end 지선이고, 물리적으로
// 금천구청보다 남쪽이다(광명 37.4176 < 금천구청 37.4568). 1호선 규칙상
// 남쪽 = 하행이므로 `금천구청 → 광명` 이 하행, `광명 → 금천구청` 이 상행이다.
//
// 2026-08-01 이전에는 이 판정이 **양방향 모두 뒤집혀** 있었다. 원인은
// `_parseNumericId('1A1')` 이 뒤쪽 숫자만 뽑아 `1` 을 반환하고, 1호선이
// 일반 규칙(`toNum > fromNum` = 하행)을 그대로 타기 때문이다:
//   isDownBetween('1A1','166','1') → 166 > 1  → true  (하행, 실제로는 상행)
//   isDownBetween('166','1A1','1') → 1  > 166 → false (상행, 실제로는 하행)
//
// 증상 세 가지:
//   1) `광명 → 금천구청` 이 하행으로 판정돼 `t['1A1']` 의 하행 슬롯을 조회하는데
//      광명은 하행 종착역이라 그 슬롯이 null 이다 → `buildDepartureCandidates`
//      가 빈 리스트를 반환해 경로 결과 화면의 "출발시각 선택"이 비활성.
//   2) `금천구청 → 광명` 이 상행으로 판정돼 `t['166']` 의 **상행**(청량리 방면)
//      시간표를 조회한다 → 목록은 채워지지만 반대 방향 열차 시각이 나온다.
//   3) `findPreviousStationId(currentId:'1A1', isDown:true)` 가 null 을 반환해
//      광명행 하행 열차의 경로 역방향 확장이 실패한다.
//
// 여기에 더해, rank 를 고쳐도 **세그먼트 방향 판정 기준** 때문에 증상 1이
// 목적지에 따라 남아 있었다. `isDownDirection` 이 세그먼트의 첫/끝 역을 비교했는데
// `광명 → 금천구청 → 독산` 은 rank 가 166.5 → 166 → 167 로 꺾이는 비단조
// 세그먼트라 첫/끝(166.5 vs 167)만 보면 하행이 된다. 실제 탑승 방향은 상행이다.
// → `isDownDirection` 을 **첫 두 역** 기준으로 바꿨다(2호선이 이미 쓰던 방식).
//
// 방향 근거 (데이터가 맞고 판정이 틀렸음을 확정한 실측):
//   - 서울교통공사 SearchSTNTimeTableByIDService (STATION_CD 1750, WEEK_TAG 1):
//     INOUT_TAG=1(상행) 20편 = 광명 → 영등포 (LEFTTIME 채워짐),
//     INOUT_TAG=2(하행) 20편 = 영등포 → 광명 (ARRIVETIME 만 채워짐 = 당역종착).
//     즉 광명 출발은 상행뿐이고, `t['1A1'] = [20편, null]` 은 올바른 데이터다.
//   - 국가철도공단 getTrainSch 캐시(`data/timetables/1_광명_{상행,하행}.json`)도
//     동일: 상행 80행은 광명 출발·영등포 종착, 하행 80행은 영등포 출발·광명 종착.
//
// 수정: `line_direction.dart` 의 `_line1Ranks` 에 `'1A1': 166.5` 를 추가해
// 금천구청(166) 바로 다음 남쪽 역으로 rank 를 부여했다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/core/utils/upstream_stations.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/local/timetable_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/usecases/find_next_departure.dart';
import 'package:seoul_subway/domain/usecases/search_route.dart';
import 'package:seoul_subway/features/route_search/utils/departure_candidates.dart';
import 'package:seoul_subway/features/route_search/utils/direction_resolver.dart';

/// 광명(1호선 지선) 역 ID.
const _gwangmyeong = '1A1';

/// 금천구청 — 광명 지선의 분기역.
const _geumcheon = '166';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LineSchedule line1;
  late List<Connection> connections;

  setUpAll(() async {
    line1 = (await TimetableDataSource().loadSchedules())['1']!;
    connections = (jsonDecode(
                await rootBundle.loadString('assets/json/connections.json'))
            as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  test('광명 → 금천구청은 상행, 금천구청 → 광명은 하행', () {
    expect(isDownBetween(_gwangmyeong, _geumcheon, '1'), isFalse,
        reason: '광명은 금천구청보다 남쪽이므로 북상 = 상행');
    expect(isDownBetween(_geumcheon, _gwangmyeong, '1'), isTrue,
        reason: '금천구청 → 광명은 남하 = 하행');
  });

  test('광명 지선 rank 가 본선 판정을 바꾸지 않는다', () {
    // 166 앞뒤 본선 구간은 그대로여야 한다.
    expect(isDownBetween('142', _geumcheon, '1'), isTrue); // 구로 → 금천구청
    expect(isDownBetween(_geumcheon, '167', '1'), isTrue); // 금천구청 → 독산
    expect(isDownBetween('167', _geumcheon, '1'), isFalse);
    // 광명 rank(166.5)는 167 을 넘지 않는다.
    expect(isDownBetween(_gwangmyeong, '167', '1'), isTrue);
    expect(isDownBetween('167', _gwangmyeong, '1'), isFalse);
    // 금정(1715) rank 보정도 그대로.
    expect(isDownBetween('171', '1715', '1'), isTrue);
    expect(isDownBetween('1715', '172', '1'), isTrue);
  });

  test('findPreviousStationId 가 금천구청 하행 직전역으로 광명을 고르지 않는다', () {
    // 광명이 하행으로 오판되던 시절엔 구로(142)와 광명(1A1) 두 후보가 잡혀
    // ID 거리 타이브레이크에 의존했다. 이제는 후보가 구로 하나뿐이다.
    expect(
      findPreviousStationId(
        currentId: _geumcheon,
        lineId: '1',
        isDown: true,
        connections: connections,
      ),
      '142',
    );
    // 광명행(하행) 열차의 직전역은 금천구청.
    expect(
      findPreviousStationId(
        currentId: _gwangmyeong,
        lineId: '1',
        isDown: true,
        connections: connections,
      ),
      _geumcheon,
    );
  });

  test('광명 출발 시간표는 상행 슬롯에만 있다 (데이터 계약)', () {
    final up = line1.weekday.stationDepartures?[_gwangmyeong];
    final down = line1.weekdayDown?.stationDepartures?[_gwangmyeong];

    expect(up, isNotNull);
    expect(up!.length, 20, reason: 'SearchSTNTimeTableByIDService INOUT_TAG=1');
    expect(down, isNull,
        reason: '광명은 하행 종착역이라 하행 출발 편성이 없다');
  });

  test('광명 → 금천구청 경로에서 출발시각 선택이 활성화된다', () {
    // 회귀 당시엔 하행으로 오판해 null 슬롯을 조회 → 빈 리스트 → 선택 비활성.
    final isDown = isDownBetween(_gwangmyeong, _geumcheon, '1');
    final candidates = buildDepartureCandidates(
      schedule: line1,
      anchorDate: DateTime(2026, 8, 3), // 월요일
      isDown: isDown,
      stationId: _gwangmyeong,
      express: false,
    );

    expect(candidates, isNotEmpty, reason: '출발시각 선택이 비활성이면 빈 리스트다');
    expect(candidates.length, 20);
    expect(candidates.first, 390, reason: '광명 첫차 06:30');

    // findNextDeparture 도 같은 슬롯을 타 배차간격 폴백이 아닌 실제 시각을 준다.
    final next = findNextDeparture(
      schedule: line1,
      now: DateTime(2026, 8, 3, 6, 0),
      isDown: isDown,
      stationId: _gwangmyeong,
    );
    expect(next, DateTime(2026, 8, 3, 6, 30));
  });

  test('광명 출발은 목적지가 어디든 상행 — 분기역 이남으로 가도 마찬가지', () async {
    // 비단조 세그먼트(166.5 → 166 → 167 …) 회귀 가드. 첫/끝 비교로 방향을
    // 잡던 시절엔 금천구청 이남 목적지에서 하행이 잡혀 후보가 0개였다.
    final searchRoute = SearchRoute(
      stationRepository:
          StationRepositoryImpl(localDataSource: LocalDataSource()),
      timetableDataSource: TimetableDataSource(),
    );

    // 금천구청(북), 구로(북), 독산·관악(남), 금정(남) — 방향이 꺾이든 말든 상행.
    for (final destination in ['166', '140', '167', '168', '1715']) {
      final route = await searchRoute.execute(_gwangmyeong, destination);
      expect(route, isNotNull, reason: '광명 → $destination 경로 없음');

      final segment = findFirstDirectionalSegment(route!);
      expect(segment, isNotNull);
      expect(segment!.stations.first.id, _gwangmyeong);
      expect(isDownDirection(segment), isFalse,
          reason: '광명 → $destination: 광명 탑승은 언제나 상행(영등포행 셔틀)');

      final candidates = buildDepartureCandidates(
        schedule: line1,
        anchorDate: DateTime(2026, 8, 3),
        isDown: isDownDirection(segment),
        stationId: _gwangmyeong,
        express: false,
      );
      expect(candidates.length, 20,
          reason: '광명 → $destination 출발시각 선택이 비활성이다');
    }
  });

  test('금천구청 상류역 판정에 광명이 방향에 맞게 반영된다', () {
    // 하행(남행) 열차의 상류에는 광명이 없어야 하고,
    // 상행 열차의 상류에는 광명발 셔틀이 포함돼야 한다.
    final down = departureUpstreamStationIds(
      departureId: _geumcheon,
      routeNextId: '167', // 금천구청 → 독산 = 하행
      lineId: '1',
      connections: connections,
      routeStationIds: const {},
    );
    expect(down, isNot(contains(_gwangmyeong)),
        reason: '남행 열차에 광명 셔틀이 섞이면 안 된다');

    final up = departureUpstreamStationIds(
      departureId: _geumcheon,
      routeNextId: '142', // 금천구청 → 구로 = 상행
      lineId: '1',
      connections: connections,
      routeStationIds: const {},
    );
    expect(up, contains(_gwangmyeong),
        reason: '광명발 상행 셔틀은 금천구청으로 접근하는 열차다');
  });

  test('금천구청 → 광명 경로는 금천구청 하행 시간표를 조회한다', () {
    // 회귀 당시엔 상행으로 오판해 청량리 방면 열차 시각을 보여줬다.
    final isDown = isDownBetween(_geumcheon, _gwangmyeong, '1');
    expect(isDown, isTrue);

    final down = buildDepartureCandidates(
      schedule: line1,
      anchorDate: DateTime(2026, 8, 3),
      isDown: isDown,
      stationId: _geumcheon,
      express: false,
    );
    final up = buildDepartureCandidates(
      schedule: line1,
      anchorDate: DateTime(2026, 8, 3),
      isDown: false,
      stationId: _geumcheon,
      express: false,
    );

    expect(down, isNotEmpty);
    expect(down, isNot(equals(up)),
        reason: '상·하행 시간표가 같으면 이 테스트는 방향 오판을 잡지 못한다');
  });
}
