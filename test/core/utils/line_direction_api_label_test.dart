import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/core/utils/path_on_line.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 앱 `isDownBetween` 이 서울 API `realtimeStationArrival` 의 `updnLine` 라벨과
/// 일치하는지 **실측 표**로 잠근다.
///
/// 배경(2026-10-20): `isDownBetween` 의 라벨 반전 규칙에 9호선·공항철도만 있고
/// 우이신설이 빠져 있었다. 솔샘 질의 실측은
///   하행 → 북한산우이행(W01 방면, ID 감소) / 상행 → 신설동행(W13 방면, ID 증가)
/// 인데 앱은 ID 증가 = 하행으로 판정해 **정확히 반대**였다. 영향:
///  - 지도: 방향 게이트(`isDownDirectionString(label) != routeFilter.isDown`)와
///    `findPathOnLine(현재역→출발역, isDown)` 이 전부 어긋나 우이신설 열차가 38행 중
///    1행(터미널 이중 행) 빼고 안 그려졌다.
///  - 출발 시각: `departure_time_calculator` 가 라벨 필터로 반대 방향 열차를 후보로 썼다.
///
/// 아래 표의 각 행은 같은 날 실측한 `(질의역, 행선지 bstatnNm, updnLine)` 이다.
/// 방향 판정은 `질의역 → 행선지` 로 한다 — 열차가 가는 쪽이 곧 라벨이 가리키는 방향.
///
/// ⚠ 이 파일 전체가 **lock-in 이지 탐지기가 아니다.** 아래 실측 표는 2026-10-20 시점의
/// 스냅샷을 고정할 뿐이라, API 라벨이 나중에 바뀌어도 계속 통과한다. 라벨 변화를
/// 잡으려면 `dart run tool/check_api_direction_labels.dart` 를 주기적으로 돌릴 것.
///
/// 의정부경전철·김포골드라인은 `realtimeStationArrival` 이 INFO-200 으로 응답하지
/// 않아(실측 2026-10-20: 탑석·송산·…·발곡, 양촌·구래·…·김포공항 전수) 대조할 라벨이
/// 없다. 그래서 반전 대상이 아니며 일반 규칙(ID 증가 = 하행)을 유지한다.
void main() {
  group('isDownBetween ↔ API updnLine 실측 대조 (2026-10-20)', () {
    // (노선, 질의역 ID, 행선지 ID, API updnLine, 설명)
    const rows = <(String, String, String, String, String)>[
      // 우이신설 — 이번에 고친 노선.
      ('우이신설', 'W08', 'W01', '하행', '솔샘 → 북한산우이행'),
      ('우이신설', 'W08', 'W13', '상행', '솔샘 → 신설동행'),
      ('우이신설', 'W04', 'W01', '하행', '가오리 → 북한산우이행'),
      ('우이신설', 'W04', 'W13', '상행', '가오리 → 신설동행'),
      ('우이신설', 'W11', 'W01', '하행', '성신여대입구 → 북한산우이행'),
      ('우이신설', 'W11', 'W13', '상행', '성신여대입구 → 신설동행'),
      // 9호선 — 기존 반전. 회귀 방지.
      ('9', '902', '901', '하행', '김포공항 → 개화행'),
      ('9', '902', '938', '상행', '김포공항 → 중앙보훈병원행'),
      ('9', '920', '901', '하행', '동작 → 개화행'),
      ('9', '920', '938', '상행', '동작 → 중앙보훈병원행'),
      // 공항철도 — 기존 반전. 회귀 방지.
      ('공항철도', 'A06', 'A01', '하행', '김포공항 → 서울행'),
      ('공항철도', 'A06', 'A14', '상행', '김포공항 → 인천공항2터미널행'),
      ('공항철도', 'A03', 'A01', '하행', '홍대입구 → 서울행'),
      ('공항철도', 'A03', 'A14', '상행', '홍대입구 → 인천공항2터미널행'),
    ];

    for (final (line, from, to, label, desc) in rows) {
      test('$line $desc: updnLine=$label', () {
        expect(isDownBetween(from, to, line), label == '하행',
            reason: '$line $from→$to 는 API 라벨 "$label" 과 같은 방향이어야 한다');
      });
    }

    test('가상 급행 접미사(`9E`)도 같은 규칙', () {
      expect(isDownBetween('920', '901', '9E'), isTrue);
      expect(isDownBetween('920', '938', '9E'), isFalse);
    });

    test('종점 간 전체 구간 — 우이신설 W13→W01 하행, W01→W13 상행', () {
      expect(isDownBetween('W13', 'W01', '우이신설'), isTrue);
      expect(isDownBetween('W01', 'W13', '우이신설'), isFalse);
    });

    test('같은 역(W08→W08) = false', () {
      expect(isDownBetween('W08', 'W08', '우이신설'), isFalse);
    });
  });

  group('반전하지 않는 노선 — 일반 규칙(ID 증가 = 하행) 유지', () {
    // ⚠ 이 고정은 탐지기가 아니다 — API 가 반대 라벨을 주기 시작해도 이 테스트는
    // 통과한다(현재 동작을 잠글 뿐이다). 의정부·김포골드는 getTrainSch 기준으로는 반전
    // 저장돼 있어 "라벨 ≠ 앱 규칙" 일 가능성이 있으므로, API 가 열리면 같은 버그가 된다.
    // 주기적으로 `dart run tool/check_api_direction_labels.dart` 를 돌릴 것
    // (전 노선 라벨 대조 · 수동 실행 도구 · 네트워크/API 키 필요라 flutter test 에는 없다).
    test('의정부경전철: API 미제공 노선이라 반전 대상 아님', () {
      expect(isDownBetween('U01', 'U02', '의정부'), isTrue);
      expect(isDownBetween('U02', 'U01', '의정부'), isFalse);
    });

    // ⚠ 위 의정부 케이스와 같다 — 이 고정은 탐지기가 아니다. API 가 반대 라벨을 주기
    // 시작해도 이 테스트는 통과한다. 주기적으로
    // `dart run tool/check_api_direction_labels.dart` 를 돌릴 것.
    test('김포골드라인: API 미제공 노선이라 반전 대상 아님', () {
      expect(isDownBetween('P01', 'P02', '김포골드'), isTrue);
      expect(isDownBetween('P02', 'P01', '김포골드'), isFalse);
    });

    test('일반 노선 대조군(1호선): ID 증가 = 하행', () {
      expect(isDownBetween('133', '134', '1'), isTrue);
      expect(isDownBetween('134', '133', '1'), isFalse);
    });
  });

  group('지도 게이트 — 우이신설 findPathOnLine(현재역→출발역, isDown)', () {
    late List<Station> stations;
    late List<Connection> connections;

    setUpAll(() {
      stations = (jsonDecode(File('assets/json/stations.json').readAsStringSync())
              as List)
          .map((e) => Station.fromJson(e as Map<String, dynamic>))
          .toList();
      connections =
          (jsonDecode(File('assets/json/connections.json').readAsStringSync())
                  as List)
              .map((e) => Connection.fromJson(e as Map<String, dynamic>))
              .toList();
    });

    PathWithDurations? gate(String current, String departure, bool isDown) =>
        findPathOnLine(
          fromStationName: current,
          toStationName: departure,
          lineId: '우이신설',
          stations: stations,
          connections: connections,
          isDown: isDown,
        );

    test('솔샘 → 가오리 방면 이용자(북한산우이행, 하행): 상류 화계에서 오는 열차가 그려진다', () {
      // 이용자: 가오리(W04) 승차, 북한산우이행. API 라벨 = 하행.
      final routeIsDown = isDownBetween('W04', 'W03', '우이신설');
      expect(routeIsDown, isTrue, reason: '북한산우이 방면 = API 하행');
      // 열차는 화계(W05, 가오리의 상류)에서 온다.
      expect(gate('화계', '가오리', routeIsDown), isNotNull);
      // 반대편(솔밭공원, 가오리 하류)에서는 올 수 없다.
      expect(gate('솔밭공원', '가오리', routeIsDown), isNull);
    });

    test('신설동행 이용자(상행): 상류 솔밭공원에서 오는 열차가 그려진다', () {
      final routeIsDown = isDownBetween('W04', 'W05', '우이신설');
      expect(routeIsDown, isFalse, reason: '신설동 방면 = API 상행');
      expect(gate('솔밭공원', '가오리', routeIsDown), isNotNull);
      expect(gate('화계', '가오리', routeIsDown), isNull);
    });

    test('전 역 대조 — 라벨 방향 게이트 통과 시 상류 역은 반드시 경로가 있다', () {
      // 우이신설 13역 × 양 방향. 이용자 방향의 상류에 있는 모든 역에서 경로가 나와야 한다.
      final ids = [for (var i = 1; i <= 13; i++) 'W${i.toString().padLeft(2, '0')}'];
      final names = {
        for (final s in stations.where((s) => s.lineId == '우이신설')) s.id: s.name
      };
      var checked = 0;
      for (var dep = 0; dep < ids.length; dep++) {
        for (var cur = 0; cur < ids.length; cur++) {
          if (cur == dep) continue;
          // cur 이 dep 보다 ID 가 작으면 열차는 ID 증가 방향(신설동행 = 상행)으로 온다.
          final trainHeadsInc = cur < dep;
          final apiIsDown = !trainHeadsInc; // 상행 = 신설동행 = ID 증가
          final neighbor = trainHeadsInc ? dep + 1 : dep - 1;
          if (neighbor < 0 || neighbor >= ids.length) continue;
          final routeIsDown = isDownBetween(ids[dep], ids[neighbor], '우이신설');
          expect(routeIsDown, apiIsDown,
              reason: '${names[ids[dep]]} 승차 ${trainHeadsInc ? "신설동" : "북한산우이"}행 방향 판정');
          expect(gate(names[ids[cur]]!, names[ids[dep]]!, routeIsDown), isNotNull,
              reason: '${names[ids[cur]]} → ${names[ids[dep]]} (isDown=$routeIsDown)');
          checked++;
        }
      }
      expect(checked, greaterThan(100));
    });
  });

  group('2호선 성수지선 — 라벨만 반전(규칙은 유지)', () {
    // 성수(211) ─ 용답(244) ─ 신답(245) ─ 용두(246) ─ 신설동(250) 4역 셔틀.
    //
    // 2026-10-28 15:54 실측(`tool/check_api_direction_labels.dart --verbose`):
    //   내선 | 현재=용두   → 조회=신설동 | 행선=신설동
    //   외선 | 현재=신설동 → 조회=용두   | 행선=성수지선
    // 앱 규칙은 ID 증가(신설동 방향) = 하행이라 양방향 모두 라벨과 반대다.
    //
    // 고치는 방법으로 **규칙을 뒤집지 않았다**(사용자 결정 2026-10-28). 시간표
    // (`INOUT_TAG`)는 앱 규칙과 이미 맞아 있어(커밋 75b9e03) 규칙을 뒤집으면
    // 시간표가 다시 반대 방향을 읽는다. 그래서 라벨 해석만 뒤집는다.

    test('규칙(isDownBetween)은 그대로다 — 시간표 인덱스를 흔들지 않는다', () {
      // ID 증가 = 하행. 이 값이 바뀌면 `line_schedules.json` 의 t[0]/t[1] 이
      // 어긋나고 75b9e03 이 고친 역방향 조회 버그가 되살아난다.
      expect(isDownBetween('246', '250', '2'), isTrue, reason: '용두→신설동 = 하행');
      expect(isDownBetween('250', '246', '2'), isFalse, reason: '신설동→용두 = 상행');
      expect(isDownBetween('211', '244', '2'), isTrue, reason: '성수→용답 = 하행');
    });

    test('지선 구간은 라벨 반전 대상이다', () {
      expect(isApiLabelReversedBetween('246', '250', '2'), isTrue);
      expect(isApiLabelReversedBetween('250', '246', '2'), isTrue);
      expect(isApiLabelReversedBetween('211', '244', '2'), isTrue,
          reason: '분기역 성수에서 지선으로 들어가는 쌍도 포함');
      expect(isApiLabelReversedBetween('244', '245', '2'), isTrue);
    });

    test('본선·신정지선은 반전 대상이 아니다', () {
      expect(isApiLabelReversedBetween('201', '202', '2'), isFalse, reason: '본선');
      expect(isApiLabelReversedBetween('211', '212', '2'), isFalse,
          reason: '성수는 본선 순환에도 쓰인다 — 본선 쪽 쌍은 오염되면 안 된다');
      expect(isApiLabelReversedBetween('234', '247', '2'), isFalse, reason: '신정지선');
      expect(isApiLabelReversedBetween('249', '251', '2'), isFalse, reason: '까치산');
    });

    test('다른 노선은 전부 false — 이 함수는 2호선 지선 전용이다', () {
      for (final l in ['1', '3', '4', '5', '9', '공항철도', '우이신설', '경의중앙']) {
        expect(isApiLabelReversedBetween('100', '101', l), isFalse, reason: l);
      }
    });

    test('가상 급행 노선 ID(2E)도 base 로 정규화된다', () {
      expect(isApiLabelReversedBetween('246', '250', '2E'), isTrue);
    });

    test('숫자가 아닌 ID 는 false (안전한 기본값)', () {
      expect(isApiLabelReversedBetween('W01', 'W02', '2'), isFalse);
    });

    test('isApiLabelReversedOnRoute 는 첫 인접 쌍만 본다', () {
      // isDownDirection(segment) 이 stations[0], stations[1] 로 방향을 정하므로
      // 같은 쌍을 봐야 짝이 맞는다.
      expect(isApiLabelReversedOnRoute('2', ['246', '250']), isTrue);
      expect(isApiLabelReversedOnRoute('2', ['201', '202', '244']), isFalse,
          reason: '뒤쪽에 지선 ID 가 있어도 첫 쌍이 본선이면 본선이다');
      expect(isApiLabelReversedOnRoute('2', ['246']), isFalse, reason: '역 1개');
      expect(isApiLabelReversedOnRoute('2', const []), isFalse, reason: '빈 목록');
    });

    test('라벨 반전을 적용하면 실측 라벨과 앱 방향이 맞는다', () {
      // 지도·출발시각 게이트가 하는 계산 그대로.
      bool gateAccepts(String label, String fromId, String toId) {
        var labelDown = label == '하행' || label == '외선';
        if (isApiLabelReversedOnRoute('2', [fromId, toId])) labelDown = !labelDown;
        return labelDown == isDownBetween(fromId, toId, '2');
      }

      // 용두 → 신설동 을 타는 사용자: API 가 "내선" 으로 보고한 열차가 맞는 열차.
      expect(gateAccepts('내선', '246', '250'), isTrue);
      expect(gateAccepts('외선', '246', '250'), isFalse, reason: '반대 방향은 걸러야 한다');
      // 신설동 → 용두 를 타는 사용자: "외선" 이 맞는 열차.
      expect(gateAccepts('외선', '250', '246'), isTrue);
      expect(gateAccepts('내선', '250', '246'), isFalse);
      // 본선은 반전 없이 종전대로.
      expect(gateAccepts('내선', '201', '202'), isTrue, reason: '본선 ID 증가 = 내선/상행');
    });
  });
}
