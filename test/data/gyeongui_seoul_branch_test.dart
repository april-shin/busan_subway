@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/constants/station_api_name_overrides.dart';
import 'package:seoul_subway/core/utils/chosung_search.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';
import 'package:seoul_subway/core/utils/same_station.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/graph/shortest_path.dart';
import 'package:seoul_subway/graph/subway_graph.dart';

/// 경의중앙선 서울역 지선 교정 회귀 가드 (2026-10-16).
///
/// 서울역 지선은 **가좌(K20)에서 분기**하는 `가좌 – 신촌(경의중앙선) – 서울역`
/// 이다. 종전에는 서울역(K54)이 효창공원앞(K24)에 붙어 있었고(생성기의
/// 워크어라운드), 신촌(경의중앙선)은 아예 없었다. SVG 는 처음부터 가좌 분기로
/// 그려져 있어 그림과 그래프가 어긋나 있었다.
///
/// 지키는 것:
///  - 가짜 간선 K24↔K54 부재, 효창공원앞 차수 2, 가좌 차수 3
///  - 신촌(K57)은 2호선 신촌(240)과 **별개 역** — 환승 아님, 환승시간 없음
///  - 역명은 도착정보 API 등록명 `신촌(경의중앙선)` 과 바이트 단위로 같고
///    치환 맵에 넣지 않는다(항등)
///  - 지도(SVG) 마커·라벨, 시간표, 방향 판정, 검색
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sinchonName = '신촌(경의중앙선)';
  const line = '경의중앙';

  late List<Station> stations;
  late List<Connection> connections;
  late Map<String, int> transferTimes;
  late SubwayGraph graph;
  late ShortestPathFinder finder;

  Station byId(String id) => stations.firstWhere((s) => s.id == id);

  Set<String> neighbours(String id) => {
    for (final c in connections)
      if (c.lineId == line && !c.isTransfer) ...[
        if (c.fromStationId == id) c.toStationId,
        if (c.toStationId == id) c.fromStationId,
      ],
  };

  setUpAll(() async {
    stations =
        (jsonDecode(await rootBundle.loadString('assets/json/stations.json'))
                as List)
            .map((e) => Station.fromJson(e as Map<String, dynamic>))
            .toList();
    connections =
        (jsonDecode(await rootBundle.loadString('assets/json/connections.json'))
                as List)
            .map((e) => Connection.fromJson(e as Map<String, dynamic>))
            .toList();
    transferTimes =
        (jsonDecode(
                  await rootBundle.loadString(
                    'assets/json/transfer_times.json',
                  ),
                )
                as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int));
    graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );
    finder = ShortestPathFinder(graph: graph);
  });

  group('토폴로지', () {
    test('가짜 간선 효창공원앞(K24)↔서울역(K54) 이 없다', () {
      expect(neighbours('K24'), isNot(contains('K54')));
      expect(neighbours('K54'), isNot(contains('K24')));
    });

    test('효창공원앞은 차수 2 — 공덕·용산뿐이다 (분기점 아님)', () {
      expect(neighbours('K24'), {'K23', 'K25'});
    });

    test('가좌가 분기점이다 — 디지털미디어시티·홍대입구·신촌', () {
      expect(neighbours('K20'), {'K19', 'K21', 'K57'});
    });

    test('서울역 지선은 가좌 – 신촌 – 서울역 로 이어진 dead-end 다', () {
      expect(neighbours('K57'), {'K20', 'K54'});
      expect(neighbours('K54'), {'K57'});
    });

    test('지평(K53)에 서울역이 잘못 붙어 있지 않다 (생성기 자동 인접 오연결)', () {
      expect(neighbours('K53'), {'K52'});
    });

    test('소요시간은 코레일 경의선 시각표 실측이다 (가좌→신촌 180, 신촌→서울역 330)', () {
      int time(String a, String b) => connections
          .singleWhere(
            (c) =>
                c.lineId == line &&
                ((c.fromStationId == a && c.toStationId == b) ||
                    (c.fromStationId == b && c.toStationId == a)),
          )
          .travelTimeSeconds;
      expect(time('K20', 'K57'), 180);
      expect(time('K57', 'K54'), 330);
    });

    test('경의중앙 연결 수가 역 수 - 1 이다 (트리 — 끊김·순환 없음)', () {
      final lineStations = stations.where((s) => s.lineId == line).length;
      final lineEdges = connections
          .where((c) => c.lineId == line && !c.isTransfer)
          .map(
            (c) =>
                ({c.fromStationId, c.toStationId}.toList()..sort()).join('|'),
          )
          .toSet();
      expect(lineEdges.length, lineStations - 1);
    });
  });

  group('신촌(경의중앙선) 역 레코드', () {
    test('K57 — 이름·노선·좌표', () {
      final s = byId('K57');
      expect(s.name, sinchonName);
      expect(s.lineId, line);
      expect(s.latitude, closeTo(37.5597, 0.001));
      expect(s.longitude, closeTo(126.9431, 0.001));
    });

    test('2호선 신촌(240)과 환승역이 아니다', () {
      final s = byId('K57');
      expect(s.isTransfer, isFalse);
      expect(s.transferLines, [line]);
      expect(byId('240').isTransfer, isFalse);
      expect(byId('240').transferLines, ['2']);
      // 이름이 달라 환승 edge(동일 역명 + isTransfer)가 만들어질 수 없다.
      expect(byId('240').name, '신촌');
      expect(byId('240').name, isNot(s.name));
    });

    test('transfer_times 에 신촌(경의중앙선) 항목이 없다', () {
      expect(transferTimes.keys.where((k) => k.contains(sinchonName)), isEmpty);
      // 2호선 신촌도 환승역이 아니라 원래 항목이 없다.
      expect(transferTimes.keys.where((k) => k.startsWith('신촌_')), isEmpty);
    });

    test('그래프에서 K57 노드는 환승 edge 를 갖지 않는다', () {
      final edges = graph.getNeighbors('K57_$line');
      expect(edges.where((e) => e.isTransfer), isEmpty);
      expect(edges.map((e) => e.toNodeId).toSet(), {'K20_$line', 'K54_$line'});
    });

    test('lines.json 경의중앙 stationIds 에 K57 이 있다', () async {
      final lines =
          jsonDecode(await rootBundle.loadString('assets/json/lines.json'))
              as List;
      final ids =
          (lines.cast<Map<String, dynamic>>().firstWhere(
                    (l) => l['id'] == line,
                  )['stationIds']
                  as List)
              .cast<String>();
      expect(ids, contains('K57'));
      expect(ids.toSet().length, ids.length, reason: '중복 ID');
    });
  });

  group('경로', () {
    test('가좌 → 서울역 은 신촌을 지나는 2정거장이다', () {
      final result = finder.findShortestPath('K20_$line', 'K54_$line');
      expect(result, isNotNull);
      expect(result!.nodeIds, ['K20_$line', 'K57_$line', 'K54_$line']);
      // 180 + 330 + 중간역(신촌) 정차 30
      expect(result.totalTimeSeconds, 540);
    });

    test('가좌 → 서울역 최단은 어떤 경로 변형으로도 경의중앙 직결이다', () {
      final results = finder.findShortestPathBetweenStations('가좌', '서울역');
      expect(results, isNotEmpty);
      final best = results.first;
      expect(best.nodeIds, ['K20_$line', 'K57_$line', 'K54_$line']);
      expect(best.edges.where((e) => e.isTransfer), isEmpty);
    });

    test('서울역 → 가좌 역방향도 같은 2정거장이다', () {
      final result = finder.findShortestPath('K54_$line', 'K20_$line');
      expect(result!.nodeIds, ['K54_$line', 'K57_$line', 'K20_$line']);
    });

    test('효창공원앞 → 서울역 을 경의중앙만으로 가면 가좌 분기를 거친다 (가짜 간선 부재)', () {
      final result = finder.findShortestPath(
        'K24_$line',
        'K54_$line',
        nodeFilter: (id) => id.endsWith('_$line'),
      );
      expect(result, isNotNull);
      // 종전 가짜 간선이면 ['K24', 'K54'] 2노드 직결이었다. 지금은 본선을 가좌까지 올라가
      // 지선(신촌)으로 들어가야 한다.
      expect(result!.nodeIds.length, greaterThan(2));
      expect(result.nodeIds.sublist(result.nodeIds.length - 3), [
        'K20_$line',
        'K57_$line',
        'K54_$line',
      ]);
    });

    test('신촌(경의중앙선) ↔ 신촌(2호선) 은 직접 환승이 아니다', () {
      final results = finder.findShortestPathBetweenStations(sinchonName, '신촌');
      expect(results, isNotEmpty);
      // 두 역 사이 최단은 홍대입구 등 실제 환승역을 거쳐야 한다.
      final best = results.first;
      expect(
        best.nodeIds.length,
        greaterThan(2),
        reason: '이름만 같은 두 신촌이 직접 연결돼 있다: ${best.nodeIds}',
      );
    });
  });

  group('방향 판정', () {
    test('가좌 → 신촌 → 서울역 은 모두 하행(서울역 방면 = ID 증가 규약)이다', () {
      expect(isDownBetween('K20', 'K57', line), isTrue);
      expect(isDownBetween('K57', 'K54', line), isTrue);
      expect(isDownBetween('K54', 'K57', line), isFalse);
      expect(isDownBetween('K57', 'K20', line), isFalse);
    });

    test('서울역 지선 직전역 확장이 가좌 쪽으로 정확히 거슬러 올라간다', () {
      // 하행 열차의 신촌 직전역 = 가좌, 서울역 직전역 = 신촌.
      expect(
        findPreviousStationId(
          currentId: 'K57',
          lineId: line,
          isDown: true,
          connections: connections,
        ),
        'K20',
      );
      expect(
        findPreviousStationId(
          currentId: 'K54',
          lineId: line,
          isDown: true,
          connections: connections,
        ),
        'K57',
      );
      // 상행(문산 방면) 열차는 가좌에 홍대입구(본선)와 신촌(지선) 두 쪽에서 들어올 수
      // 있다. 후보가 둘이면 번호 거리가 가장 가까운 본선(홍대입구)을 고른다 —
      // 분기역(가좌)의 기존 규칙이다(`findPreviousStationId` 문서 참조).
      expect(
        findPreviousStationId(
          currentId: 'K20',
          lineId: line,
          isDown: false,
          connections: connections,
        ),
        'K21',
        reason: '분기 후보가 둘이면 본선(숫자 거리 최소)을 고른다',
      );
    });
  });

  group('검색·표기', () {
    test('"신촌" 검색에 두 신촌이 모두 잡힌다 (같은 물리 역으로 합쳐지지 않는다)', () {
      final hits = stations
          .where((s) => matchesStationQuery(s.name, '신촌'))
          .toList();
      final unique = uniqueStationsByLocation(hits);
      expect(unique.map((s) => s.id).toSet(), containsAll(['240', 'K57']));
    });

    test('초성 검색 ㅅㅊ 에 신촌(경의중앙선)이 잡힌다', () {
      expect(matchesStationQuery(sinchonName, 'ㅅㅊ'), isTrue);
    });

    test('역명은 API 등록명과 같고 치환 맵에 없다 (항등)', () {
      expect(arrivalApiStationNameOverrides.containsKey(sinchonName), isFalse);
      expect(
        arrivalApiStationNameOverrides.containsKey('신촌'),
        isFalse,
        reason: '신촌 항목을 넣으면 2호선 질의가 깨진다',
      );
      expect(resolveArrivalApiStationName(sinchonName), sinchonName);
      expect(resolveArrivalApiStationNames(sinchonName), [sinchonName]);
      expect(resolveArrivalApiStationName('신촌'), '신촌');
      expect(resolveDisplayStationName(sinchonName), sinchonName);
      // 반각 괄호·공백 없음.
      expect(sinchonName, '신촌(경의중앙선)');
    });
  });

  group('지도(SVG)', () {
    late String svg;
    late String html;
    setUpAll(() {
      svg = File('assets/svg/seoul_metro_map.svg').readAsStringSync();
      html = File('assets/html/map.html').readAsStringSync();
    });

    test('신촌(경의중앙선) 마커·라벨이 SVG 와 생성된 map.html 에 있다', () {
      for (final src in [svg, html]) {
        expect(src, contains('data-station="신촌&#10;(경의중앙선)"'));
        expect(src, contains('<circle cx="876.0" cy="500.0" r="4.5"'));
      }
    });

    test('마커가 서울역 지선 폴리라인 위(가좌→서울역 대각 구간)에 놓인다', () {
      // 지선: (864,488) → (960,584) — 기울기 1 의 선분. 마커는 그 위여야 한다.
      final s = byId('K57');
      expect(s.svgY - 488, closeTo(s.svgX - 864, 0.01));
      expect(s.svgX, inInclusiveRange(864, 960));
    });
  });

  group('시간표', () {
    test('line_schedules.json 에 K57 의 양방향 시간표가 있다', () async {
      final schedules =
          jsonDecode(
                await rootBundle.loadString('assets/json/line_schedules.json'),
              )
              as List;
      final entry = schedules.cast<Map<String, dynamic>>().firstWhere(
        (s) => s['id'] == line,
      );
      for (final day in ['wd', 'we']) {
        final t =
            (entry[day] as Map<String, dynamic>)['t'] as Map<String, dynamic>;
        expect(t.containsKey('K57'), isTrue, reason: '$day: K57 시간표 없음');
        final dirs = (t['K57'] as List).cast<List?>();
        expect(dirs[0], isNotEmpty, reason: '$day: 가좌(문산) 방면 출발 없음');
        expect(dirs[1], isNotEmpty, reason: '$day: 서울역 방면 출발 없음');
      }
    });
  });
}
