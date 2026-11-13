import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/line_schedule.dart';
import 'package:busan_subway/domain/entities/route_result.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/route_search/utils/departure_query_time.dart';
import 'package:busan_subway/features/route_search/utils/departure_time_calculator.dart';
import 'package:busan_subway/features/route_search/utils/route_timing.dart';

void main() {
  // 2026-02-23(월) 09:00 — 평일 시간표를 쓰는 고정 기준 시각.
  final wallClock = DateTime(2026, 2, 23, 9, 0);
  final query = DepartureQueryTime.nowAt(wallClock);

  Station station(String id, String lineId) => Station(
        id: id,
        name: '역$id',
        lineId: lineId,
        latitude: 0,
        longitude: 0,
      );

  /// 배차간격만 있는(역별 시간표 없는) 노선 시간표.
  LineSchedule scheduleWithHeadway(String lineId, int headwayMinutes) {
    final day = DaySchedule(
      firstTrain: '05:00',
      lastTrain: '00:00',
      periods: [
        TimePeriod(start: '05:00', end: '00:00', headwayMinutes: headwayMinutes),
      ],
    );
    return LineSchedule(lineId: lineId, weekday: day, weekend: day);
  }

  /// 환승 1회 경로 — A선 1역 → 환승 → B선 1역.
  RouteResult transferRoute({
    required int walkSeconds,
    required int estimatedWaitSeconds,
  }) {
    return RouteResult(
      segments: [
        RouteSegment(
          lineId: 'A',
          lineName: 'A선',
          stations: [station('101', 'A'), station('102', 'A')],
          durationSeconds: 120,
          direction: '하행',
        ),
        RouteSegment(
          lineId: 'B',
          lineName: 'B선',
          stations: [station('201', 'B'), station('202', 'B')],
          durationSeconds: 120,
          direction: '하행',
        ),
      ],
      totalTimeSeconds: 240 + walkSeconds + estimatedWaitSeconds,
      transferCount: 1,
      stationCount: 2,
      transferDurations: [walkSeconds + estimatedWaitSeconds],
      transferWalkDurations: [walkSeconds],
    );
  }

  /// 환승 없는 직통 경로 — A선만 타고 [durationSeconds] 만큼 간다.
  RouteResult directRoute(int durationSeconds) {
    return RouteResult(
      segments: [
        RouteSegment(
          lineId: 'A',
          lineName: 'A선',
          stations: [station('101', 'A'), station('109', 'A')],
          durationSeconds: durationSeconds,
          direction: '하행',
        ),
      ],
      totalTimeSeconds: durationSeconds,
      transferCount: 0,
      stationCount: 1,
    );
  }

  RouteTiming? timingOf(
    RouteResult route,
    Map<String, LineSchedule> schedules,
  ) {
    return computeRouteTiming(
      routeResult: route,
      query: query,
      wallClock: wallClock,
      schedules: schedules,
    );
  }

  group('computeRouteTiming', () {
    test('세그먼트가 없으면 null', () {
      const empty = RouteResult(
        segments: [],
        totalTimeSeconds: 0,
        transferCount: 0,
        stationCount: 0,
      );
      expect(timingOf(empty, {'A': scheduleWithHeadway('A', 3)}), isNull);
    });

    test('환승 대기는 그래프 추정치가 아니라 시간표의 다음 열차로 잡힌다', () {
      // A선 3분 배차 → 09:03 출발, 09:05 환승역 도착.
      // 도보 2분 → 09:07 승강장. B선 20분 배차의 다음 열차는 09:20.
      final timing = timingOf(
        transferRoute(walkSeconds: 120, estimatedWaitSeconds: 600),
        {
          'A': scheduleWithHeadway('A', 3),
          'B': scheduleWithHeadway('B', 20),
        },
      );

      expect(timing, isNotNull);
      expect(timing!.departure, DateTime(2026, 2, 23, 9, 3));
      // 그래프 추정 대기(10분)를 기준 시각에 더했다면 09:17 이후를 뒤져
      // 09:20 이 아니라 09:40 열차가 잡힌다(이중 계상).
      expect(timing.segmentDepartures[1], DateTime(2026, 2, 23, 9, 20));
      expect(timing.arrival, DateTime(2026, 2, 23, 9, 22));
    });
  });

  group('compareByArrival — 탭 순서 판정', () {
    // 두 후보의 그래프 비용은 환승 경로가 더 짧다(240s + 도보 120s + 대기 추정
    // 240s = 600s < 직통 900s). 그래서 `SearchRoute` 는 환승 경로를 "최단시간",
    // 직통을 "최소환승" 으로 내놓는다. 그러나 실제 도착 시각은 환승 노선의
    // 배차에 따라 뒤집힐 수 있다 — 그 역전을 잡아내는 것이 이 판정이다.
    final transfer = transferRoute(walkSeconds: 120, estimatedWaitSeconds: 240);
    final direct = directRoute(900);

    test('환승 노선 배차가 길면 직통(최소환승)이 먼저 도착한다', () {
      final schedules = {
        'A': scheduleWithHeadway('A', 3),
        'B': scheduleWithHeadway('B', 20),
      };
      // 환승: 09:03 출발 → 09:20 재승차 → 09:22 도착.
      // 직통: 09:03 출발 → 09:18 도착.
      final result = compareByArrival(
        timingOf(direct, schedules),
        timingOf(transfer, schedules),
      );
      expect(result, isNotNull);
      expect(result! < 0, isTrue, reason: '직통이 먼저 도착 → 탭 순서를 바꿔야 한다');
    });

    test('환승 노선 배차가 짧으면 환승 경로(최단시간)가 먼저 도착한다', () {
      final schedules = {
        'A': scheduleWithHeadway('A', 3),
        'B': scheduleWithHeadway('B', 2),
      };
      final result = compareByArrival(
        timingOf(direct, schedules),
        timingOf(transfer, schedules),
      );
      expect(result, isNotNull);
      expect(result! > 0, isTrue, reason: '기존 순서(최단시간 먼저)를 유지해야 한다');
    });

    test('시각을 못 구하면(운행 시간 외) null — 호출측은 순서를 유지한다', () {
      // 시간표가 없는 노선 → source unavailable.
      final result = compareByArrival(
        timingOf(direct, const {}),
        timingOf(transfer, const {}),
      );
      expect(result, isNull);
    });

    test('한쪽이 null 이면 null', () {
      const empty = RouteResult(
        segments: [],
        totalTimeSeconds: 0,
        transferCount: 0,
        stationCount: 0,
      );
      final schedules = {'A': scheduleWithHeadway('A', 3)};
      expect(
        compareByArrival(
          timingOf(empty, schedules),
          timingOf(direct, schedules),
        ),
        isNull,
      );
    });
  });

  group('RouteTiming.totalMinutes', () {
    test('탑승부터 도착까지만 센다 (탑승 전 대기 제외)', () {
      final timing = timingOf(
        directRoute(900),
        {'A': scheduleWithHeadway('A', 3)},
      );
      // 09:00 조회 → 09:03 탑승 → 09:18 도착. 대기 3분은 빠진다.
      expect(timing!.departure, DateTime(2026, 2, 23, 9, 3));
      expect(timing.totalMinutes, 15);
      expect(timing.source, DepartureSource.timetable);
    });
  });

  group('routeExpressRunsOnDay', () {
    /// 역별 완행 시간표는 있고, 급행 시간표는 [express] 로 제어하는 노선.
    LineSchedule scheduleWithStationTimes(
      String lineId, {
      required List<int> local,
      List<int>? express,
    }) {
      final day = DaySchedule(
        firstTrain: '05:00',
        lastTrain: '00:00',
        periods: const [
          TimePeriod(start: '05:00', end: '00:00', headwayMinutes: 5),
        ],
        // 두 세그먼트의 출발역(101 / 201)에 같은 목록을 달아 둔다.
        stationDepartures: {'101': local, '201': local},
        expressStationDepartures:
            express == null ? null : {'101': express, '201': express},
      );
      return LineSchedule(lineId: lineId, weekday: day, weekend: day);
    }

    /// 첫 구간이 **완행**(A), 환승 후 두 번째 구간이 **급행**(`BE`)인 경로.
    ///
    /// `SearchRoute` 는 경로가 급행 edge 를 하나라도 쓰면 급행/완행 탭을 만들기
    /// 때문에(`expressUsed`) 이런 조합이 실재한다 — 주석의 총신대입구→마곡나루.
    final expressOnSecondSegment = RouteResult(
      segments: [
        RouteSegment(
          lineId: 'A',
          lineName: 'A선',
          stations: [station('101', 'A'), station('102', 'A')],
          durationSeconds: 120,
          direction: '하행',
        ),
        RouteSegment(
          lineId: 'BE',
          lineName: 'B선',
          stations: [station('201', 'B'), station('202', 'B')],
          durationSeconds: 120,
          direction: '하행',
        ),
      ],
      totalTimeSeconds: 240,
      transferCount: 1,
      stationCount: 2,
      transferDurations: const [120],
      transferWalkDurations: const [60],
    );

    test('첫 구간이 완행이어도 뒤쪽 급행 구간의 결손을 잡아낸다 (회귀 가드)', () {
      // 회귀 가드: 초기 구현은 `resolveDepartureContext`(= 첫 방향 판별 세그먼트)
      // 만 봐서 첫 구간이 완행이면 급행 결손을 통과시켰다. 그 경로는
      // `computeSegmentDepartures` 의 3순위 폴백으로 조작된 환승 출발시각을
      // 표시하면서도 탭이 그대로 남았다.
      final schedules = {
        'A': scheduleWithStationTimes('A', local: [480]),
        // B 노선에 완행은 있고 급행(tE)은 없다 — 경춘·수인분당 주말 재현.
        'B': scheduleWithStationTimes('B', local: [480]),
      };

      expect(
        routeExpressRunsOnDay(
          routeResult: expressOnSecondSegment,
          query: query,
          schedules: schedules,
          wallClock: wallClock,
        ),
        isFalse,
      );
    });

    test('뒤쪽 급행 구간에 시간표가 있으면 통과한다 (과잉 차단 방지)', () {
      final schedules = {
        'A': scheduleWithStationTimes('A', local: [480]),
        'B': scheduleWithStationTimes('B', local: [480], express: [490]),
      };

      expect(
        routeExpressRunsOnDay(
          routeResult: expressOnSecondSegment,
          query: query,
          schedules: schedules,
          wallClock: wallClock,
        ),
        isTrue,
      );
    });

    test('급행 구간이 없는 경로는 완행 시간표 유무와 무관하게 통과한다', () {
      // 완행 구간은 검사 대상이 아니다 — 23개 노선 전 역이 `t` 를 보유하고,
      // 비어 있는 경우는 종착역의 진행 불가 방향뿐이라 경로가 만들어지지 않는다.
      expect(
        routeExpressRunsOnDay(
          routeResult: directRoute(900),
          query: query,
          schedules: {'A': scheduleWithHeadway('A', 3)}, // 역별 시간표 없음
          wallClock: wallClock,
        ),
        isTrue,
      );
    });

    test('시간표 로딩 전(schedules 비어 있음)에는 내리지 않는다 (fail-open)', () {
      expect(
        routeExpressRunsOnDay(
          routeResult: expressOnSecondSegment,
          query: query,
          schedules: const {},
          wallClock: wallClock,
        ),
        isTrue,
      );
    });
  });
}
