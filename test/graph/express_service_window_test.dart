// 급행 운행 시간대 게이트 회귀 가드.
//
// 배경: 1호선 경부선 급행은 계통이 둘이고 성격이 정반대다.
//   · A급행 — 청량리 착발, 경부2선. 평일 47편성으로 하루 종일 운행. 금정 정차.
//   · B급행 — 지상 서울역 착발, 경부1선. **평일 3편성뿐**(상행 2·하행 1).
//     경부1선에 승강장이 없는 역이 많아 금정·신도림·구로까지 통과한다.
//
// B급행은 통과역이 많은 만큼 A급행보다 빠르다(영등포~수원 33분 vs 38.5분).
// 그래서 시각 개념이 없던 그래프에서는 Dijkstra 가 **언제 조회하든** B급행을
// 골랐고, 낮 2시에도 아침 3편성뿐인 열차의 소요시간을 안내했다.
//
// 게이트는 `ExpressSkipEdge.serviceWindows` + `GraphBuilder.build(at:)` 조합이다.
// 창이 있는 edge 는 창이 열린 **방향에 대해서만** 그래프에 실린다 — B급행은
// 아침 상행·저녁 하행으로 갈려서, 방향을 나누지 않으면 아침에 저녁 열차를
// 안내하게 된다.
//
// ⚠ `at` 을 넘기지 않으면 게이트가 없다(종전 동작). 시각 개념이 없는 호출과
//   그래프 단위 테스트가 벽시계에 흔들리지 않도록 한 기본값이라, 이 파일의
//   테스트는 전부 시각을 명시한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';
import 'package:seoul_subway/graph/graph_builder.dart';
import 'package:seoul_subway/graph/subway_graph.dart';

/// 서울역(134) — B급행 전용 정차역. A급행도 서지만 그 구간은 전역 정차라
/// skip edge 가 없어, `1E` 노드는 B급행 edge(서울역→용산) 하나에만 매달려 있다.
const _seoulE = '134_1E';

/// 영등포(140) ↔ 금천구청(167) — B급행 전용 skip edge
/// (신도림·구로·가산디지털단지·독산 통과). ID 증가 방향이 하행이다.
const _yeongdeungpoE = '140_1E';
const _geumcheonE = '167_1E';

/// 안양(170) → 금정(1715) — A급행 edge. 상시 운행이라 게이트와 무관하다.
const _anyangE = '170_1E';
const _geumjeongE = '1715_1E';

/// 평일 낮 — B급행 두 방향 모두 닫힘.
final _weekdayNoon = DateTime(2026, 9, 1, 14, 0); // 화요일

/// 평일 아침 — B급행 상행만 열림 (창 05:44~08:09).
final _weekdayMorning = DateTime(2026, 9, 1, 7, 0);

/// 평일 저녁 — B급행 하행만 열림 (창 18:32~20:02).
final _weekdayEvening = DateTime(2026, 9, 1, 19, 0);

