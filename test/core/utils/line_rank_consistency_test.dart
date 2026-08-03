// 전 노선 방향 판정 단조성 가드.
//
// `isDownDirection` 은 세그먼트의 **첫 두 역**으로 방향을 정한다. 이 기준이
// 성립하려면 "인접 두 역 사이의 `isDownBetween` 판정이 노선 체인을 따라 단조"
// 여야 한다. 어느 역에서 같은 방향 이웃이 둘 이상 나오면 그 지점에서 번호
// 순서와 물리 순서가 어긋난 것이고, 그 역을 출발지로 하는 경로는 방향이 뒤집힌다
// (출발시각 조회가 반대 방향 시간표를 보거나, 종착역이면 빈 목록이 된다).
//
// 이 테스트는 `connections.json` 전체를 순회하며 그런 지점을 찾는다. 실제 분기역
// (한 방향에 갈래가 둘인 역)은 정상이므로 [_realJunctions] 로 제외한다.
//
// 새 역·연장 구간을 추가했을 때 이 테스트가 깨지면 둘 중 하나다:
//   1) 번호가 물리 순서와 어긋난다 → `line_direction.dart` 의 `_stationRanks` 에
//      해당 역 rank 를 추가한다.
//   2) 진짜 분기역이 새로 생겼다 → 아래 [_realJunctions] 에 근거와 함께 추가한다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';

