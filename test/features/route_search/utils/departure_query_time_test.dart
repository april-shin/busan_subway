import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/features/route_search/utils/departure_query_time.dart';

void main() {
  // 2026-02-23 은 월요일. 아래 테스트들은 이 날짜를 기준으로 요일을 오프셋한다.
  final monday = DateTime(2026, 2, 23, 9, 0);
  DateTime dayOffset(int days) => monday.add(Duration(days: days));

  group('dayTypeOf', () {
    test('월~금은 평일', () {
      for (var i = 0; i < 5; i++) {
        expect(
          dayTypeOf(dayOffset(i)),
          DepartureDayType.weekday,
          reason: '${dayOffset(i).weekday}요일',
        );
      }
    });

    test('토·일은 주말', () {
      expect(dayTypeOf(dayOffset(5)), DepartureDayType.weekend); // 토
      expect(dayTypeOf(dayOffset(6)), DepartureDayType.weekend); // 일
    });
  });

  group('anchorDateFor', () {
    // 앵커일의 핵심 계약: 앵커일과 **그 전날**이 모두 같은 요일 타입이어야
    // 한다. findNextDeparture 가 심야 조회에서 전날 운영일 스케줄을 다시
    // 보기 때문이다(_nextStationDeparture).
    test('모든 요일 × 모든 타입에서 앵커일과 그 전날의 타입이 일치한다', () {
      for (var i = 0; i < 7; i++) {
        final now = dayOffset(i);
        for (final type in DepartureDayType.values) {
          final anchor = anchorDateFor(type, now);
          expect(
            dayTypeOf(anchor),
            type,
            reason: 'now=${now.weekday}요일, type=$type → 앵커일 타입 불일치',
          );
          expect(
            dayTypeOf(anchor.subtract(const Duration(days: 1))),
            type,
            reason: 'now=${now.weekday}요일, type=$type → 앵커 전날 타입 불일치',
          );
        }
      }
    });

    test('앵커일은 오늘 이후 7일 이내이며 자정으로 정규화된다', () {
      for (var i = 0; i < 7; i++) {
        final now = dayOffset(i);
        for (final type in DepartureDayType.values) {
          final anchor = anchorDateFor(type, now);
          expect(anchor.hour, 0);
          expect(anchor.minute, 0);
          expect(anchor.isBefore(DateTime(now.year, now.month, now.day)),
              isFalse);
          expect(anchor.difference(DateTime(now.year, now.month, now.day)).inDays,
              lessThan(7));
        }
      }
    });

    test('평일 앵커는 화~금 중 하나 (월요일은 전날이 일요일이라 제외)', () {
      for (var i = 0; i < 7; i++) {
        final anchor = anchorDateFor(DepartureDayType.weekday, dayOffset(i));
        expect(
          anchor.weekday,
          isIn([
            DateTime.tuesday,
            DateTime.wednesday,
            DateTime.thursday,
            DateTime.friday,
          ]),
        );
      }
    });

    test('주말 앵커는 항상 일요일 (토요일은 전날이 금요일이라 제외)', () {
      for (var i = 0; i < 7; i++) {
        final anchor = anchorDateFor(DepartureDayType.weekend, dayOffset(i));
        expect(anchor.weekday, DateTime.sunday);
      }
    });

    test('오늘이 조건을 만족하면 오늘을 쓴다', () {
      final wednesday = dayOffset(2);
      final anchor = anchorDateFor(DepartureDayType.weekday, wednesday);
      expect(anchor, DateTime(wednesday.year, wednesday.month, wednesday.day));

      final sunday = dayOffset(6);
      final weekendAnchor = anchorDateFor(DepartureDayType.weekend, sunday);
      expect(weekendAnchor, DateTime(sunday.year, sunday.month, sunday.day));
    });
  });

  group('resolveQueryDateTime', () {
    test('"지금 출발"이면 now 를 그대로 반환한다', () {
      const query = DepartureQueryTime(dayType: DepartureDayType.weekday);
      expect(resolveQueryDateTime(query, monday), monday);
    });

    // 시간표 탐색이 strict `>` 라 선택 시각 그대로 넘기면 다음 열차가 잡힌다.
    // 1분을 빼야 사용자가 고른 바로 그 열차가 반환된다.
    test('고정 시각은 선택 시각보다 1분 이른 시각으로 해석된다', () {
      const query = DepartureQueryTime(
        minutes: 492, // 08:12
        dayType: DepartureDayType.weekday,
      );
      final resolved = resolveQueryDateTime(query, monday);
      expect(resolved.hour, 8);
      expect(resolved.minute, 11);
    });

    test('정각 선택도 1분 빼기가 시간 경계를 넘어간다', () {
      const query = DepartureQueryTime(
        minutes: 480, // 08:00
        dayType: DepartureDayType.weekday,
      );
      final resolved = resolveQueryDateTime(query, monday);
      expect(resolved.hour, 7);
      expect(resolved.minute, 59);
    });

    test('1440 이상(자정 넘김)은 다음 달력일로 정규화된다', () {
      const query = DepartureQueryTime(
        minutes: 1489, // 24:49 = 익일 00:49
        dayType: DepartureDayType.weekend,
      );
      final resolved = resolveQueryDateTime(query, monday);
      final anchor = anchorDateFor(DepartureDayType.weekend, monday);

      // 앵커(일요일)의 다음날 00:48 (= 1489 - 1분)
      expect(resolved.day, anchor.add(const Duration(days: 1)).day);
      expect(resolved.hour, 0);
      expect(resolved.minute, 48);
      expect(resolved.weekday, DateTime.monday);
    });

    test('앵커 요일 타입이 반영된다', () {
      const weekday = DepartureQueryTime(
        minutes: 600,
        dayType: DepartureDayType.weekday,
      );
      const weekend = DepartureQueryTime(
        minutes: 600,
        dayType: DepartureDayType.weekend,
      );
      expect(dayTypeOf(resolveQueryDateTime(weekday, monday)),
          DepartureDayType.weekday);
      expect(dayTypeOf(resolveQueryDateTime(weekend, monday)),
          DepartureDayType.weekend);
    });
  });

  group('formatOperatingMinutes', () {
    test('일반 시각', () {
      expect(formatOperatingMinutes(0), '00:00');
      expect(formatOperatingMinutes(339), '05:39');
      expect(formatOperatingMinutes(492), '08:12');
      expect(formatOperatingMinutes(1439), '23:59');
    });

    test('1440 이상은 24시간으로 감싼다', () {
      expect(formatOperatingMinutes(1440), '00:00');
      expect(formatOperatingMinutes(1489), '00:49');
      expect(formatOperatingMinutes(1530), '01:30');
    });
  });

  group('describeQueryTime', () {
    test('지금 출발', () {
      expect(
        describeQueryTime(
          const DepartureQueryTime(dayType: DepartureDayType.weekday),
        ),
        '지금 출발',
      );
    });

    test('고정 시각은 요일 타입과 함께 표기한다', () {
      expect(
        describeQueryTime(const DepartureQueryTime(
          minutes: 492,
          dayType: DepartureDayType.weekday,
        )),
        '평일 08:12 출발',
      );
      expect(
        describeQueryTime(const DepartureQueryTime(
          minutes: 1489,
          dayType: DepartureDayType.weekend,
        )),
        '주말 00:49 출발',
      );
    });
  });

  group('DepartureQueryTime', () {
    // 회귀 가드: dayType 은 isNow 일 때 계산에 쓰이지 않아, 되돌릴 때 함께
    // 정리하지 않으면 조용히 남아 있다가 다음에 시트를 열 때 그 요일 탭으로
    // 열린다(주말 시각을 골랐다 되돌리면 화요일에도 주말 탭이 뜨던 버그).
    test('nowAt 은 minutes 를 비우고 요일도 그 시점 기준으로 다시 잡는다', () {
      final tuesday = DateTime(2026, 7, 28);
      final sunday = DateTime(2026, 8, 2);
      expect(dayTypeOf(tuesday), DepartureDayType.weekday);
      expect(dayTypeOf(sunday), DepartureDayType.weekend);

      final resetOnWeekday = DepartureQueryTime.nowAt(tuesday);
      expect(resetOnWeekday.isNow, isTrue);
      expect(resetOnWeekday.dayType, DepartureDayType.weekday);

      final resetOnWeekend = DepartureQueryTime.nowAt(sunday);
      expect(resetOnWeekend.isNow, isTrue);
      expect(resetOnWeekend.dayType, DepartureDayType.weekend);
    });

    test('copyWith 로 요일만 바꿀 수 있다', () {
      const query = DepartureQueryTime(
        minutes: 492,
        dayType: DepartureDayType.weekday,
      );
      final changed = query.copyWith(dayType: DepartureDayType.weekend);
      expect(changed.minutes, 492);
      expect(changed.dayType, DepartureDayType.weekend);
    });

    test('값 동등성', () {
      const a = DepartureQueryTime(
        minutes: 492,
        dayType: DepartureDayType.weekday,
      );
      const b = DepartureQueryTime(
        minutes: 492,
        dayType: DepartureDayType.weekday,
      );
      const c = DepartureQueryTime(
        minutes: 493,
        dayType: DepartureDayType.weekday,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
