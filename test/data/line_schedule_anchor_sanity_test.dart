import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 노선 대표값(`f`/`l`/`p`/`pD`)이 **회차역 앵커 결함**을 다시 겪지 않는지 잠근다.
///
/// `tool/extract_schedules.dart` 는 노선 대표값을 **역 하나**(앵커역)의 API 행에서
/// 뽑는다. 앵커가 회차역이면 그 방향 열차 대부분이 당역종착이라 API 가
/// `trainDptreTm=null` 을 주고, 살아남은 소수 편성이 노선 전체 대표값이 된다.
///
/// 실제로 두 노선이 이 상태였다(2026-08-13 정정):
/// - 수인분당 앵커 왕십리 — 상행 168행 중 159편 당역종착 → 9편만 남음
/// - 경춘 앵커 상봉 — 상행 56행 중 42편 당역종착 → 14편만 남음
///
/// 그 결과 수인분당 평일 상행이 "07:32 첫차 ~ 18:51 막차", 주말 상행은
/// "11:02 ~ 16:59"(6시간), 경춘 주말 상행은 배차 band 가 `10:00~11:00`
/// **한 시간짜리 하나**로 기록됐다.
///
/// ## 왜 첫차·막차 값이 아니라 배차 band 커버리지를 재는가
///
/// `f`/`l` 을 역별 시간표(`t`)의 최소·최대와 직접 비교하면 **자정 넘김 인코딩
/// 편차**에 걸려 거짓 실패가 난다. 노선마다 인코딩이 다르다 — GTX-A 는 첫차가
/// 실제로 `00:06` 이고, 경의중앙은 심야 열차를 1440+ 가 아니라 0~1439 로 담는다
/// (`departure_candidates.dart` 의 `lateNightCutoffMinutes` 주석 참조). 그 편차를
/// 넘으려면 노선별 예외 표가 필요해지고, 그 표 자체가 다음 결함의 숨을 곳이 된다.
///
/// 배차 band 커버리지는 인코딩과 무관하다. 그리고 이 결함의 signature 를 더
/// 날카롭게 잡는다 — 실측 분리가 뚜렷하다:
/// - 정상: 전 노선·요일·방향 최소 **1020분**(김포골드 주말 상행)
/// - 결함이었던 4건: 60 · 240 · 357 · 679분
///
/// 임계 900분은 그 사이에 둔다(결함 최대 679 위, 정상 최소 1020 아래).
void main() {
  /// "HH:MM" → 자정 기준 분.
  int parseMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// 배차 band 들이 덮는 총 시간(분). 자정을 넘기는 band(`end <= start`)는
  /// +1440 으로 정규화한다 — `TimePeriod.endMinutes` 와 같은 규약이다.
  int coverageMinutes(List<dynamic> bands) {
    var total = 0;
    for (final b in bands) {
      final band = b as List<dynamic>;
      final start = parseMinutes(band[0] as String);
      var end = parseMinutes(band[1] as String);
      if (end <= start) end += 1440;
      total += end - start;
    }
    return total;
  }

  /// 앵커 결함과 정상 데이터를 가르는 커븐선. 위 독스트링의 실측 근거 참조.
  const minCoverageMinutes = 900;

  late List<dynamic> schedules;

  setUpAll(() {
    schedules = jsonDecode(
      File('assets/json/line_schedules.json').readAsStringSync(),
    ) as List<dynamic>;
  });

  test('모든 노선의 배차간격이 하루 운행을 덮는다 (회차역 앵커 결함 가드)', () {
    final tooNarrow = <String>[];

    for (final entry in schedules) {
      final line = entry as Map<String, dynamic>;
      final lineId = line['id'] as String;
      for (final dayKey in const ['wd', 'we']) {
        final day = line[dayKey] as Map<String, dynamic>?;
        if (day == null) continue; // `we` 없으면 `wd` 폴백 (컴팩트 스키마 규약)

        // `p` = 상행(공유), `pD` = 하행 전용. `pD` 가 없으면 하행도 `p` 를 쓴다.
        final checks = <String, List<dynamic>>{
          '상행': day['p'] as List<dynamic>,
          if (day['pD'] != null) '하행': day['pD'] as List<dynamic>,
        };

        for (final check in checks.entries) {
          final minutes = coverageMinutes(check.value);
          if (minutes < minCoverageMinutes) {
            tooNarrow.add('$lineId/$dayKey/${check.key}: $minutes분');
          }
        }
      }
    }

    expect(tooNarrow, isEmpty,
        reason: '배차간격이 하루 운행을 덮지 못한다 — 앵커역이 회차역인지 확인할 것. '
            'tool/extract_schedules.dart 의 lineConfigs 에서 그 노선 station 을 '
            '"양방향 전구간 운행역"으로 바꾸고 재생성한다: $tooNarrow');
  });

  test('앵커 교체가 필요했던 두 노선의 상행 대표값이 하루를 덮는다', () {
    // 위 전수 검사가 이미 커버하지만, 회귀 시 원인을 즉시 알 수 있도록 이 두
    // 노선만 이름을 박아 따로 둔다. 값이 예전으로 되돌아가면 여기가 먼저 깨진다.
    for (final probe in [
      (lineId: '수인분당', dayKey: 'wd'),
      (lineId: '수인분당', dayKey: 'we'),
      (lineId: '경춘', dayKey: 'wd'),
      (lineId: '경춘', dayKey: 'we'),
    ]) {
      final line = schedules.firstWhere(
        (e) => (e as Map<String, dynamic>)['id'] == probe.lineId,
      ) as Map<String, dynamic>;
      final day = line[probe.dayKey] as Map<String, dynamic>;

      expect(
        coverageMinutes(day['p'] as List<dynamic>),
        greaterThanOrEqualTo(minCoverageMinutes),
        reason: '${probe.lineId} ${probe.dayKey} 상행 배차가 다시 좁아졌다 — '
            '앵커역이 회차역(수인분당 왕십리 / 경춘 상봉)으로 되돌아갔는지 확인',
      );
    }
  });
}
