// 6호선 응암 순환 구간(구산-응암-새절) 인접 관계 회귀 가드.
//
// 2026-08 까지 `connections.json` 이 구산(606)→새절(607)을 직접 연결해
// 응암(601)을 건너뛰었다. 응암은 역촌(602)하고만 이어져 있어,
// 연신내→새절 경로가 "연신내→구산→새절" 로 나오는 버그가 있었다.
// 실제 선로는 **구산→응암→새절** 이다(응암 순환: 새절 방면 본선이 응암에서
// 역촌~구산 단선 루프와 만난다).
//
// 올바른 인접의 근거:
//   ① 공식 역번호 — 응암 610, 역촌 611, 불광 612, 독바위 613, 연신내 614,
//      구산 615, 새절 616. 열차는 새절→응암→역촌→…→구산→응암→새절 순환 운행.
//   ② 서울교통공사 노선도 — 구산과 새절 사이에 응암이 있다.
//
// 소요시간은 6호선 시간표 캐시(`data/timetables/6_*`)가 없어 실측 재계산이
// 불가능했고, 인근 구간 값과 정합하는 추정치다(구산→응암 120s, 응암→새절 90s).
//
// 방향성 모델링 현황:
//   - 폐합 edge(구산 606→응암 601)는 `isOneWay` 로 단방향이다 — 양방향으로
//     열면 "응암→구산"이 실존하지 않는 1구간 역주행 최단경로로 잡힌다.
//   - 루프 내부(601~606) edge 의 양방향성은 이 수정 이전부터 있던 한계로
//     그대로 둔다(예: 연신내→독바위가 역방향 직결로 나옴).
//   - 방향별 인접 리스트는 `line_direction.dart` 의 폐합 edge 반전 특례로
//     상·하행 체인이 모두 이어진다(하단 방향 필터 테스트 참조).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/path_on_line.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/graph/shortest_path.dart';
import 'package:seoul_subway/graph/subway_graph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;
  late SubwayGraph graph;

  setUpAll(() async {
    final stationsJson =
        await rootBundle.loadString('assets/json/stations.json');
    stations = (jsonDecode(stationsJson) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();

    final connectionsJson =
        await rootBundle.loadString('assets/json/connections.json');
    connections = (jsonDecode(connectionsJson) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();

    final transferJson =
        await rootBundle.loadString('assets/json/transfer_times.json');
    final transferTimes = (jsonDecode(transferJson) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));

    graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );
  });

  Set<String> line6Neighbors(String stationId) => {
        for (final c in connections)
          if (c.lineId == '6' && !c.isTransfer)
            if (c.fromStationId == stationId)
              c.toStationId
            else if (c.toStationId == stationId)
              c.fromStationId,
      };

  test('구산(606)의 6호선 인접역은 연신내(605)와 응암(601)이다', () {
    expect(line6Neighbors('606'), {'605', '601'});
  });

  test('응암(601)의 6호선 인접역은 역촌(602)·구산(606)·새절(607)이다', () {
    expect(line6Neighbors('601'), {'602', '606', '607'});
  });

  test('구산↔새절 직접 연결(응암 건너뛰기)이 없다', () {
    expect(
      connections.any((c) =>
          c.lineId == '6' &&
          !c.isTransfer &&
          {c.fromStationId, c.toStationId}.containsAll({'606', '607'})),
      isFalse,
    );
  });

  test('연신내→새절 최단경로가 구산·응암을 순서대로 지난다', () {
    final result = ShortestPathFinder(graph: graph).findShortestPath(
      '605_6', // 연신내
      '607_6', // 새절
    );
    expect(result, isNotNull);
    expect(result!.nodeIds, ['605_6', '606_6', '601_6', '607_6']);
  });

  test('응암→구산 최단경로가 역주행(폐합 edge 역방향)이 아니라 순환 정방향이다', () {
    // 폐합 edge 가 양방향이면 601→606 직결(1구간 역주행)이 최단으로 잡힌다.
    // isOneWay 가드: 실제 승차 경로인 응암→역촌→불광→독바위→연신내→구산.
    final result = ShortestPathFinder(graph: graph).findShortestPath(
      '601_6', // 응암
      '606_6', // 구산
    );
    expect(result, isNotNull);
    expect(result!.nodeIds,
        ['601_6', '602_6', '603_6', '604_6', '605_6', '606_6']);
  });

  // 방향별 인접 리스트(`buildLineAdjacency` + `isDownBetween`) 회귀 가드.
  // 폐합 edge 606→601 이 ID 감소라 일반 규칙으로는 상행으로 분류되는데,
  // 그러면 하행 체인이 구산에서 끊겨 순환 구간 ↔ 본선 간 방향 경로가 전부
  // null 이 된다(실시간 열차 아이콘·위치 폴백 도착정보 소실).
  // `line_direction.dart` 의 6호선 폐합 edge 반전 특례가 이를 막는다.
  test('하행 필터: 구산→새절 방향 경로가 응암을 지나 이어진다', () {
    final path = findStationIdPathOnLine(
      fromStationId: '606',
      toStationId: '607',
      lineId: '6',
      connections: connections,
      isDown: true,
    );
    expect(path, ['606', '601', '607']);
  });

  test('하행 필터: 역촌→새절(순환 구간→본선) 방향 경로가 존재한다', () {
    final path = findStationIdPathOnLine(
      fromStationId: '602',
      toStationId: '607',
      lineId: '6',
      connections: connections,
      isDown: true,
    );
    expect(path, ['602', '603', '604', '605', '606', '601', '607']);
  });

  test('상행 필터: 증산→연신내(본선→순환 구간) 방향 경로가 존재한다', () {
    // ⚠ 기대값은 방향 모델의 산물이지 실제 승차 경로가 아니다. 응암 루프는
    // 단선 일방이라 물리 경로는 608→607→601→602→603→604→605 (루프 정방향)다.
    // 방향별 인접 리스트에서 상행 체인의 연결성(본선→루프 도달 가능)만 보장한다.
    final path = findStationIdPathOnLine(
      fromStationId: '608',
      toStationId: '605',
      lineId: '6',
      connections: connections,
      isDown: false,
    );
    expect(path, ['608', '607', '601', '606', '605']);
  });
}
