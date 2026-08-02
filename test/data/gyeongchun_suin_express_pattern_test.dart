// 경춘선·수인분당선 급행 정차 패턴 회귀 가드.
//
// 배경 — 2026-08 까지 이 두 노선의 가상 급행 노선(`경춘E`·`수인분당E`)은 완행의
// **복제본**이었다. `express_skip_edges.json` 의 경춘 22개·수인분당 55개 edge 가
// 전부 `skippedStationIds` 가 빈 인접쌍이어서, 급행/완행 비교 탭이 실질적으로
// 같은 여정을 둘로 보여주고 있었다.
//
// 원인은 1호선과 같다 — data.go.kr 시간표 API 가 `etrnYn='Y'` 열차에 대해
// **통과역까지 trainDptreTm 을 채워** 주기 때문에 자동 수집이 전 역을 정차역으로
// 잡는다. 다만 1호선과 달리 **시각 자체는 진짜 급행 시각이었다.** 교차검증:
//   · 편성 수 — 경춘 Y 5편성 = 공표 "평일 상행 2회·하행 3회".
//     수인분당 Y 는 분당 계열 14 + 수인 계열 8 = 공표 14 + 8.
//   · 소요시간 — 죽전→수원 Y 중앙값 23분 00초(n=14) = 공표 급행 23분.
//     같은 구간 N 중앙값 31분 30초(n=205) = 공표 완행 31분.
// 그래서 `tool/manual_express_stops.json` 의 정차역 목록을 강제 생성이 아니라
// **Y 편성 시퀀스 필터**로 쓴다(`_STOP_FILTER_LINES`). 통과역 레코드를 걸러내면
// 남은 인접 정차쌍의 시간차가 그대로 실측 급행 소요시간이 되므로, 1호선처럼
// `0.7 × 완행 합` 근사를 쓸 필요가 없다.
//
// 이 테스트가 잡는 것:
//   1) 통과역 집합 — 급행이 통과한다고 표시된 역이 실제 통과역과 정확히 일치하는지
//   2) 정차역 집합 — 가상 노선에 등장하는 역이 실제 정차역뿐인지
//   3) 물리 불변식 — 급행 소요시간이 같은 구간 완행 합을 넘지 않는지
//   4) 복제본 회귀 — 통과역 있는 edge 가 0 개로 돌아가지 않는지
//
// 정차역을 의도적으로 바꿀 때는 `manual_express_stops.json` 을 고쳐 재생성한 뒤
// (`python3 tool/extract_express_skip_edges.py`) 이 표도 함께 갱신할 것 —
// 산출물만 손으로 고치면 다음 재생성에 되돌아간다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 경춘선 급행 통과역 9개 (전체 24역 − 정차 15역).
const _gyeongchunPassed = <String>{
  '중랑', '망우', '금곡', '천마산', '대성리', '상천', '굴봉산', '백양리', '김유정',
};

/// 경춘선 급행 정차역 15개.
const _gyeongchunStops = <String>{
  '청량리', '회기', '상봉', '신내', '갈매', '별내', '퇴계원', '사릉',
  '평내호평', '마석', '청평', '가평', '강촌', '남춘천', '춘천',
};

