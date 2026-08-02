// 장항선(천안~신창) 역 순서 회귀 가드.
//
// 2026-08 까지 `stations.json` 이 아산 다음을 배방으로 배정해(196=배방·197=온양온천·
// 198=탕정) 인접 관계가 **아산-배방-온양온천-탕정-신창** 으로 잘못 잡혀 있었다.
// 증상:
//   1) 경로 탐색이 실재하지 않는 인접을 따라가 아산~신창 소요가 1200s 로 계산됨
//      (실측 960s).
//   2) 탕정→신창이 인접으로 잡혀 `travelTimeSeconds=60` 이라는 값이 굳었다.
//      실측은 780s 인데 `tool/compute_travel_times.dart` 의 600s 상한(종착/회차
//      제외용)에 걸려 **자동 교정조차 되지 않는** 상태였다.
//
// 올바른 순서의 근거 4중 일치:
//   ① 공식 역번호 `stnNo` — 아산 P172, 탕정 P173, 배방 P174, 온양온천 P176,
//      신창 P177 (data.go.kr getTrainSch 응답).
//   ② 실제 편성 시각 순서 — K1904 상행: 신창 06:09 → 온양온천 06:14 →
//      배방 06:18 → 탕정 06:22 → 아산 06:25.
//   ③ `line_schedules.json` 상행 첫차(분) — 신창 300 → 온양온천 305 →
//      배방 309 → 탕정 313 → 아산 316.
//   ④ SVG 좌표 `svgX` — 아산 1908 → 탕정 1960 → 배방 2024 → 온양온천 2088 →
//      신창 2152 (지도는 처음부터 올바른 순서였다).
//
// 앱 규칙 "ID 증가 = 하행"(`lib/core/utils/line_direction.dart`)에 따라 역 ID 는
// 노선 진행 순서와 단조여야 하므로, 이 테스트는 ID·좌표·소요시간 세 축을 함께 고정한다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 천안(하행 방향) → 신창 순서의 `(stationId, 역명)`.
const _janghangOrder = <(String, String)>[
  ('192', '천안'),
  ('193', '봉명'),
  ('194', '쌍용'),
  ('195', '아산'),
  ('196', '탕정'),
  ('197', '배방'),
  ('198', '온양온천'),
  ('199', '신창'),
];

