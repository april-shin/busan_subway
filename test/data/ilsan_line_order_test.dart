// 3호선 일산선 원흥 결선 회귀 가드.
//
// 2026-08-01 까지 connections.json 의 일산선 북단이 실제와 달랐다:
//   앱   원당(308) - 삼송(309) - 원흥(344) - 지축(310)
//   실제 원당(308) - 원흥(344) - 삼송(309) - 지축(310)
// 원흥은 2014년 원당~삼송 사이에 개통해 번호만 344 로 뒤에 붙은 역인데,
// 결선이 번호 순서를 따라가면서 삼송과 원흥이 뒤바뀌었다.
//
// 근거: getTrainSch(`data/timetables/3_*.json`) 의 공식 역 순번 `stnNo` —
// 원당 316 / 원흥 317 / 삼송 318 / 지축 319. 소요시간도 같은 캐시의
// `다음역 trainArvlTm − 현재역 trainDptreTm`(dwell 제외 = 앱 규약) 실측이며
// 평일 상·하행 n=120~132 에서 편차가 사실상 0이다.
//
// 증상:
//   1) 원당↔지축 구간 소요시간이 810초로 실제(420초)의 두 배 가까이 부풀었다.
//      뒤바뀐 인접쌍(원당-삼송 330s, 원흥-지축 330s)이 사실은 한 역을 건너뛴
//      값이었기 때문이다.
//   2) 지도 경로 하이라이트가 결선을 따라 그려지는데, SVG 좌표는 올바른 순서
//      (원당 496 → 원흥 536 → 삼송 576 → 지축 617.6)라서 이 구간만 지그재그로
//      꺾여 그려졌다.
//   3) 방향 판정 rank(`_stationRanks['3']`)도 뒤바뀐 결선에 맞춰져 있었다.
//
// SVG 는 이미 올바른 순서로 그려져 있어 수정 대상이 아니었다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 일산선 북단 물리 순서 — 원당에서 지축 방향(= 상행, 대화 반대).
const _order = [
  ('308', '원당'),
  ('344', '원흥'),
  ('309', '삼송'),
  ('310', '지축'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;
  late List<String> line3Ids;

  setUpAll(() async {
    stations = (jsonDecode(
                await rootBundle.loadString('assets/json/stations.json'))
            as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    connections = (jsonDecode(
                await rootBundle.loadString('assets/json/connections.json'))
            as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
    final lines =
        (jsonDecode(await rootBundle.loadString('assets/json/lines.json'))
            as List).cast<Map<String, dynamic>>();
    line3Ids = (lines.firstWhere((l) => l['id'] == '3')['stationIds'] as List)
        .cast<String>();
  });

  Connection? edge(String a, String b) => connections.cast<Connection?>().firstWhere(
        (c) =>
            c!.lineId == '3' &&
            !c.isTransfer &&
            ((c.fromStationId == a && c.toStationId == b) ||
                (c.fromStationId == b && c.toStationId == a)),
        orElse: () => null,
      );

  test('일산선 북단이 원당 - 원흥 - 삼송 - 지축 순으로 이어진다', () {
    final byId = {for (final s in stations) s.id: s};
    for (final (id, name) in _order) {
      expect(byId[id]?.name, name, reason: '$id 는 $name 이어야 한다');
    }

    // 뒤바뀐 옛 결선이 남아 있으면 안 된다.
    expect(edge('308', '309'), isNull, reason: '원당↔삼송은 인접이 아니다');
    expect(edge('344', '310'), isNull, reason: '원흥↔지축은 인접이 아니다');

    // getTrainSch 실측 (평일 상·하행, dwell 제외).
    expect(edge('308', '344')?.travelTimeSeconds, 150, reason: '원당↔원흥');
    expect(edge('344', '309')?.travelTimeSeconds, 120, reason: '원흥↔삼송');
    expect(edge('309', '310')?.travelTimeSeconds, 150, reason: '삼송↔지축');

    // 구간 합 — 뒤바뀐 결선에서는 810초로 부풀어 있었다.
    expect(
      [
        edge('308', '344')!.travelTimeSeconds,
        edge('344', '309')!.travelTimeSeconds,
        edge('309', '310')!.travelTimeSeconds,
      ].reduce((a, b) => a + b),
      420,
      reason: '원당→지축 주행 합계는 7분이다',
    );
  });

  test('lines.json 역 순서도 물리 순서와 같다', () {
    final start = line3Ids.indexOf('307');
    expect(
      line3Ids.sublist(start, start + 5),
      ['307', '308', '344', '309', '310'],
    );
  });

  test('stations.json 배열 순서도 물리 순서와 같다', () {
    // 역 선택 화면(`station_picker_screen.dart`)은 검색어가 없을 때
    // `stations.json` 파일 순서를 그대로 그린다(정렬하지 않는다). 여기가
    // 어긋나면 목록에서 삼송이 원흥보다 먼저 나온다.
    final line3 = [for (final s in stations) if (s.lineId == '3') s.id];
    final start = line3.indexOf('307');
    expect(
      line3.sublist(start, start + 5),
      ['307', '308', '344', '309', '310'],
    );
  });

  test('위경도도 결선 순서와 정합한다 (삼송 경도 회귀 가드)', () {
    // 종전 삼송 경도가 126.8561 로 원흥(126.8730)보다 서쪽이라 결선 순서와
    // 모순됐다. 서울 열린데이터 `subwayStationMaster`(서울교통공사 역사마스터)
    // 공식값 기준으로 정정: 원당 126.843041 / 원흥 126.872642 /
    // 삼송 126.895558 / 지축 126.913970 → 물리 순서대로 단조 증가.
    final byId = {for (final s in stations) s.id: s};
    final lngs = [for (final (id, _) in _order) byId[id]!.longitude];
    for (var i = 0; i + 1 < lngs.length; i++) {
      expect(lngs[i], lessThan(lngs[i + 1]),
          reason: '결선 순서(원당→지축)대로 경도가 동쪽으로 증가해야 한다');
    }
    // 공식값과 100m 이내(경도 0.0012°≈100m).
    expect((byId['309']!.longitude - 126.895558).abs(), lessThan(0.0012));
    expect((byId['309']!.latitude - 37.653083).abs(), lessThan(0.001));
  });

  test('SVG 좌표가 결선 순서대로 단조 증가한다', () {
    // 지도 경로 하이라이트는 결선을 따라 그려진다. 결선 순서와 좌표 순서가
    // 어긋나면 이 구간만 지그재그로 꺾인다(회귀 당시 증상).
    // 좌표 절대값은 SVG 재추출 시 바뀔 수 있으므로 단조성만 고정한다.
    final byId = {for (final s in stations) s.id: s};
    final xs = [for (final (id, _) in _order) byId[id]!.svgX];
    for (var i = 0; i + 1 < xs.length; i++) {
      expect(xs[i], lessThan(xs[i + 1]),
          reason: '결선 순서대로 x 좌표가 단조 증가해야 꺾이지 않는다');
    }
    // 같은 수평선 위에 놓여 있다.
    expect({for (final (id, _) in _order) byId[id]!.svgY}.length, 1);
  });

  test('원흥 rank 보정으로 대화 방면이 상행으로 판정된다', () {
    // 원당(308) → 원흥(344) → 삼송(309) → 지축(310) 은 하행(오금 방면).
    for (var i = 0; i + 1 < _order.length; i++) {
      final a = _order[i].$1;
      final b = _order[i + 1].$1;
      expect(isDownBetween(a, b, '3'), isTrue,
          reason: '$a → $b 는 하행(오금 방면)');
      expect(isDownBetween(b, a, '3'), isFalse,
          reason: '$b → $a 는 상행(대화 방면)');
    }
    // 회귀 당시 지축 → 대화 방면 첫 홉이 하행으로 뒤집혔다.
    expect(isDownBetween('310', '309', '3'), isFalse);
  });
}
