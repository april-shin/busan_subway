import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';

/// 경의중앙 노선 대표값(`f`/`l`)이 역별 시간표(`t`)와 어긋나지 않는지 잠근다.
///
/// 경의중앙은 두 시간표 API 모두 미제공이라, 대표값이 오랫동안
/// `tool/extract_schedules.dart` 의 **하드코딩 추정치**(평일 `05:10`~`23:40`)였다.
/// 실제 `t` 는 05:00 에 시작해 자정을 넘겨 끝나므로 "노선 첫차·막차"라는 이름과
/// 값이 어긋나 있었다.
///
/// 이 어긋남의 **소비자 영향은 거의 없다** — `t` 가 있는 역은
/// `find_next_departure` 의 역별 시간표 경로를 타고, 그 경로에서 `f` 는 "전날
/// 자정 넘김 분을 먼저 볼지"만 정하는데 경의중앙은 자정 넘김을 0~239 로 담아
/// 그 조회가 항상 빈손으로 끝나기 때문이다. 실측(평일·토·일 각 56역 × 2방향 ×
/// 1440분 = 483,840 조합)에서 답이 달라진 것은 `t` 가 없는 종점 방향 3개
/// (K53 하행·K54 하행·K55 상행)뿐이고, "운행 종료"로 바뀐 조합은 0건이다.
/// 그럼에도 잠그는 이유는 첫차·막차를 화면에 쓰는 기능이 생기면 즉시 오답이
/// 되기 때문이다(2026-08-13 앵커역 정정과 같은 사유).
///
/// 지금은 `tool/build_center_line_timetable.py` 가 `t` 에서 도출해 넣는다.
/// 이 테스트는 그 도출 결과가 유지되는지 본다 — 특히
/// `tool/extract_schedules.dart` 를 다시 돌렸을 때 추정치로 되돌아가면 깨진다
/// (그쪽의 `_representativeCarryOverLines` 가 방어선이다).
///
/// ## 왜 이 노선만 직접 비교하는가
///
/// `line_schedule_anchor_sanity_test.dart` 는 `f`/`l` 을 `t` 의 최소·최대와
/// 직접 비교하지 **않는다** — 자정 넘김 인코딩이 노선마다 달라 전 노선 공통
/// 규칙으로는 거짓 실패가 나기 때문이다. 여기서는 경의중앙 하나만 보고,
/// 그 노선의 인코딩 규약(자정 이후 출발을 1440+ 가 아니라 0~1439 로 담는다)을
/// 명시적으로 적용하므로 그 문제가 없다.
void main() {
  /// 자정 넘김 인코딩 경계. `departure_candidates.dart` 의
  /// `lateNightCutoffMinutes` 와 같은 값이며, 경의중앙 `t` 는 이 아래 값을
  /// "자정 이후 출발"로 담는다(00:39 → 39).
  const lateNightCutoff = 240;

  int parseMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// 벽시계 분 → 운영일 분(자정 넘김은 1440+).
  int operatingMinutes(int m) {
    if (m >= 1440) return m;
    return m < lateNightCutoff ? m + 1440 : m;
  }

  late Map<String, dynamic> line;

  setUpAll(() {
    final raw = File('assets/json/line_schedules.json').readAsStringSync();
    final schedules = json.decode(raw) as List;
    line = schedules
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['id'] == '경의중앙');
  });

  for (final day in const ['wd', 'we']) {
    for (final dir in const [0, 1]) {
      final label = '$day idx$dir';

      test('[$label] f 는 그 방향 첫 출발과 같다', () {
        final dayObj = line[day] as Map<String, dynamic>;
        final table = (dayObj['t'] as Map).cast<String, dynamic>();

        final sameDay = <int>[];
        for (final dirs in table.values) {
          final list = (dirs as List)[dir];
          if (list == null) continue;
          for (final m in (list as List).cast<int>()) {
            if (m >= lateNightCutoff && m < 1440) sameDay.add(m);
          }
        }
        expect(sameDay, isNotEmpty, reason: '$label 에 정상 시간대 출발이 있어야 한다');

        final ds = DaySchedule(
          firstTrain: (dayObj['f'] as List)[dir] as String,
          lastTrain: (dayObj['l'] as List)[dir] as String,
          periods: const [],
        );
        expect(
          ds.firstTrainMinutes,
          sameDay.reduce((a, b) => a < b ? a : b),
          reason: 'f 가 첫 출발보다 늦으면 그 사이에 실제로는 다니는 열차를 '
              '"첫차 전"으로 보게 되고, 이르면 없는 열차를 안내한다',
        );
      });

      test('[$label] l 은 그 방향 마지막 출발과 같다', () {
        final dayObj = line[day] as Map<String, dynamic>;
        final table = (dayObj['t'] as Map).cast<String, dynamic>();

        final all = <int>[];
        for (final dirs in table.values) {
          final list = (dirs as List)[dir];
          if (list == null) continue;
          all.addAll((list as List).cast<int>().map(operatingMinutes));
        }
        expect(all, isNotEmpty);

        // 자정 넘김 보정 규칙을 손으로 옮겨 적지 않고 엔티티에 직접 묻는다 —
        // `lastTrainMinutes` 가 바뀌면 이 테스트도 함께 따라가야 한다.
        final ds = DaySchedule(
          firstTrain: (dayObj['f'] as List)[dir] as String,
          lastTrain: (dayObj['l'] as List)[dir] as String,
          periods: const [],
        );

        expect(
          ds.lastTrainMinutes,
          all.reduce((a, b) => a > b ? a : b),
          reason: 'l 이 마지막 출발보다 이르면 심야 조회가 "운행 종료"로 오판된다',
        );
      });
    }
  }

  for (final day in const ['wd', 'we']) {
    test('[$day] 첫 배차 band 가 f 이전을 비워 두지 않는다', () {
      // `f` 만 당기고 `p` 를 두면 그 사이를 덮는 band 가 없어
      // `_findNextByHeadway` → `_findPeriod` 가 null("운행 종료")을 돌려준다.
      // 경의중앙은 배차간격 경로가 `t` 없는 종점 방향에서만 쓰이지만,
      // f 와 p 가 어긋난 상태를 데이터에 남기지 않는다.
      final dayObj = line[day] as Map<String, dynamic>;
      final bands = dayObj['p'] as List;
      expect(bands, isNotEmpty);

      final firstBandStart = parseMinutes((bands.first as List)[0] as String);
      final earliest = (dayObj['f'] as List)
          .cast<String>()
          .map(parseMinutes)
          .reduce((a, b) => a < b ? a : b);
      // 도구는 `!=` 로 양방향 정렬하므로 지금은 등호가 성립한다. 그래도
      // `lessThanOrEqualTo` 로 잠그는 이유는, 이 테스트가 지켜야 할 계약이
      // "첫 band 가 첫차보다 늦게 시작하지 않는다"이기 때문이다 — 더 이르게
      // 시작하는 것은 `firstTrainMinutes` 게이트가 막아 주어 무해하다.
      expect(firstBandStart, lessThanOrEqualTo(earliest),
          reason: '첫 band 가 첫차보다 늦게 시작하면 그 사이가 "운행 종료"가 된다');
    });
  }

  test('추정치(05:10~23:40 / 05:30~23:00)로 되돌아가지 않았다', () {
    // extract_schedules.dart 의 _getEstimatedSchedule 값. 이 조합이 그대로
    // 보이면 그 도구가 도출값을 덮어썼다는 뜻이다.
    expect(
      [(line['wd'] as Map)['f'], (line['wd'] as Map)['l']],
      isNot([
        ['05:10', '05:10'],
        ['23:40', '23:40'],
      ]),
    );
    expect(
      [(line['we'] as Map)['f'], (line['we'] as Map)['l']],
      isNot([
        ['05:30', '05:30'],
        ['23:00', '23:00'],
      ]),
    );
  });
}
