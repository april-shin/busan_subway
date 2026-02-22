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
  });
}
