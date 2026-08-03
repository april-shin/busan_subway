// 1호선 경부선 구로 이남 역 순서 회귀 가드.
//
// `stations.json` 이 구로(142) 다음을 금천구청으로, 석수보다 관악을 앞으로
// 배정해 결선이 지그재그였다:
//   앱   구로(142) - 금천구청(166) - 독산(167) - 관악(168) - 석수(169) - 안양(170)
//   실제 구로(142) - 독산(166)   - 금천구청(167) - 석수(168) - 관악(169) - 안양(170)
// 즉 독산/금천구청 한 쌍과 석수/관악 한 쌍이 각각 뒤바뀐 상태였다.
//
// 정정 근거 4중 일치:
//   ① 공식 역번호 stnNo (`data/timetables/1_*.json`, getTrainSch) —
//      구로 141 · 독산 P143 · 금천구청 P144 · 석수 P145 · 관악 P146 · 안양 P147.
//      (P142 는 가산디지털단지. 1호선 노드가 없어 비어 있다 — 아래 별건 참조)
//   ② 편성 시각 — 평일 하행 K403: 구로 05:56 → 독산 06:03 → 금천구청 06:05:30
//      → 석수 06:08:30 → 관악 06:11 → 안양 06:14. 전 편성이 같은 순서다.
//   ③ SVG 좌표 svgY — 896 → 1072 → 1128 → 1128 → 1176 → 1240 (지도는 원래 옳았다).
//   ④ 공식 위경도 (서울 열린데이터광장 `subwayStationMaster`, LINE_NUM=경부선) —
//      37.503039 → 37.466613 → 37.455626 → 37.435047 → 37.419232 → 37.401592.
//      석수·관악은 앱 값이 1.6km·4.8km 어긋나 순서와 모순됐으므로 공식값으로
//      정정했다. 나머지는 200m 이내라 그대로 뒀다(813bd1b 삼송과 같은 취지).
//
// 증상: 뒤바뀐 인접쌍이 사실은 역을 건너뛴 값이라 소요시간이 부풀어 있었다.
//   구로→안양 1680s → 실측 930s (12.5분 과다). 경부선 **본선**이라 서울↔수원·
//   천안·아산 전 경로에 걸렸다.
//
// ⚠ 이 파일은 `id`↔`이름` 짝을 고정한다. 86d/장항선·수인선 가드와 같은 구조이며,
//   역 ID 하드코딩 대신 **역명으로 조회**한다 — 이 버그의 수정 자체가 ID 재배정
//   이었으므로 ID 를 박아 두면 다음 재배정에 조용히 무의미해진다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/local/timetable_data_source.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';
import 'package:seoul_subway/domain/entities/line_schedule.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 구로 이남 경부선 본선 물리 순서.
const _physicalOrder = <String>[
  '구로',
  '가산디지털단지',
  '독산',
  '금천구청',
  '석수',
  '관악',
  '안양',
];

/// [_physicalOrder] 에서 구로를 뺀 "경부선 남쪽 블록".
///
/// `stations.json`·`lines.json` 은 구로 다음에 **경인선**(구일~인천)을 먼저
/// 나열하고 그 뒤에 이 블록을 둔다. 배열 순서 검사는 이 블록만 연속으로 본다.
const _southBlock = <String>[
  '가산디지털단지',
  '독산',
  '금천구청',
  '석수',
  '관악',
  '안양',
];

/// 공식 `subwayStationMaster` 위도 (LINE_NUM=경부선).
///
/// 가산디지털단지는 경부선 37.481581 / 7호선 37.480338 두 레코드가 있다(승강장이
/// 갈린다). 앱은 환승 쌍의 좌표를 공유하는 관례라 7호선 값(37.4821)을 쓰고,
/// 경부선 공식값과 약 58m 차이라 아래 500m 허용범위에 들어온다.
const _officialLat = <String, double>{
  '구로': 37.503039,
  '가산디지털단지': 37.481581,
  '독산': 37.466613,
  '금천구청': 37.455626,
  '석수': 37.435047,
  '관악': 37.419232,
  '안양': 37.401592,
};

