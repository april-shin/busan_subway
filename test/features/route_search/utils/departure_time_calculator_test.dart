import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/utils/departure_time_calculator.dart';

void main() {
  final fixedNow = DateTime(2026, 2, 23, 9, 0, 0); // 월요일

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

  LineSchedule makeSchedule({String lineId = '2'}) {
    return LineSchedule(
      lineId: lineId,
      weekday: const DaySchedule(
        firstTrain: '05:00',
        lastTrain: '00:00',
        periods: [
          TimePeriod(start: '05:00', end: '06:30', headwayMinutes: 5),
          TimePeriod(start: '06:30', end: '09:00', headwayMinutes: 3),
          TimePeriod(start: '09:00', end: '16:30', headwayMinutes: 5),
          TimePeriod(start: '16:30', end: '19:30', headwayMinutes: 3),
          TimePeriod(start: '19:30', end: '21:00', headwayMinutes: 5),
          TimePeriod(start: '21:00', end: '00:00', headwayMinutes: 8),
        ],
      ),
      weekend: const DaySchedule(
        firstTrain: '05:30',
        lastTrain: '23:40',
        periods: [
          TimePeriod(start: '05:30', end: '23:40', headwayMinutes: 6),
        ],
      ),
    );
  }

  group('computeDepartureTime', () {
    test('로딩 상태일 때 시간표 기반으로 반환한다', () {
      final result = computeDepartureTime(
        arrivalAsync: const AsyncLoading(),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
        lineSchedule: makeSchedule(),
      );

      // 09:00 → 시간대 "09:00~16:30", 배차 5분
      // 09:00은 시간대 시작이므로 다음 출발은 09:05
      expect(result, DateTime(2026, 2, 23, 9, 5));
    });

    test('로딩 상태이고 시간표도 없으면 now를 반환한다', () {
      final result = computeDepartureTime(
        arrivalAsync: const AsyncLoading(),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
      );

      expect(result, fixedNow);
    });

    test('에러 상태일 때 시간표 기반으로 반환한다', () {
      final result = computeDepartureTime(
        arrivalAsync:
            AsyncError(Exception('네트워크 오류'), StackTrace.current),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
        lineSchedule: makeSchedule(),
      );

      expect(result, DateTime(2026, 2, 23, 9, 5));
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

    test('실시간 도착정보가 있으면 시간표보다 우선한다', () {
      final arrivals = [
        makeArrival(subwayId: '1002', arrivalSeconds: 60),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
        lineSchedule: makeSchedule(),
      );

      // 실시간: 60초 후 = 09:01
      expect(result, fixedNow.add(const Duration(seconds: 60)));
    });

    test('실시간 매칭 없으면 시간표 기반으로 반환한다', () {
      final arrivals = [
        makeArrival(subwayId: '1003', arrivalSeconds: 60), // 3호선, 매칭 안됨
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
        lineSchedule: makeSchedule(),
      );

      // 시간표: 09:05
      expect(result, DateTime(2026, 2, 23, 9, 5));
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
        lineSchedule: makeSchedule(),
      );

      expect(result, DateTime(2026, 2, 23, 9, 5));
    });

    test('arrivalSeconds가 null인 항목은 무시한다', () {
      final arrivals = [
        makeArrival(subwayId: '1002', arrivalSeconds: null),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: makeRouteResult(lineId: '2'),
        now: fixedNow,
        lineSchedule: makeSchedule(),
      );

      expect(result, DateTime(2026, 2, 23, 9, 5));
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

  group('computeDepartureTime - 방향 필터', () {
    test('하행 방향(ID 증가)이면 하행 실시간 도착정보만 사용한다', () {
      // 3호선: 역 ID 증가 = 하행
      final route = RouteResult(
        segments: [
          RouteSegment(
            lineId: '3',
            lineName: '3호선',
            stations: const [
              Station(id: '310', name: '교대', lineId: '3', latitude: 0, longitude: 0),
              Station(id: '320', name: '남부터미널', lineId: '3', latitude: 0, longitude: 0),
            ],
            durationSeconds: 120,
            direction: '수서 방면',
          ),
        ],
        totalTimeSeconds: 120,
        transferCount: 0,
        stationCount: 2,
      );

      final arrivals = [
        ArrivalInfo(
          subwayId: '1003',
          stationName: '교대',
          trainLineNm: '3호선',
          direction: '하행',
          arrivalMessage: '곧 도착',
          destination: '수서',
          trainType: '일반',
          arrivalSeconds: 60,
          receivedAt: fixedNow,
        ),
        ArrivalInfo(
          subwayId: '1003',
          stationName: '교대',
          trainLineNm: '3호선',
          direction: '상행',
          arrivalMessage: '곧 도착',
          destination: '구파발',
          trainType: '일반',
          arrivalSeconds: 30,
          receivedAt: fixedNow,
        ),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: route,
        now: fixedNow,
        lineSchedule: makeSchedule(lineId: '3'),
      );

      // 하행(60초)만 매칭, 상행(30초)은 무시
      expect(result, fixedNow.add(const Duration(seconds: 60)));
    });

    test('상행 방향(ID 감소)이면 상행 실시간 도착정보만 사용한다', () {
      // 역 ID 감소 = 상행
      final route = RouteResult(
        segments: [
          RouteSegment(
            lineId: '3',
            lineName: '3호선',
            stations: const [
              Station(id: '330', name: '충무로', lineId: '3', latitude: 0, longitude: 0),
              Station(id: '320', name: '종로3가', lineId: '3', latitude: 0, longitude: 0),
            ],
            durationSeconds: 120,
            direction: '구파발 방면',
          ),
        ],
        totalTimeSeconds: 120,
        transferCount: 0,
        stationCount: 2,
      );

      final arrivals = [
        ArrivalInfo(
          subwayId: '1003',
          stationName: '충무로',
          trainLineNm: '3호선',
          direction: '상행',
          arrivalMessage: '곧 도착',
          destination: '구파발',
          trainType: '일반',
          arrivalSeconds: 90,
          receivedAt: fixedNow,
        ),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: route,
        now: fixedNow,
        lineSchedule: makeSchedule(lineId: '3'),
      );

      // 상행 매칭
      expect(result, fixedNow.add(const Duration(seconds: 90)));
    });

    test('방향 불일치 실시간 데이터는 무시하고 시간표로 폴백', () {
      // 3호선: 역 ID 감소 = 상행
      final route = RouteResult(
        segments: [
          RouteSegment(
            lineId: '3',
            lineName: '3호선',
            stations: const [
              Station(id: '320', name: '남부터미널', lineId: '3', latitude: 0, longitude: 0),
              Station(id: '310', name: '교대', lineId: '3', latitude: 0, longitude: 0),
            ],
            durationSeconds: 120,
            direction: '구파발 방면',
          ),
        ],
        totalTimeSeconds: 120,
        transferCount: 0,
        stationCount: 2,
      );

      // 하행 도착정보만 있으나 경로는 상행(ID 감소)
      final arrivals = [
        ArrivalInfo(
          subwayId: '1003',
          stationName: '남부터미널',
          trainLineNm: '3호선',
          direction: '하행',
          arrivalMessage: '곧 도착',
          destination: '수서',
          trainType: '일반',
          arrivalSeconds: 30,
          receivedAt: fixedNow,
        ),
      ];

      final result = computeDepartureTime(
        arrivalAsync: AsyncData(arrivals),
        routeResult: route,
        now: fixedNow,
        lineSchedule: makeSchedule(lineId: '3'),
      );

      // 실시간 무시(방향 불일치) → 시간표 기반: 09:05
      expect(result, DateTime(2026, 2, 23, 9, 5));
    });
  });

  group('computeSegmentDepartures', () {
    test('단일 구간이면 출발시각만 반환한다', () {
      final route = makeRouteResult(lineId: '2');
      final departure = DateTime(2026, 2, 23, 9, 5);

      final result = computeSegmentDepartures(
        routeResult: route,
        initialDeparture: departure,
        schedules: {'2': makeSchedule()},
        now: fixedNow,
      );

      expect(result, [departure]);
    });

    test('2개 구간이면 환승 후 시간표 기반 출발시각을 계산한다', () {
      const route = RouteResult(
        segments: [
          RouteSegment(
            lineId: '2',
            lineName: '2호선',
            stations: [
              Station(id: '216', name: '강남', lineId: '2', latitude: 0, longitude: 0),
              Station(id: '222', name: '시청', lineId: '2', latitude: 0, longitude: 0),
            ],
            durationSeconds: 600, // 10분
            direction: '시청 방면',
          ),
          RouteSegment(
            lineId: '3',
            lineName: '3호선',
            stations: [
              Station(id: '330', name: '충무로', lineId: '3', latitude: 0, longitude: 0),
              Station(id: '331', name: '동대입구', lineId: '3', latitude: 0, longitude: 0),
            ],
            durationSeconds: 300, // 5분
            direction: '수서 방면',
          ),
        ],
        totalTimeSeconds: 1080,
        transferCount: 1,
        stationCount: 4,
        transferDurations: [180], // 환승 3분
      );

      final departure = DateTime(2026, 2, 23, 9, 5);
      final schedule3 = LineSchedule(
        lineId: '3',
        weekday: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:00',
          periods: [
            TimePeriod(start: '05:30', end: '09:00', headwayMinutes: 3),
            TimePeriod(start: '09:00', end: '16:30', headwayMinutes: 6),
          ],
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
      );

      final result = computeSegmentDepartures(
        routeResult: route,
        initialDeparture: departure,
        schedules: {'2': makeSchedule(), '3': schedule3},
        now: fixedNow,
      );

      expect(result.length, 2);
      expect(result[0], departure); // 첫 구간 출발: 09:05
      // 첫 구간 종료: 09:15, 환승 3분 → 09:18
      // 3호선 09:00~16:30 배차 6분, 09:18 → 09:00+(3+1)*6 = 09:24
      expect(result[1], DateTime(2026, 2, 23, 9, 24));
    });

    test('시간표가 없는 노선은 환승 후 시각을 그대로 사용한다', () {
      const route = RouteResult(
        segments: [
          RouteSegment(
            lineId: '2',
            lineName: '2호선',
            stations: [
              Station(id: '216', name: '강남', lineId: '2', latitude: 0, longitude: 0),
            ],
            durationSeconds: 300,
            direction: '시청 방면',
          ),
          RouteSegment(
            lineId: 'UNKNOWN',
            lineName: '미등록',
            stations: [
              Station(id: 'U01', name: '역A', lineId: 'UNKNOWN', latitude: 0, longitude: 0),
            ],
            durationSeconds: 200,
            direction: '방면',
          ),
        ],
        totalTimeSeconds: 680,
        transferCount: 1,
        stationCount: 2,
        transferDurations: [180],
      );

      final departure = DateTime(2026, 2, 23, 9, 5);

      final result = computeSegmentDepartures(
        routeResult: route,
        initialDeparture: departure,
        schedules: {'2': makeSchedule()},
        now: fixedNow,
      );

      expect(result.length, 2);
      expect(result[0], departure);
      // 구간 종료 09:10, 환승 3분 → 09:13
      expect(result[1], DateTime(2026, 2, 23, 9, 13));
    });
  });

  group('computeSegmentDepartures - 환승역 실시간 폴백', () {
    // 공통 2구간 경로: 2호선(강남→시청) → 3호선(충무로→동대입구)
    const twoSegmentRoute = RouteResult(
      segments: [
        RouteSegment(
          lineId: '2',
          lineName: '2호선',
          stations: [
            Station(id: '216', name: '강남', lineId: '2', latitude: 0, longitude: 0),
            Station(id: '222', name: '시청', lineId: '2', latitude: 0, longitude: 0),
          ],
          durationSeconds: 600, // 10분
          direction: '시청 방면',
        ),
        RouteSegment(
          lineId: '3',
          lineName: '3호선',
          stations: [
            Station(id: '330', name: '충무로', lineId: '3', latitude: 0, longitude: 0),
            Station(id: '331', name: '동대입구', lineId: '3', latitude: 0, longitude: 0),
          ],
          durationSeconds: 300, // 5분
          direction: '수서 방면',
        ),
      ],
      totalTimeSeconds: 1080,
      transferCount: 1,
      stationCount: 4,
      transferDurations: [180], // 환승 3분
    );

    LineSchedule makeSchedule3() {
      return LineSchedule(
        lineId: '3',
        weekday: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:00',
          periods: [
            TimePeriod(start: '05:30', end: '09:00', headwayMinutes: 3),
            TimePeriod(start: '09:00', end: '16:30', headwayMinutes: 6),
          ],
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
      );
    }

    test('환승역 실시간 데이터가 있으면 시간표보다 우선한다', () {
      final departure = DateTime(2026, 2, 23, 9, 5);
      // 환승역 도착 예정: 09:05 + 10분(구간) + 3분(환승) = 09:18
      // afterTransfer.difference(now) = 18분 = 1080초
      // 실시간: 1200초 후 도착 (09:20) → afterTransfer(09:18) 이후이므로 유효
      final transferArrivals = <String, AsyncValue<List<ArrivalInfo>>>{
        '충무로': AsyncData([
          ArrivalInfo(
            subwayId: '1003',
            stationName: '충무로',
            trainLineNm: '3호선',
            direction: '하행',
            arrivalMessage: '3분 후',
            destination: '수서',
            trainType: '일반',
            arrivalSeconds: 1200,
            receivedAt: fixedNow,
          ),
        ]),
      };

      final result = computeSegmentDepartures(
        routeResult: twoSegmentRoute,
        initialDeparture: departure,
        schedules: {'2': makeSchedule(), '3': makeSchedule3()},
        transferArrivals: transferArrivals,
        now: fixedNow,
      );

      expect(result.length, 2);
      expect(result[0], departure);
      // 실시간: now + 1200초 = 09:00 + 20분 = 09:20
      expect(result[1], fixedNow.add(const Duration(seconds: 1200)));
    });

    test('환승역 실시간 데이터가 afterTransfer 이전이면 무시하고 시간표 폴백', () {
      final departure = DateTime(2026, 2, 23, 9, 5);
      // afterTransfer = 09:18, now = 09:00
      // afterTransfer.difference(now) = 1080초
      // 실시간: 600초 후 도착 (09:10) → afterTransfer(09:18) 이전이므로 무효
      final transferArrivals = <String, AsyncValue<List<ArrivalInfo>>>{
        '충무로': AsyncData([
          ArrivalInfo(
            subwayId: '1003',
            stationName: '충무로',
            trainLineNm: '3호선',
            direction: '하행',
            arrivalMessage: '곧 도착',
            destination: '수서',
            trainType: '일반',
            arrivalSeconds: 600,
            receivedAt: fixedNow,
          ),
        ]),
      };

      final result = computeSegmentDepartures(
        routeResult: twoSegmentRoute,
        initialDeparture: departure,
        schedules: {'2': makeSchedule(), '3': makeSchedule3()},
        transferArrivals: transferArrivals,
        now: fixedNow,
      );

      expect(result.length, 2);
      expect(result[0], departure);
      // 실시간 무효 → 시간표: 09:24
      expect(result[1], DateTime(2026, 2, 23, 9, 24));
    });

    test('환승역 실시간 데이터가 로딩 상태이면 시간표 폴백', () {
      final departure = DateTime(2026, 2, 23, 9, 5);
      final transferArrivals = <String, AsyncValue<List<ArrivalInfo>>>{
        '충무로': const AsyncLoading(),
      };

      final result = computeSegmentDepartures(
        routeResult: twoSegmentRoute,
        initialDeparture: departure,
        schedules: {'2': makeSchedule(), '3': makeSchedule3()},
        transferArrivals: transferArrivals,
        now: fixedNow,
      );

      expect(result.length, 2);
      expect(result[0], departure);
      // 로딩 → 시간표: 09:24
      expect(result[1], DateTime(2026, 2, 23, 9, 24));
    });

    test('환승역 실시간 데이터가 에러 상태이면 시간표 폴백', () {
      final departure = DateTime(2026, 2, 23, 9, 5);
      final transferArrivals = <String, AsyncValue<List<ArrivalInfo>>>{
        '충무로': AsyncError(Exception('네트워크 오류'), StackTrace.current),
      };

      final result = computeSegmentDepartures(
        routeResult: twoSegmentRoute,
        initialDeparture: departure,
        schedules: {'2': makeSchedule(), '3': makeSchedule3()},
        transferArrivals: transferArrivals,
        now: fixedNow,
      );

      expect(result.length, 2);
      expect(result[0], departure);
      // 에러 → 시간표: 09:24
      expect(result[1], DateTime(2026, 2, 23, 9, 24));
    });

    test('방향 필터가 환승역에서도 동작한다', () {
      final departure = DateTime(2026, 2, 23, 9, 5);
      // 3호선 구간은 ID 증가(330→331) = 하행
      // 상행 도착정보만 있으면 매칭 안 됨
      final transferArrivals = <String, AsyncValue<List<ArrivalInfo>>>{
        '충무로': AsyncData([
          ArrivalInfo(
            subwayId: '1003',
            stationName: '충무로',
            trainLineNm: '3호선',
            direction: '상행',
            arrivalMessage: '곧 도착',
            destination: '구파발',
            trainType: '일반',
            arrivalSeconds: 1200,
            receivedAt: fixedNow,
          ),
        ]),
      };

      final result = computeSegmentDepartures(
        routeResult: twoSegmentRoute,
        initialDeparture: departure,
        schedules: {'2': makeSchedule(), '3': makeSchedule3()},
        transferArrivals: transferArrivals,
        now: fixedNow,
      );

      expect(result.length, 2);
      expect(result[0], departure);
      // 방향 불일치(상행 vs 하행) → 시간표: 09:24
      expect(result[1], DateTime(2026, 2, 23, 9, 24));
    });
  });
}
