import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/usecases/find_next_departure.dart';
import 'package:seoul_subway/features/route_search/utils/departure_candidates.dart';
import 'package:seoul_subway/features/route_search/utils/departure_query_time.dart';

import '../../../helpers/compact_schedule_parser.dart';

/// 실제 `assets/json/line_schedules.json` 전 노선·전 역에 대한 왕복 계약 검증.
///
/// 합성 스케줄만으로는 데이터 컨벤션의 편차를 잡을 수 없다. 실제로 다음 두
/// 이상치가 합성 테스트를 통과한 채 남아 있었다:
///
/// - **GTX-A**: `firstTrain` 이 "00:06"/"00:15" 이라, 자정 넘김(1440+) 후보를
///   고르면 심야 폴백 가드(`currentMinutes < firstTrainMinutes`)가 거짓이 되어
///   아침 첫차가 잡혔다.
/// - **경의중앙**: 자정 넘김 열차를 1440+ 가 아니라 0~1439 로 담는다
///   (00:01 → `1`). 0 은 1분 빼기에서 전날 23:59 로 언더플로했다.
///
/// 이 파일은 `rootBundle` 대신 `dart:io` 로 직접 읽는다 — 순수 Dart 계산만
/// 검증하므로 위젯 바인딩이 필요 없고, 7.4MB 를 1회만 파싱한다.
void main() {
  late Map<String, LineSchedule> schedules;

  setUpAll(() {
    final file = File('assets/json/line_schedules.json');
    if (!file.existsSync()) {
      fail('line_schedules.json 이 없습니다: ${file.absolute.path}');
    }
    final raw = json.decode(file.readAsStringSync()) as List<dynamic>;
    schedules = {
      for (final item in raw)
        (item as Map<String, dynamic>)['id'] as String:
            parseCompactSchedule(item),
    };
  });

  // 월요일 고정 — anchorDateFor 가 여기서 요일 타입별 앵커를 유도한다.
  final monday = DateTime(2026, 2, 23, 9, 0);

  /// 특정 (노선, 요일, 방향, 역, 모드) 조합의 모든 후보를 왕복 검증한다.
  /// 위반 목록을 반환한다(빈 리스트 = 통과).
  List<String> verifyCombination({
    required String lineId,
    required LineSchedule schedule,
    required DepartureDayType dayType,
    required bool isDown,
    required String stationId,
    required bool express,
  }) {
    final anchor = anchorDateFor(dayType, monday);
    final candidates = buildDepartureCandidates(
      schedule: schedule,
      anchorDate: anchor,
      isDown: isDown,
      stationId: stationId,
      express: express,
    );
    if (candidates.isEmpty) return const [];

    final violations = <String>[];
    for (final minutes in candidates) {
      final query = DepartureQueryTime(minutes: minutes, dayType: dayType);
      // 화면이 실제로 쓰는 결정 함수를 그대로 태운다 — 이 경로가 탐색 기반으로
      // 되돌아가면 GTX-A 등에서 즉시 깨진다.
      final resolved = resolveChosenDeparture(
        query: query,
        candidates: candidates,
        now: monday,
      );

      if (resolved == null) {
        violations.add(
          '$lineId/$stationId $minutes → null (후보에 있는데 확정 실패)',
        );
        continue;
      }
      final label = '$lineId/$stationId ${dayType.label}'
          '${isDown ? "하행" : "상행"}${express ? "급행" : ""} '
          '${formatOperatingMinutes(minutes)}($minutes)';

      // (1) 확정 시각을 앵커 기준 분으로 되돌리면 고른 값과 같아야 한다.
      final actual = resolved.difference(anchor).inMinutes;
      if (actual != minutes) {
        violations.add(
          '$label → ${formatOperatingMinutes(actual)}($actual) [분 불일치]',
        );
      }

      // (2) 확정 시각의 벽시계 HH:mm 이 그리드에 표시한 라벨과 같아야 한다.
      //     1440+ 를 다음 달력일로 푸는 매핑과 라벨의 `% 24` 가 어긋나면
      //     사용자는 24:27 을 눌렀는데 다른 시각이 표시된다.
      final wallClock = '${resolved.hour.toString().padLeft(2, '0')}:'
          '${resolved.minute.toString().padLeft(2, '0')}';
      if (wallClock != formatOperatingMinutes(minutes)) {
        violations.add('$label → 벽시계 $wallClock [라벨 불일치]');
      }

      // (3) 자정 넘김 후보는 앵커 다음날로 넘어가야 하고, 그 외는 앵커 당일.
      final expectedDayOffset = minutes ~/ 1440;
      final actualDayOffset =
          DateTime(resolved.year, resolved.month, resolved.day)
              .difference(anchor)
              .inDays;
      if (actualDayOffset != expectedDayOffset) {
        violations.add(
          '$label → 날짜 오프셋 $actualDayOffset (기대 $expectedDayOffset)',
        );
      }
    }
    return violations;
  }

  test('전 노선·전 역·전 조합에서 고른 시각이 그대로 출발 시각이 된다', () {
    final violations = <String>[];
    var checkedCombinations = 0;
    var checkedCandidates = 0;

    for (final entry in schedules.entries) {
      for (final dayType in DepartureDayType.values) {
        for (final isDown in [false, true]) {
          for (final express in [false, true]) {
            final anchor = anchorDateFor(dayType, monday);
            final day = entry.value.getSchedule(anchor, isDown: isDown);
            final map = express
                ? day.expressStationDepartures
                : day.stationDepartures;
            if (map == null) continue;

            for (final stationId in map.keys) {
              final found = verifyCombination(
                lineId: entry.key,
                schedule: entry.value,
                dayType: dayType,
                isDown: isDown,
                stationId: stationId,
                express: express,
              );
              violations.addAll(found);
              checkedCombinations++;
              checkedCandidates += map[stationId]?.length ?? 0;
            }
          }
        }
      }
    }

    expect(checkedCombinations, greaterThan(1000),
        reason: '실데이터가 제대로 로드되지 않았다 (조합 $checkedCombinations개)');
    expect(checkedCandidates, greaterThan(10000),
        reason: '후보 수가 비정상적으로 적다 ($checkedCandidates개)');
    expect(
      violations,
      isEmpty,
      reason: '${violations.length}건 불일치. 앞 20건:\n'
          '${violations.take(20).join("\n")}',
    );
  });

  // 부정형 가드 — "무엇이 뒤로 가는가"가 아니라 **"무엇이 뒤로 가면 안 되는가"**.
  //
  // 앞선 구현은 재배치 경계로 `daySchedule.firstTrainMinutes`(노선 첫차)를 썼는데,
  // 그건 역별 출발시각의 하한이 아니다(차량기지 출고로 중간역이 더 이르다).
  // 그 결과 실제 아침 첫차 수천 건이 목록 끝으로 밀려 사용자가 그리드 맨 위에서
  // 자기 첫차를 못 찾는 상태였다. 긍정형 테스트("이동된 값이 뒤에 온다")는 구현과
  // 같은 술어를 쓰는 항등식이라 이걸 통과시켰다.
  test('아침 이후 열차는 절대 뒤로 밀리지 않는다 (재배치 경계 회귀 가드)', () {
    const cutoff = 240; // 04:00 — 구현의 _lateNightCutoffMinutes 와 동일 계약
    final misplaced = <String>[];
    var relocatedCount = 0;

    for (final entry in schedules.entries) {
      for (final dayType in DepartureDayType.values) {
        for (final isDown in [false, true]) {
          for (final express in [false, true]) {
            final anchor = anchorDateFor(dayType, monday);
            final day = entry.value.getSchedule(anchor, isDown: isDown);
            final map = express
                ? day.expressStationDepartures
                : day.stationDepartures;
            if (map == null) continue;

            for (final stationId in map.keys) {
              final original = map[stationId]!;
              final candidates = buildDepartureCandidates(
                schedule: entry.value,
                anchorDate: anchor,
                isDown: isDown,
                stationId: stationId,
                express: express,
              );
              if (candidates.isEmpty) continue;

              // 값 집합은 보존돼야 한다 (재배치는 순서만 바꾼다).
              expect(candidates.toSet(), original.toSet(),
                  reason: '${entry.key}/$stationId 값 집합이 변했다');

              // 결과는 "오름차순 앞부분 + 오름차순 꼬리" 형태이고, 꼬리 첫 값이
              // 앞부분 마지막보다 작다. 따라서 내림 지점이 정확히 재배치 경계다.
              var tailStart = candidates.length;
              for (var i = 1; i < candidates.length; i++) {
                if (candidates[i] < candidates[i - 1]) {
                  tailStart = i;
                  break;
                }
              }
              final relocated = candidates.sublist(tailStart);
              relocatedCount += relocated.length;

              // 뒤로 간 값은 전부 진짜 심야여야 한다.
              for (final m in relocated) {
                if (m >= cutoff) {
                  misplaced.add(
                    '${entry.key}/$stationId ${dayType.label}'
                    '${isDown ? "하행" : "상행"}${express ? "급행" : ""} '
                    '${formatOperatingMinutes(m)}($m) [뒤로 밀림]',
                  );
                }
              }
              // 반대로 심야 값이 앞부분에 남아 있어도 안 된다.
              for (final m in candidates.take(tailStart)) {
                if (m < cutoff) {
                  misplaced.add(
                    '${entry.key}/$stationId '
                    '${formatOperatingMinutes(m)}($m) [앞에 남음]',
                  );
                }
              }
            }
          }
        }
      }
    }

    expect(relocatedCount, greaterThan(0),
        reason: '재배치 대상(경의중앙 심야)이 하나도 없으면 이 가드가 무의미하다');
    expect(
      misplaced,
      isEmpty,
      reason: '아침 이후 열차 ${misplaced.length}건이 목록 끝으로 밀렸다. 앞 10건:\n'
          '${misplaced.take(10).join("\n")}',
    );
  });

  test('심야 열차는 표시 순서상 목록 끝으로 간다 (인코딩 편차 흡수)', () {
    // 경의중앙은 자정 넘김을 0~1439 로 담아 정렬상 목록 맨 앞에 온다.
    // buildDepartureCandidates 가 첫차 이전 값을 뒤로 돌려야 한다.
    final gyeonguiJungang = schedules['경의중앙'];
    expect(gyeonguiJungang, isNotNull, reason: '경의중앙 스케줄이 있어야 한다');

    final anchor = anchorDateFor(DepartureDayType.weekday, monday);
    final day = gyeonguiJungang!.getSchedule(anchor);
    final firstTrain = day.firstTrainMinutes;

    // 첫차 이전 값이 실제로 존재하는 역을 찾는다(데이터 전제 확인).
    final stationWithLateNight = day.stationDepartures?.entries.firstWhere(
      (e) => e.value.any((m) => m < firstTrain),
      orElse: () => const MapEntry('', []),
    );
    expect(stationWithLateNight?.key, isNotEmpty,
        reason: '경의중앙에 첫차 이전 인코딩 값이 있어야 이 테스트가 의미 있다');

    final candidates = buildDepartureCandidates(
      schedule: gyeonguiJungang,
      anchorDate: anchor,
      isDown: false,
      stationId: stationWithLateNight!.key,
      express: false,
    );

    final firstLateNightIndex =
        candidates.indexWhere((m) => m < firstTrain);
    final lastNormalIndex =
        candidates.lastIndexWhere((m) => m >= firstTrain);
    expect(firstLateNightIndex, greaterThan(lastNormalIndex),
        reason: '첫차 이전(심야) 값은 모두 정상 시간대 뒤에 와야 한다');
  });

  test('GTX-A 자정 넘김 선택 — 탐색 기반으로 되돌리면 깨진다는 것을 고정', () {
    // 데이터 전제: GTX-A 첫차가 자정 직후라 심야 폴백 가드가 발동하지 않는다.
    final gtxA = schedules['GTX-A'];
    expect(gtxA, isNotNull);
    expect(gtxA!.weekday.firstTrainMinutes, lessThan(60),
        reason: 'GTX-A 첫차가 자정 직후(00:xx)라는 전제');

    final anchor = anchorDateFor(DepartureDayType.weekday, monday);
    final day = gtxA.getSchedule(anchor);
    final station = day.stationDepartures!.entries
        .firstWhere((e) => e.value.any((m) => m >= 1440));
    final lateNight = station.value.firstWhere((m) => m >= 1440);

    final query =
        DepartureQueryTime(minutes: lateNight, dayType: DepartureDayType.weekday);

    // 현재 구현(확정): 고른 그 열차가 나온다.
    final chosen = resolveChosenDeparture(
      query: query,
      candidates: buildDepartureCandidates(
        schedule: gtxA,
        anchorDate: anchor,
        isDown: false,
        stationId: station.key,
        express: false,
      ),
      now: monday,
    );
    expect(chosen, isNotNull);
    expect(chosen!.difference(anchor).inMinutes, lateNight);

    // 대조군: 탐색 기반(findNextDeparture)은 같은 입력에서 다른 열차를 준다.
    // 이 기대가 깨진다면 상류 usecase 가 고쳐진 것이므로, 그때 확정 경로가
    // 여전히 필요한지 재검토하라는 신호다.
    final searched = findNextDeparture(
      schedule: gtxA,
      now: resolveQueryDateTime(query, monday),
      isDown: false,
      stationId: station.key,
    );
    expect(
      searched?.difference(anchor).inMinutes,
      isNot(lateNight),
      reason: 'GTX-A 탐색 경로가 고쳐졌다면 확정 경로의 필요성을 재검토할 것',
    );
  });
}
