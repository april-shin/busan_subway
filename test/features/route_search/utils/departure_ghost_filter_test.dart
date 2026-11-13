// 출발 시각 후보의 유령 열차 제거 회귀 가드.
//
// 종착이 노선 중간인 열차(회차·셔틀)를 API 가 종착 너머 역에도 도착 예정으로
// 이어 붙이는 경우가 있다. 행선지·방향·노선 필드만으로는 정상 행과 구분되지 않아
// 실시간 출발 시각이 이르게 나온다. 부산 실데이터(1호선 동래 하행 부전행, 3호선
// 거제 상행 종합운동장행)로 같은 위상 판정이 출발 시각 후보에 걸리는지 검증한다.
//
// 실제 노선 데이터(stations.json / connections.json)로 검증한다. 환승 구간
// (`computeSegmentDepartures`)도 같은 `_getRealtimeDeparture` 를 쓰므로 함께 본다.
// (실시간 API 의 호선 코드 매핑이 비어 있어 subwayId 는 lineId 원문('1','3')을 쓴다.)
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/route_result.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/route_search/utils/departure_time_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 11, 13, 21, 0, 0);

  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
    stations = (jsonDecode(
      await rootBundle.loadString('assets/json/stations.json'),
    ) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    connections = (jsonDecode(
      await rootBundle.loadString('assets/json/connections.json'),
    ) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  Station stationOf(String name, String lineId) =>
      stations.firstWhere((s) => s.name == name && s.lineId == lineId);

  RouteSegment segmentOf({
    required List<String> stationNames,
    required String lineId,
    int durationSeconds = 300,
  }) =>
      RouteSegment(
        lineId: lineId,
        lineName: '$lineId호선',
        stations: [for (final n in stationNames) stationOf(n, lineId)],
        durationSeconds: durationSeconds,
        direction: '${stationNames.last} 방면',
      );

  RouteResult routeOf(List<RouteSegment> segments) => RouteResult(
        segments: segments,
        totalTimeSeconds: segments.fold(0, (a, s) => a + s.durationSeconds),
        transferCount: segments.length - 1,
        stationCount: segments.fold(0, (a, s) => a + s.stations.length),
        transferDurations: [for (var i = 1; i < segments.length; i++) 180],
      );

  ArrivalInfo arrivalOf({
    required String subwayId,
    required String stationName,
    required String destination,
    required String current,
    required int arrivalSeconds,
    String direction = '하행',
  }) =>
      ArrivalInfo(
        subwayId: subwayId,
        stationName: stationName,
        trainLineNm: '$destination행',
        direction: direction,
        arrivalMessage: '',
        destination: destination,
        trainType: '일반',
        arrivalSeconds: arrivalSeconds,
        receivedAt: fixedNow,
        currentStationName: current,
      );

  RouteResult dongnae() => routeOf([
        segmentOf(stationNames: ['동래', '명륜', '온천장'], lineId: '1'),
      ]);

  ({DateTime departure, DepartureSource source}) compute(
    List<ArrivalInfo> arrivals, {
    RouteResult? route,
    bool withTopology = true,
  }) =>
      computeDepartureTimeDetailed(
        arrivalAsync: AsyncData(arrivals),
        routeResult: route ?? dongnae(),
        now: fixedNow,
        stations: withTopology ? stations : const [],
        connections: withTopology ? connections : const [],
      );

  ArrivalInfo ghostBujeon(int secs, {String current = '서면'}) =>
      arrivalOf(
        subwayId: '1',
        stationName: '동래',
        destination: '부전',
        current: current,
        arrivalSeconds: secs,
      );

  ArrivalInfo realNopo(int secs, {String current = '교대', String? dest}) =>
      arrivalOf(
        subwayId: '1',
        stationName: '동래',
        destination: dest ?? '노포',
        current: current,
        arrivalSeconds: secs,
      );

  group('computeDepartureTimeDetailed — 유령 열차 제거', () {
    test('동래 하행: 부전행 유령(20초)을 건너뛰고 실제 노포행(150초)을 쓴다', () {
      final result = compute([
        ghostBujeon(20),
        realNopo(150),
        realNopo(510, dest: '범어사', current: '연산'),
      ]);

      expect(result.source, DepartureSource.realtime);
      expect(result.departure, fixedNow.add(const Duration(seconds: 150)));
    });

    test('현재역이 어디든(서면 20초 · 범내골 35초·95초) 부전행은 모두 제거', () {
      for (final (cur, secs) in [
        ('서면', 20),
        ('범내골', 35),
        ('범내골', 95),
      ]) {
        final result = compute([
          ghostBujeon(secs, current: cur),
          realNopo(450),
        ]);
        expect(
          result.departure,
          fixedNow.add(const Duration(seconds: 450)),
          reason: '$cur $secs초',
        );
      }
    });

    test('정상 열차는 보존 — 유령이 없으면 가장 빠른 열차 그대로', () {
      final result = compute([
        realNopo(60),
        realNopo(300, dest: '범어사', current: '연산'),
      ]);
      expect(result.departure, fixedNow.add(const Duration(seconds: 60)));
    });

    test('유령이 정상 열차보다 느려도 결과는 같다 (정렬 순서 무관)', () {
      final result = compute([
        realNopo(150),
        ghostBujeon(900),
      ]);
      expect(result.departure, fixedNow.add(const Duration(seconds: 150)));
    });

    test('유령뿐이면 실시간 후보가 없는 것으로 보고 폴백한다 (실제 열차로 오인하지 않음)', () {
      final result = compute([ghostBujeon(20)]);
      expect(result.source, isNot(DepartureSource.realtime));
    });

    test('passed — 현재역이 이미 동래를 지난 실제 열차는 그대로 후보', () {
      // 현재역 표기가 지연·불일치한 실제 열차는 숨기지 않는다.
      final result = compute([
        realNopo(40, current: '명륜'),
        realNopo(450),
      ]);
      expect(result.departure, fixedNow.add(const Duration(seconds: 40)));
    });

    test('판정 불가(현재역 이름 없음)는 통과 — fail-open', () {
      final result = compute([
        ghostBujeon(20, current: ''),
        realNopo(150),
      ]);
      expect(result.departure, fixedNow.add(const Duration(seconds: 20)));
    });

    test('stations/connections 미로딩이면 필터 미적용 — fail-open', () {
      final result = compute(
        [ghostBujeon(20), realNopo(150)],
        withTopology: false,
      );
      expect(result.departure, fixedNow.add(const Duration(seconds: 20)));
    });

    test('3호선 거제 상행: 종합운동장행 유령(60초)을 건너뛰고 수영행(360초)을 쓴다', () {
      final route = routeOf([
        segmentOf(stationNames: ['거제', '연산', '물만골'], lineId: '3'),
      ]);
      ArrivalInfo row(String dest, String cur, int secs) => arrivalOf(
            subwayId: '3',
            stationName: '거제',
            destination: dest,
            current: cur,
            arrivalSeconds: secs,
            direction: '상행',
          );

      final result = compute([
        row('종합운동장', '사직', 60),
        row('수영', '종합운동장', 360),
      ], route: route);

      expect(result.departure, fixedNow.add(const Duration(seconds: 360)));
    });

    test('방향·행선지 모순 행(대저행, 현재역 종합운동장 — 상행으로 갈 수 없음)은 통과 — fail-open 정책 유지', () {
      // 이 행은 열차가 표기 방향의 **반대**로 가는 모순이다. 현재역 → 행선지 경로가 탑승 방향으로는
      // 구해지지 않아 판정하지 않고 통과시킨다 — 극성 데이터 오류가 "열차 전부
      // 소실"로 증폭되는 걸 막는 route_branch 의 fail-open 을 대체하지 않는다.
      // (이 테스트는 그 한계를 고정한다 — 고치려면 사용자 결정 사안.)
      final route = routeOf([
        segmentOf(stationNames: ['거제', '연산', '물만골'], lineId: '3'),
      ]);
      ArrivalInfo row(String dest, String cur, int secs) => arrivalOf(
            subwayId: '3',
            stationName: '거제',
            destination: dest,
            current: cur,
            arrivalSeconds: secs,
            direction: '상행',
          );

      final result = compute([
        row('대저', '종합운동장', 210),
        row('수영', '사직', 360),
      ], route: route);

      expect(result.departure, fixedNow.add(const Duration(seconds: 210)));
    });
  });

  group('computeSegmentDepartures — 환승역에도 같은 필터', () {
    // 2호선 전포 → 서면 → (환승) 1호선 하행 부전 방면.
    RouteResult transferRoute() => routeOf([
          segmentOf(
            stationNames: ['전포', '서면'],
            lineId: '2',
            durationSeconds: 300,
          ),
          segmentOf(stationNames: ['서면', '부전', '양정'], lineId: '1'),
        ]);

    final initialDeparture = DateTime(2026, 10, 20, 21, 5);

    List<DateTime> departures(List<ArrivalInfo> arrivals,
        {bool withTopology = true}) {
      return computeSegmentDepartures(
        routeResult: transferRoute(),
        initialDeparture: initialDeparture,
        schedules: const {},
        transferArrivals: {'서면': AsyncData(arrivals)},
        now: fixedNow,
        stations: withTopology ? stations : const [],
        connections: withTopology ? connections : const [],
      );
    }

    ArrivalInfo row(String dest, String cur, int secs) => arrivalOf(
          subwayId: '1',
          stationName: '서면',
          destination: dest,
          current: cur,
          arrivalSeconds: secs,
        );

    // 첫 구간 21:05 출발 → 서면 21:10 도착 → 환승 3분 → 21:13 이후(780초) 열차만 유효.
    test('환승역(서면)의 1호선 하행: 범내골행 유령을 건너뛴다', () {
      final result = departures([
        // 서면 **앞**(범내골)에서 끝나는 열차 — 서면에 오지 않는다.
        row('범내골', '부산진', 800),
        row('노포', '범일', 900),
      ]);

      expect(result.length, 2);
      expect(result[1], fixedNow.add(const Duration(seconds: 900)));
    });

    test('정상 열차는 보존 — 유령이 없으면 가장 빠른 열차', () {
      final result = departures([
        row('노포', '범내골', 800),
        row('노포', '범일', 900),
      ]);
      expect(result[1], fixedNow.add(const Duration(seconds: 800)));
    });

    test('미로딩이면 필터 미적용 — fail-open', () {
      final result = departures([
        row('범내골', '부산진', 800),
        row('노포', '범일', 900),
      ], withTopology: false);
      expect(result[1], fixedNow.add(const Duration(seconds: 800)));
    });
  });
}