/// 한 방향으로 갈래가 둘인 실제 분기역 — 같은 방향 이웃이 2개인 게 정상이다.
/// `'{lineId}|{stationId}'`.
const _realJunctions = <String>{
  '1|142', // 구로 — 경인선(구일)/경부선(가산디지털단지 1425) 분기
  // 금천구청 — 본선(석수)/광명 지선 분기.
  // 구로 이남 순서 교정으로 ID 가 166 → 167 이 됐다(166 = 독산, 분기역 아님).
  '1|167',
  '1|179', // 병점 — 본선(세마)/서동탄 지선 분기
  '2|211', // 성수 — 본선(뚝섬)/성수지선(용답) 분기
  '2|234', // 신도림 — 본선(문래)/신정지선(도림천) 분기
  '5|539', // 강동 — 하남검단산/마천 분기
  '경의중앙|K24', // 효창공원앞 — 용산/서울역 분기
  // 응암 — 새절(본선)/역촌·구산(응암 단선 순환) 분기. 폐합 edge 반전
  // (`line_direction.dart` 의 606↔601 특례) 적용 후에도 하행 이웃이
  // 역촌(602)·새절(607) 둘인데, 실제 분기역이라 정상이다.
  // 구산(606)은 특례 반전으로 연신내(605)=상행·응암(601)=하행 단조가
  // 성립해 예외가 필요 없다.
  '6|601',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;

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
  });

  test('모든 노선에서 인접역 방향 판정이 단조다', () {
    final names = {for (final s in stations) '${s.lineId}|${s.id}': s.name};

    // 노선별 인접 리스트 (비환승 연결만).
    final adjacency = <String, Map<String, List<String>>>{};
    for (final c in connections) {
      if (c.isTransfer) continue;
      final line = adjacency.putIfAbsent(c.lineId, () => {});
      line.putIfAbsent(c.fromStationId, () => []).add(c.toStationId);
      line.putIfAbsent(c.toStationId, () => []).add(c.fromStationId);
    }

    final violations = <String>[];
    for (final entry in adjacency.entries) {
      final lineId = entry.key;
      for (final node in entry.value.entries) {
        final stationId = node.key;
        final neighbours = node.value;
        if (neighbours.length < 2) continue;
        if (_realJunctions.contains('$lineId|$stationId')) continue;

        final down = <String>[];
        final up = <String>[];
        for (final other in neighbours) {
          (isDownBetween(stationId, other, lineId) ? down : up).add(other);
        }
        if (down.length < 2 && up.length < 2) continue;

        String label(String id) => '$id(${names['$lineId|$id'] ?? '?'})';
        final side = down.length >= 2 ? down : up;
        final direction = down.length >= 2 ? '하행' : '상행';
        violations.add(
          '[$lineId] ${label(stationId)} 의 $direction 이웃이 '
          '${side.map(label).join(', ')} 로 둘 이상이다',
        );
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '번호 순서가 물리 순서와 어긋난다 — line_direction.dart 의 '
          '_stationRanks 에 rank 를 추가하거나, 실제 분기역이면 _realJunctions 에 '
          '등록하라:\n${violations.join('\n')}',
    );
  });

  test('rank 보정이 필요한 구간의 방향이 물리 순서와 맞는다', () {
    // 각 항목: 물리적으로 이어진 역 순서 + 그 진행이 하행인지.
    // 체인을 따라가며 인접 쌍마다 방향이 일정한지 확인한다.
    const chains = <(String, List<String>, bool)>[
      // 1호선 경원선 북단 — 남행(하행): 연천 → 전곡 → 청산 → 소요산 → 동두천
      ('1', ['165', '164', '163', '101', '102'], true),
      // 1호선 금정 — 남행(하행): 안양 → 명학 → 금정 → 군포
      ('1', ['170', '171', '1715', '172'], true),
      // 1호선 광명 지선 — 금천구청(167)에서 남하(하행).
      // 구로 이남 순서 교정으로 금천구청 ID 가 166 → 167 이 됐다(166 = 독산).
      ('1', ['167', '1A1'], true),
      // 1호선 경부선 구로 이남 — 남행(하행): 구로 → 독산 → 금천구청 → 석수 → 관악 → 안양.
      // 종전에는 독산/금천구청, 석수/관악 이 뒤바뀌어 결선이 지그재그였다.
      ('1', ['142', '166', '167', '168', '169', '170'], true),
      // 3호선 — 대화 방면(상행): 지축 → 삼송 → 원흥 → 원당.
      // 원흥(344)이 원당(308)과 삼송(309) 사이라 번호만 뒤에 붙어 있다.
      ('3', ['310', '309', '344', '308'], false),
      // 8호선 별내선 — 남행(하행): 별내 → … → 암사역사공원 → 암사 → 천호
      ('8', ['819', '820', '821', '822', '823', '824', '801', '802'], true),
      // 경의중앙 임진강 지선 — 남행(하행): 임진강 → 운천 → 문산 → 파주
      ('경의중앙', ['K55', 'K56', 'K01', 'K02'], true),
      // 서해 — 남행(하행): 김포공항 → 원종 → 소새울
      ('서해', ['H12', 'H01', 'H02'], true),
      // 수인분당 인천 방면(하행). 남동인더스파크부터 인천까지 한 번에 —
      // 원인재(K266)와 인하대~인천(B54~B57) 두 역전 구간을 모두 지난다.
      (
        '수인분당',
        ['B58', 'B59', 'B60', 'K266', 'B61', 'B62', 'B54', 'B55', 'B56', 'B57'],
        true
      ),
    ];

    for (final (lineId, chain, isDown) in chains) {
      for (var i = 0; i + 1 < chain.length; i++) {
        expect(
          isDownBetween(chain[i], chain[i + 1], lineId),
          isDown,
          reason: '[$lineId] ${chain[i]} → ${chain[i + 1]} 은 '
              '${isDown ? '하행' : '상행'} 이어야 한다',
        );
        // 역방향도 반대로 나와야 한다.
        expect(
          isDownBetween(chain[i + 1], chain[i], lineId),
          !isDown,
          reason: '[$lineId] ${chain[i + 1]} → ${chain[i]} 은 '
              '${isDown ? '상행' : '하행'} 이어야 한다',
        );
      }
    }
  });

  test('rank 보정이 2·4호선 특수 규칙을 침범하지 않는다', () {
    // 2호선 순환 경계와 성수·신정지선.
    expect(isDownBetween('201', '243', '2'), isTrue);
    expect(isDownBetween('243', '201', '2'), isFalse);
    expect(isDownBetween('202', '201', '2'), isTrue);
    expect(isDownBetween('211', '244', '2'), isTrue);
    expect(isDownBetween('234', '247', '2'), isFalse);
    // 4호선 진접선 경계.
    expect(isDownBetween('452', '402', '4'), isTrue);
    expect(isDownBetween('402', '452', '4'), isFalse);
    expect(isDownBetween('449', '450', '4'), isTrue);
    // 9호선·공항철도 규칙 반전.
    expect(isDownBetween('905', '904', '9'), isTrue);
    expect(isDownBetween('A02', 'A01', '공항철도'), isTrue);
    // 가상 급행 노선은 base 규칙으로 정규화된다.
    expect(isDownBetween('B62', 'B54', '수인분당E'), isTrue);
    expect(isDownBetween('310', '344', '3E'), isFalse);
  });
}
