import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/usecases/find_next_departure.dart';

void main() {
  LineSchedule makeSchedule() {
    return const LineSchedule(
      lineId: '2',
      weekday: DaySchedule(
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
      weekend: DaySchedule(
        firstTrain: '05:30',
        lastTrain: '23:40',
        periods: [
          TimePeriod(start: '05:30', end: '23:40', headwayMinutes: 6),
        ],
      ),
    );
  }

  group('findNextDeparture', () {
    test('첫차 전이면 첫차 시각을 반환한다', () {
      // 평일 04:30
      final now = DateTime(2026, 2, 23, 4, 30); // 월요일
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      expect(result, DateTime(2026, 2, 23, 5, 0));
    });

    test('막차 이후이면 null을 반환한다', () {
      // 주말 23:50 (주말 막차 23:40)
      final now = DateTime(2026, 2, 22, 23, 50); // 일요일
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      expect(result, isNull);
    });

    test('평일 자정 전이면 null을 반환하지 않는다 (막차 00:00)', () {
      // 평일 23:30
      final now = DateTime(2026, 2, 23, 23, 30); // 월요일
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      // 21:00~00:00 시간대, 배차 8분
      // 23:30 → (23:30-21:00)/8 = 150/8 = 18.x → 다음 출발 21:00 + 19*8 = 21:00 + 152 = 23:32
      expect(result, isNotNull);
      expect(result!.hour, 23);
      expect(result.minute, 32);
    });

    test('러시아워(06:30~09:00)에는 3분 배차를 사용한다', () {
      final now = DateTime(2026, 2, 23, 7, 0); // 월요일 07:00
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      // 06:30~09:00, 배차 3분
      // 07:00 → (30)/3 = 10 → 다음: 06:30 + 11*3 = 06:30 + 33 = 07:03
      expect(result, DateTime(2026, 2, 23, 7, 3));
    });

    test('비첨두(09:00~16:30)에는 5분 배차를 사용한다', () {
      final now = DateTime(2026, 2, 23, 10, 0); // 월요일 10:00
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      // 09:00~16:30, 배차 5분
      // 10:00 → (60)/5 = 12 → 다음: 09:00 + 13*5 = 09:00 + 65 = 10:05
      expect(result, DateTime(2026, 2, 23, 10, 5));
    });

    test('주말에는 주말 스케줄을 사용한다', () {
      // 토요일 10:00
      final now = DateTime(2026, 2, 21, 10, 0); // 토요일
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      // 주말: 05:30~23:40, 배차 6분
      // 10:00 → (270)/6 = 45 → 다음: 05:30 + 46*6 = 05:30 + 276 = 10:06
      expect(result, DateTime(2026, 2, 21, 10, 6));
    });

    test('일요일에도 주말 스케줄을 사용한다', () {
      final now = DateTime(2026, 2, 22, 8, 0); // 일요일
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      // 주말: 배차 6분
      // 08:00 → (150)/6 = 25 → 다음: 05:30 + 26*6 = 05:30 + 156 = 08:06
      expect(result, DateTime(2026, 2, 22, 8, 6));
    });

    test('시간대 경계에서 다음 시간대로 넘어간다', () {
      // 06:28 → 05:00~06:30 시간대, 배차 5분
      final now = DateTime(2026, 2, 23, 6, 28); // 월요일
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      // (88)/5 = 17.6 → 다음: 05:00 + 18*5 = 05:00 + 90 = 06:30
      // 06:30은 다음 시간대 시작 → 06:30 반환
      expect(result, DateTime(2026, 2, 23, 6, 30));
    });

    test('정확히 시간대 시작 시각이면 다음 배차를 반환한다', () {
      final now = DateTime(2026, 2, 23, 9, 0); // 정확히 09:00
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      // 09:00~16:30, 배차 5분, elapsed=0, intervalsPassed=0 → 다음: 09:05
      expect(result, DateTime(2026, 2, 23, 9, 5));
    });
  });

  group('findNextDeparture - 방향별', () {
    LineSchedule makeScheduleWithDown() {
      return const LineSchedule(
        lineId: '3',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:00',
          periods: [
            TimePeriod(start: '05:30', end: '09:00', headwayMinutes: 3),
            TimePeriod(start: '09:00', end: '00:00', headwayMinutes: 5),
          ],
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 6),
          ],
        ),
        weekdayDown: DaySchedule(
          firstTrain: '05:20',
          lastTrain: '23:50',
          periods: [
            TimePeriod(start: '05:20', end: '09:00', headwayMinutes: 4),
            TimePeriod(start: '09:00', end: '23:50', headwayMinutes: 6),
          ],
        ),
      );
    }

    test('isDown=false이면 상행 스케줄을 사용한다', () {
      final now = DateTime(2026, 2, 23, 4, 30); // 월요일, 첫차 전
      final result = findNextDeparture(
        schedule: makeScheduleWithDown(),
        now: now,
        isDown: false,
      );

      // 상행 첫차: 05:30
      expect(result, DateTime(2026, 2, 23, 5, 30));
    });

    test('isDown=true이면 하행 스케줄을 사용한다', () {
      final now = DateTime(2026, 2, 23, 4, 30); // 월요일, 첫차 전
      final result = findNextDeparture(
        schedule: makeScheduleWithDown(),
        now: now,
        isDown: true,
      );

      // 하행 첫차: 05:20
      expect(result, DateTime(2026, 2, 23, 5, 20));
    });

    test('하행에서 다른 배차간격을 사용한다', () {
      final now = DateTime(2026, 2, 23, 10, 0); // 월요일 10:00
      final resultUp = findNextDeparture(
        schedule: makeScheduleWithDown(),
        now: now,
        isDown: false,
      );
      final resultDn = findNextDeparture(
        schedule: makeScheduleWithDown(),
        now: now,
        isDown: true,
      );

      // 상행: 09:00~00:00 배차 5분 → 10:05
      expect(resultUp, DateTime(2026, 2, 23, 10, 5));
      // 하행: 09:00~23:50 배차 6분 → 10:06
      expect(resultDn, DateTime(2026, 2, 23, 10, 6));
    });

    test('하행 데이터 없으면 상행으로 폴백한다', () {
      final now = DateTime(2026, 2, 23, 4, 30);
      final result = findNextDeparture(
        schedule: makeSchedule(), // weekdayDown 없음
        now: now,
        isDown: true,
      );

      // 상행과 동일: 05:00
      expect(result, DateTime(2026, 2, 23, 5, 0));
    });

    test('기본 isDown=false로 기존 동작 유지', () {
      final now = DateTime(2026, 2, 23, 4, 30);
      final result = findNextDeparture(
        schedule: makeSchedule(),
        now: now,
      );

      expect(result, DateTime(2026, 2, 23, 5, 0));
    });
  });

  group('findNextDeparture - 역별 시간표', () {
    LineSchedule makeScheduleWithStationDepartures() {
      return LineSchedule(
        lineId: '김포골드',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:55',
          periods: const [
            TimePeriod(start: '05:30', end: '23:55', headwayMinutes: 6),
          ],
          stationDepartures: const {
            'P01': [330, 350, 370, 390, 410],
            'P05': [335, 345, 355, 365, 375],
          },
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
        weekdayDown: DaySchedule(
          firstTrain: '05:26',
          lastTrain: '23:50',
          periods: const [
            TimePeriod(start: '05:26', end: '23:50', headwayMinutes: 6),
          ],
          stationDepartures: const {
            'P01': [327, 340, 360, 380, 400],
            'P05': [332, 342, 352, 362, 372],
          },
        ),
      );
    }

    test('stationId 지정 시 정확한 출발시각을 반환한다', () {
      // 05:40 (340분) → P01 상행: [330, 350, ...] → 350분(05:50)
      final now = DateTime(2026, 2, 23, 5, 40);
      final result = findNextDeparture(
        schedule: makeScheduleWithStationDepartures(),
        now: now,
        stationId: 'P01',
      );

      expect(result, DateTime(2026, 2, 23, 5, 50));
    });

    test('stationId 지정 + isDown=true이면 하행 시간표를 사용한다', () {
      // 05:40 (340분) → P01 하행: [327, 340, 360, ...] → 360분(06:00)
      // 340은 현재 시각과 같으므로 다음인 360 반환
      final now = DateTime(2026, 2, 23, 5, 40);
      final result = findNextDeparture(
        schedule: makeScheduleWithStationDepartures(),
        now: now,
        isDown: true,
        stationId: 'P01',
      );

      expect(result, DateTime(2026, 2, 23, 6, 0));
    });

    test('현재 시각 이후 출발이 없으면 null을 반환한다', () {
      // 07:00 (420분) → P01 상행: [330, 350, 370, 390, 410] → 모두 ≤420 → null
      final now = DateTime(2026, 2, 23, 7, 0);
      final result = findNextDeparture(
        schedule: makeScheduleWithStationDepartures(),
        now: now,
        stationId: 'P01',
      );

      expect(result, isNull);
    });

    test('stationId가 시간표에 없으면 배차간격으로 폴백한다', () {
      // P09는 stationDepartures에 없음 → 배차간격 6분 사용
      final now = DateTime(2026, 2, 23, 10, 0);
      final result = findNextDeparture(
        schedule: makeScheduleWithStationDepartures(),
        now: now,
        stationId: 'P09',
      );

      // 배차간격 폴백: 05:30~23:55, 6분 간격
      expect(result, isNotNull);
    });

    test('stationId가 null이면 배차간격으로 폴백한다', () {
      final now = DateTime(2026, 2, 23, 10, 0);
      final result = findNextDeparture(
        schedule: makeScheduleWithStationDepartures(),
        now: now,
      );

      // stationId null → 배차간격 사용
      expect(result, isNotNull);
    });

    test('주말에는 stationDepartures가 없으면 배차간격을 사용한다', () {
      // 주말 스케줄에 stationDepartures 없음
      final now = DateTime(2026, 2, 22, 10, 0); // 일요일
      final result = findNextDeparture(
        schedule: makeScheduleWithStationDepartures(),
        now: now,
        stationId: 'P01',
      );

      // 주말 배차 8분 → 폴백
      expect(result, isNotNull);
    });

    test('정확히 출발 시각이면 다음 출발을 반환한다', () {
      // P05 상행: [335, 345, 355, 365, 375]
      // 현재 345분(05:45) → 다음은 355분(05:55)
      final now = DateTime(2026, 2, 23, 5, 45);
      final result = findNextDeparture(
        schedule: makeScheduleWithStationDepartures(),
        now: now,
        stationId: 'P05',
      );

      expect(result, DateTime(2026, 2, 23, 5, 55));
    });
  });

  group('getExpectedWaitMinutes', () {
    test('러시아워 평균 대기시간은 배차간격/2이다', () {
      final now = DateTime(2026, 2, 23, 8, 0); // 월요일 08:00
      final result = getExpectedWaitMinutes(
        schedule: makeSchedule(),
        now: now,
      );

      // 배차 3분 → 평균 대기 2분 (올림)
      expect(result, 2);
    });

    test('비첨두 평균 대기시간을 올바르게 계산한다', () {
      final now = DateTime(2026, 2, 23, 12, 0); // 월요일 12:00
      final result = getExpectedWaitMinutes(
        schedule: makeSchedule(),
        now: now,
      );

      // 배차 5분 → 평균 대기 3분 (올림)
      expect(result, 3);
    });

    test('심야 시간대 배차간격을 사용한다', () {
      final now = DateTime(2026, 2, 23, 22, 0); // 월요일 22:00
      final result = getExpectedWaitMinutes(
        schedule: makeSchedule(),
        now: now,
      );

      // 배차 8분 → 평균 대기 4분
      expect(result, 4);
    });

    test('역별 시간표가 있으면 정확한 대기시간을 반환한다', () {
      final schedule = LineSchedule(
        lineId: '김포골드',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:55',
          periods: const [
            TimePeriod(start: '05:30', end: '23:55', headwayMinutes: 6),
          ],
          stationDepartures: const {
            'P05': [335, 345, 355, 365, 375, 600, 610, 620],
          },
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
      );

      // 현재 05:48 (348분) → P05 상행: [335, 345, 355, ...] → 다음 355분(05:55)
      // 대기: 355 - 348 = 7분
      final now = DateTime(2026, 2, 23, 5, 48);
      final result = getExpectedWaitMinutes(
        schedule: schedule,
        now: now,
        stationId: 'P05',
      );

      expect(result, 7);
    });

    test('역별 시간표에서 1분 미만 대기는 1분을 반환한다', () {
      final schedule = LineSchedule(
        lineId: '김포골드',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:55',
          periods: const [
            TimePeriod(start: '05:30', end: '23:55', headwayMinutes: 6),
          ],
          stationDepartures: const {
            'P05': [335, 336, 345],
          },
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
      );

      // 현재 05:35 (335분) → 다음 336분 → 대기 1분 미만 → 1 반환
      final now = DateTime(2026, 2, 23, 5, 35);
      final result = getExpectedWaitMinutes(
        schedule: schedule,
        now: now,
        stationId: 'P05',
      );

      expect(result, 1);
    });
  });
}
