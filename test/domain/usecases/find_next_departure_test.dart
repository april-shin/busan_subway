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

  group('findNextDeparture - 급행(express)', () {
    // 참고: lastTrain을 '00:50'처럼 자정을 넘기는 값으로 두면
    // DaySchedule.lastTrainMinutes/TimePeriod.endMinutes가 "00:00" 리터럴만
    // 특별 처리하고 그 외 자정 이후 값은 그대로 반환하는 기존 버그(별도 보고 대상,
    // 아래 "경계: 자정 전후" 그룹 참고)와 얽혀 배차간격 폴백 자체가 깨진다.
    // 이 그룹은 express/완행 분기 검증이 목적이므로 자정을 넘기지 않는
    // lastTrain('23:50')으로 고정해 그 버그와 분리한다.
    LineSchedule makeScheduleWithExpress() {
      return LineSchedule(
        lineId: '9',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:50',
          periods: const [
            TimePeriod(start: '05:30', end: '23:50', headwayMinutes: 6),
          ],
          stationDepartures: const {
            // 완행(급행 미정차역 포함) 목록.
            // 905는 배차간격 폴백 계산 결과(05:42)와 절대 겹치지 않도록
            // 의도적으로 다른 분(349)을 배치해, 폴백이 아니라 완행표를
            // 잘못 참조했을 경우 명확히 구분되는 값이 나오게 한다.
            '902': [330, 340, 350, 360, 370],
            '905': [331, 341, 349, 359, 369],
          },
          expressStationDepartures: const {
            // 급행 정차역만 존재 (905는 급행 미정차)
            '902': [335, 355, 375, 395, 415],
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
    }

    test('express=true + 급행 데이터가 있는 역은 급행 목록에서 이진탐색한다', () {
      // 05:40(340분) → 902 급행: [335, 355, 375, ...] → 다음은 355분(05:55)
      final now = DateTime(2026, 2, 23, 5, 40);
      final result = findNextDeparture(
        schedule: makeScheduleWithExpress(),
        now: now,
        stationId: '902',
        express: true,
      );

      expect(result, DateTime(2026, 2, 23, 5, 55));
    });

    test('express=true + 급행 데이터가 없는 역(급행 미정차역)은 완행과 섞이지 않고 배차간격으로 폴백한다', () {
      // 905는 expressStationDepartures에 없음.
      // 완행(stationDepartures) 목록에는 905가 있고 다음 값은 349분(05:49)이지만,
      // express=true이므로 완행 목록을 참조해서는 안 되고 배차간격(6분) 폴백을 사용해야 한다.
      final now = DateTime(2026, 2, 23, 5, 40);
      final result = findNextDeparture(
        schedule: makeScheduleWithExpress(),
        now: now,
        stationId: '905',
        express: true,
      );

      // 배차간격 폴백: 05:30~23:50, 6분 간격
      // elapsed = 340-330=10 → intervalsPassed=1 → 다음: 330+2*6=342 == 05:42
      expect(result, DateTime(2026, 2, 23, 5, 42));
      // 완행 시간표 값(349=05:49)이 반환되면 안 됨 — 섞이지 않아야 함
      expect(result, isNot(DateTime(2026, 2, 23, 5, 49)));
    });

    test('express=true + 완행표에도 없는 미지의 역은 배차간격으로 폴백한다 (교차 오염 없음 재확인)', () {
      final now = DateTime(2026, 2, 23, 10, 0);
      final result = findNextDeparture(
        schedule: makeScheduleWithExpress(),
        now: now,
        stationId: '999', // t/tE 어디에도 없는 역
        express: true,
      );

      // 배차간격 폴백만 가능 (완행/급행 어느 목록도 조회되지 않음)
      expect(result, isNotNull);
    });

    test('express=false이면 완행(stationDepartures) 목록을 조회한다 (기존 동작)', () {
      // 05:40(340분) → 902 완행: [330, 340, 350, ...] → 다음은 350분(05:50)
      // (급행 목록이었다면 355분(05:55)이 반환되었을 것 — 서로 다른 값으로 분기 검증)
      final now = DateTime(2026, 2, 23, 5, 40);
      final result = findNextDeparture(
        schedule: makeScheduleWithExpress(),
        now: now,
        stationId: '902',
        express: false,
      );

      expect(result, DateTime(2026, 2, 23, 5, 50));
    });

    test('하위호환: expressStationDepartures가 아예 없는 기존 노선에서 express=false는 정상 동작한다', () {
      final schedule = LineSchedule(
        lineId: '김포골드',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:55',
          periods: const [
            TimePeriod(start: '05:30', end: '23:55', headwayMinutes: 6),
          ],
          stationDepartures: const {
            'P01': [330, 350, 370, 390, 410],
          },
          // expressStationDepartures 없음 (기존 노선)
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
      );

      // 05:40(340분) → P01 완행: [330, 350, ...] → 다음 350분(05:50)
      final now = DateTime(2026, 2, 23, 5, 40);
      final result = findNextDeparture(
        schedule: schedule,
        now: now,
        stationId: 'P01',
        express: false,
      );

      expect(result, DateTime(2026, 2, 23, 5, 50));
    });

    test('하위호환: expressStationDepartures가 없는 노선에서 express=true여도 배차간격으로 안전하게 폴백한다', () {
      final schedule = LineSchedule(
        lineId: '김포골드',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:55',
          periods: const [
            TimePeriod(start: '05:30', end: '23:55', headwayMinutes: 6),
          ],
          stationDepartures: const {
            'P01': [330, 350, 370, 390, 410],
          },
          // expressStationDepartures 없음 (기존 노선) — null 참조로 죽지 않아야 함
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
      );

      final now = DateTime(2026, 2, 23, 10, 0);
      final result = findNextDeparture(
        schedule: schedule,
        now: now,
        stationId: 'P01',
        express: true,
      );

      // NPE 없이 배차간격 폴백으로 정상 반환되어야 함
      expect(result, isNotNull);
    });
  });

  group('getExpectedWaitMinutes - 급행(express)', () {
    test('express=true + 급행 데이터가 있는 역은 급행 목록 기준 대기시간을 반환한다', () {
      final schedule = LineSchedule(
        lineId: '9',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:50',
          periods: const [
            TimePeriod(start: '05:30', end: '00:50', headwayMinutes: 6),
          ],
          stationDepartures: const {
            '902': [330, 340, 350],
          },
          expressStationDepartures: const {
            '902': [330, 360, 390],
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

      // 05:40(340분) → 급행: 다음은 360분(06:00) → 대기 20분
      final now = DateTime(2026, 2, 23, 5, 40);
      final result = getExpectedWaitMinutes(
        schedule: schedule,
        now: now,
        stationId: '902',
        express: true,
      );

      expect(result, 20);
    });

    test('express=true + 급행 미정차역은 완행과 섞이지 않고 배차간격 절반을 반환한다', () {
      final schedule = LineSchedule(
        lineId: '9',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:50',
          periods: const [
            TimePeriod(start: '05:30', end: '00:50', headwayMinutes: 6),
          ],
          stationDepartures: const {
            '905': [330, 340, 350], // 완행에만 존재
          },
          // 905는 expressStationDepartures에 없음
        ),
        weekend: const DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [
            TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8),
          ],
        ),
      );

      final now = DateTime(2026, 2, 23, 5, 40);
      final result = getExpectedWaitMinutes(
        schedule: schedule,
        now: now,
        stationId: '905',
        express: true,
      );

      // 완행표 기반 결과(다음 350분 → 대기 10분)가 아니라
      // 배차간격 절반(6/2=3분) 폴백이어야 한다.
      expect(result, 3);
    });
  });

  group('경계: 자정 전후(1440분+) 출발분 처리 문서화', () {
    // ⚠️ 4원칙(실시간 열차 애니메이션)과 무관한 시간표 로직 경계 테스트.
    //
    // 9호선처럼 막차가 자정을 넘기는 노선은 t/tE 배열에 1440 이상의 값
    // (예: 1489 = 24:49 = 다음날 00:49)을 저장해 정렬 순서를 유지한다.
    LineSchedule makeLateNightSchedule() {
      return LineSchedule(
        lineId: '9',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:50',
          periods: const [
            TimePeriod(start: '05:30', end: '00:50', headwayMinutes: 6),
          ],
          expressStationDepartures: const {
            '902': [330, 340, 1408, 1420, 1450, 1489],
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
    }

    test('23:50(1430분) 조회 시 1440분을 넘는 다음 출발(00:10)은 다음날 날짜로 정상 롤오버된다', () {
      // 1430분 기준 다음 값은 1450 → _minutesToDateTime(1450)은
      // DateTime(...,24,10)이 되고, Dart DateTime 생성자가 자동으로
      // 다음 날 00:10으로 정규화한다. 이 롤오버 자체는 올바르게 동작한다.
      final now = DateTime(2026, 2, 23, 23, 50); // 월요일 23:50
      final result = findNextDeparture(
        schedule: makeLateNightSchedule(),
        now: now,
        stationId: '902',
        express: true,
      );

      expect(result, DateTime(2026, 2, 24, 0, 10));
    });

    test('전날 운영일(주말)에 급행 심야 데이터가 없으면 당일 급행 첫차로 폴백한다', () {
      // 자정 직후(00:10, 첫차 전) 조회는 _nextStationDeparture 가 "전날 운영일"의
      // 심야(1440+) 출발분을 먼저 확인한다. 월요일 00:10 의 전날은 일요일(주말)인데
      // makeLateNightSchedule 의 주말 스케줄에는 급행(tE) 데이터가 없으므로,
      // 매칭할 심야 출발분이 없어 당일 급행 첫차(05:30)로 귀결된다.
      // (전날이 평일이어서 급행 심야분이 실제로 존재하는 경우의 매칭은
      //  'findNextDeparture - 급행 심야 운영일 매칭' 그룹에서 검증한다.)
      final now = DateTime(2026, 2, 23, 0, 10); // 월요일 00:10 → 전날=일요일(주말)
      final result = findNextDeparture(
        schedule: makeLateNightSchedule(),
        now: now,
        stationId: '902',
        express: true,
      );

      expect(result, DateTime(2026, 2, 23, 5, 30));
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

  group('findNextDeparture - 급행 심야 운영일 매칭 (express + 자정 처리 통합)', () {
    // 완행(t)과 급행(tE) 모두 자정 넘김(1440+) 심야 출발분을 가지되 값이 다른
    // 스케줄. 급행 조회의 전날 폴백이 완행 목록으로 오염되지 않아야 한다.
    LineSchedule makeExpressLateNightSchedule() {
      return const LineSchedule(
        lineId: '9',
        weekday: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '00:50',
          periods: [TimePeriod(start: '05:30', end: '00:50', headwayMinutes: 6)],
          stationDepartures: {
            '902': [330, 1460], // 완행 심야 00:20
          },
          expressStationDepartures: {
            '902': [330, 1489], // 급행 심야 00:49
          },
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:30',
          periods: [TimePeriod(start: '05:30', end: '23:30', headwayMinutes: 8)],
        ),
      );
    }

    test('express=true 심야(00:10) 조회는 전날 급행 심야분(00:49)을 반환한다', () {
      // 화요일 00:10 → 전날 월요일(평일) 급행 [330,1489], boosted=1450
      // → 1450 초과 첫 값 1489 → 월(2/23)+1489분 = 화(2/24) 00:49
      final now = DateTime(2026, 2, 24, 0, 10); // 화요일
      final result = findNextDeparture(
        schedule: makeExpressLateNightSchedule(),
        now: now,
        stationId: '902',
        express: true,
      );

      expect(result, DateTime(2026, 2, 24, 0, 49));
    });

    test('express=false 동일 조회는 전날 완행 심야분(00:20)을 반환한다 (교차 오염 없음)', () {
      // 급행이 아니라 완행을 봐야 하므로 00:20이 나와야 한다.
      final now = DateTime(2026, 2, 24, 0, 10); // 화요일
      final result = findNextDeparture(
        schedule: makeExpressLateNightSchedule(),
        now: now,
        stationId: '902',
        express: false,
      );

      expect(result, DateTime(2026, 2, 24, 0, 20));
    });
  });

  group('findNextDeparture - 마지막 period 배차 그리드가 실제 막차와 불일치', () {
    // 막차가 배차간격 배수에 정확히 안 맞는 노선(예: SB 23:00~00:33, 10분 배차 →
    // 이론상 다음 칸은 00:40으로 막차 00:33을 넘김)에서, "다음 칸이 period end를
    // 초과 && 다음 period 없음"일 때 null(운행 종료)이 아니라 period.end(실제 막차)를
    // 반환해야 한다. null이면 상위에서 오늘 첫차로 오폴백된다.
    test('당일 마지막 period에서 그리드가 막차를 넘어서면 실제 막차 시각을 반환한다', () {
      const schedule = LineSchedule(
        lineId: 'SB',
        weekday: DaySchedule(
          firstTrain: '05:00',
          lastTrain: '23:33',
          // 단일 period, 배차 10분: 05:00,05:10,... 23:30 다음 칸 23:40 > 막차 23:33
          periods: [TimePeriod(start: '05:00', end: '23:33', headwayMinutes: 10)],
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:00',
          periods: [TimePeriod(start: '05:30', end: '23:00', headwayMinutes: 12)],
        ),
      );

      // 23:31 → 그리드 다음 칸 23:40 ≥ 막차 23:33, 다음 period 없음 → 막차 23:33 반환
      final now = DateTime(2026, 2, 24, 23, 31); // 화요일
      final result = findNextDeparture(schedule: schedule, now: now);

      expect(result, DateTime(2026, 2, 24, 23, 33));
    });

    test('심야(전날 운영일)의 자정 넘김 마지막 period에서도 실제 막차를 반환한다', () {
      const schedule = LineSchedule(
        lineId: 'SB',
        weekday: DaySchedule(
          firstTrain: '05:00',
          lastTrain: '00:33', // 자정 넘김 막차
          periods: [
            TimePeriod(start: '05:00', end: '23:00', headwayMinutes: 10),
            TimePeriod(start: '23:00', end: '00:33', headwayMinutes: 10),
          ],
        ),
        weekend: DaySchedule(
          firstTrain: '05:30',
          lastTrain: '23:00',
          periods: [TimePeriod(start: '05:30', end: '23:00', headwayMinutes: 12)],
        ),
      );

      // 화요일 00:31 → 전날 월요일 period "23:00~00:33"(end=1473) boosted=1471
      // 그리드 다음 칸 00:40(1480) ≥ 1473 → 실제 막차 00:33 반환
      final now = DateTime(2026, 2, 24, 0, 31); // 화요일
      final result = findNextDeparture(schedule: schedule, now: now);

      expect(result, DateTime(2026, 2, 24, 0, 33));
    });
  });
}
