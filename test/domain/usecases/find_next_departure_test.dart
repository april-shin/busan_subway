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

  group('findNextDeparture - 자정 처리 회귀 (버그1: 심야 운영일 매칭)', () {
    // 김포골드류: 평일(금) 심야 운행이 자정을 넘겨 1440+ 값으로 저장되고,
    // 다음날(토) 새벽 조회 시 이를 찾아야 한다.
    LineSchedule makeMidnightSpanningSchedule() {
      return const LineSchedule(
        lineId: '김포골드',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:50', // 자정 이후 막차 (버그2 케이스 겸용)
          periods: [
            TimePeriod(start: '05:30', end: '23:55', headwayMinutes: 6),
          ],
          stationDepartures: {
            // 금요일(평일) P01: 정상 운행 + 자정을 넘긴 심야 운행분(1440+)
            'P01': [330, 350, 1420, 1440, 1460, 1480],
          },
        ),
        weekend: DaySchedule(
          firstTrain: '06:00',
          lastTrain: '23:00',
          periods: [
            TimePeriod(start: '06:00', end: '23:00', headwayMinutes: 8),
          ],
          stationDepartures: {
            // 토요일(주말) P01: 자체 심야 운행분 없음 (00시대 진입 시엔
            // 항상 전날 평일 운영분을 우선 확인해야 함)
            'P01': [360, 380, 400],
          },
        ),
      );
    }

    test('토요일 00:10 조회 시 금요일(평일) 운영일의 1440+ 출발분을 반환한다', () {
      // 토요일 00:10 (10분) → current+1440=1450 → 금요일 P01 리스트
      // [330,350,1420,1440,1460,1480] 중 1450 초과 첫 값 1460
      // reference: 금요일(2/20) 자정 + 1460분 = 토요일(2/21) 00:20
      final now = DateTime(2026, 2, 21, 0, 10); // 토요일
      final result = findNextDeparture(
        schedule: makeMidnightSpanningSchedule(),
        now: now,
        stationId: 'P01',
      );

      expect(result, DateTime(2026, 2, 21, 0, 20));
    });

    test('전날 운영분(1440+)이 없으면 기존대로 오늘 스케줄에서 첫차를 찾는다', () {
      final schedule = LineSchedule(
        lineId: '경의중앙',
        weekday: DaySchedule(
          firstTrain: '05:10',
          lastTrain: '23:40',
          periods: const [
            TimePeriod(start: '05:10', end: '23:40', headwayMinutes: 10),
          ],
          stationDepartures: const {
            // 금요일: 자정을 넘기지 않는 정상 운행분만 존재
            'K01': [310, 330, 350],
          },
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:00',
          periods: const [
            TimePeriod(start: '05:30', end: '23:00', headwayMinutes: 12),
          ],
          stationDepartures: const {
            'K01': [330, 350, 370],
          },
        ),
      );

      // 토요일 00:10 → 전날(금) K01 최대값 350(<1440) → 심야 매칭 대상 아님
      // → 오늘(토) 스케줄에서 첫 항목 330(05:30) 반환 (기존 동작 유지)
      final now = DateTime(2026, 2, 21, 0, 10); // 토요일
      final result = findNextDeparture(
        schedule: schedule,
        now: now,
        stationId: 'K01',
      );

      expect(result, DateTime(2026, 2, 21, 5, 30));
    });

    test('정상 첫차 시간대(예: 04:30) 조회는 기존 동작(첫차 반환)이 유지된다', () {
      // makeMidnightSpanningSchedule의 금요일 firstTrain은 05:30이므로
      // 04:30 조회도 여전히 첫차 전 구간 — 심야 매칭 로직이 개입해도
      // 결과는 기존과 동일하게 정상 계산되어야 한다.
      final now = DateTime(2026, 2, 20, 4, 30); // 금요일
      final result = findNextDeparture(
        schedule: makeMidnightSpanningSchedule(),
        now: now,
        stationId: 'P01',
      );

      expect(result, DateTime(2026, 2, 20, 5, 30));
    });

    test('getExpectedWaitMinutes도 동일한 심야 운영일 매칭을 사용한다', () {
      // 토요일 00:10 → 금요일 1440+ 매칭 1460분(00:20) → 대기 10분
      final now = DateTime(2026, 2, 21, 0, 10); // 토요일
      final result = getExpectedWaitMinutes(
        schedule: makeMidnightSpanningSchedule(),
        now: now,
        stationId: 'P01',
      );

      expect(result, 10);
    });

    test('전날 1440+가 존재하나 모두 지나갔으면 오늘 첫차로 폴백한다', () {
      // 토요일 01:20 (80분) → current+1440=1520 > 금요일 P01 최대값 1480
      //   → 심야 매칭 실패 → 오늘(토) 주말 리스트 [360,380,400]에서 첫 항목 360(06:00)
      final now = DateTime(2026, 2, 21, 1, 20); // 토요일
      final result = findNextDeparture(
        schedule: makeMidnightSpanningSchedule(),
        now: now,
        stationId: 'P01',
      );

      expect(result, DateTime(2026, 2, 21, 6, 0));
    });

    // 상/하행 및 주말 각각 자정 넘김 운행분을 가진 스케줄.
    LineSchedule makeMidnightBothDirections() {
      return const LineSchedule(
        lineId: '9',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:50',
          periods: [TimePeriod(start: '05:30', end: '23:55', headwayMinutes: 6)],
          stationDepartures: {
            'P01': [330, 1450, 1470], // 평일 상행: 심야 1450,1470
          },
        ),
        weekend: DaySchedule(
          firstTrain: '05:40',
          lastTrain: '00:30',
          periods: [TimePeriod(start: '05:40', end: '23:55', headwayMinutes: 8)],
          stationDepartures: {
            'P01': [340, 1450, 1465], // 주말 상행: 심야 1450,1465
          },
        ),
        weekdayDown: DaySchedule(
          firstTrain: '05:25',
          lastTrain: '00:45',
          periods: [TimePeriod(start: '05:25', end: '23:55', headwayMinutes: 6)],
          stationDepartures: {
            'P01': [325, 1455, 1475], // 평일 하행: 심야 1455,1475
          },
        ),
      );
    }

    test('전날이 주말인 경계도 요일 타입을 올바르게 재선택한다 (월요일 새벽 → 일요일 주말 운영분)', () {
      // 월요일 00:10 (10분) → 전날 일요일 = 주말 스케줄 재선택
      //   → current+1440=1450 → 주말 P01 [340,1450,1465] 중 1450 초과 첫 값 1465
      //   → reference 일요일(2/22) + 1465분 = 월요일(2/23) 00:25
      final now = DateTime(2026, 2, 23, 0, 10); // 월요일
      final result = findNextDeparture(
        schedule: makeMidnightBothDirections(),
        now: now,
        stationId: 'P01',
      );

      expect(result, DateTime(2026, 2, 23, 0, 25));
    });

    test('isDown=true이면 하행 시간표로 전날 심야 운영분을 매칭한다', () {
      // 토요일 00:10 (10분), 하행 → 전날 금요일 = 평일 하행(weekdayDown) 재선택
      //   → current+1440=1450 → 하행 P01 [325,1455,1475] 중 1450 초과 첫 값 1455
      //   → reference 금요일(2/20) + 1455분 = 토요일(2/21) 00:15
      final now = DateTime(2026, 2, 21, 0, 10); // 토요일
      final result = findNextDeparture(
        schedule: makeMidnightBothDirections(),
        now: now,
        isDown: true,
        stationId: 'P01',
      );

      expect(result, DateTime(2026, 2, 21, 0, 15));
    });
  });

  group('findNextDeparture - 자정 처리 회귀 (버그2: lastTrainMinutes 자정 이후)', () {
    test('lastTrain이 "00:50"인 배차간격 스케줄로 주간(14:00) 조회 시 null이 아닌 배차 기반 출발을 반환한다', () {
      final schedule = LineSchedule(
        lineId: '2',
        weekday: DaySchedule(
          firstTrain: '05:41',
          lastTrain: '00:50', // 자정 이후 막차 (버그 수정 전엔 50분으로 오인)
          periods: const [
            TimePeriod(start: '05:41', end: '09:00', headwayMinutes: 4),
            TimePeriod(start: '09:00', end: '16:30', headwayMinutes: 6),
            TimePeriod(start: '16:30', end: '00:50', headwayMinutes: 5),
          ],
        ),
        weekend: const DaySchedule(
          firstTrain: '05:41',
          lastTrain: '23:55',
          periods: [
            TimePeriod(start: '05:41', end: '23:55', headwayMinutes: 8),
          ],
        ),
      );

      // 월요일 14:00 (840분) → firstMin=341, lastMin은 수정 후 50+1440=1490
      // → 840 < 1490 이므로 운행 종료(null) 처리되지 않고 배차 기반 출발 반환
      final now = DateTime(2026, 2, 23, 14, 0); // 월요일
      final result = findNextDeparture(schedule: schedule, now: now);

      expect(result, isNotNull);
    });

    test('"00:00" 막차는 여전히 1440으로 처리되어 주간 조회가 null이 아니다 (경계 회귀 방지)', () {
      // makeSchedule()의 평일 lastTrain은 "00:00". 새 getter는
      // 0 <= firstTrainMinutes(300) 이므로 1440으로 보정한다.
      // 만약 잘못하여 0으로 해석되면 currentMinutes >= lastMin(0)이 종일 참이 되어
      // _findNextByHeadway가 하루 종일 null을 반환하는 버그2 증상이 재발한다.
      final now = DateTime(2026, 2, 23, 12, 0); // 월요일 정오 (운행 시간대 한복판)
      final result = findNextDeparture(schedule: makeSchedule(), now: now);

      expect(result, isNotNull);
    });

    test('"00:00" 막차의 lastTrainMinutes는 1440이다 (경계 단위 검증)', () {
      const day = DaySchedule(
        firstTrain: '05:00',
        lastTrain: '00:00',
        periods: [],
      );
      expect(day.lastTrainMinutes, 1440);
    });
  });

  group('findNextDeparture - 배차 자정 넘김 period (endMinutes)', () {
    // 우이신설/인천1류: 마지막 배차 period가 자정을 넘긴다("19:30~00:40").
    // 역별 시간표(stationDepartures) 없이 배차간격 폴백만 사용.
    LineSchedule makeSpanningHeadwaySchedule() {
      return const LineSchedule(
        lineId: '우이신설',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:40',
          periods: [
            TimePeriod(start: '05:30', end: '19:30', headwayMinutes: 5),
            TimePeriod(start: '19:30', end: '00:40', headwayMinutes: 6),
          ],
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:40',
          periods: [
            TimePeriod(start: '05:30', end: '19:30', headwayMinutes: 7),
            TimePeriod(start: '19:30', end: '00:40', headwayMinutes: 8),
          ],
        ),
      );
    }

    test('저녁(20:00) 자정 넘김 period가 활성이면 배차 기반 출발을 반환한다', () {
      // 월요일 20:00 (1200분) → period "19:30~00:40"(end=1480) 활성, 배차 6분
      // (1200-1170)/6=5 → 다음: 1170+6*6=1206 → 20:06
      // endMinutes 수정 전에는 end=40으로 절단돼 _findPeriod가 null → 버그(null 반환)
      final now = DateTime(2026, 2, 23, 20, 0); // 월요일
      final result =
          findNextDeparture(schedule: makeSpanningHeadwaySchedule(), now: now);

      expect(result, DateTime(2026, 2, 23, 20, 6));
    });

    test('심야(00:20) 조회 시 전날 운영일의 자정 넘김 배차 출발을 반환한다', () {
      // 화요일 00:20 (20분) → 전날 월요일(평일) period "19:30~00:40" 배차 6분
      // boosted=1460 → (1460-1170)/6=48 → 다음: 1170+49*6=1464
      // reference 월요일(2/23) + 1464분 = 화요일(2/24) 00:24
      final now = DateTime(2026, 2, 24, 0, 20); // 화요일
      final result =
          findNextDeparture(schedule: makeSpanningHeadwaySchedule(), now: now);

      expect(result, DateTime(2026, 2, 24, 0, 24));
    });

    test('심야 조회 시 전날이 주말이면 주말 배차로 자정 넘김 출발을 계산한다', () {
      // 월요일 00:20 (20분) → 전날 일요일(주말) period "19:30~00:40" 배차 8분
      // boosted=1460 → (1460-1170)/8=36 → 다음: 1170+37*8=1466
      // reference 일요일(2/22) + 1466분 = 월요일(2/23) 00:26
      final now = DateTime(2026, 2, 23, 0, 20); // 월요일
      final result =
          findNextDeparture(schedule: makeSpanningHeadwaySchedule(), now: now);

      expect(result, DateTime(2026, 2, 23, 0, 26));
    });

    test('심야지만 전날 자정 넘김 운행이 이미 끝났으면 오늘 첫차를 반환한다', () {
      // 화요일 00:50 (50분) → boosted=1490 > period end 1480 → 매칭 없음
      // → 오늘(화) 첫차 05:30
      final now = DateTime(2026, 2, 24, 0, 50); // 화요일
      final result =
          findNextDeparture(schedule: makeSpanningHeadwaySchedule(), now: now);

      expect(result, DateTime(2026, 2, 24, 5, 30));
    });

    test('전날에 자정 넘김 period가 없는 노선은 심야 조회 시 오늘 첫차를 반환한다', () {
      // 막차 23:40, 자정 넘김 period 없음 → 00:20 조회는 전날 매칭 실패 → 오늘 첫차
      const schedule = LineSchedule(
        lineId: '경의중앙',
        weekday: DaySchedule(
          firstTrain: '05:10',
          lastTrain: '23:40',
          periods: [TimePeriod(start: '05:10', end: '23:40', headwayMinutes: 10)],
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:00',
          periods: [TimePeriod(start: '05:30', end: '23:00', headwayMinutes: 12)],
        ),
      );

      final now = DateTime(2026, 2, 24, 0, 20); // 화요일
      final result = findNextDeparture(schedule: schedule, now: now);

      expect(result, DateTime(2026, 2, 24, 5, 10));
    });
  });
}
