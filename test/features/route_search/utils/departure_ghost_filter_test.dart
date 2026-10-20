// 출발 시각 후보의 유령 열차 제거 회귀 가드.
//
// 종착이 노선 중간인 열차(회차·셔틀)를 서울 API 가 종착 너머 역에도 도착 예정으로
// 이어 붙인다. 행선지·방향·노선 필드만으로는 정상 행과 구분되지 않아(2026-10-20 야간
// 실측) 실시간 출발 시각이 2~7분 이르게 나왔다.
//  - 4호선 남태령 하행: 사당행(현재역 총신대입구(이수)·이촌, 20·35·95초)이 최단 후보였다.
//    실제 다음 열차는 안산·오이도행 150~510초.
//  - 3호선 지축 상행: 구파발행(현재역 불광, 60초)이 대화행(360초)보다 앞섰다.
//
// 실제 노선 데이터(stations.json / connections.json)로 검증한다. 환승 구간
// (`computeSegmentDepartures`)도 같은 `_getRealtimeDeparture` 를 쓰므로 함께 본다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/utils/departure_time_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 10, 20, 21, 0, 0);

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

  RouteResult namtaeryeong() => routeOf([
        segmentOf(stationNames: ['남태령', '선바위', '경마공원'], lineId: '4'),
      ]);

  ({DateTime departure, DepartureSource source}) compute(
    List<ArrivalInfo> arrivals, {
    RouteResult? route,
    bool withTopology = true,
  }) =>
      computeDepartureTimeDetailed(
        arrivalAsync: AsyncData(arrivals),
        routeResult: route ?? namtaeryeong(),
        now: fixedNow,
        stations: withTopology ? stations : const [],
        connections: withTopology ? connections : const [],
      );

  ArrivalInfo ghostSadang(int secs, {String current = '총신대입구(이수)'}) =>
      arrivalOf(
        subwayId: '1004',
        stationName: '남태령',
        destination: '사당',
        current: current,
        arrivalSeconds: secs,
      );

  ArrivalInfo realAnsan(int secs, {String current = '사당', String? dest}) =>
      arrivalOf(
        subwayId: '1004',
        stationName: '남태령',
        destination: dest ?? '안산',
        current: current,
        arrivalSeconds: secs,
      );

  group('computeDepartureTimeDetailed — 유령 열차 제거', () {
    test('남태령 하행: 사당행 유령(20초)을 건너뛰고 실제 안산행(150초)을 쓴다', () {
      final result = compute([
        ghostSadang(20),
        realAnsan(150),
        realAnsan(510, dest: '오이도', current: '동작'),
      ]);

      expect(result.source, DepartureSource.realtime);
      expect(result.departure, fixedNow.add(const Duration(seconds: 150)));
    });

    test('실측 3종(현재역 총신대입구(이수) 20초 · 이촌 35초·95초) 모두 제거', () {
      for (final (cur, secs) in [
        ('총신대입구(이수)', 20),
        ('이촌', 35),
        ('이촌', 95),
      ]) {
        final result = compute([
          ghostSadang(secs, current: cur),
          realAnsan(450),
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
        realAnsan(60),
        realAnsan(300, dest: '오이도', current: '동작'),
      ]);
      expect(result.departure, fixedNow.add(const Duration(seconds: 60)));
    });

    test('유령이 정상 열차보다 느려도 결과는 같다 (정렬 순서 무관)', () {
      final result = compute([
        realAnsan(150),
        ghostSadang(900),
      ]);
      expect(result.departure, fixedNow.add(const Duration(seconds: 150)));
    });

    test('유령뿐이면 실시간 후보가 없는 것으로 보고 폴백한다 (실제 열차로 오인하지 않음)', () {
      final result = compute([ghostSadang(20)]);
      expect(result.source, isNot(DepartureSource.realtime));
    });

    test('passed — 현재역이 이미 남태령을 지난 실제 열차는 그대로 후보', () {
      // arvlMsg3 가 지연·불일치한 실제 열차(6호선 신내 6310 사례)는 숨기지 않는다.
      final result = compute([
        realAnsan(40, current: '선바위'),
        realAnsan(450),
      ]);
      expect(result.departure, fixedNow.add(const Duration(seconds: 40)));
    });

    test('판정 불가(현재역 이름 없음)는 통과 — fail-open', () {
      final result = compute([
        ghostSadang(20, current: ''),
        realAnsan(150),
      ]);
      expect(result.departure, fixedNow.add(const Duration(seconds: 20)));
    });

    test('stations/connections 미로딩이면 필터 미적용 — fail-open', () {
      final result = compute(
        [ghostSadang(20), realAnsan(150)],
        withTopology: false,
      );
      expect(result.departure, fixedNow.add(const Duration(seconds: 20)));
    });

    test('3호선 지축 상행: 구파발행 유령(60초)을 건너뛰고 대화행(360초)을 쓴다', () {
      final route = routeOf([
        segmentOf(stationNames: ['지축', '삼송', '원흥'], lineId: '3'),
      ]);
      ArrivalInfo row(String dest, String cur, int secs) => arrivalOf(
            subwayId: '1003',
            stationName: '지축',
            destination: dest,
            current: cur,
            arrivalSeconds: secs,
            direction: '상행',
          );

      final result = compute([
        row('구파발', '불광', 60),
        row('대화', '연신내', 360),
      ], route: route);

      expect(result.departure, fixedNow.add(const Duration(seconds: 360)));
    });

    test('방향·행선지 모순 행(독립문행, 현재역 구파발)은 통과 — fail-open 정책 유지', () {
      // 같은 실측(21시대)에서 "독립문행 210초"도 후보로 잡혔지만, 이 행은 열차가
      // 표기 방향의 **반대**로 가는 모순이다. 현재역 → 행선지 경로가 탑승 방향으로는
      // 구해지지 않아 판정하지 않고 통과시킨다 — 극성 데이터 오류가 "열차 전부
      // 소실"로 증폭되는 걸 막는 route_branch 의 fail-open 을 대체하지 않는다.
      // (이 테스트는 그 한계를 고정한다 — 고치려면 사용자 결정 사안.)
      final route = routeOf([
        segmentOf(stationNames: ['지축', '삼송', '원흥'], lineId: '3'),
      ]);
      ArrivalInfo row(String dest, String cur, int secs) => arrivalOf(
            subwayId: '1003',
            stationName: '지축',
            destination: dest,
            current: cur,
            arrivalSeconds: secs,
            direction: '상행',
          );

      final result = compute([
        row('독립문', '구파발', 210),
        row('대화', '연신내', 360),
      ], route: route);

      expect(result.departure, fixedNow.add(const Duration(seconds: 210)));
    });
  });

  group('computeSegmentDepartures — 환승역에도 같은 필터', () {
    // 2호선 낙성대 → 사당 → (환승) 4호선 하행 남태령 방면.
    RouteResult transferRoute() => routeOf([
          segmentOf(
            stationNames: ['낙성대', '사당'],
            lineId: '2',
            durationSeconds: 300,
          ),
          segmentOf(stationNames: ['사당', '남태령', '선바위'], lineId: '4'),
        ]);

    final initialDeparture = DateTime(2026, 10, 20, 21, 5);

    List<DateTime> departures(List<ArrivalInfo> arrivals,
        {bool withTopology = true}) {
      return computeSegmentDepartures(
        routeResult: transferRoute(),
        initialDeparture: initialDeparture,
        schedules: const {},
        transferArrivals: {'사당': AsyncData(arrivals)},
        now: fixedNow,
        stations: withTopology ? stations : const [],
        connections: withTopology ? connections : const [],
      );
    }

    ArrivalInfo row(String dest, String cur, int secs) => arrivalOf(
          subwayId: '1004',
          stationName: '사당',
          destination: dest,
          current: cur,
          arrivalSeconds: secs,
        );

    // 첫 구간 21:05 출발 → 사당 21:10 도착 → 환승 3분 → 21:13 이후(780초) 열차만 유효.
    test('환승역(사당)의 4호선 하행: 총신대입구(이수)행 유령을 건너뛴다', () {
      final result = departures([
        // 사당 너머가 아니라 사당 **앞**에서 끝나는 열차 — 사당에 오지 않는다.
        row('총신대입구(이수)', '동작', 800),
        row('오이도', '이촌', 900),
      ]);

      expect(result.length, 2);
      expect(result[1], fixedNow.add(const Duration(seconds: 900)));
    });

    test('정상 열차는 보존 — 유령이 없으면 가장 빠른 열차', () {
      final result = departures([
        row('안산', '총신대입구(이수)', 800),
        row('오이도', '이촌', 900),
      ]);
      expect(result[1], fixedNow.add(const Duration(seconds: 800)));
    });

    test('미로딩이면 필터 미적용 — fail-open', () {
      final result = departures([
        row('총신대입구(이수)', '동작', 800),
        row('오이도', '이촌', 900),
      ], withTopology: false);
      expect(result[1], fixedNow.add(const Duration(seconds: 800)));
    });
  });
}