/// 실측 인접 구간 소요시간(초) — `data/timetables/1_*.json` 출발시각 차 중앙값.
const _segmentSeconds = <String, int>{
  '195|196': 180, // 아산→탕정
  '196|197': 210, // 탕정→배방
  '197|198': 270, // 배방→온양온천
  '198|199': 300, // 온양온천→신창
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Station> byId;
  late List<String> line1FileOrder;
  late List<String> line1LineIds;
  late Map<String, Connection> line1Local;

  setUpAll(() async {
    final stations = await LocalDataSource().loadStations();
    byId = {
      for (final s in stations)
        if (s.lineId == '1') s.id: s,
    };
    line1FileOrder = [
      for (final s in stations)
        if (s.lineId == '1') s.id,
    ];
    line1LineIds = (await LocalDataSource().loadLines())
        .firstWhere((l) => l.id == '1')
        .stationIds;

    final raw = await rootBundle.loadString('assets/json/connections.json');
    line1Local = {};
    for (final json in jsonDecode(raw) as List<dynamic>) {
      final c = Connection.fromJson(json as Map<String, dynamic>);
      if (c.lineId != '1' || c.isTransfer) continue;
      line1Local['${c.fromStationId}|${c.toStationId}'] = c;
      line1Local['${c.toStationId}|${c.fromStationId}'] = c;
    }
  });

  group('장항선 역 순서', () {
    test('역 ID 배정이 실제 순서와 일치한다', () {
      for (final (id, name) in _janghangOrder) {
        expect(
          byId[id]?.name,
          name,
          reason: 'id $id 는 $name 이어야 한다. 특히 아산(195) 다음은 탕정(196)이며 '
              '배방(197)이 아니다 — tool/generate_station_data.dart 주석의 근거 참조.',
        );
      }
    });

    test('ID 증가 방향과 지도 좌표(svgX) 증가 방향이 일치한다', () {
      // "ID 증가 = 하행" 규칙이 성립해야 방향 판별이 올바르게 동작한다.
      var prev = -1.0;
      for (final (id, name) in _janghangOrder) {
        final x = byId[id]!.svgX;
        expect(
          x,
          greaterThan(prev),
          reason: '$name($id) 의 svgX($x) 가 직전 역보다 작다 — ID 순서와 '
              '지도 배치가 어긋난다',
        );
        prev = x;
      }
    });

    test('stations.json 배열 순서도 물리 순서와 같다', () {
      // ⚠ 이 축이 따로 필요한 이유: 이 버그의 수정 방식이 "이름·좌표는 그대로 두고
      // `id` 만 제자리 교체"였기 때문이다(86b313e, 수인선 bab3788 도 같다). 그러면
      // 위의 'ID 배정' 축은 통과하지만 **배열 위치는 뒤집힌 채로 남는다.**
      // 역 선택 화면(`station_picker_screen.dart`)은 검색어가 없을 때
      // `stations.json` 파일 순서를 그대로 그리므로(정렬하지 않는다) 여기가
      // 어긋나면 목록에서 배방이 탕정보다 먼저 나온다.
      final expected = [for (final (id, _) in _janghangOrder) id];
      final start = line1FileOrder.indexOf('192');
      expect(
        line1FileOrder.sublist(start, start + expected.length),
        expected,
      );
    });

    test('lines.json 역 순서도 물리 순서와 같다', () {
      final expected = [for (final (id, _) in _janghangOrder) id];
      final start = line1LineIds.indexOf('192');
      expect(
        line1LineIds.sublist(start, start + expected.length),
        expected,
      );
    });

    test('실재하지 않는 인접이 없다 (역명 기준)', () {
      // ⚠ ID 쌍으로 검사하면 의미가 없다 — connections.json 은 언제나 연속 ID
      // 쌍만 담으므로 `195|197` 같은 키는 오배정 상태에서도 존재하지 않는다.
      // 이 버그의 본질은 "그 ID 가 어느 역인가"였으므로 **역명으로** 확인한다.
      // 종전 오배정에서는 `195|196` 이 아산↔배방(가짜)이었다.
      String nameOf(String id) => byId[id]!.name;
      final adjacentNames = <String>{};
      for (final key in line1Local.keys) {
        final parts = key.split('|');
        if (!byId.containsKey(parts[0]) || !byId.containsKey(parts[1])) continue;
        adjacentNames.add('${nameOf(parts[0])}↔${nameOf(parts[1])}');
      }

      // 실제로 인접해야 하는 쌍
      for (var i = 0; i < _janghangOrder.length - 1; i++) {
        final a = _janghangOrder[i].$2;
        final b = _janghangOrder[i + 1].$2;
        expect(
          adjacentNames,
          contains('$a↔$b'),
          reason: '$a→$b 연결이 없다',
        );
      }
      // 종전 오배정(아산-배방-온양온천-탕정-신창)만 만들어냈던 가짜 인접.
      // 배방↔온양온천 은 양쪽 순서에 모두 존재하는 실제 인접이라 제외한다.
      for (final fake in ['아산↔배방', '온양온천↔탕정', '탕정↔신창']) {
        expect(
          adjacentNames,
          isNot(contains(fake)),
          reason: '$fake 는 실재하지 않는 인접이다 (종전 오배정의 흔적)',
        );
      }
    });

    test('구간 소요시간이 실측값이고, 아산~신창 총합은 960초다', () {
      var total = 0;
      _segmentSeconds.forEach((key, expected) {
        final c = line1Local[key];
        expect(c, isNotNull, reason: '$key 연결이 없다');
        expect(
          c!.travelTimeSeconds,
          expected,
          reason: '$key 소요시간이 실측과 다르다. connections.json 을 손으로 고쳤다면 '
              'dart run tool/compute_travel_times.dart --line=1 로 재산출할 것.',
        );
        total += c.travelTimeSeconds;
      });
      expect(total, 960, reason: '종전 오배정 상태의 합은 1200초였다');
    });
  });
}
