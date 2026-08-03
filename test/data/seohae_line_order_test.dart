// 서해선(대곡소사선 포함) 역 순서·연결 회귀 가드.
//
// 2026-08 까지 앱 서해선은 12역(H01 원종 ~ H11 원시 + H12 김포공항)뿐이었다.
// 2023년 대곡소사선(대곡~소사)·일산 연장 개통이 부분 반영된 상태로,
//   1) 김포공항 이북(일산~능곡) 5역과 엣지가 통째로 없어
//      "김포공항-능곡이 연결되지 않았어" 제보가 들어왔고,
//   2) 원종↔소새울(570s)·선부↔시우(360s)가 중간역(부천종합운동장·소사 / 초지)을
//      건너뛴 합산 엣지로 굳어 있었다.
// 수인선(`suin_line_order_test.dart`)·장항선(`janghang_line_order_test.dart`)과
// 같은 부류의 데이터 버그다.
//
// 보수 내용:
//   - H13 일산 ~ H20 초지 8역 신설 (동명 타노선 엔트리 좌표 재사용)
//   - 합산 엣지 2개 분해 + 이북 5엣지 신설 → 서해 엣지 19개(20역 체인)
//   - 번호가 물리 순서와 어긋나므로 `line_direction.dart` `_stationRanks['서해']`
//     에 H13~H20 rank 등재 (김포공항 H12=0.5 와 같은 사정)
//
// ⚠ 곡산은 서해선 열차가 정차하지 않는 통과역이다 — 서해 엔트리를 추가하지 말 것.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 일산(북단) → 원시(남단) 하행 물리 순서의 `(stationId, 역명)`.
const _seohaeOrder = <(String, String)>[
  ('H13', '일산'),
  ('H14', '풍산'),
  ('H15', '백마'),
  ('H16', '대곡'),
  ('H17', '능곡'),
  ('H12', '김포공항'),
  ('H01', '원종'),
  ('H18', '부천종합운동장'),
  ('H19', '소사'),
  ('H02', '소새울'),
  ('H03', '시흥대야'),
  ('H04', '신천'),
  ('H05', '신현'),
  ('H06', '시흥시청'),
  ('H07', '시흥능곡'),
  ('H08', '달미'),
  ('H09', '선부'),
  ('H20', '초지'),
  ('H10', '시우'),
  ('H11', '원시'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Station> byId;
  late List<String> seohaeFileOrder;
  late List<String> seohaeLineIds;
  late Map<String, Connection> seohaeLocal;
  late Map<String, int> transferTimes;

  setUpAll(() async {
    final stations = await LocalDataSource().loadStations();
    seohaeFileOrder = [
      for (final s in stations)
        if (s.lineId == '서해') s.id,
    ];
    seohaeLineIds = (await LocalDataSource().loadLines())
        .firstWhere((l) => l.id == '서해')
        .stationIds;
    byId = {
      for (final s in stations)
        if (s.lineId == '서해') s.id: s,
    };

    final raw = await rootBundle.loadString('assets/json/connections.json');
    seohaeLocal = {};
    for (final json in jsonDecode(raw) as List<dynamic>) {
      final c = Connection.fromJson(json as Map<String, dynamic>);
      if (c.lineId != '서해' || c.isTransfer) continue;
      seohaeLocal['${c.fromStationId}|${c.toStationId}'] = c;
      seohaeLocal['${c.toStationId}|${c.fromStationId}'] = c;
    }

    final rawTransfers =
        await rootBundle.loadString('assets/json/transfer_times.json');
    transferTimes = (jsonDecode(rawTransfers) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));
  });

  group('서해선 역 순서', () {
    test('20역이 모두 존재하고 ID 배정이 역명과 일치한다', () {
      expect(byId.length, _seohaeOrder.length,
          reason: '서해선은 20역이다 (곡산은 통과역이라 제외)');
      for (final (id, name) in _seohaeOrder) {
        expect(byId[id]?.name, name, reason: 'id $id 는 $name 이어야 한다');
      }
    });

    test('stations.json 배열 순서가 물리 순서(일산→원시)와 같다', () {
      // 역 선택 화면은 파일 순서를 그대로 그리므로 배열 위치도 물리 순서여야 한다
      // (`suin_line_order_test.dart` 의 같은 축 참조).
      expect(seohaeFileOrder, [for (final (id, _) in _seohaeOrder) id]);
    });

    test('lines.json 역 순서도 물리 순서와 같다', () {
      expect(seohaeLineIds, [for (final (id, _) in _seohaeOrder) id]);
    });

    test('신설 역의 좌표가 동명 타노선 엔트리와 일치한다', () async {
      // 환승역 관례: 동명 엔트리는 svg 좌표를 그대로 공유한다(김포공항 5/9/공항철도/
      // 김포골드/서해 참조). 좌표가 어긋나면 지도에서 유령 마커가 생긴다.
      final all = await LocalDataSource().loadStations();
      const sources = <String, (String, String)>{
        'H13': ('일산', '경의중앙'),
        'H14': ('풍산', '경의중앙'),
        'H15': ('백마', '경의중앙'),
        'H16': ('대곡', '3'),
        'H17': ('능곡', '경의중앙'),
        'H18': ('부천종합운동장', '7'),
        'H19': ('소사', '1'),
        'H20': ('초지', '4'),
      };
      for (final entry in sources.entries) {
        final (name, line) = entry.value;
        final src =
            all.firstWhere((s) => s.name == name && s.lineId == line);
        final neu = byId[entry.key]!;
        expect((neu.svgX, neu.svgY), (src.svgX, src.svgY),
            reason: '${entry.key} $name 좌표가 $line 엔트리와 다르다');
      }
    });

    test('인접 체인이 물리 순서 그대로 이어진다 (역명 기준)', () {
      String nameOf(String id) => byId[id]!.name;
      final adjacentNames = <String>{};
      for (final key in seohaeLocal.keys) {
        final parts = key.split('|');
        adjacentNames.add('${nameOf(parts[0])}↔${nameOf(parts[1])}');
      }

      for (var i = 0; i < _seohaeOrder.length - 1; i++) {
        final a = _seohaeOrder[i].$2;
        final b = _seohaeOrder[i + 1].$2;
        expect(adjacentNames, contains('$a↔$b'), reason: '$a→$b 연결이 없다');
      }
      // 종전 합산 엣지의 흔적 — 중간역을 건너뛰는 가짜 인접이 남으면 안 된다.
      for (final fake in ['원종↔소새울', '선부↔시우']) {
        expect(adjacentNames, isNot(contains(fake)),
            reason: '$fake 는 중간역을 건너뛴 종전 합산 엣지의 흔적이다');
      }
      // 서해 엣지 수 = 20역 체인 = 19개 (합산 잔재·중복이 있으면 어긋난다).
      expect(seohaeLocal.length, 19 * 2,
          reason: '서해 비환승 엣지는 정확히 19개여야 한다');
    });

    test('분해된 구간의 합이 기존 합산값을 보존한다', () {
      int sec(String key) => seohaeLocal[key]!.travelTimeSeconds;
      // 원종↔소새울 570s → 원종-부천종합운동장-소사-소새울
      expect(sec('H01|H18') + sec('H18|H19') + sec('H19|H02'), 570);
      // 선부↔시우 360s → 선부-초지-시우
      expect(sec('H09|H20') + sec('H20|H10'), 360);
    });

    test('김포공항 이북 신설 구간이 연결되어 있다 (제보 재현 가드)', () {
      // 사용자 제보: "김포공항-능곡이 연결되지 않았어"
      expect(seohaeLocal['H12|H17'], isNotNull,
          reason: '김포공항↔능곡 엣지가 없다');
      for (final key in ['H13|H14', 'H14|H15', 'H15|H16', 'H16|H17']) {
        expect(seohaeLocal[key], isNotNull, reason: '$key 엣지가 없다');
      }
    });

    test('방향 판정이 체인 전체에서 하행 단조다 (rank 등재 확인)', () {
      // H13~H20 은 번호가 물리 순서와 무관하므로 `_stationRanks['서해']` rank 가
      // 없으면 김포공항(H12) 등에서 하행 이웃이 둘이 되어 방향이 뒤집힌다.
      for (var i = 0; i < _seohaeOrder.length - 1; i++) {
        final a = _seohaeOrder[i].$1;
        final b = _seohaeOrder[i + 1].$1;
        expect(isDownBetween(a, b, '서해'), isTrue,
            reason: '$a → $b 는 하행(원시 방면)이어야 한다');
        expect(isDownBetween(b, a, '서해'), isFalse,
            reason: '$b → $a 는 상행(일산 방면)이어야 한다');
      }
    });

    test('신설 환승 조합이 transfer_times.json 에 있다', () {
      // 키는 lineId 오름차순 정렬 무방향 쌍 (`tool/build_transfer_times.dart`).
      const requiredKeys = [
        '일산_경의중앙_서해',
        '풍산_경의중앙_서해',
        '백마_경의중앙_서해',
        '대곡_3_서해',
        '대곡_GTX-A_서해',
        '대곡_경의중앙_서해',
        '능곡_경의중앙_서해',
        '부천종합운동장_7_서해',
        '소사_1_서해',
        '초지_4_서해',
        '초지_서해_수인분당',
      ];
      for (final key in requiredKeys) {
        expect(transferTimes[key], isNotNull, reason: '$key 누락 — '
            'dart run tool/build_transfer_times.dart 로 재생성할 것');
      }
    });
  });
}
