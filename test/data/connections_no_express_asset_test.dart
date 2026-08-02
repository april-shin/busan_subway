// 구 급행 모델(`expressTimeSeconds`) 부활 방지 회귀 가드.
//
// 배경 — 급행 모델이 오래 둘로 병립했다.
//   · 신 모델: `assets/json/express_skip_edges.json` → 가상 노선 `{base}E` 노드
//     + skip edge. 경로 탐색과 급행/완행 탭 판정이 이걸 쓴다.
//   · 구 모델: `connections.json` 의 완행 edge 에 붙은 `expressTimeSeconds`
//     → `GraphEdge.expressWeightSeconds` → 세그먼트 `expressDurationSeconds`.
//     Dijkstra 가중치가 아닌 **표시 전용** 값이었다.
//
// 구 모델은 2026-08 에 데이터·배관 전부 제거됐다. 폐지 근거는 `etrnYn` 이 급행
// 지표가 아니라는 실측(`data/timetables/`) 이다:
//   · 1호선 — Y 편성 대부분이 전 역에 레코드를 갖는 사실상 완행. 93개 값 중
//     68개가 급행 미운행 구간에 붙고 36개는 완행보다 빠르다고 표시했다.
//   · 경춘 — Y 편성 5개 전부 24역 전역 정차. 값 23개가 신 모델 skip edge 와
//     완전 중복이었다(같은 원천·같은 median 알고리즘).
//   · 수인분당 — Y 편성 22개 중 14개 전역 정차, 나머지 8개도 캐시 파일이 없는
//     원인재 1역만 "통과". 값 49개 중 31개가 완행보다 느리거나 같았다.
//   · 9호선 — Y 편성은 실제로 역을 건너뛰므로 인접쌍 매칭이 거의 실패해 값이
//     1개(봉은사→종합운동장)뿐이었고 그마저 완행과 동일했다.
//
// 이 테스트가 막는 것: 에셋을 손으로 패치하거나 옛 생성기를 되살려 이 키가
// 다시 들어오는 것. `Connection` 엔티티에 필드가 없으므로 키가 돌아와도 앱은
// 조용히 무시하지만(→ connection_test.dart), 그렇게 되면 아무도 읽지 않는
// 값을 계속 동기화해야 하는 드리프트 발생원이 부활한다.
//
// 생성기 쪽 방어선은 `tool/compute_travel_times.dart` 다 — 헤더 주석에 폐지
// 사유가 있고, `etrnYn=='Y'` 표본을 버리며, 잔재 키를 발견하면 걷어낸다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> rows;

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/json/connections.json');
    rows = [
      for (final json in jsonDecode(raw) as List<dynamic>)
        json as Map<String, dynamic>,
    ];
  });

  group('connections.json — 구 급행 모델 잔재 없음', () {
    test('어떤 connection 에도 expressTimeSeconds 키가 없다', () {
      final offenders = [
        for (final r in rows)
          if (r.containsKey('expressTimeSeconds'))
            '${r['lineId']} ${r['fromStationId']}→${r['toStationId']}'
                ' (${r['expressTimeSeconds']})',
      ];

      expect(
        offenders,
        isEmpty,
        reason: '구 급행 모델은 폐지됐다. 급행은 express_skip_edges.json 의 가상 노선 '
            '`{base}E` 으로만 표현한다. 되살아난 항목: ${offenders.take(10).join(', ')}',
      );
    });

    test('에셋이 비어 있지 않다 (위 검사가 공허하게 통과하지 않도록)', () {
      expect(rows.length, greaterThan(700));
      expect(
        rows.every((r) => r.containsKey('travelTimeSeconds')),
        isTrue,
        reason: '모든 connection 은 완행 소요시간을 가져야 한다',
      );
    });
  });
}
