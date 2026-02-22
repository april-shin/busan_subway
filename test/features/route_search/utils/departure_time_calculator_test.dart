import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/utils/departure_time_calculator.dart';

void main() {
  final fixedNow = DateTime(2026, 2, 22, 9, 0, 0);

  RouteResult makeRouteResult({required String lineId}) {
    return RouteResult(
      segments: [
        RouteSegment(
          lineId: lineId,
          lineName: '2호선',
          stations: const [
            Station(
              id: '201',
              name: '강남',
              lineId: '2',
              latitude: 37.49,
              longitude: 127.02,
            ),
          ],
          durationSeconds: 120,
          direction: '강남 방면',
        ),
      ],
      totalTimeSeconds: 120,
      transferCount: 0,
      stationCount: 1,
    );
  }

  ArrivalInfo makeArrival({
    required String subwayId,
    required int? arrivalSeconds,
  }) {
    return ArrivalInfo(
      subwayId: subwayId,
      stationName: '강남',
      trainLineNm: '2호선',
      direction: '상행',
      arrivalMessage: '곧 도착',
      destination: '시청',
      trainType: '일반',
      arrivalSeconds: arrivalSeconds,
      receivedAt: fixedNow,
    );
  }

  group('computeDepartureTime', () {
    test('로딩 상태일 때 now를 반환한다', () {
      final result = computeDepartureTime(
        arrivalAsync: const AsyncLoading(),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
      );

      expect(result, fixedNow);
    });

    test('에러 상태일 때 now를 반환한다', () {
      final result = computeDepartureTime(
        arrivalAsync: AsyncError(Exception('네트워크 오류'), StackTrace.current),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
      );

      expect(result, fixedNow);
    });

    test('segments가 비어있을 때 now를 반환한다', () {
      const emptyRoute = RouteResult(
        segments: [],
        totalTimeSeconds: 0,
        transferCount: 0,
        stationCount: 0,
      );

      final result = computeDepartureTime(
        arrivalAsync: const AsyncData([]),
        routeResult: emptyRoute,
        now: fixedNow,
      );

      expect(result, fixedNow);
    });

    test('매칭되는 도착정보가 없을 때 now를 반환한다', () {
      final arrivals = [
        makeArrival(subwayId: '1003', arrivalSeconds: 60),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
      );

      expect(result, fixedNow);
    });

    test('arrivalSeconds가 0 이하인 항목은 무시한다', () {
      final arrivals = [
        makeArrival(subwayId: '1002', arrivalSeconds: 0),
        makeArrival(subwayId: '1002', arrivalSeconds: -5),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
      );

      expect(result, fixedNow);
    });

    test('arrivalSeconds가 null인 항목은 무시한다', () {
      final arrivals = [
        makeArrival(subwayId: '1002', arrivalSeconds: null),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
      );

      expect(result, fixedNow);
    });

    test('매칭되는 도착정보가 있으면 가장 빠른 열차 기준으로 시각을 반환한다', () {
      final arrivals = [
        makeArrival(subwayId: '1002', arrivalSeconds: 180),
        makeArrival(subwayId: '1002', arrivalSeconds: 60),
        makeArrival(subwayId: '1002', arrivalSeconds: 300),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
      );

      expect(result, fixedNow.add(const Duration(seconds: 60)));
    });

    test('subwayId를 lineId로 변환하여 매칭한다 (1002 -> 2호선)', () {
      final arrivals = [
        makeArrival(subwayId: '1002', arrivalSeconds: 120),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
      );

      expect(result, fixedNow.add(const Duration(seconds: 120)));
    });

    test('subwayId 매핑에 없는 값은 그대로 lineId와 비교한다', () {
      final arrivals = [
        makeArrival(subwayId: 'SB', arrivalSeconds: 90),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: 'SB'),
        now: fixedNow,
      );

      expect(result, fixedNow.add(const Duration(seconds: 90)));
    });
  });
}