/// 인접 구간 실측 소요시간 — `다음역 trainArvlTm − 현재역 trainDptreTm`(dwell 제외).
///
/// 평일 상·하행 양방향 수집, 편차 사실상 0.
/// 출처: `data/timetables/1_{역명}_{상행,하행}.json` (getTrainSch 캐시).
const _measuredSeconds = <String, int>{
  '구로|가산디지털단지': 240,
  '가산디지털단지|독산': 120,
  '독산|금천구청': 120,
  '금천구청|석수': 150,
  '석수|관악': 120,
  '관악|안양': 150,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Station> line1ByName;
  late List<Connection> line1Conns;

  /// `stations.json` 파일 순서대로의 1호선 역 ID.
  late List<String> line1FileOrder;

  /// `lines.json` 의 1호선 `stationIds` 순서.
  late List<String> line1LineIds;

  /// 1호선 급행 skip edge.
  late List<ExpressSkipEdge> line1Express;

  /// 1호선 시간표.
  late LineSchedule line1Schedule;

  setUpAll(() async {
    final stations = await LocalDataSource().loadStations();
    line1Express = (await LocalDataSource().loadExpressSkipEdges())
        .where((e) => e.lineId == '1')
        .toList();
    line1Schedule = (await TimetableDataSource().loadSchedules())['1']!;
    line1ByName = {
      for (final s in stations.where((s) => s.lineId == '1')) s.name: s,
    };
    line1FileOrder = [
      for (final s in stations.where((s) => s.lineId == '1')) s.id,
    ];

    final raw = await rootBundle.loadString('assets/json/connections.json');
    line1Conns = (jsonDecode(raw) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .where((c) => c.lineId == '1' && !c.isTransfer)
        .toList();

    final linesRaw = await rootBundle.loadString('assets/json/lines.json');
    final line1 = (jsonDecode(linesRaw) as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((l) => l['id'] == '1');
    line1LineIds = (line1['stationIds'] as List).cast<String>();
  });

  String idOf(String name) {
    final s = line1ByName[name];
    expect(s, isNotNull, reason: '1호선 $name 레코드가 없다');
    return s!.id;
  }

  Connection? edgeBetween(String a, String b) {
    for (final c in line1Conns) {
      if (c.fromStationId == a && c.toStationId == b) return c;
      if (c.fromStationId == b && c.toStationId == a) return c;
    }
    return null;
  }

  group('경부선 구로 이남 — ID 배정', () {
    test('독산~안양 ID 가 물리 순서대로 증가한다', () {
      // 1호선 방향 판정은 "ID 증가 = 하행" 규칙을 쓰므로 물리 순서와 어긋나면
      // 상·하행이 반전된다.
      //
      // ⚠ 가산디지털단지(1425)는 이 규칙을 **의도적으로 위반**한다 — 142~165 가
      //   경인선·경원선 북단에 소진돼 구로(142)와 독산(166) 사이에 정수 번호가
      //   없어 "142.5" 를 뜻하는 1425 를 부여했다(금정 1715 와 같은 관례).
      //   그래서 이 축은 독산~안양 만 보고, 가산의 방향 정합성은 아래
      //   '방향 판별' 그룹이 rank 보정까지 포함해 검사한다.
      const intContiguous = ['독산', '금천구청', '석수', '관악', '안양'];
      final nums = intContiguous.map((n) => int.parse(idOf(n))).toList();
      for (var i = 0; i < nums.length - 1; i++) {
        expect(
          nums[i] < nums[i + 1],
          isTrue,
          reason: '${intContiguous[i]}(${nums[i]}) → '
              '${intContiguous[i + 1]}(${nums[i + 1]}) 가 ID 역행이다. '
              'stations.json 의 id-이름 짝이 뒤바뀌었는지 확인할 것.',
        );
      }
      // 구로 → 가산은 정수 규칙으로도 증가한다(142 < 1425).
      expect(int.parse(idOf('구로')), lessThan(int.parse(idOf('가산디지털단지'))));
    });

    test('가산디지털단지·독산·금천구청·석수·관악의 ID 가 고정된다', () {
      // 회귀 시 되돌아갈 정확한 값을 명시적으로 막는다.
      expect(idOf('가산디지털단지'), '1425',
          reason: '"142.5" 를 뜻하는 번호. 정수 공백이 없어 금정 1715 와 같은 관례를 썼다');
      expect(idOf('독산'), '166', reason: '종전 오배정: 독산=167');
      expect(idOf('금천구청'), '167', reason: '종전 오배정: 금천구청=166');
      expect(idOf('석수'), '168', reason: '종전 오배정: 석수=169');
      expect(idOf('관악'), '169', reason: '종전 오배정: 관악=168');
    });

    test('stations.json 배열 순서도 물리 순서와 같다', () {
      // ⚠ 이 축이 따로 필요한 이유: 이 버그의 수정 방식이 "이름·좌표는 그대로 두고
      // `id` 만 제자리 교체"였기 때문이다(장항선 86b313e·수인선 bab3788 도 같고,
      // 그 잔여분은 1c53ced 에서 따로 정렬해야 했다). 그러면 위의 'ID 배정' 축은
      // 통과하지만 **배열 위치는 뒤집힌 채로 남는다.**
      // 역 선택 화면(`station_picker_screen.dart`)은 검색어가 없을 때
      // `stations.json` 파일 순서를 정렬 없이 그대로 그리므로, 여기가 어긋나면
      // 목록에서 금천구청이 독산보다·관악이 석수보다 먼저 나온다.
      // ⚠ 구로(142)는 이 블록에 **연속으로 붙어 있지 않다.** 파일은 경인선
      //   (구일 143 ~ 인천 162)을 먼저 나열하고 그 뒤에 경부선 남쪽 블록
      //   (166~199 + 광명)을 둔다. 그래서 구로를 뺀 _southBlock 만 검사한다.
      final expected = _southBlock.map(idOf).toList();
      final start = line1FileOrder.indexOf(expected.first);
      expect(start, greaterThanOrEqualTo(0), reason: '독산이 목록에 없다');
      expect(
        line1FileOrder.sublist(start, start + expected.length),
        expected,
        reason: 'stations.json 배열이 물리 순서와 어긋난다 — 역 선택 목록 순서가 틀어진다',
      );
      // 구로는 경부선 남쪽 블록보다 앞에 있어야 한다(경인선 블록을 사이에 두고).
      expect(line1FileOrder.indexOf(idOf('구로')), lessThan(start));
    });

    test('lines.json 역 순서도 물리 순서와 같다', () {
      final expected = _southBlock.map(idOf).toList();
      final start = line1LineIds.indexOf(expected.first);
      expect(start, greaterThanOrEqualTo(0));
      expect(
        line1LineIds.sublist(start, start + expected.length),
        expected,
      );
    });
  });

  group('경부선 구로 이남 — 좌표 정합성', () {
    test('svgY 가 물리 순서대로 단조 증가한다 (지도 하이라이트 지그재그 방지)', () {
      double? prev;
      for (final name in _physicalOrder) {
        final y = line1ByName[name]!.svgY;
        if (prev != null) {
          expect(y, greaterThanOrEqualTo(prev),
              reason: '$name 의 svgY 가 앞 역보다 북쪽이다 — 결선이 꺾인다');
        }
        prev = y;
      }
    });

    test('위경도가 물리 순서와 정합하고 공식값과 500m 이내다', () {
      double? prev;
      for (final name in _physicalOrder) {
        final lat = line1ByName[name]!.latitude;
        if (prev != null) {
          expect(lat, lessThan(prev),
              reason: '$name 의 위도가 앞 역보다 북쪽이다 — 물리 순서와 모순');
        }
        prev = lat;

        // 위도 1도 ≈ 111km. 0.0045도 ≈ 500m.
        expect(
          (lat - _officialLat[name]!).abs(),
          lessThan(0.0045),
          reason: '$name 위도가 공식 subwayStationMaster 값과 500m 이상 어긋난다',
        );
      }
    });
  });

  group('경부선 구로 이남 — 결선과 소요시간', () {
    test('물리 순서대로 인접 edge 가 존재한다', () {
      for (var i = 0; i < _physicalOrder.length - 1; i++) {
        final a = _physicalOrder[i], b = _physicalOrder[i + 1];
        expect(
          edgeBetween(idOf(a), idOf(b)),
          isNotNull,
          reason: '$a ↔ $b 인접 연결이 없다',
        );
      }
    });

    test('실재하지 않는 인접(건너뛴 쌍)이 없다', () {
      // 종전 결선(구로-금천구청-독산-관악-석수-안양)이 만들던 가짜 인접.
      // 금천구청↔독산·관악↔석수 는 무방향으로 보면 실제 인접과 같은 쌍이라 제외.
      const ghosts = <(String, String)>[
        ('구로', '금천구청'), // 독산·가산디지털단지를 건너뜀
        ('구로', '독산'), // 가산디지털단지를 건너뜀 (노드 신설 전의 합침 edge)
        ('독산', '관악'), // 금천구청·석수를 건너뜀
        ('석수', '안양'), // 관악을 건너뜀
      ];
      for (final (a, b) in ghosts) {
        expect(
          edgeBetween(idOf(a), idOf(b)),
          isNull,
          reason: '$a ↔ $b 는 실재하지 않는 인접이다 (종전 결선의 산물)',
        );
      }
    });

    test('인접 소요시간이 실측값이다', () {
      for (final entry in _measuredSeconds.entries) {
        final parts = entry.key.split('|');
        final edge = edgeBetween(idOf(parts[0]), idOf(parts[1]));
        expect(edge, isNotNull, reason: '${entry.key} edge 없음');
        expect(
          edge!.travelTimeSeconds,
          entry.value,
          reason: '${entry.key} 소요시간이 실측과 다르다. '
              'tool/compute_travel_times.dart 를 돌렸다면 dwell 규약 충돌이다 — '
              '이 도구는 dptre→dptre(dwell 포함)라 값이 부풀어 되돌아간다. '
              '파일 상단 경고 참조.',
        );
      }
    });

    test('구로→안양 총 주행시간이 실측 900초다', () {
      // 종전 1680초. 경부선 본선이라 서울↔수원·천안 전 경로에 걸렸다.
      //
      // 순서 교정 직후에는 930초였다(가산디지털단지 1호선 노드가 없어 구로→독산
      // 이 두 물리 구간을 390초 한 edge 로 담았다). 노드를 신설해 240+120 으로
      // 쪼개면 edge 합은 900초가 되고, 앱이 중간역이 된 가산에 dwell 30초를
      // 따로 더하므로(`lib/core/constants/dwell_time.dart`) **경로 총시간은
      // 930초로 동일하다.** 두 값이 정확히 맞물리는 것이 분할의 교차검증이다.
      var total = 0;
      for (var i = 0; i < _physicalOrder.length - 1; i++) {
        total +=
            edgeBetween(idOf(_physicalOrder[i]), idOf(_physicalOrder[i + 1]))!
                .travelTimeSeconds;
      }
      expect(total, 900);
    });
  });

  group('경부선 구로 이남 — 방향 판별과 광명 지선', () {
    test('물리 순서 진행이 전 구간 하행으로 판정된다', () {
      for (var i = 0; i < _physicalOrder.length - 1; i++) {
        final a = _physicalOrder[i], b = _physicalOrder[i + 1];
        expect(
          isDownBetween(idOf(a), idOf(b), '1'),
          isTrue,
          reason: '$a → $b 가 하행으로 판정되지 않는다',
        );
        expect(
          isDownBetween(idOf(b), idOf(a), '1'),
          isFalse,
          reason: '$b → $a 가 상행으로 판정되지 않는다',
        );
      }
    });

    test('광명 지선은 금천구청에서 분기한다', () {
      // 분기점이 독산(166)으로 밀리면 rank(167.5)와 어긋나 방향 판정이 깨진다.
      final edge = edgeBetween(idOf('금천구청'), '1A1');
      expect(edge, isNotNull, reason: '금천구청 ↔ 광명 연결이 없다');
      expect(edgeBetween(idOf('독산'), '1A1'), isNull,
          reason: '광명이 독산에서 분기하면 안 된다');
      expect(isDownBetween(idOf('금천구청'), '1A1', '1'), isTrue);
      expect(isDownBetween('1A1', idOf('금천구청'), '1'), isFalse);
    });
  });

  group('가산디지털단지 1호선 노드', () {
    test('1호선 레코드가 존재하고 7호선과 좌표를 공유한다', () {
      final one = line1ByName['가산디지털단지'];
      expect(one, isNotNull, reason: '1호선 가산디지털단지 노드가 사라졌다');
      expect(one!.isTransfer, isTrue);
      expect(one.transferLines, containsAll(<String>['1', '7']));
      // 환승 쌍은 좌표를 공유한다(금정 1715/435 선례). SVG 는 이 좌표를
      // 1호선 path(dataLine '2-1') 위에 이미 그리고 있었다.
      expect(one.svgX, 656.0);
      expect(one.svgY, 1000.0);
    });

    test('1↔7 환승 시간이 등록돼 있다', () async {
      final raw =
          await rootBundle.loadString('assets/json/transfer_times.json');
      final times = (jsonDecode(raw) as Map).cast<String, dynamic>();
      expect(times['가산디지털단지_1_7'], isNotNull,
          reason: '환승 edge 는 역명 일치로 생성되므로 두 레코드가 다 있어야 한다');
    });

    test('구로→가산→독산 으로 쪼개져 있다 (합침 edge 부재)', () {
      expect(edgeBetween(idOf('구로'), idOf('가산디지털단지')), isNotNull);
      expect(edgeBetween(idOf('가산디지털단지'), idOf('독산')), isNotNull);
      expect(edgeBetween(idOf('구로'), idOf('독산')), isNull,
          reason: '노드 신설 전의 합침 edge(390초)가 남아 있다');
    });

    test('1호선 시간표(t/tE)가 채워져 있다', () {
      // 금정(17e97af)은 서울교통공사 API 조회가 안 돼 공백으로 남겼다가 이번에
      // 함께 해소됐다. 가산은 `SearchInfoBySubwayNameService` 에 01호선
      // STATION_CD 1702 가 있어 처음부터 수집 가능하다.
      // 이 키가 없으면 가산에서 1호선 승차 시 "출발시각 선택"이 조용히 사라진다.
      expect(line1Schedule.weekday.stationDepartures?['1425'], isNotNull,
          reason: 'wd.t 에 1425 가 없다 — '
              'dart run tool/build_metro_timetable.dart --lines=1 로 채울 것');
    });

    test('급행은 가산디지털단지를 통과한다', () {
      // getTrainSch 실측: 급행 3편성(K1902·K1904·K1945)에 가산 레코드가 없다.
      // 통과역 판별의 유일한 신호가 "레코드 부재"다.
      final skipped = <String>{};
      for (final e in line1Express) {
        skipped.addAll(e.skippedStationIds);
      }
      expect(skipped, contains(idOf('가산디지털단지')));
    });
  });
}
