// 급행 운행 시간대 게이트(`ExpressSkipEdge.runsAt`) 로직 가드 — 합성 픽스처만 쓴다.
//
// 부산 전환(2026-11-13)으로 급행 자산(`express_skip_edges.json`)이 비어 실제 에셋에
// 게이트를 적용하던 그룹은 삭제했다. 창이 있는 edge 는 창이 열린 방향·요일·시각에만
// 운행한다는 판정 로직 자체는 lib 에 남아 있으므로 이 그룹은 유지한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/express_skip_edge.dart';

/// 평일 낮 — B급행 두 방향 모두 닫힘.
final _weekdayNoon = DateTime(2026, 9, 1, 14, 0); // 화요일

/// 평일 아침 — B급행 상행만 열림 (창 05:44~08:09).
final _weekdayMorning = DateTime(2026, 9, 1, 7, 0);

/// 평일 저녁 — B급행 하행만 열림 (창 18:32~20:02).
final _weekdayEvening = DateTime(2026, 9, 1, 19, 0);

/// 토요일 아침 — 창이 있는 계통은 평일 전용이라 닫힘.
final _saturdayMorning = DateTime(2026, 9, 5, 7, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExpressSkipEdge.runsAt', () {
    const always = ExpressSkipEdge(
      lineId: '1',
      fromStationId: '170',
      toStationId: '1715',
      seconds: 210,
    );
    const windowed = ExpressSkipEdge(
      lineId: '1',
      fromStationId: '140',
      toStationId: '167',
      seconds: 480,
      serviceWindows: [
        ExpressServiceWindow(isDown: false, startMinute: 344, endMinute: 489),
        ExpressServiceWindow(isDown: true, startMinute: 1112, endMinute: 1202),
      ],
    );

    test('창이 없으면 언제나 운행한다', () {
      expect(always.runsAt(_weekdayNoon, isDown: true), isTrue);
      expect(always.runsAt(_saturdayMorning, isDown: false), isTrue);
    });

    test('시각을 모르면(at == null) 게이트를 적용하지 않는다', () {
      expect(windowed.runsAt(null, isDown: true), isTrue);
      expect(windowed.runsAt(null, isDown: false), isTrue);
    });

    test('창 안이라도 방향이 다르면 운행하지 않는다', () {
      // 아침은 상행(isDown: false)만.
      expect(windowed.runsAt(_weekdayMorning, isDown: false), isTrue);
      expect(windowed.runsAt(_weekdayMorning, isDown: true), isFalse);
      // 저녁은 하행만.
      expect(windowed.runsAt(_weekdayEvening, isDown: true), isTrue);
      expect(windowed.runsAt(_weekdayEvening, isDown: false), isFalse);
    });

    test('창 밖이면 두 방향 모두 운행하지 않는다', () {
      expect(windowed.runsAt(_weekdayNoon, isDown: true), isFalse);
      expect(windowed.runsAt(_weekdayNoon, isDown: false), isFalse);
    });

    test('경계 시각은 포함한다 (창은 닫힌 구간)', () {
      expect(
        windowed.runsAt(DateTime(2026, 9, 1, 5, 44), isDown: false),
        isTrue,
      );
      expect(
        windowed.runsAt(DateTime(2026, 9, 1, 8, 9), isDown: false),
        isTrue,
      );
      expect(
        windowed.runsAt(DateTime(2026, 9, 1, 8, 10), isDown: false),
        isFalse,
      );
    });

    test('창이 있는 계통은 주말에 운행하지 않는다', () {
      expect(windowed.runsAt(_saturdayMorning, isDown: false), isFalse);
      expect(
        windowed.runsAt(DateTime(2026, 9, 6, 7, 0), isDown: false),
        isFalse,
      );
    });
  });
}