/// 토요일 아침 — 창이 있는 계통은 평일 전용이라 닫힘.
final _saturdayMorning = DateTime(2026, 9, 5, 7, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExpressSkipEdge.runsAt', () {
    const always = ExpressSkipEdge(
      lineId: '1',
      fromStationId: '170',
      toStationId: '1715',
      seconds: 210,
    );
    const windowed = ExpressSkipEdge(
      lineId: '1',
      fromStationId: '140',
      toStationId: '167',
      seconds: 480,
      serviceWindows: [
        ExpressServiceWindow(isDown: false, startMinute: 344, endMinute: 489),
        ExpressServiceWindow(isDown: true, startMinute: 1112, endMinute: 1202),
      ],
    );

    test('창이 없으면 언제나 운행한다', () {
      expect(always.runsAt(_weekdayNoon, isDown: true), isTrue);
      expect(always.runsAt(_saturdayMorning, isDown: false), isTrue);
    });

    test('시각을 모르면(at == null) 게이트를 적용하지 않는다', () {
      expect(windowed.runsAt(null, isDown: true), isTrue);
      expect(windowed.runsAt(null, isDown: false), isTrue);
    });

    test('창 안이라도 방향이 다르면 운행하지 않는다', () {
      // 아침은 상행(isDown: false)만.
      expect(windowed.runsAt(_weekdayMorning, isDown: false), isTrue);
      expect(windowed.runsAt(_weekdayMorning, isDown: true), isFalse);
      // 저녁은 하행만.
      expect(windowed.runsAt(_weekdayEvening, isDown: true), isTrue);
      expect(windowed.runsAt(_weekdayEvening, isDown: false), isFalse);
    });

    test('창 밖이면 두 방향 모두 운행하지 않는다', () {
      expect(windowed.runsAt(_weekdayNoon, isDown: true), isFalse);
      expect(windowed.runsAt(_weekdayNoon, isDown: false), isFalse);
    });

    test('경계 시각은 포함한다 (창은 닫힌 구간)', () {
      expect(
        windowed.runsAt(DateTime(2026, 9, 1, 5, 44), isDown: false),
        isTrue,
      );
      expect(
        windowed.runsAt(DateTime(2026, 9, 1, 8, 9), isDown: false),
        isTrue,
      );
      expect(
        windowed.runsAt(DateTime(2026, 9, 1, 8, 10), isDown: false),
        isFalse,
      );
    });

    test('창이 있는 계통은 주말에 운행하지 않는다', () {
      expect(windowed.runsAt(_saturdayMorning, isDown: false), isFalse);
      expect(
        windowed.runsAt(DateTime(2026, 9, 6, 7, 0), isDown: false),
        isFalse,
      );
    });
  });

  group('GraphBuilder — 실제 에셋에 게이트 적용', () {
    late SubwayGraph Function(DateTime? at) buildAt;

    setUpAll(() async {
      final repo = StationRepositoryImpl(localDataSource: LocalDataSource());
      final stations = await repo.getAllStations();
      final connections = await repo.getAllConnections();
      final transferTimes = await repo.getTransferTimes();
      final expressSkipEdges = await repo.getExpressSkipEdges();
      buildAt = (at) => GraphBuilder().build(
            stations: stations,
            connections: connections,
            transferTimes: transferTimes,
            expressSkipEdges: expressSkipEdges,
            at: at,
          );
    });

    bool hasEdge(SubwayGraph graph, String from, String to) =>
        graph.containsNode(from) &&
        graph.getNeighbors(from).any((e) => e.toNodeId == to);

    test('평일 낮에는 B급행 edge 가 두 방향 모두 사라진다', () {
      final graph = buildAt(_weekdayNoon);
      expect(hasEdge(graph, _yeongdeungpoE, _geumcheonE), isFalse);
      expect(hasEdge(graph, _geumcheonE, _yeongdeungpoE), isFalse);
    });

    test('평일 낮에도 A급행 edge 는 양방향 그대로다', () {
      final graph = buildAt(_weekdayNoon);
      expect(hasEdge(graph, _anyangE, _geumjeongE), isTrue);
      expect(hasEdge(graph, _geumjeongE, _anyangE), isTrue);
    });

    test('평일 아침에는 B급행 상행만 열린다', () {
      final graph = buildAt(_weekdayMorning);
      // 금천구청 → 영등포 = 상행.
      expect(hasEdge(graph, _geumcheonE, _yeongdeungpoE), isTrue);
      expect(hasEdge(graph, _yeongdeungpoE, _geumcheonE), isFalse);
    });

    test('평일 저녁에는 B급행 하행만 열린다', () {
      final graph = buildAt(_weekdayEvening);
      expect(hasEdge(graph, _yeongdeungpoE, _geumcheonE), isTrue);
      expect(hasEdge(graph, _geumcheonE, _yeongdeungpoE), isFalse);
    });

    test('주말 아침에는 B급행이 열리지 않는다', () {
      final graph = buildAt(_saturdayMorning);
      expect(hasEdge(graph, _geumcheonE, _yeongdeungpoE), isFalse);
      expect(hasEdge(graph, _yeongdeungpoE, _geumcheonE), isFalse);
    });

    test('두 방향 모두 닫힌 edge 는 급행 노드도 만들지 않는다', () {
      // 서울역 `1E` 는 B급행 edge(서울역→용산) 하나에만 매달려 있다. 노드만
      // 남기면 갈 곳 없는 노드에 모드전환 대기(1M)만 붙어 경로에 끼어든다.
      expect(buildAt(_weekdayNoon).containsNode(_seoulE), isFalse);
      expect(buildAt(_weekdayMorning).containsNode(_seoulE), isTrue);
      // 영등포는 A급행 정차역이기도 해서 낮에도 노드가 남는다.
      expect(buildAt(_weekdayNoon).containsNode(_yeongdeungpoE), isTrue);
    });

    test('at 을 넘기지 않으면 게이트가 없다 (종전 동작)', () {
      final graph = buildAt(null);
      expect(hasEdge(graph, _yeongdeungpoE, _geumcheonE), isTrue);
      expect(hasEdge(graph, _geumcheonE, _yeongdeungpoE), isTrue);
      expect(graph.containsNode(_seoulE), isTrue);
    });
  });
}
