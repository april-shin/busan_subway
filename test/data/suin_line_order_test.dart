// 수인선(소래포구~연수) 역 순서 회귀 가드.
//
// 2026-08 까지 `stations.json` 이 소래포구 다음을 남동인더스파크로 배정해
// (B58=남동인더스파크·B60=인천논현) 인접 관계가
// **소래포구-남동인더스파크-호구포-인천논현-원인재-연수** 로 잘못 잡혀 있었다.
// 장항선(`janghang_line_order_test.dart`)과 같은 부류의 버그다.
// 증상:
//   1) 실재하지 않는 인접이라 소래포구→남동인더스파크 360s·인천논현→원인재 240s
//      처럼 이상하게 긴 값이 굳었다(소래포구~연수 합 1080s, 실측 600s).
//   2) `express_skip_edges.json` 에 남동인더스파크→연수(240s)·연수→남동인더스파크
//      (180s) 라는 가짜 급행 skip edge 2개가 생겼다. 추출기가 잘못된 순서 위를
//      BFS 한 산물이며, 실제로 이 역들을 통과하는 급행은 없다.
//      (원인재의 시간표 캐시가 아예 없어 급행 정차 시퀀스에서 빠진 것도 겹쳤다.
//       `data/timetables/수인분당_원인재_{상행,하행}.json` 을 받아 함께 해소했다.)
//
// 올바른 순서의 근거 4중 일치:
//   ① 공식 역번호 `stnNo` — 소래포구 K261, 인천논현 K262, 호구포 K263,
//      남동인더스파크 K264, 원인재 K265, 연수 K266 (data.go.kr getTrainSch).
//   ② 실제 편성 시각 순서 — K6802 상행: 연수 06:21 → 원인재 06:23 →
//      남동인더스파크 06:24 → 호구포 06:25 → 인천논현 06:27 → 소래포구 06:29.
//      K6801 하행은 정확히 그 역순(18:44:30 → 18:52:30).
//   ③ `line_schedules.json` 하행 첫차(분) — 소래포구 326 → 인천논현 328 →
//      호구포 330 → 남동인더스파크 332 → 원인재 334 → 연수 336.
//   ④ SVG 좌표 `svgX` — 소래포구 248 → 인천논현 320 → 호구포 384 →
//      남동인더스파크 448 → 원인재 504 (지도는 처음부터 올바른 순서였다).
//
// ⚠ 위경도는 근거에서 제외했다 — 세 역 모두 부정확해 경도 순이 실제 배열과
//   어긋난다(호구포 126.7477 > 남동인더스파크 126.7325). 장항선과 같은 사정이다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 소래포구(하행 방향) → 연수 순서의 `(stationId, 역명)`.
const _suinOrder = <(String, String)>[
  ('B52', '월곶'),
  ('B53', '소래포구'),
  ('B58', '인천논현'),
  ('B59', '호구포'),
  ('B60', '남동인더스파크'),
  ('K266', '원인재'),
  ('B61', '연수'),
];

