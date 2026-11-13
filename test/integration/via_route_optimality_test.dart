// 경유역 경로가 "정차역 플랫폼 조합 전수탐색"의 최적과 일치하는지 실데이터로 검증.
//
// `findShortestPathVia` 는 정차역마다 모든 플랫폼 후보를 DP 상태로 남긴다. 이 테스트는
// 같은 문제를 브루트포스(모든 플랫폼 조합 × 구간 Dijkstra)로 다시 풀어 **참조 구현**
// 으로 삼고, DP 결과가 그 최적과 같은지 비교한다.
//
// 배경 — 초기 구현은 구간별 그리디였고, 앞 구간 비용만 보고 경유역 플랫폼을 고정해
// 환승역에서 손해를 보는 경로가 나왔다(서울 선릉 사례). 부산 데이터로도 같은 불변식을
// 잠근다.
//
// 실데이터(배차간격·환승시간)가 바뀌어도 "DP == 전수탐색 최적" 불변식은 유지되므로
// 절대 분 수를 하드코딩하지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/headway_estimator.dart';
import 'package:busan_subway/data/local/local_data_source.dart';
import 'package:busan_subway/data/local/timetable_data_source.dart';
import 'package:busan_subway/data/repositories/station_repository_impl.dart';
import 'package:busan_subway/graph/graph_builder.dart';
import 'package:busan_subway/graph/shortest_path.dart';
import 'package:busan_subway/graph/subway_graph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SubwayGraph graph;
  late ShortestPathFinder finder;

  setUpAll(() async {
    final repo = StationRepositoryImpl(localDataSource: LocalDataSource());
    graph = GraphBuilder().build(
      stations: await repo.getAllStations(),
      connections: await repo.getAllConnections(),
      transferTimes: await repo.getTransferTimes(),
      expressSkipEdges: await repo.getExpressSkipEdges(),
      headwaySeconds:
          buildHeadwayMap(await TimetableDataSource().loadSchedules()),
    );
    finder = ShortestPathFinder(graph: graph);
  });

  /// 정차역 이름 목록 → 역별 노드 후보 집합.
  List<Set<String>> stopsFor(List<String> names) => [
        for (final n in names) graph.getNodeIdsForStation(n).toSet(),
      ];

  /// 모든 플랫폼 조합을 전수탐색한 최소 비용(초). 도달 불가면 null.
  ///
  /// [stops] 의 중간 정차역마다 플랫폼 후보를 하나씩 고정해 구간 Dijkstra 를 잇고,
  /// 구간 소요시간 합이 가장 작은 조합을 찾는다. 경유역이 2개 이하일 때만 쓴다
  /// (조합 수가 지수로 늘어남).
  int? bruteForceCost(List<Set<String>> stops) {
    int? best;

    void recurse(Set<String> from, int stopIndex, int acc) {
      if (stopIndex == stops.length - 1) {
        final leg = finder.findShortestPathMulti(from, stops.last);
        if (leg == null) return;
        final total = acc + leg.totalTimeSeconds;
        if (best == null || total < best!) best = total;
        return;
      }
      for (final candidate in stops[stopIndex]) {
        final leg = finder.findShortestPathMulti(from, {candidate});
        if (leg == null) continue;
        recurse({leg.nodeIds.last}, stopIndex + 1, acc + leg.totalTimeSeconds);
      }
    }

    recurse(stops.first, 1, 0);
    return best;
  }

  group('경유 경로 최적성 (실데이터 vs 전수탐색)', () {
    // 각 케이스: [출발, ...경유, 도착] 역 이름.
    final cases = <List<String>>[
      // 환승역(서면)을 경유 — 1호선·2호선 두 플랫폼 후보가 DP 상태로 남는다.
      ['다대포해수욕장', '서면', '노포'],
      // 경유역이 이미 최단경로상에 있는 경우.
      ['다대포해수욕장', '부산진', '노포'],
      // 환승이 필요한 경유 — 1호선 출발, 2호선 경유, 동해선 도착.
      ['남포', '센텀시티', '태화강'],
      // 이름 다른 환승(벡스코)을 포함한 구간.
      ['장산', '벡스코(시립미술관)', '일광'],
      // 서로 다른 권역 — 구간마다 환승이 필요한 케이스.
      ['가야대', '덕천', '안평'],
    ];

    for (final names in cases) {
      test(names.join(' → '), () {
        final stops = stopsFor(names);
        for (var i = 0; i < names.length; i++) {
          expect(stops[i], isNotEmpty, reason: '${names[i]} 노드가 그래프에 있어야 한다');
        }

        final dp = finder.findShortestPathVia(stops);
        expect(dp, isNotNull, reason: '경유 경로를 찾아야 한다');

        final brute = bruteForceCost(stops);
        expect(brute, isNotNull);

        // DP 의 조립 총시간은 구간 합과 정차시간 계산 방식이 미세하게 다르다
        // (경유역 노드가 이어붙인 뒤 "중간 노드"가 되어 정차 30초가 붙는다).
        // 경유역 개수 × dwell 만큼의 오차를 허용하고, 그 이상 나쁘면 실패.
        final slack = (names.length - 2) * 30;
        expect(
          dp!.totalTimeSeconds,
          lessThanOrEqualTo(brute! + slack),
          reason: 'DP 결과(${dp.totalTimeSeconds}초)가 전수탐색 최적'
              '($brute초, 허용오차 $slack초)보다 나쁘면 플랫폼 선택 로직 회귀',
        );

        // 경유역을 실제로 지나야 한다.
        final passed = dp.nodeIds.map((id) => graph.nodes[id]?.stationName).toSet();
        for (final name in names) {
          expect(passed, contains(name), reason: '$name 을 지나야 한다');
        }
      });
    }

    test('경유역 3개도 전수탐색 최적 이하', () {
      final names = ['다대포해수욕장', '서면', '연산', '동래', '노포'];
      final stops = stopsFor(names);

      final dp = finder.findShortestPathVia(stops);
      expect(dp, isNotNull);

      final brute = bruteForceCost(stops);
      expect(brute, isNotNull);
      expect(
        dp!.totalTimeSeconds,
        lessThanOrEqualTo(brute! + (names.length - 2) * 30),
      );
    });
  });
}