/// 수인분당선 급행 통과역 15개 — 분당선 급행 8 + 수인선 급행 7.
const _suinPassed = <String>{
  // 분당선 급행: 죽전 이남만 통과 (왕십리~죽전은 전역 정차)
  '보정', '구성', '신갈', '상갈', '청명', '영통', '매탄권선', '매교',
  // 수인선 급행
  '달월', '월곶', '호구포', '남동인더스파크', '송도', '숭의', '신포',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Map<String, Station>> byId; // lineId -> id -> Station
  late Map<String, Map<String, int>> local; // lineId -> 'a|b' -> seconds
  late Map<String, List<ExpressSkipEdge>> express;

  setUpAll(() async {
    final stations = await LocalDataSource().loadStations();
    byId = {};
    for (final s in stations) {
      (byId[s.lineId] ??= {})[s.id] = s;
    }

    final raw = await rootBundle.loadString('assets/json/connections.json');
    local = {};
    for (final json in jsonDecode(raw) as List<dynamic>) {
      final c = Connection.fromJson(json as Map<String, dynamic>);
      if (c.isTransfer) continue;
      final m = local[c.lineId] ??= {};
      m['${c.fromStationId}|${c.toStationId}'] = c.travelTimeSeconds;
      m['${c.toStationId}|${c.fromStationId}'] = c.travelTimeSeconds;
    }

    final rawExpress =
        await rootBundle.loadString('assets/json/express_skip_edges.json');
    final byLine = jsonDecode(rawExpress) as Map<String, dynamic>;
    express = {
      for (final entry in byLine.entries)
        entry.key: [
          for (final e in (entry.value as List<dynamic>))
            ExpressSkipEdge.fromJson(e as Map<String, dynamic>),
        ],
    };
  });

  String? nameOf(String line, String id) => byId[line]?[id]?.name;

  void runChecks({
    required String line,
    required Set<String> passed,
    required Set<String> stops,
  }) {
    group('$line 급행 정차 패턴', () {
      test('통과역으로 표시된 역이 실제 통과역과 일치한다', () {
        final seen = <String>{};
        for (final e in express[line]!) {
          for (final s in e.skippedStationIds) {
            seen.add(nameOf(line, s) ?? s);
          }
        }
        expect(
          seen.difference(passed),
          isEmpty,
          reason: '급행이 통과하지 않는 역이 통과역으로 표시됐다',
        );
        expect(
          passed.difference(seen),
          isEmpty,
          reason: '실제 통과역이 어느 skip edge 에도 나타나지 않는다 — '
              '정차역 필터가 풀렸거나 빈도 문턱에 걸렸다',
        );
      });

      test('가상 급행 노선에 등장하는 역은 실제 정차역뿐이다', () {
        final ends = <String>{};
        for (final e in express[line]!) {
          ends.add(nameOf(line, e.fromStationId) ?? e.fromStationId);
          ends.add(nameOf(line, e.toStationId) ?? e.toStationId);
        }
        expect(
          ends.difference(stops),
          isEmpty,
          reason: '급행 미정차역에 `${line}E` 노드가 생긴다 — '
              'Dijkstra 가 통과역을 급행으로 지나간다',
        );
      });

      test('급행 소요시간이 같은 구간 완행 합을 넘지 않는다', () {
        final violations = <String>[];
        for (final e in express[line]!) {
          final chain = [
            e.fromStationId,
            ...e.skippedStationIds,
            e.toStationId,
          ];
          var sum = 0;
          var ok = true;
          for (var i = 0; i < chain.length - 1; i++) {
            final v = local[line]?['${chain[i]}|${chain[i + 1]}'];
            if (v == null) {
              ok = false;
              break;
            }
            sum += v;
          }
          if (ok && e.seconds > sum) {
            violations.add('${nameOf(line, e.fromStationId)}→'
                '${nameOf(line, e.toStationId)} 급행 ${e.seconds}s > 완행합 ${sum}s');
          }
        }
        expect(violations, isEmpty, reason: violations.join(' / '));
      });

      test('통과역 있는 edge 가 존재한다 (완행 복제본 회귀 방지)', () {
        final withSkip =
            express[line]!.where((e) => e.skippedStationIds.isNotEmpty).length;
        expect(
          withSkip,
          greaterThan(0),
          reason: '`${line}E` 가 다시 완행의 복제본이 됐다 — '
              'extract_express_skip_edges.py 의 _STOP_FILTER_LINES 확인',
        );
      });
    });
  }

  runChecks(line: '경춘', passed: _gyeongchunPassed, stops: _gyeongchunStops);
  runChecks(line: '수인분당', passed: _suinPassed, stops: {
    // 분당선 급행 29역
    '왕십리', '서울숲', '압구정로데오', '강남구청', '선정릉', '선릉', '한티',
    '도곡', '구룡', '개포동', '대모산입구', '수서', '복정', '가천대', '태평',
    '모란', '야탑', '이매', '서현', '수내', '정자', '미금', '오리', '죽전',
    '기흥', '망포', '수원시청', '수원', '고색',
    // 수인선 급행 7역
    '오이도', '소래포구', '인천논현', '원인재', '연수', '인하대', '인천',
  });

  test('9호선 급행은 이 변경에 영향받지 않는다', () {
    // 9호선은 `etrnYn` 이 유일하게 신뢰 가능한 노선(Y 편성 232개 전부가 실제로
    // 역을 건너뛴다)이라 필터 대상이 아니다. edge 수가 바뀌면 회귀다.
    expect(express['9']!.length, 28);
    expect(
      express['9']!.where((e) => e.skippedStationIds.isNotEmpty).length,
      26,
    );
  });
}
