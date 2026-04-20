import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/headway_estimator.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';

LineSchedule _scheduleWith({
  required List<TimePeriod> weekdayPeriods,
}) {
  return LineSchedule(
    lineId: 'test',
    weekday: DaySchedule(
      firstTrain: '05:00',
      lastTrain: '23:30',
      periods: weekdayPeriods,
    ),
    weekend: const DaySchedule(
      firstTrain: '05:00',
      lastTrain: '23:30',
      periods: [],
    ),
  );
}

void main() {
  group('estimateHeadwaySeconds', () {
    test('평일 평시(10~16) 구간 평균 사용', () {
      final schedule = _scheduleWith(weekdayPeriods: const [
        TimePeriod(start: '05:00', end: '07:00', headwayMinutes: 10), // 평시 외
        TimePeriod(start: '10:00', end: '12:00', headwayMinutes: 4),
        TimePeriod(start: '12:00', end: '16:00', headwayMinutes: 6),
        TimePeriod(start: '20:00', end: '23:00', headwayMinutes: 8), // 평시 외
      ]);

      // 평시 두 항목 평균 = (4+6)/2 = 5분 → 300초
      expect(estimateHeadwaySeconds(schedule), 300);
    });

    test('평시 구간이 없으면 평일 전체 평균 폴백', () {
      final schedule = _scheduleWith(weekdayPeriods: const [
        TimePeriod(start: '05:00', end: '07:00', headwayMinutes: 10),
        TimePeriod(start: '07:00', end: '09:00', headwayMinutes: 6),
      ]);

      // 평시 항목 0개 → 전체 평균 (10+6)/2 = 8분 → 480초
      expect(estimateHeadwaySeconds(schedule), 480);
    });

    test('평일 periods가 비어있으면 기본값 180초 폴백', () {
      final schedule = _scheduleWith(weekdayPeriods: const []);
      expect(estimateHeadwaySeconds(schedule), 180);
    });

    test('평시 시간대와 부분적으로 겹치는 구간도 포함된다', () {
      final schedule = _scheduleWith(weekdayPeriods: const [
        TimePeriod(start: '09:00', end: '11:00', headwayMinutes: 3), // 일부 겹침
        TimePeriod(start: '15:00', end: '17:00', headwayMinutes: 5), // 일부 겹침
      ]);

      // 두 구간 모두 평시와 겹침. 평균 = (3+5)/2 = 4분 → 240초
      expect(estimateHeadwaySeconds(schedule), 240);
    });

    test('비정상 구간(end <= start)은 무시', () {
      final schedule = _scheduleWith(weekdayPeriods: const [
        TimePeriod(start: '10:00', end: '10:00', headwayMinutes: 1), // 무시
        TimePeriod(start: '11:00', end: '13:00', headwayMinutes: 4),
      ]);

      // 정상 구간 1개 = 4분 → 240초
      expect(estimateHeadwaySeconds(schedule), 240);
    });
  });

  group('buildHeadwayMap', () {
    test('여러 노선의 배차간격 맵 생성', () {
      final schedules = {
        '9': _scheduleWith(weekdayPeriods: const [
          TimePeriod(start: '10:00', end: '16:00', headwayMinutes: 4),
        ]),
        '2': _scheduleWith(weekdayPeriods: const [
          TimePeriod(start: '10:00', end: '16:00', headwayMinutes: 3),
        ]),
      };

      final map = buildHeadwayMap(schedules);
      expect(map['9'], 240);
      expect(map['2'], 180);
    });

    test('빈 맵을 받으면 빈 맵을 반환', () {
      expect(buildHeadwayMap({}), isEmpty);
    });
  });
}
