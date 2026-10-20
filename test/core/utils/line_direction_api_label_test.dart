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
    test('의정부경전철: API 미제공 노선이라 반전 대상 아님', () {
      expect(isDownBetween('U01', 'U02', '의정부'), isTrue);
      expect(isDownBetween('U02', 'U01', '의정부'), isFalse);
    });

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
}