/// 실측 인접 구간 소요시간(초) — `data/timetables/수인분당_*.json` 출발시각 차 중앙값.
/// (`tool/compute_travel_times.dart --line=수인분당` 산출)
const _segmentSeconds = <String, int>{
  'B53|B58': 120, // 소래포구→인천논현
  'B58|B59': 120, // 인천논현→호구포
  'B59|B60': 120, // 호구포→남동인더스파크
  'B60|K266': 120, // 남동인더스파크→원인재
  'K266|B61': 120, // 원인재→연수
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Station> byId;
  late Map<String, Connection> suinLocal;
  late List<ExpressSkipEdge> suinExpress;

  setUpAll(() async {
    final stations = await LocalDataSource().loadStations();
    byId = {
      for (final s in stations)
        if (s.lineId == '수인분당') s.id: s,
    };

    final raw = await rootBundle.loadString('assets/json/connections.json');
    suinLocal = {};
    for (final json in jsonDecode(raw) as List<dynamic>) {
      final c = Connection.fromJson(json as Map<String, dynamic>);
      if (c.lineId != '수인분당' || c.isTransfer) continue;
      suinLocal['${c.fromStationId}|${c.toStationId}'] = c;
      suinLocal['${c.toStationId}|${c.fromStationId}'] = c;
    }

    final rawExpress =
        await rootBundle.loadString('assets/json/express_skip_edges.json');
    final byLine = jsonDecode(rawExpress) as Map<String, dynamic>;
    suinExpress = [
      for (final e in (byLine['수인분당'] as List<dynamic>? ?? []))
        ExpressSkipEdge.fromJson(e as Map<String, dynamic>),
    ];
  });

  group('수인선 역 순서', () {
    test('역 ID 배정이 실제 순서와 일치한다', () {
      for (final (id, name) in _suinOrder) {
        expect(
          byId[id]?.name,
          name,
          reason: 'id $id 는 $name 이어야 한다. 특히 소래포구(B53) 다음은 인천논현(B58)이며 '
              '남동인더스파크(B60)가 아니다 — tool/generate_station_data.dart 주석의 근거 참조.',
        );
      }
    });

    test('ID 증가 방향과 지도 좌표(svgX) 증가 방향이 일치한다', () {
      // 소래포구~남동인더스파크 는 지도상 수평 구간이라 svgX 가 순서를 그대로
      // 반영한다. 원인재 다음 연수부터는 노선이 북쪽으로 꺾여 svgX 가 다시
      // 줄어들므로(원인재 504 → 연수 492) 검사 범위에서 제외한다.
      const horizontal = ['B52', 'B53', 'B58', 'B59', 'B60', 'K266'];
      var prev = -1.0;
      for (final id in horizontal) {
        final s = byId[id]!;
        expect(
          s.svgX,
          greaterThan(prev),
          reason: '${s.name}($id) 의 svgX(${s.svgX}) 가 직전 역보다 작다 — '
              'ID 순서와 지도 배치가 어긋난다',
        );
        prev = s.svgX;
      }
    });

    test('실재하지 않는 인접이 없다 (역명 기준)', () {
      // ⚠ ID 쌍으로 검사하면 의미가 없다 — 이 버그의 본질은 "그 ID 가 어느
      // 역인가"였으므로 **역명으로** 확인한다. 종전 오배정에서는 `B53|B58` 이
      // 소래포구↔남동인더스파크(가짜)였다.
      String nameOf(String id) => byId[id]!.name;
      final adjacentNames = <String>{};
      for (final key in suinLocal.keys) {
        final parts = key.split('|');
        if (!byId.containsKey(parts[0]) || !byId.containsKey(parts[1])) continue;
        adjacentNames.add('${nameOf(parts[0])}↔${nameOf(parts[1])}');
      }

      for (var i = 0; i < _suinOrder.length - 1; i++) {
        final a = _suinOrder[i].$2;
        final b = _suinOrder[i + 1].$2;
        expect(adjacentNames, contains('$a↔$b'), reason: '$a→$b 연결이 없다');
      }
      // 종전 오배정(소래포구-남동인더스파크-호구포-인천논현-원인재-연수)만
      // 만들어냈던 가짜 인접. 호구포 는 양쪽 순서에서 모두 가운데라 그 두 쌍
      // (인천논현↔호구포·호구포↔남동인더스파크)은 실제 인접이므로 제외한다.
      for (final fake in ['소래포구↔남동인더스파크', '인천논현↔원인재']) {
        expect(
          adjacentNames,
          isNot(contains(fake)),
          reason: '$fake 는 실재하지 않는 인접이다 (종전 오배정의 흔적)',
        );
      }
    });

    test('구간 소요시간이 실측값이고, 소래포구~연수 총합은 600초다', () {
      var total = 0;
      _segmentSeconds.forEach((key, expected) {
        final c = suinLocal[key];
        expect(c, isNotNull, reason: '$key 연결이 없다');
        expect(
          c!.travelTimeSeconds,
          expected,
          reason: '$key 소요시간이 실측과 다르다. connections.json 을 손으로 고쳤다면 '
              'dart run tool/compute_travel_times.dart --line=수인분당 로 재산출할 것.',
        );
        total += c.travelTimeSeconds;
      });
      expect(total, 600, reason: '종전 오배정 상태의 합은 1080초였다');
    });

    test('line_schedules 하행 첫차가 역 순서대로 증가한다', () async {
      // 근거 ③ 을 고정한다. `stations.json` 의 ID 만 옮기고 `line_schedules.json`
      // 의 `t`/`tE` 를 함께 옮기지 않으면 두 파일이 어긋나 여기서 잡힌다.
      final raw = await rootBundle.loadString('assets/json/line_schedules.json');
      final line = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((e) => e['id'] == '수인분당');

      for (final dayKind in ['wd', 'we']) {
        final block = line[dayKind] as Map<String, dynamic>?;
        final table = block?['t'] as Map<String, dynamic>?;
        if (table == null) continue;
        var prev = -1;
        for (final (id, name) in _suinOrder) {
          // `t[stationId]` = [상행 시각[], 하행 시각[]] (분 단위).
          final downFirst = ((table[id] as List<dynamic>)[1] as List<dynamic>)
              .first as int;
          expect(
            downFirst,
            greaterThan(prev),
            reason: '[$dayKind] $name($id) 하행 첫차 $downFirst 가 직전 역보다 이르다 — '
                'stations.json 의 ID 재배정과 line_schedules 의 t 키가 어긋났다',
          );
          prev = downFirst;
        }
      }
    });

    test('잘못된 순서에서 나온 유령 급행 skip edge 가 없다', () {
      // 종전 유령: 남동인더스파크↔연수 가 호구포·인천논현·원인재 3역을 통과한다고
      // 주장했다. 잘못된 인접 위를 BFS 한 산물이며, 실제로는 그 사이에 원인재가
      // 있고 수인선 급행은 원인재에 **정차**한다.
      //
      // 역 ID 를 하드코딩하지 않는다 — 이 버그의 수정 자체가 ID 재배정이었고
      // (인천논현 B60→B58, 남동인더스파크 B58→B60), 박아 두면 다음 재배정에
      // 조용히 무의미해진다. 역명으로 조회한다.
      final nameToId = {for (final e in byId.entries) e.value.name: e.key};
      final nam = nameToId['남동인더스파크'];
      final yeonsu = nameToId['연수'];
      expect(nam, isNotNull);
      expect(yeonsu, isNotNull);
      final phantom = suinExpress
          .where((e) =>
              (e.fromStationId == nam && e.toStationId == yeonsu) ||
              (e.fromStationId == yeonsu && e.toStationId == nam))
          .map((e) => '${e.fromStationId}→${e.toStationId}'
              '(${e.skippedStationIds.join(",")})')
          .toList();
      expect(
        phantom,
        isEmpty,
        reason: '남동인더스파크↔연수 직결 급행은 존재하지 않는다(사이에 원인재 정차). '
            'python3 tool/extract_express_skip_edges.py 로 재생성할 것.',
      );
    });

    test('급행이 통과한다고 표시된 역은 실제 수인선 급행 통과역뿐이다', () {
      // 2026-08 이후 수인분당선 급행은 실제 정차 패턴으로 모델링된다
      // (`tool/manual_express_stops.json` 의 "수인선 급행" = 오이도·소래포구·
      // 인천논현·원인재·연수·인하대·인천, "분당선 급행" = 왕십리~죽전 전역 정차 +
      // 기흥·망포·수원시청·수원·고색).
      //
      // 특히 **원인재는 통과역이 아니라 정차역**이다 — 종전에는 시간표 캐시가
      // 아예 없어 통과로 오인됐다. 원인재가 skippedStationIds 에 들어가면
      // `data/timetables/수인분당_원인재_*.json` 이 다시 비었거나 정차역 목록이
      // 깨진 것이다. (역 ID 대신 역명으로 검사 — 위 테스트와 같은 이유.)
      const passableNames = <String>{
        // 수인선 급행 통과
        '달월', '월곶', '호구포', '남동인더스파크', '송도', '숭의', '신포',
        // 분당선 급행 통과 (죽전 이남)
        '보정', '구성', '신갈', '상갈', '청명', '영통', '매탄권선', '매교',
      };
      final unexpected = <String>[];
      for (final e in suinExpress) {
        for (final s in e.skippedStationIds) {
          final name = byId[s]?.name ?? s;
          if (!passableNames.contains(name)) {
            unexpected.add('${byId[e.fromStationId]?.name}→'
                '${byId[e.toStationId]?.name} 가 $name($s) 을 통과한다고 표시');
          }
        }
      }
      expect(unexpected, isEmpty, reason: unexpected.join(' / '));
    });
  });
}
