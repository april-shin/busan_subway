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

    // 버그2 회귀: 자정 이후 막차("00:3x"~"00:5x")가 firstTrain보다 작은 분
    // 값으로 파싱되어 그대로 반환되던 문제. firstTrain 이하이면 +1440.
    test('lastTrainMinutes가 자정 이후(예: 00:50)이면 firstTrain 기준으로 +1440한다', () {
      const schedule = DaySchedule(
        firstTrain: '05:41',
        lastTrain: '00:50',
        periods: [],
      );

      // 00:50 → 50분, firstTrain(341분)보다 작으므로 다음날로 간주 → 50+1440
      expect(schedule.lastTrainMinutes, 1490);
    });

    test('lastTrainMinutes가 자정 직후(00:02)이고 firstTrain이 새벽이면 +1440한다', () {
      const schedule = DaySchedule(
        firstTrain: '05:37',
        lastTrain: '00:02',
        periods: [],
      );

      expect(schedule.lastTrainMinutes, 1442); // 2 + 1440
    });

    test('"00:00" 막차는 여전히 1440을 반환한다 (경계 회귀 방지)', () {
      const schedule = DaySchedule(
        firstTrain: '05:30',
        lastTrain: '00:00',
        periods: [],
      );

      expect(schedule.lastTrainMinutes, 1440);
    });

    // 범위 밖 데이터 이상(1호선 f=00:00 등): firstTrain 자체가 자정 근처라
    // lastTrain이 firstTrain보다 크게 유지되면 이 보정에 걸리지 않아야 한다
    // (기존 동작 그대로 유지 — 악화 방지 확인용).
    test('firstTrain이 자정 근처(00:00)인 데이터 이상 케이스는 보정되지 않는다', () {
      const schedule = DaySchedule(
        firstTrain: '00:00', // 1호선 상행처럼 자정 근처인 데이터 이상
        lastTrain: '00:48',
        periods: [],
      );

      // 48 > firstTrainMinutes(0) 이므로 그대로 48 반환 (기존 동작과 동일)
      expect(schedule.lastTrainMinutes, 48);
    });

    // firstTrain == lastTrain 퇴화 데이터(예: 1호선 주말 하행 f=l="00:07")는
    // 등호(<=) 판정으로 +1440 되어 "종일 운행"으로 완화된다. endMinutes(<) 와
    // 달리 막차는 이 케이스를 보정하는 편이 안전하므로 동작을 고정한다.
    test('firstTrain == lastTrain이면 +1440으로 완화한다 (등호 판정 고정)', () {
      const schedule = DaySchedule(
        firstTrain: '00:07',
        lastTrain: '00:07',
        periods: [],
      );

      expect(schedule.lastTrainMinutes, 1447); // 7 <= 7 → 7 + 1440
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

    test('endMinutes가 자정 이후(시작 시각 이하)이면 1440을 더한다', () {
      // 우이신설류 "19:30~00:40" 자정 넘김 period
      const period = TimePeriod(
        start: '19:30',
        end: '00:40',
        headwayMinutes: 6,
      );

      expect(period.endMinutes, 1480); // 40 <= 1170 → 40 + 1440
    });

    test('endMinutes가 시작 시각보다 크면(자정 전) 그대로 반환한다', () {
      const period = TimePeriod(
        start: '06:30',
        end: '09:00',
        headwayMinutes: 3,
      );

      expect(period.endMinutes, 540); // 540 > 390 → 보정 없음
    });

    test('endMinutes: start == end 인 길이 0 구간은 보정하지 않는다', () {
      // 자정 넘김 보정이 길이 0 구간을 24h+로 부풀리면 headway_estimator의
      // "end <= start 무시" 가드가 무력화되므로, 이 경우 그대로 두어야 한다.
      const period = TimePeriod(
        start: '10:00',
        end: '10:00',
        headwayMinutes: 1,
      );

      expect(period.endMinutes, 600); // 600 (보정 없음) → end <= start 가드 유효
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

    test('stationDepartures 포함 JSON 라운드트립이 동작한다', () {
      final schedule = LineSchedule(
        lineId: '김포골드',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:00',
          periods: const [
            TimePeriod(start: '05:30', end: '00:00', headwayMinutes: 6),
          ],
          stationDepartures: const {
            'P01': [330, 340, 350, 360],
            'P05': [335, 345, 355, 365],
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

      final jsonString = json.encode(schedule.toJson());
      final restored = LineSchedule.fromJson(
        json.decode(jsonString) as Map<String, dynamic>,
      );

      expect(restored.weekday.stationDepartures, isNotNull);
      expect(restored.weekday.stationDepartures!['P01'], [330, 340, 350, 360]);
      expect(restored.weekday.stationDepartures!['P05'], [335, 345, 355, 365]);
      expect(restored.weekend.stationDepartures, isNull);
    });
  });
}
