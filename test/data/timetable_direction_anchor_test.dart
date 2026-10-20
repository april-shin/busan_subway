import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';

/// 시간표(`line_schedules.json`) 방향 인덱스가 앱 `isDownBetween` 과 같은 방향을
/// 가리키는지 **양 종점 앵커**로 잠근다 — 이중 보정 가드.
///
/// 시간표 `t[역ID] = [idx0(상행), idx1(하행)]` 는 앱 `isDown` 을 기준으로 저장된다
/// (`tool/build_gettrainsch_timetable.dart` 의 `_reversed` 가 외부 라벨을 앱 방향으로
/// 맞춘다). 그래서 `isDownBetween` 의 노선별 반전 규칙을 고치면 시간표도 같이
/// 뒤집어야 한다. 한쪽만 고치면 **출발 시각이 반대 방향 열차로 읽힌다.**
///
/// 앵커 원리: 종점역에서 출발하는 열차는 **한 방향(노선 안쪽)뿐**이다. 반대 방향 열차는
/// 도착 전용이라 출발시각이 없다(getTrainSch `trainDptreTm=null` → 스킵 → idx 가 null).
/// 따라서 종점 T 와 그 이웃 N 에 대해
///   `isDownBetween(T, N)` 이 가리키는 idx 에만 출발시각이 있어야 한다.
///
/// 2026-10-20 우이신설: `isDownBetween` 을 API 라벨(하행=북한산우이 방면)에 맞춰 반전하면서
/// 시간표 t 를 함께 뒤집었다(W01 이 idx1 → idx0). 이 테스트 없이는 한쪽만 고쳐도 통과했다.
void main() {
  late Map<String, Map<String, dynamic>> byLine;

  setUpAll(() {
    final raw = jsonDecode(File('assets/json/line_schedules.json').readAsStringSync())
        as List<dynamic>;
    byLine = {
      for (final e in raw) (e as Map<String, dynamic>)['id'] as String: e,
    };
  });

  // (노선, 종점역 ID, 안쪽 이웃역 ID, 설명)
  const anchors = <(String, String, String, String)>[
    ('우이신설', 'W01', 'W02', '북한산우이(신설동행만 출발)'),
    ('우이신설', 'W13', 'W12', '신설동(북한산우이행만 출발)'),
    ('공항철도', 'A01', 'A02', '서울역(인천공항행만 출발)'),
    ('공항철도', 'A14', 'A13', '인천공항2터미널(서울행만 출발)'),
    ('9', '901', '902', '개화(중앙보훈병원행만 출발)'),
    ('9', '938', '937', '중앙보훈병원(개화행만 출발)'),
    ('김포골드', 'P01', 'P02', '양촌(김포공항행만 출발)'),
    ('김포골드', 'P10', 'P09', '김포공항(양촌행만 출발)'),
    ('의정부', 'U01', 'U02', '탑석(발곡행만 출발)'),
    ('의정부', 'U14', 'U15', '발곡(탑석행만 출발)'),
  ];

  for (final (line, term, neighbor, desc) in anchors) {
    for (final day in const ['wd', 'we']) {
      test('$line $desc [$day] — 출발시각은 isDownBetween 방향 idx 에만 있다', () {
        final dayObj = byLine[line]![day] as Map<String, dynamic>?;
        if (dayObj == null) return; // `we` 없으면 `wd` 폴백
        final dirs = (dayObj['t'] as Map<String, dynamic>)[term] as List<dynamic>;

        final goesDown = isDownBetween(term, neighbor, line);
        final live = goesDown ? 1 : 0; // 이 방향으로 출발 열차가 있어야 한다
        final dead = 1 - live;

        final liveList = dirs[live] as List<dynamic>?;
        final deadList = dirs[dead] as List<dynamic>?;
        expect(liveList, isNotNull,
            reason: '$line $term: isDown=$goesDown 방향(idx$live)에 출발시각이 있어야 한다. '
                '시간표 방향 인덱스와 isDownBetween 이 어긋남(이중 보정 의심)');
        expect(liveList!.length, greaterThan(50));
        expect(deadList == null || deadList.isEmpty, isTrue,
            reason: '$line $term: 반대 방향(idx$dead)은 도착 전용이라 비어야 한다');
      });
    }
  }
}
