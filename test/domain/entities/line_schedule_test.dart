import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';

void main() {
  group('DaySchedule', () {
    test('firstTrainMinutes를 올바르게 계산한다', () {
      const schedule = DaySchedule(
        firstTrain: '05:30',
        lastTrain: '23:00',
        periods: [],
      );

      expect(schedule.firstTrainMinutes, 330); // 5*60+30
    });

    test('lastTrainMinutes가 자정이면 1440을 반환한다', () {
      const schedule = DaySchedule(
        firstTrain: '05:00',
        lastTrain: '00:00',
        periods: [],
      );

      expect(schedule.lastTrainMinutes, 1440);
    });

    test('lastTrainMinutes가 자정이 아니면 정상 계산한다', () {
      const schedule = DaySchedule(
        firstTrain: '05:00',
        lastTrain: '23:50',
        periods: [],
      );

      expect(schedule.lastTrainMinutes, 1430); // 23*60+50
    });
  });

  group('TimePeriod', () {
    test('startMinutes를 올바르게 계산한다', () {
      const period = TimePeriod(
        start: '06:30',
        end: '09:00',
        headwayMinutes: 3,
      );

      expect(period.startMinutes, 390); // 6*60+30
    });

    test('endMinutes가 자정이면 1440을 반환한다', () {
      const period = TimePeriod(
        start: '21:00',
        end: '00:00',
        headwayMinutes: 8,
      );

      expect(period.endMinutes, 1440);
    });
  });

  group('LineSchedule JSON 파싱', () {
    test('JSON에서 올바르게 파싱한다', () {
      const jsonStr = '''
      {
        "lineId": "2",
        "weekday": {
          "firstTrain": "05:00",
          "lastTrain": "00:00",
          "periods": [
            {"start": "05:00", "end": "09:00", "headwayMinutes": 3},
            {"start": "09:00", "end": "16:30", "headwayMinutes": 5}
          ]
        },
        "weekend": {
          "firstTrain": "05:30",
          "lastTrain": "23:40",
          "periods": [
            {"start": "05:30", "end": "23:40", "headwayMinutes": 6}
          ]
        }
      }
      ''';

      final schedule = LineSchedule.fromJson(
        json.decode(jsonStr) as Map<String, dynamic>,
      );

      expect(schedule.lineId, '2');
      expect(schedule.weekday.firstTrain, '05:00');
      expect(schedule.weekday.lastTrain, '00:00');
      expect(schedule.weekday.periods.length, 2);
      expect(schedule.weekday.periods[0].headwayMinutes, 3);
      expect(schedule.weekday.periods[1].start, '09:00');
      expect(schedule.weekend.periods.length, 1);
      expect(schedule.weekend.periods[0].headwayMinutes, 6);
    });

    test('toJson → fromJson 라운드트립이 동작한다', () {
      const schedule = LineSchedule(
        lineId: '7',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:00',
          periods: [
            TimePeriod(start: '05:30', end: '09:00', headwayMinutes: 3),
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

      // json.encode를 통해 완전한 JSON 문자열로 변환 후 다시 파싱
      final jsonString = json.encode(schedule.toJson());
      final restored = LineSchedule.fromJson(
        json.decode(jsonString) as Map<String, dynamic>,
      );

      expect(restored.lineId, '7');
      expect(restored.weekday.firstTrain, '05:30');
      expect(restored.weekday.periods.length, 1);
      expect(restored.weekend.periods[0].headwayMinutes, 8);
      expect(restored, schedule);
    });
  });
}
