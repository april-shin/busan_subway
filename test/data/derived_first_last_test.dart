import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';

/// 노선 대표값(`f`/`l`)을 역별 시간표(`t`)에서 **도출하는 노선**들이 그 도출
/// 결과를 유지하는지 잠근다.
///
/// `tool/extract_schedules.dart` 는 노선마다 앵커역 한 곳의 API 행에서 대표값을
/// 뽑는데, 그 API 가 없는 노선은 `_getEstimatedSchedule` 의 **하드코딩 추정치**가
/// 들어간다. 그 추정치가 실측 `t` 와 어긋나 "노선 첫차·막차"라는 이름과 값이
/// 맞지 않는 상태가 오래 있었다:
/// - 경의중앙: 평일 `05:10`~`23:40` (실측 05:00~00:39)
/// - 김포골드: 평일 `05:30`~`23:30` (실측 05:26~00:58), 주말 `06:00`~`23:00`
///
/// 지금은 각 노선의 `t` 수집 도구가 함께 도출한다 —
/// 경의중앙은 `tool/build_center_line_timetable.py`,
/// 김포골드는 `tool/build_gettrainsch_timetable.dart` 의 `_deriveRepresentative`.
/// 이 테스트는 `tool/extract_schedules.dart` 를 다시 돌렸을 때 추정치로
/// 되돌아가면 깨진다(그쪽의 `_representativeCarryOverLines` 가 방어선이다).
///
/// ## 소비자 영향은 거의 없다 — 그래도 잠그는 이유
///
/// 두 노선 모두 전 역이 `t` 를 가져 `find_next_departure` 의 역별 시간표 경로를
/// 타고, 그 경로는 `f`/`l` 을 사실상 보지 않는다. 실측 전수 대조에서 답이
/// 달라진 것은 **`t` 가 없는 종점 방향**뿐이었다 — 경의중앙 3개(K53 하행·K54
/// 하행·K55 상행), 김포골드 2개(P01 상행·P10 하행). 그 방향엔 애초에 출발
/// 열차가 없고, "운행 종료"(null)로 바뀐 조합은 양쪽 다 0건이다.
/// 그럼에도 잠그는 이유는 첫차·막차를 화면에 쓰는 기능이 생기면 즉시 오답이
/// 되기 때문이다(2026-08-13 앵커역 정정과 같은 사유).
///
/// ⚠ **오진 기록**: 경의중앙 작업 때 "`f`=05:10 이라 05:00~05:09 조회가 전날
/// 운영일로 폴백한다"고 진단했으나 **틀렸다.** 전날 분기는
/// `prevDepartures.last >= 1440` 을 요구하는데 경의중앙은 자정 넘김을 0~239 로
/// 담아 해당되지 않는다. 이 인코딩은 `departure_candidates.dart` 에 이미 적혀
/// 있던 사실이다 — 같은 추론을 처음부터 다시 밟지 말 것.
///
/// ## 왜 전 노선 공통 규칙으로 하지 않는가
///
/// `line_schedule_anchor_sanity_test.dart` 는 `f`/`l` 을 `t` 의 최소·최대와
/// 직접 비교하지 **않는다** — 자정 넘김 인코딩이 노선마다 달라 전 노선 공통
/// 규칙으로는 거짓 실패가 나기 때문이다. 여기서는 도출 대상 노선만 보고,
/// 두 인코딩(1440+ / 0~1439)을 모두 흡수하는 규약을 명시적으로 적용한다.
///
/// **아직 대상이 아닌 노선**(같은 어긋남이 남아 있음): 우이신설(평일 `l=00:40`
/// vs 실측 00:58), 인천1(평일 `f=05:00` vs 실측 05:30). 고치면 여기 목록에
/// 추가할 것.
void main() {
  /// 도출 대상 노선 → 되돌아가면 안 되는 옛 추정치 {요일: [f, l]}.
  const derivedLines = <String, Map<String, List<List<String>>>>{
    '경의중앙': {
      'wd': [
        ['05:10', '05:10'],
        ['23:40', '23:40'],
      ],
      'we': [
        ['05:30', '05:30'],
        ['23:00', '23:00'],
      ],
    },
    '김포골드': {
      'wd': [
        ['05:30', '05:30'],
        ['23:30', '23:30'],
      ],
      'we': [
        ['06:00', '06:00'],
        ['23:00', '23:00'],
      ],
    },
  };

  /// 자정 넘김 인코딩 경계. `departure_candidates.dart` 의
  /// `lateNightCutoffMinutes` 와 같은 값이다. `t` 는 자정 이후 출발을 1440+ 로
  /// 담는 노선(김포골드 24:58 → 1498)과 0~1439 로 담는 노선(경의중앙 00:39 →
  /// 39)이 섞여 있어, 두 경우를 이 경계로 가른다.
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

  late List<Map<String, dynamic>> schedules;

  setUpAll(() {
    final raw = File('assets/json/line_schedules.json').readAsStringSync();
    schedules = (json.decode(raw) as List).cast<Map<String, dynamic>>();
  });

  Map<String, dynamic> lineOf(String id) =>
      schedules.firstWhere((s) => s['id'] == id);

  for (final entry in derivedLines.entries) {
    final lineId = entry.key;
    final estimates = entry.value;

    for (final day in const ['wd', 'we']) {
      for (final dir in const [0, 1]) {
        final label = '$lineId $day idx$dir';

        test('[$label] f 는 그 방향 첫 출발과 같다', () {
          final dayObj = lineOf(lineId)[day] as Map<String, dynamic>;
          final table = (dayObj['t'] as Map).cast<String, dynamic>();

          final sameDay = <int>[];
          for (final dirs in table.values) {
            final list = (dirs as List)[dir];
            if (list == null) continue;
            for (final m in (list as List).cast<int>()) {
              if (m >= lateNightCutoff && m < 1440) sameDay.add(m);
            }
          }
          expect(sameDay, isNotEmpty,
              reason: '$label 에 정상 시간대 출발이 있어야 한다');

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
          final dayObj = lineOf(lineId)[day] as Map<String, dynamic>;
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

      test('[$lineId $day] 첫 배차 band 가 f 이전을 비워 두지 않는다', () {
        // `f` 만 당기고 `p` 를 두면 그 사이를 덮는 band 가 없어
        // `_findNextByHeadway` → `_findPeriod` 가 null("운행 종료")을 돌려준다.
        // 두 노선 모두 배차간격 경로가 `t` 없는 종점 방향에서만 쓰이지만,
        // f 와 p 가 어긋난 상태를 데이터에 남기지 않는다.
        //
        // ⛔ 꼬리 갭(마지막 band 끝 ~ `l`)은 **의도적으로 남긴다.** 끝을 `l` 까지
        // 늘리면 배차간격이 실재하지 않는 심야 출발을 지어낸다.
        final dayObj = lineOf(lineId)[day] as Map<String, dynamic>;
        final bands = dayObj['p'] as List;
        expect(bands, isNotEmpty);

        final firstBandStart = parseMinutes((bands.first as List)[0] as String);
        final earliest = (dayObj['f'] as List)
            .cast<String>()
            .map(parseMinutes)
            .reduce((a, b) => a < b ? a : b);
        // 도구는 양방향으로 정렬하므로 지금은 등호가 성립한다. 그래도
        // `lessThanOrEqualTo` 로 잠그는 이유는, 지켜야 할 계약이 "첫 band 가
        // 첫차보다 늦게 시작하지 않는다"이기 때문이다 — 더 이르게 시작하는
        // 것은 `firstTrainMinutes` 게이트가 막아 주어 무해하다.
        expect(firstBandStart, lessThanOrEqualTo(earliest),
            reason: '첫 band 가 첫차보다 늦게 시작하면 그 사이가 "운행 종료"가 된다');
      });
    }

    test('[$lineId] 하드코딩 추정치로 되돌아가지 않았다', () {
      // extract_schedules.dart 의 _getEstimatedSchedule 값. 이 조합이 그대로
      // 보이면 그 도구가 도출값을 덮어썼다는 뜻이다.
      final line = lineOf(lineId);
      for (final day in const ['wd', 'we']) {
        final dayObj = line[day] as Map<String, dynamic>;
        expect(
          [dayObj['f'], dayObj['l']],
          isNot(estimates[day]),
          reason: '$lineId.$day 가 추정치로 되돌아갔다 — '
              'extract_schedules.dart 의 _representativeCarryOverLines 확인',
        );
      }
    });
  }
}
