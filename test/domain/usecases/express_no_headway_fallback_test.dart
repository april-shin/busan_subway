import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/usecases/find_next_departure.dart';

import '../../helpers/compact_schedule_parser.dart';

/// 급행 조회는 배차간격(= 완행 간격) 폴백을 타지 않는다 — 실데이터 회귀 가드.
///
/// 배경: `DaySchedule.periods` 는 완행 배차간격이다. 급행 조회가 여기로 떨어지면
/// "급행이 완행 간격으로 온다"는 없는 열차를 만든다. 경춘·수인분당은 주말 급행
/// 시간표(`we.tE`)가 아예 없어(getTrainSch 가 주말 열차를 전부 `etrnYn=N` 으로
/// 제공) 주말 급행 조회가 전량 이 폴백을 탔고, 수인분당 하행은 05:00~23:36
/// 하루 종일 "9분마다 급행"이라는 가짜 시각을 냈다.
///
/// 이 테스트는 번들 JSON 을 직접 읽어 **데이터와 규칙을 함께** 잠근다:
/// 1. 급행 skip-edge 의 `(출발역, 진행 방향)` 마다 평일 `tE` 슬롯이 채워져 있다
///    — 게이트가 정상 급행을 막지 않는다는 근거.
/// 2. 주말 결손은 "그 요일 급행 미운행"과 일치한다(경춘·수인분당 전량, 1·9호선 0).
/// 3. 결손 요일·역에 급행을 조회하면 `null` 이다(가짜 시각 없음).
///
/// **방향별로 판정한다.** `tE[역]` 은 `[상행목록, 하행목록]` 이고 런타임 게이트는
/// 조회 방향 슬롯만 본다. "어느 방향이든 있으면 보유"로 세면, 특정 방향 슬롯이
/// 비었는데 그 방향으로 급행 edge 가 있는 데이터 회귀 — 즉 게이트가 정상 급행을
/// 막는 바로 그 사고 — 를 놓친다.
void main() {
  // rootBundle 없이 도는 순수 Dart 테스트 — 에셋 경로를 직접 읽는다.
  Map<String, dynamic> readJsonMap(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  List<dynamic> readJsonList(String path) =>
      jsonDecode(File(path).readAsStringSync()) as List<dynamic>;

  late Map<String, dynamic> schedulesRaw;
  late Map<String, LineSchedule> schedules;

  /// 급행 skip-edge 를 `(노선, 출발역, 하행여부)` 로 펼친 목록.
  /// 게이트가 실제로 보는 축과 같다 — 방향은 `isDownBetween` 으로 판정한다.
  late List<({String lineId, String from, bool isDown})> expressLegs;

  setUpAll(() {
    final raw = readJsonList('assets/json/line_schedules.json');
    schedulesRaw = {
      for (final l in raw) (l as Map<String, dynamic>)['id'] as String: l,
    };
    schedules = parseCompactSchedules(raw);

    final edges = readJsonMap('assets/json/express_skip_edges.json');
    expressLegs = [
      for (final entry in edges.entries)
        for (final e in entry.value as List<dynamic>)
          (
            lineId: entry.key,
            from: (e as Map<String, dynamic>)['fromStationId'] as String,
            isDown: isDownBetween(
              e['fromStationId'] as String,
              e['toStationId'] as String,
              entry.key,
            ),
          ),
    ];
  });

  /// [dayKey](`wd`/`we`) 급행 시간표에서 [from] 의 [isDown] 방향 슬롯이 찼는지.
  bool hasExpressSlot(String lineId, String dayKey, String from, bool isDown) {
    final day = schedulesRaw[lineId]?[dayKey] as Map<String, dynamic>?;
    // `we` 가 없으면 `wd` 폴백 (컴팩트 스키마 규약).
    final effective =
        day ?? schedulesRaw[lineId]?['wd'] as Map<String, dynamic>?;
    final entry = (effective?['tE'] as Map<String, dynamic>?)?[from]
        as List<dynamic>?;
    if (entry == null) return false;
    final index = isDown ? 1 : 0;
    if (index >= entry.length) return false;
    final slot = entry[index];
    return slot is List && slot.isNotEmpty;
  }

  int blockedCount(String lineId, String dayKey) => expressLegs
      .where((leg) => leg.lineId == lineId)
      .where((leg) => !hasExpressSlot(lineId, dayKey, leg.from, leg.isDown))
      .length;

  int legCount(String lineId) =>
      expressLegs.where((leg) => leg.lineId == lineId).length;

  test('평일에는 급행 skip-edge 가 하나도 막히지 않는다 (게이트 오작동 방지)', () {
    for (final lineId in ['1', '9', '경춘', '수인분당']) {
      expect(blockedCount(lineId, 'wd'), 0,
          reason: '$lineId 평일 급행 구간이 게이트에 막힌다 — '
              '정상 급행 경로가 사라진다');
    }
  });

  test('주말 결손은 경춘·수인분당 전량, 1·9호선은 0 (대조군)', () {
    // 1·9호선은 주말에도 급행이 운행하므로 하나도 막히지 않아야 한다.
    expect(blockedCount('1', 'we'), 0);
    expect(blockedCount('9', 'we'), 0);

    // 경춘·수인분당은 주말 급행 데이터가 통째로 없다(= 그 요일 급행 미운행).
    // 일부만 결손이면 "운행하는데 데이터가 빠진" 상태라 별도 조사가 필요하다.
    for (final lineId in ['경춘', '수인분당']) {
      expect(blockedCount(lineId, 'we'), legCount(lineId),
          reason: '$lineId 주말 tE 가 부분 결손 — 데이터 수집 상태를 다시 확인할 것');
    }
  });

  group('주말 급행 조회는 가짜 시각을 만들지 않는다', () {
    // 2026-08-16 은 일요일 — `getSchedule` 이 주말 스케줄을 고른다.
    final sunday = DateTime(2026, 8, 16, 14, 0);

    // 하행으로 검증한다 — 수인분당·경춘 주말 `pD` 가 하루를 거의 다 덮어,
    // 폴백이 살아 있으면 종일 가짜 시각이 나오는 최악의 경우다.
    for (final probe in [
      (lineId: '수인분당', stationId: 'B22'), // 정자
      (lineId: '경춘', stationId: 'C04'), // 상봉
    ]) {
      test('${probe.lineId} ${probe.stationId} 주말 급행 → null', () {
        final schedule = schedules[probe.lineId]!;

        expect(
          findNextDeparture(
            schedule: schedule,
            now: sunday,
            isDown: true,
            stationId: probe.stationId,
            express: true,
          ),
          isNull,
          reason: '주말 급행 시간표가 없는데 완행 배차간격으로 시각이 만들어졌다',
        );

        // 대조군 — 같은 시각 완행은 정상적으로 잡혀야 한다(과잉 차단 방지).
        expect(
          findNextDeparture(
            schedule: schedule,
            now: sunday,
            isDown: true,
            stationId: probe.stationId,
            express: false,
          ),
          isNotNull,
          reason: '완행까지 막혔다 — 게이트가 express 조회에만 걸려야 한다',
        );
      });
    }
  });
}
