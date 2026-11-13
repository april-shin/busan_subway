import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/line_schedule.dart';

import '../../tool/derive_representative.dart';

/// `tool/derive_representative.dart` 의 **함수 계약**을 잠근다.
///
/// `test/data/derived_first_last_test.dart` 는 산출된 JSON 을 검증하므로,
/// 이 모듈이 경계에서 어떻게 행동하는지(자정 넘김 인코딩 두 종류, band 끝 규칙,
/// 값이 없을 때의 실패 처리)는 그쪽에서 잠기지 않는다.
void main() {
  group('operatingMinutes — 두 인코딩을 모두 흡수한다', () {
    test('1440+ 인코딩은 그대로 (getTrainSch·인천1 CSV 계열)', () {
      // 김포골드 24:58 → 1498.
      expect(operatingMinutes(1498), 1498);
      expect(operatingMinutes(1440), 1440);
    });

    test('0~239 인코딩은 +1440 (경의중앙 엑셀 계열)', () {
      // 경의중앙 00:39 → 39.
      expect(operatingMinutes(39), 39 + 1440);
      expect(operatingMinutes(0), 1440);
    });

    test('정상 시간대는 손대지 않는다', () {
      expect(operatingMinutes(lateNightCutoff), lateNightCutoff);
      expect(operatingMinutes(330), 330);
      expect(operatingMinutes(1439), 1439);
    });
  });

  group('bandEndMinutes — TimePeriod.endMinutes 를 미러한다', () {
    /// 엔티티가 실제로 내는 값. 규칙이 갈라지면 이 헬퍼와 비교해 드러난다.
    int entityEnd(String start, String end) =>
        TimePeriod(start: start, end: end, headwayMinutes: 5).endMinutes;

    for (final pair in const [
      ['05:30', '00:00'], // 우이신설 주말 단일 band — 자정 넘김
      ['19:30', '00:40'], // 우이신설 평일 마지막 band
      ['05:30', '07:00'], // 평범한 band
      ['00:00', '00:00'], // 길이 0(1~9호선 등 실데이터에 존재)
      ['09:00', '17:00'],
    ]) {
      test('${pair[0]}~${pair[1]}', () {
        expect(bandEndMinutes(pair[0], pair[1]), entityEnd(pair[0], pair[1]));
      });
    }

    test('문자열 비교였다면 놓쳤을 경우를 잡는다', () {
      // `"05:31" >= "00:00"` 은 문자열로는 참이라 자정 넘김 band 를
      // "이미 지난 band" 로 오판했다.
      expect(bandEndMinutes('05:30', '00:00'), 1440);
      expect(parseMinutes('05:31') >= bandEndMinutes('05:30', '00:00'), isFalse);
    });
  });

  group('deriveRepresentativeValues', () {
    Map<String, dynamic> dayObj({
      required Map<String, dynamic> t,
      List<String> f = const ['06:00', '06:00'],
      List<String> l = const ['23:00', '23:00'],
      List<dynamic>? p,
    }) =>
        <String, dynamic>{
          'f': [...f],
          'l': [...l],
          'p': p ?? [
                ['06:00', '09:00', 10],
                ['09:00', '23:00', 12],
              ],
          't': t,
        };

    test('f 는 정상 시간대 최소, l 은 운영일 기준 최대', () {
      final day = dayObj(t: {
        'A': [
          [330, 1000, 1490], // 05:30 · 16:40 · 24:50
          [335, 1005],
        ],
      });

      final failures = deriveRepresentativeValues(
        lineId: 'test',
        day: 'wd',
        dayObj: day,
        log: (_) {},
      );

      expect(failures, isEmpty);
      expect(day['f'], ['05:30', '05:35']);
      expect(day['l'], ['00:50', '16:45']);
    });

    test('심야 인코딩(0~239)을 첫차로 잡지 않는다', () {
      // 경의중앙형 — 00:39 가 최소값이지만 첫차는 05:00 이다.
      final day = dayObj(t: {
        'A': [
          [39, 300, 600],
          null,
        ],
      });

      deriveRepresentativeValues(
        lineId: 'test',
        day: 'wd',
        dayObj: day,
        log: (_) {},
      );

      expect((day['f'] as List)[0], '05:00');
      expect((day['l'] as List)[0], '00:39');
    });

    test('출발이 없는 방향은 기존 값을 유지한다', () {
      final day = dayObj(t: {
        'A': [
          [400],
          null, // 종점의 진행 불가 방향
        ],
      });

      final failures = deriveRepresentativeValues(
        lineId: 'test',
        day: 'wd',
        dayObj: day,
        log: (_) {},
      );

      expect(failures, isEmpty);
      expect((day['f'] as List)[1], '06:00'); // 기존 값 그대로
      expect((day['l'] as List)[1], '23:00');
    });

    test('근거도 기존 값도 없으면 예외 대신 실패 목록을 돌려준다', () {
      // 예외를 던지면 호출 도구가 병합 결과를 쓰기 전에 죽는다.
      final day = dayObj(
        t: {
          'A': [
            [400],
            null,
          ],
        },
        f: const ['', ''],
        l: const ['', ''],
      );

      late List<String> failures;
      expect(
        () => failures = deriveRepresentativeValues(
          lineId: 'test',
          day: 'wd',
          dayObj: day,
          log: (_) {},
        ),
        returnsNormally,
      );
      expect(failures, hasLength(1));
      expect(failures.single, contains('idx1'));
    });

    test('p 첫 band 시작을 f 에 맞춘다 — 당기는 방향', () {
      final day = dayObj(
        t: {
          'A': [
            [300],
            [300],
          ],
        },
        p: [
          ['06:00', '09:00', 10],
        ],
      );

      deriveRepresentativeValues(
        lineId: 'test',
        day: 'wd',
        dayObj: day,
        log: (_) {},
      );

      expect((day['p'] as List).first, ['05:00', '09:00', 10]);
    });

    test('p 첫 band 시작을 f 에 맞춘다 — 미는 방향(인천1 사례)', () {
      final day = dayObj(
        t: {
          'A': [
            [330],
            [330],
          ],
        },
        f: const ['05:00', '05:00'],
        p: [
          ['05:00', '09:00', 10],
        ],
      );

      deriveRepresentativeValues(
        lineId: 'test',
        day: 'wd',
        dayObj: day,
        log: (_) {},
      );

      expect((day['p'] as List).first, ['05:30', '09:00', 10]);
    });

    test('도출 첫차가 첫 band 끝 이후면 p 를 건드리지 않는다', () {
      final day = dayObj(
        t: {
          'A': [
            [700],
            [700],
          ],
        },
        p: [
          ['06:00', '07:00', 10],
          ['07:00', '23:00', 12],
        ],
      );

      deriveRepresentativeValues(
        lineId: 'test',
        day: 'wd',
        dayObj: day,
        log: (_) {},
      );

      expect((day['p'] as List).first, ['06:00', '07:00', 10]);
    });

    test('자정 넘김 단일 band 는 정렬을 건너뛰지 않는다 (우이신설 주말 형태)', () {
      // 문자열 비교였다면 `"05:30" >= "00:00"` 이 참이라 정렬을 건너뛰었다.
      final day = dayObj(
        t: {
          'A': [
            [330],
            [330],
          ],
        },
        p: [
          ['06:00', '00:00', 5],
        ],
      );

      deriveRepresentativeValues(
        lineId: 'test',
        day: 'we',
        dayObj: day,
        log: (_) {},
      );

      expect((day['p'] as List).first, ['05:30', '00:00', 5]);
    });
  });
}
