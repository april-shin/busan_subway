// 출발 시각 계산의 지선 필터 회귀 가드.
//
// 노선 ID + 상/하행 + 급행여부만으로 실시간 도착정보를 필터하면, 지선이 있는
// 노선에서 경로를 태워주지 않는 열차가 출발 시각의 기준이 된다. 예) `천호 →
// 굽은다리` 경로에서 5호선 하행 "마천행"은 강동에서 갈라져 굽은다리를 지나지
// 않으므로, 그 열차가 가장 빨라도 출발 시각으로 쓰면 안 된다.
//
// 실제 노선 데이터(stations.json / connections.json)로 검증한다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/utils/departure_time_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 2, 23, 9, 0, 0); // 월요일

  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
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
  });

  /// 노선 [lineId] 의 이름이 [name] 인 역.
  Station stationOf(String name, String lineId) => stations.firstWhere(
        (s) => s.name == name && s.lineId == lineId,
      );

  RouteSegment segmentOf({
    required List<String> stationNames,
    required String lineId,
    String? segmentLineId,
    int durationSeconds = 300,
  }) {
    return RouteSegment(
      lineId: segmentLineId ?? lineId,
      lineName: '$lineId호선',
      stations: [for (final n in stationNames) stationOf(n, lineId)],
      durationSeconds: durationSeconds,
      direction: '${stationNames.last} 방면',
    );
  }

  RouteResult routeOf(List<RouteSegment> segments) => RouteResult(
        segments: segments,
        totalTimeSeconds:
            segments.fold(0, (a, s) => a + s.durationSeconds),
        transferCount: segments.length - 1,
        stationCount:
            segments.fold(0, (a, s) => a + s.stations.length),
        transferDurations: [for (var i = 1; i < segments.length; i++) 180],
      );

  ArrivalInfo arrivalOf({
    required String subwayId,
    required String destination,
    required int arrivalSeconds,
    String direction = '하행',
    String stationName = '천호',
  }) {
    return ArrivalInfo(
      subwayId: subwayId,
      stationName: stationName,
      trainLineNm: '$destination행',
      direction: direction,
      arrivalMessage: '곧 도착',
      destination: destination,
      trainType: '일반',
      arrivalSeconds: arrivalSeconds,
      receivedAt: fixedNow,
    );
  }

  /// 5호선 시간표(배차 5분) — 실시간이 걸러졌을 때의 폴백 확인용.
  LineSchedule schedule5() => const LineSchedule(
        lineId: '5',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:00',
          periods: [
            TimePeriod(start: '05:30', end: '00:00', headwayMinutes: 5),
          ],
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
      );

  group('computeDepartureTimeDetailed — 출발역 지선 필터', () {
    // 천호 → 굽은다리 (하남 방면). 마천행은 강동에서 갈라진다.
    // 역 데이터는 setUpAll 이후에만 있으므로 테스트 본문에서 만든다.
    RouteResult cheonhoToGubeun() => routeOf([
          segmentOf(stationNames: ['천호', '강동', '길동', '굽은다리'], lineId: '5'),
        ]);

    test('경로를 태워주지 않는 마천행은 무시하고 다음 하남검단산행을 쓴다', () {
      final result = computeDepartureTimeDetailed(
        arrivalAsync: AsyncData([
          arrivalOf(subwayId: '1005', destination: '마천', arrivalSeconds: 60),
          arrivalOf(
            subwayId: '1005',
            destination: '하남검단산',
            arrivalSeconds: 300,
          ),
        ]),
        routeResult: cheonhoToGubeun(),
        now: fixedNow,
        lineSchedule: schedule5(),
        stations: stations,
        connections: connections,
      );

      expect(result.source, DepartureSource.realtime);
      expect(result.departure, fixedNow.add(const Duration(seconds: 300)));
    });

    test('같은 지선의 중간 종착(상일동행)은 유효한 열차로 본다', () {
      final result = computeDepartureTimeDetailed(
        arrivalAsync: AsyncData([
          arrivalOf(subwayId: '1005', destination: '마천', arrivalSeconds: 60),
          arrivalOf(subwayId: '1005', destination: '상일동', arrivalSeconds: 120),
        ]),
        routeResult: cheonhoToGubeun(),
        now: fixedNow,
        lineSchedule: schedule5(),
        stations: stations,
        connections: connections,
      );

      expect(result.departure, fixedNow.add(const Duration(seconds: 120)));
    });

    test('마천 방면 경로에서는 반대로 하남검단산행이 걸러진다', () {
      final cheonhoToDunchon = routeOf([
        segmentOf(stationNames: ['천호', '강동', '둔촌동'], lineId: '5'),
      ]);

      final result = computeDepartureTimeDetailed(
        arrivalAsync: AsyncData([
          arrivalOf(
            subwayId: '1005',
            destination: '하남검단산',
            arrivalSeconds: 60,
          ),
          arrivalOf(subwayId: '1005', destination: '마천', arrivalSeconds: 240),
        ]),
        routeResult: cheonhoToDunchon,
        now: fixedNow,
        lineSchedule: schedule5(),
        stations: stations,
        connections: connections,
      );

      expect(result.departure, fixedNow.add(const Duration(seconds: 240)));
    });

    test('탈 수 있는 열차가 하나도 없으면 시간표로 폴백한다', () {
      final result = computeDepartureTimeDetailed(
        arrivalAsync: AsyncData([
          arrivalOf(subwayId: '1005', destination: '마천', arrivalSeconds: 60),
        ]),
        routeResult: cheonhoToGubeun(),
        now: fixedNow,
        lineSchedule: schedule5(),
        stations: stations,
        connections: connections,
      );

      expect(result.source, DepartureSource.timetable);
      expect(result.departure, DateTime(2026, 2, 23, 9, 5));
    });

    test('stations/connections 미로딩이면 필터 미적용 (fail-open)', () {
      final result = computeDepartureTimeDetailed(
        arrivalAsync: AsyncData([
          arrivalOf(subwayId: '1005', destination: '마천', arrivalSeconds: 60),
          arrivalOf(
            subwayId: '1005',
            destination: '하남검단산',
            arrivalSeconds: 300,
          ),
        ]),
        routeResult: cheonhoToGubeun(),
        now: fixedNow,
        lineSchedule: schedule5(),
      );

      // 필터 없음 → 기존 동작(가장 빠른 열차)
      expect(result.departure, fixedNow.add(const Duration(seconds: 60)));
    });

    test('행선지를 해석할 수 없어도 필터가 열차를 지우지 않는다 (fail-open)', () {
      final result = computeDepartureTimeDetailed(
        arrivalAsync: AsyncData([
          arrivalOf(subwayId: '1005', destination: '알수없는역', arrivalSeconds: 60),
        ]),
        routeResult: cheonhoToGubeun(),
        now: fixedNow,
        lineSchedule: schedule5(),
        stations: stations,
        connections: connections,
      );

      expect(result.departure, fixedNow.add(const Duration(seconds: 60)));
    });
  });

  group('computeDepartureTimeDetailed — 지선 없는 노선 회귀', () {
    test('3호선(지선 없음)은 지선 데이터를 넘겨도 출발 시각이 동일하다', () {
      // 교대 → 남부터미널 → 양재: ID 증가 = 하행
      final route = routeOf([
        segmentOf(stationNames: ['교대', '남부터미널', '양재'], lineId: '3'),
      ]);
      final arrivals = AsyncData([
        arrivalOf(
          subwayId: '1003',
          destination: '오금',
          arrivalSeconds: 90,
          stationName: '교대',
        ),
      ]);

      final withData = computeDepartureTimeDetailed(
        arrivalAsync: arrivals,
        routeResult: route,
        now: fixedNow,
        stations: stations,
        connections: connections,
      );
      final without = computeDepartureTimeDetailed(
        arrivalAsync: arrivals,
        routeResult: route,
        now: fixedNow,
      );

      expect(withData.departure, without.departure);
      expect(withData.departure, fixedNow.add(const Duration(seconds: 90)));
    });
  });

  group('computeSegmentDepartures — 환승역 지선 필터', () {
    // 8호선 천호에서 5호선으로 환승해 굽은다리까지. 환승역(천호)의 실시간
    // 도착정보에 마천행이 섞이면 환승 후 출발 시각이 못 타는 열차 기준이 된다.
    RouteResult transferRoute() => routeOf([
          segmentOf(
            stationNames: ['암사', '천호'],
            lineId: '8',
            durationSeconds: 300, // 09:05 출발 → 09:10 도착
          ),
          segmentOf(stationNames: ['천호', '강동', '길동', '굽은다리'], lineId: '5'),
        ]);

    // 첫 구간 출발 09:05 → 천호 09:10 도착 → 환승 3분 → 09:13 이후 열차만 유효.
    final initialDeparture = DateTime(2026, 2, 23, 9, 5);

    List<DateTime> compute({
      required List<ArrivalInfo> transferArrivals,
      bool withBranchData = true,
    }) {
      return computeSegmentDepartures(
        routeResult: transferRoute(),
        initialDeparture: initialDeparture,
        schedules: {'5': schedule5()},
        transferArrivals: {'천호': AsyncData(transferArrivals)},
        now: fixedNow,
        stations: withBranchData ? stations : const [],
        connections: withBranchData ? connections : const [],
      );
    }

    test('환승역의 마천행은 무시하고 다음 하남검단산행을 쓴다', () {
      final result = compute(transferArrivals: [
        // 09:14 도착 (유효 시각이지만 마천행)
        arrivalOf(subwayId: '1005', destination: '마천', arrivalSeconds: 840),
        // 09:18 도착
        arrivalOf(
          subwayId: '1005',
          destination: '하남검단산',
          arrivalSeconds: 1080,
        ),
      ]);

      expect(result.length, 2);
      expect(result[0], initialDeparture);
      expect(result[1], fixedNow.add(const Duration(seconds: 1080)));
    });

    test('stations/connections 미로딩이면 필터 미적용 (fail-open)', () {
      final result = compute(
        transferArrivals: [
          arrivalOf(subwayId: '1005', destination: '마천', arrivalSeconds: 840),
          arrivalOf(
            subwayId: '1005',
            destination: '하남검단산',
            arrivalSeconds: 1080,
          ),
        ],
        withBranchData: false,
      );

      expect(result[1], fixedNow.add(const Duration(seconds: 840)));
    });

    test('환승 후 탈 열차가 없으면 시간표로 폴백한다', () {
      final result = compute(transferArrivals: [
        arrivalOf(subwayId: '1005', destination: '마천', arrivalSeconds: 840),
      ]);

      // 실시간 제외 → 5호선 시간표(배차 5분), 09:13 이후 첫 출발
      expect(result[1].isAfter(DateTime(2026, 2, 23, 9, 13)), isTrue);
      expect(result[1], DateTime(2026, 2, 23, 9, 15));
    });
  });
}
