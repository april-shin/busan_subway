import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/usecases/find_next_departure.dart';
import 'package:seoul_subway/features/route_search/utils/departure_candidates.dart';
import 'package:seoul_subway/features/route_search/utils/departure_query_time.dart';

void main() {
  final monday = DateTime(2026, 2, 23, 9, 0); // 월요일

  const periods = [TimePeriod(start: '05:00', end: '00:00', headwayMinutes: 5)];

  /// 완행/급행·상하행·평일/주말을 모두 다르게 채운 스케줄.
  /// 어느 맵을 조회했는지 값만 보고 구분할 수 있게 의도적으로 겹치지 않게 둔다.
  LineSchedule makeSchedule() {
    return const LineSchedule(
      lineId: '9',
      weekday: DaySchedule(
        firstTrain: '05:30',
        lastTrain: '00:50',
        periods: periods,
        stationDepartures: {
          '901': [330, 342, 354, 1489], // 05:30, 05:42, 05:54, 24:49
        },
        expressStationDepartures: {
          '901': [335, 350, 365],
        },
      ),
      weekend: DaySchedule(
        firstTrain: '05:40',
        lastTrain: '00:40',
        periods: periods,
        stationDepartures: {
          '901': [340, 352],
        },
        // 주말 급행 데이터 없음 (경춘·수인분당의 we.tE 공백 케이스)
      ),
      weekdayDown: DaySchedule(
        firstTrain: '05:35',
        lastTrain: '00:45',
        periods: periods,
        stationDepartures: {
          '901': [335, 347],
        },
      ),
    );
  }

  DateTime anchor(DepartureDayType type) => anchorDateFor(type, monday);

  group('buildDepartureCandidates', () {
    test('평일 상행 완행 시간표를 반환한다', () {
      final result = buildDepartureCandidates(
        schedule: makeSchedule(),
        anchorDate: anchor(DepartureDayType.weekday),
        isDown: false,
        stationId: '901',
        express: false,
      );
      expect(result, [330, 342, 354, 1489]);
    });

    test('하행은 하행 전용 시간표를 반환한다', () {
      final result = buildDepartureCandidates(
        schedule: makeSchedule(),
        anchorDate: anchor(DepartureDayType.weekday),
        isDown: true,
        stationId: '901',
        express: false,
      );
      expect(result, [335, 347]);
    });

    test('주말은 주말 시간표를 반환한다', () {
      final result = buildDepartureCandidates(
        schedule: makeSchedule(),
        anchorDate: anchor(DepartureDayType.weekend),
        isDown: false,
        stationId: '901',
        express: false,
      );
      expect(result, [340, 352]);
    });

    test('급행은 급행 시간표만 조회하고 완행과 섞지 않는다', () {
      final result = buildDepartureCandidates(
        schedule: makeSchedule(),
        anchorDate: anchor(DepartureDayType.weekday),
        isDown: false,
        stationId: '901',
        express: true,
      );
      expect(result, [335, 350, 365]);
    });

    test('급행 데이터가 없는 요일은 배차간격으로 합성하지 않고 빈 리스트', () {
      final result = buildDepartureCandidates(
        schedule: makeSchedule(),
        anchorDate: anchor(DepartureDayType.weekend),
        isDown: false,
        stationId: '901',
        express: true,
      );
      expect(result, isEmpty);
    });

    test('역별 시간표가 없는 역은 빈 리스트', () {
      final result = buildDepartureCandidates(
        schedule: makeSchedule(),
        anchorDate: anchor(DepartureDayType.weekday),
        isDown: false,
        stationId: '999',
        express: false,
      );
      expect(result, isEmpty);
    });

    test('역별 시간표 자체가 없으면 빈 리스트', () {
      // 실데이터는 23개 노선 전부 완행 시간표를 갖지만, 급행(tE)은 4개
      // 노선뿐이라 이 경로는 여전히 유효하다.
      const noStationTable = LineSchedule(
        lineId: 'NOTT',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:00',
          periods: periods,
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:00',
          periods: periods,
        ),
      );
      final result = buildDepartureCandidates(
        schedule: noStationTable,
        anchorDate: anchor(DepartureDayType.weekday),
        isDown: false,
        stationId: '901',
        express: false,
      );
      expect(result, isEmpty);
    });

    test('schedule 이 null 이면 빈 리스트', () {
      final result = buildDepartureCandidates(
        schedule: null,
        anchorDate: anchor(DepartureDayType.weekday),
        isDown: false,
        stationId: '901',
        express: false,
      );
      expect(result, isEmpty);
    });
  });

  group('findUpcomingDeparture', () {
    // 자정 넘김 인코딩이 노선마다 달라(1440+ vs 0~1439) 원값 비교로는 심야
    // 열차가 하루의 시작으로 오인된다. operatingSortKey 로 정규화해야 한다.
    test('주간 시각 — 그 이후 첫 열차', () {
      final candidates = [330, 342, 354, 1489]; // 05:30, 05:42, 05:54, 24:49
      expect(findUpcomingDeparture(candidates, 340), 342);
      expect(findUpcomingDeparture(candidates, 342), 342, reason: '동일 분 포함');
      expect(findUpcomingDeparture(candidates, 400), 1489);
    });

    test('1440+ 인코딩 — 심야에도 심야 열차를 고른다', () {
      final candidates = [330, 1489]; // 05:30, 24:49
      // 00:30 → 운영일 기준 24:30 → 24:49 가 다음.
      expect(findUpcomingDeparture(candidates, 30), 1489);
      // 00:50 → 24:50 → 24:49 는 이미 지남 → 없음(운행 종료).
      expect(findUpcomingDeparture(candidates, 50), isNull);
    });

    test('0~1439 인코딩(경의중앙식) — 심야 값도 하루의 끝으로 취급', () {
      // 표시 순서 = buildDepartureCandidates 결과(정상 시간대 → 심야).
      final candidates = [330, 1400, 1, 19];
      // 00:00 시점이면 00:01 이 다음.
      expect(findUpcomingDeparture(candidates, 0), 1);
      // 00:10 이면 00:19.
      expect(findUpcomingDeparture(candidates, 10), 19);
      // 05:00 이면 하루의 시작이므로 05:30.
      expect(findUpcomingDeparture(candidates, 300), 330);
      // 00:30 이면 심야 열차가 모두 지났으므로 없음(운행 종료).
      expect(findUpcomingDeparture(candidates, 30), isNull);
    });

    test('막차 이후면 null', () {
      expect(findUpcomingDeparture([330, 342], 1400), isNull);
    });

    test('빈 목록은 null', () {
      expect(findUpcomingDeparture([], 600), isNull);
    });
  });

  group('operatingSortKey', () {
    test('컷오프 이전 값은 하루의 끝으로 밀린다', () {
      expect(operatingSortKey(1), 1441);
      expect(operatingSortKey(239), 1679);
      expect(operatingSortKey(240), 240);
      expect(operatingSortKey(330), 330);
      expect(operatingSortKey(1489), 1489);
    });

    test('첫차보다 심야가 항상 뒤', () {
      expect(operatingSortKey(1), greaterThan(operatingSortKey(330)));
      expect(operatingSortKey(19), greaterThan(operatingSortKey(1400)));
    });
  });

  group('resolveInitialScrollRow', () {
    // 표시 순서: 정상 시간대 → 심야(목록 끝). 경의중앙식 인코딩 재현.
    final rows = groupDeparturesByHour([330, 342, 400, 1400, 1, 19]);
    // rows = [5시:[330,342], 6시:[400], 23시:[1400], 0시:[1,19]]

    test('고른 시각이 있으면 그 칩이 든 행', () {
      expect(
        resolveInitialScrollRow(
            rows: rows, selectedMinutes: 400, upcomingMinutes: 1400),
        1,
        reason: '선택이 현재 시각보다 우선한다',
      );
    });

    test('심야 선택도 목록 끝 행을 정확히 찾는다', () {
      expect(
        resolveInitialScrollRow(
            rows: rows, selectedMinutes: 19, upcomingMinutes: null),
        3,
        reason: '0시 행이 맨 뒤(index 3)로 재배치돼 있다',
      );
    });

    test('선택이 없으면 현재 시각 이후 첫 열차 행', () {
      expect(
        resolveInitialScrollRow(
            rows: rows, selectedMinutes: null, upcomingMinutes: 1400),
        2,
      );
      expect(
        resolveInitialScrollRow(
            rows: rows, selectedMinutes: null, upcomingMinutes: 330),
        0,
      );
    });

    test('둘 다 없으면(막차 이후) 마지막 행', () {
      expect(
        resolveInitialScrollRow(
            rows: rows, selectedMinutes: null, upcomingMinutes: null),
        rows.length - 1,
      );
    });

    test('앵커가 목록에 없으면 마지막 행으로 폴백', () {
      expect(
        resolveInitialScrollRow(
            rows: rows, selectedMinutes: 999, upcomingMinutes: null),
        rows.length - 1,
      );
    });

    test('빈 목록은 -1', () {
      expect(
        resolveInitialScrollRow(
            rows: const [], selectedMinutes: 330, upcomingMinutes: null),
        -1,
      );
    });
  });

  group('groupDeparturesByHour', () {
    test('시 단위로 묶고 입력 순서를 유지한다', () {
      final grouped = groupDeparturesByHour([330, 342, 354, 400, 1489]);
      expect(grouped.map((r) => r.hour).toList(), [5, 6, 24]);
      expect(grouped[0].minutes, [330, 342, 354]);
      expect(grouped[1].minutes, [400]);
      expect(grouped[2].minutes, [1489]);
    });

    test('자정 넘김 행은 맨 끝에 온다', () {
      final grouped = groupDeparturesByHour([330, 1439, 1440, 1489]);
      expect(grouped.last.hour, 24);
      expect(grouped.map((r) => r.hour).toList(), [5, 23, 24]);
    });

    test('빈 입력은 빈 결과', () {
      expect(groupDeparturesByHour([]), isEmpty);
    });
  });

  // 이 기능의 핵심 계약 — 목록에 보인 시각을 고르면 **정확히 그 열차**가 잡혀야
  // 한다. resolveQueryDateTime 의 1분 빼기 규칙과 findNextDeparture 의 strict `>`
  // 탐색이 어긋나면 여기서 깨진다.
  group('왕복 계약: 후보 → 해석 → findNextDeparture', () {
    void verifyRoundTrip({
      required DepartureDayType dayType,
      required bool isDown,
      required bool express,
    }) {
      final schedule = makeSchedule();
      final anchorDate = anchorDateFor(dayType, monday);
      final candidates = buildDepartureCandidates(
        schedule: schedule,
        anchorDate: anchorDate,
        isDown: isDown,
        stationId: '901',
        express: express,
      );
      expect(candidates, isNotEmpty, reason: '테스트 전제: 후보가 있어야 한다');

      for (final minutes in candidates) {
        final query =
            DepartureQueryTime(minutes: minutes, dayType: dayType);
        final resolved = resolveQueryDateTime(query, monday);

        final actual = findNextDeparture(
          schedule: schedule,
          now: resolved,
          isDown: isDown,
          stationId: '901',
          express: express,
        );

        expect(actual, isNotNull,
            reason: '$minutes 분 후보를 골랐는데 열차를 못 찾음');
        // 반환 시각을 앵커 기준 분으로 환산해 후보와 일치하는지 확인.
        final actualMinutes = actual!.difference(anchorDate).inMinutes;
        expect(
          actualMinutes,
          minutes,
          reason: '후보 ${formatOperatingMinutes(minutes)} 를 골랐는데 '
              '${formatOperatingMinutes(actualMinutes)} 가 잡힘',
        );
      }
    }

    test('평일 상행 완행 (자정 넘김 1489 포함)', () {
      verifyRoundTrip(
        dayType: DepartureDayType.weekday,
        isDown: false,
        express: false,
      );
    });

    test('평일 하행 완행', () {
      verifyRoundTrip(
        dayType: DepartureDayType.weekday,
        isDown: true,
        express: false,
      );
    });

    test('평일 상행 급행', () {
      verifyRoundTrip(
        dayType: DepartureDayType.weekday,
        isDown: false,
        express: true,
      );
    });

    test('주말 상행 완행', () {
      verifyRoundTrip(
        dayType: DepartureDayType.weekend,
        isDown: false,
        express: false,
      );
    });
  });
}
