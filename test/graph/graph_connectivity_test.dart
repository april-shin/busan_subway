@Tags(['integration'])
library;

import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/data/local/timetable_data_source.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/usecases/find_next_departure.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/graph/shortest_path.dart';
import 'package:seoul_subway/graph/subway_graph.dart';

/// 그래프 연결성 회귀 가드.
///
/// 배경: 에버라인(기점 기흥)과 의정부경전철(범골↔발곡 사이 회룡)은 환승역이 데이터에
/// 빠져 있어 노선 14역씩이 그래프에서 통째로 고립돼 있었다 — 서울역에서 BFS 를 돌리면
/// 791개 노드 중 28개가 도달 불가였고, 두 노선의 역으로 가는 경로가 아예 검색되지
/// 않았다. 환승 edge 는 "isTransfer 인 역을 이름으로 묶어" 만들어지므로(graph_builder
/// `_addTransferEdges`), 환승역 한 곳이 빠지면 같은 유형의 단절이 조용히 재발한다.
///
/// 이 테스트가 깨지면: 새 노선·역을 추가했는데 기존 망과 이어지는 환승역(양쪽 노선에
/// 같은 이름 + `isTransfer=true` + `transferLines`)이 빠졌거나, 지선 연결이 끊겼다.
void main() {
  late List<Station> stations;
  late SubwayGraph graph;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    stations =
        (jsonDecode(await rootBundle.loadString('assets/json/stations.json'))
                as List)
            .map((e) => Station.fromJson(e as Map<String, dynamic>))
            .toList();
    final connections =
        (jsonDecode(await rootBundle.loadString('assets/json/connections.json'))
                as List)
            .map((e) => Connection.fromJson(e as Map<String, dynamic>))
            .toList();
    final transferTimes =
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
  });

  String nodeOf(String name, String lineId) {
    final s = stations.firstWhere(
      (s) => s.name == name && s.lineId == lineId,
      orElse: () => fail('역 없음: $name($lineId)'),
    );
    return '${s.id}_${s.lineId}';
  }

  /// [start] 에서 BFS 로 도달 가능한 노드 집합.
  /// reverse=false 는 "start 에서 갈 수 있는 곳", true 는 "start 로 올 수 있는 곳".
  Set<String> reach(String start, {required bool reverse}) {
    final incoming = <String, List<String>>{};
    if (reverse) {
      for (final id in graph.nodes.keys) {
        for (final e in graph.getNeighbors(id)) {
          incoming.putIfAbsent(e.toNodeId, () => []).add(id);
        }
      }
    }
    final seen = <String>{start};
    final queue = Queue<String>()..add(start);
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      final next = reverse
          ? (incoming[cur] ?? const <String>[])
          : graph.getNeighbors(cur).map((e) => e.toNodeId);
      for (final n in next) {
        if (seen.add(n)) queue.add(n);
      }
    }
    return seen;
  }

  String describe(Iterable<String> nodeIds) => nodeIds
      .map((id) {
        final n = graph.getNode(id);
        return n == null ? id : '${n.stationName}(${n.lineId})';
      })
      .join(', ');

  List<String> labelsOf(PathResult r) => r.nodeIds.map((id) {
    final n = graph.getNode(id)!;
    return '${n.stationName}(${n.lineId})';
  }).toList();

  group('고립 컴포넌트 0', () {
    test('서울역(1호선)에서 stations.json 의 모든 역 노드에 도달한다', () {
      final reachable = reach(nodeOf('서울역', '1'), reverse: false);
      final missing = [
        for (final s in stations)
          if (!reachable.contains('${s.id}_${s.lineId}')) '${s.id}_${s.lineId}',
      ];
      expect(
        missing,
        isEmpty,
        reason:
            '서울역에서 도달 불가한 역 ${missing.length}개 — 환승역 누락 또는 '
            '지선 단절. 노선 단위로 통째로 빠졌다면 그 노선과 기존 망을 잇는 '
            '환승역(양쪽 노선에 같은 이름 + isTransfer)을 확인하라:\n'
            '${describe(missing)}',
      );
    });

    test('모든 역 노드에서 서울역으로 돌아올 수 있다 (단방향 막다른 길 없음)', () {
      final canReach = reach(nodeOf('서울역', '1'), reverse: true);
      final stuck = [
        for (final s in stations)
          if (!canReach.contains('${s.id}_${s.lineId}')) '${s.id}_${s.lineId}',
      ];
      expect(
        stuck,
        isEmpty,
        reason: '서울역으로 못 돌아오는 역 ${stuck.length}개:\n${describe(stuck)}',
      );
    });
  });

  group('기흥·회룡 환승이 실제 경로탐색에 쓰인다', () {
    test('환승 edge 가 양방향으로 존재한다', () {
      bool hasTransfer(String a, String b) =>
          graph.getNeighbors(a).any((e) => e.toNodeId == b && e.isTransfer);

      final pairs = <(String, String, String)>[
        ('기흥', '수인분당', '에버라인'),
        ('회룡', '1', '의정부'),
      ];
      for (final (name, a, b) in pairs) {
        expect(
          hasTransfer(nodeOf(name, a), nodeOf(name, b)),
          isTrue,
          reason: '$name $a→$b 환승 edge 없음',
        );
        expect(
          hasTransfer(nodeOf(name, b), nodeOf(name, a)),
          isTrue,
          reason: '$name $b→$a 환승 edge 없음',
        );
      }
    });

    test('수인분당(신갈·상갈) → 에버라인(지석)은 기흥 환승 1회로 연결된다', () {
      final finder = ShortestPathFinder(graph: graph);
      for (final from in ['신갈', '상갈']) {
        final result = finder.findShortestPath(
          nodeOf(from, '수인분당'),
          nodeOf('지석', '에버라인'),
        );
        expect(result, isNotNull, reason: '$from(수인분당) → 지석(에버라인) 경로 없음');
        // 환승은 기흥 한 곳, 에버라인 구간은 기흥 → 강남대 → 지석.
        expect(result!.edges.where((e) => e.isTransfer).length, 1);
        expect(
          labelsOf(result),
          containsAllInOrder(['기흥(수인분당)', '기흥(에버라인)', '강남대(에버라인)', '지석(에버라인)']),
          reason: '실제 경로: ${describe(result.nodeIds)}',
        );
      }
    });

    test('1호선(망월사) → 의정부경전철(발곡)은 회룡 환승 1회로 연결된다', () {
      final finder = ShortestPathFinder(graph: graph);
      final result = finder.findShortestPath(
        nodeOf('망월사', '1'),
        nodeOf('발곡', '의정부'),
      );
      expect(result, isNotNull, reason: '망월사(1) → 발곡(의정부) 경로 없음');
      expect(result!.edges.where((e) => e.isTransfer).length, 1);
      expect(
        labelsOf(result),
        containsAllInOrder(['회룡(1)', '회룡(의정부)', '발곡(의정부)']),
        reason: '실제 경로: ${describe(result.nodeIds)}',
      );
    });

    test('의정부경전철 범골 → 발곡은 회룡을 경유한다 (단일 구간으로 건너뛰지 않음)', () {
      // 회룡 누락 시절엔 범골→발곡이 단일 edge(169초)였다.
      final finder = ShortestPathFinder(graph: graph);
      final result = finder.findShortestPath(
        nodeOf('범골', '의정부'),
        nodeOf('발곡', '의정부'),
      );
      expect(result, isNotNull);
      expect(result!.nodeIds, [
        nodeOf('범골', '의정부'),
        nodeOf('회룡', '의정부'),
        nodeOf('발곡', '의정부'),
      ]);
      expect(result.edges.every((e) => !e.isTransfer), isTrue);

      // [2026-10-06 리뷰] 소요시간 규약 회귀 가드. 회룡 누락 시절엔 범골→발곡이
      // 단일 edge 169초(= 하행 전용 통과시간. 발곡→회룡 84 + 회룡 dwell 30 +
      // 회룡→범골 55)였고 중간역이 없어 dwell 가산도 0이었다. 분할 후에는
      // `compute_travel_times` 의 방향 무차별 중앙값 72 + 84 = 156 에 회룡이
      // 중간역이 되며 dwell 30 이 붙어 **186초**가 된다(하행 실측 169 와 상행
      // 실측 197 사이). 이 값이 흔들리면 edge 값이나 dwell 규약이 바뀐 것이다.
      expect(result.edges.map((e) => e.weightSeconds).toList(), [72, 84]);
      expect(result.totalDwellTimeSeconds, 30,
          reason: '회룡이 중간역이 되었으므로 dwell 30초가 붙어야 한다');
      expect(result.totalTimeSeconds, 186,
          reason: '범골→발곡 종단은 edge 156 + 회룡 dwell 30 = 186초여야 한다');
    });
  });

  group('신설 환승역(기흥·회룡)에서 다음 출발 시각이 나온다', () {
    // 두 역은 출처가 다르다 — 어느 쪽이든 결과가 나와야 한다.
    //  - U15(회룡): 2026-10-16 에 `build_gettrainsch_timetable.dart --lines=의정부
    //    --stations=U15` 로 역별 시간표(`t`)를 넣었다. 즉 **실제 시간표**를 탄다.
    //  - E15(기흥): 에버라인은 getTrainSch 미지원이라 `t` 가 없다. 완행 **배차간격
    //    폴백**을 탄다. (`.claude/docs/pending-data.md` 3번 참조)
    // 두 노선 모두 급행이 없어(express_skip_edges.json 미등재) "급행 폴백 금지"
    // 규칙과는 무관하다.
    for (final (lineId, stationId, isDown) in [
      ('에버라인', 'E15', true),
      ('의정부', 'U15', true),
      ('의정부', 'U15', false),
    ]) {
      test('$lineId $stationId (isDown=$isDown) 평일 낮 다음 출발이 나온다', () async {
        final schedule = await TimetableDataSource().getSchedule(lineId);
        expect(schedule, isNotNull);
        // 2026-10-07 수요일 12:00 — 평일 주간.
        final now = DateTime(2026, 10, 7, 12, 0);
        final next = findNextDeparture(
          schedule: schedule!,
          now: now,
          isDown: isDown,
          stationId: stationId,
        );
        expect(next, isNotNull);
        expect(next!.difference(now).inMinutes, inInclusiveRange(0, 15));
      });
    }
  });
}
