import '../../domain/entities/arrival_info.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import 'path_on_line.dart';

/// 실시간 도착정보 한 행이 탑승역과 맺는 **위상 관계**.
enum TrainTopology {
  /// 열차의 진행 경로 `현재역 → 행선지` 위에 탑승역이 있다. 정상 열차.
  onRoute,

  /// 탑승역이 열차 앞쪽에 있는데 **행선지가 탑승역에 닿기 전에 끝난다.**
  /// 종착이 노선 중간인 열차(회차·셔틀)를 API 가 종착 너머 역에도 도착 예정으로
  /// 이어 붙인 **유령 행**이다 — 이 열차는 탑승역에 오지 않는다.
  beyondTerminus,

  /// 탑승역이 이미 열차 **뒤**에 있다 — 진행 방향으로는 못 가지만 `탑승역 → 현재역`
  /// 은 닿는다(= 한 줄기 위에서 열차가 탑승역을 지나쳤다). 유령이 **아니다**:
  /// `arvlMsg3`(현재역)가 실제보다 지연·불일치한 실제 열차가 여기 들어오므로
  /// (6호선 신내 6310 실측) 숨기지 않는다.
  ///
  /// ⚠️ **병행 지선은 여기 들어오지 않는다.** 서로 도달 불가(예: 5호선 하행
  /// 탑승역 상일동 · 현재역 둔촌동 + 마천행)는 "지나간" 것이 아니라 "오지 않는"
  /// 열차이므로 [undetermined] 다. 통과시키는 결과는 같지만, 이 값을 "실제
  /// 열차"의 근거로 쓰는 소비자가 생기면 오판하므로 의미를 분리해 둔다.
  passed,

  /// 판정 근거 부족 — 이름이 노선에서 읽히지 않거나, 현재역에서 행선지로 가는
  /// 경로가 구해지지 않는다. 통과시킨다(fail-open).
  undetermined,
}

/// 진행 경로 도달성 질의: [from] 에서 방향 인접 리스트를 따라 [to] 에 닿는가.
typedef ReachFn = bool Function(String from, String to);

/// 열차의 위상 관계를 판정한다 (양성 증거 규칙).
///
/// > 열차의 탑승 방향 진행 경로 `현재역 → 행선지` 위에 **탑승역이 없으면 유령**
///
/// "경로 위"는 **어떤 경로든** 현재역 → 탑승역 → 행선지로 이어지는지로 본다
/// (`reach(cur, B) && reach(B, dest)`). BFS 최단경로 하나만 비교하지 않는 이유는
/// 순환·병행 구간에서 실제 운행 경로가 그 하나와 다를 수 있기 때문이다 — 그
/// 경우 유령이 아닌 열차를 유령으로 오판하는 대신 "경로 위"로 넓게 잡는다.
///
/// 각 이름은 같은 노선에 여러 역 ID 가 대응할 수 있으므로 [currentIds]·
/// [destinationIds] 의 모든 조합을 본다. **하나라도 유령이 아니면 유령이 아니다**
/// (가장 유리한 판정 채택 — `classifyDestinationCoverage` 와 같은 보수성).
///
/// 판정 순서:
///  1. 이름이 안 읽히면([currentIds]/[destinationIds] 비어 있음) → [TrainTopology.undetermined]
///  2. `현재역 → 행선지` 도달 불가 → [TrainTopology.undetermined]
///     (방향·행선지 모순 라벨. 지금처럼 통과시킨다 — 극성 데이터 오류가 "열차
///     전부 흐림/소실"로 증폭되는 걸 막는 fail-open 정책을 지킨다.)
///  3. `현재역 → 탑승역` 도달 불가 → `탑승역 → 현재역` 이 닿으면 [TrainTopology.passed]
///     (열차가 탑승역을 지나쳤다), 둘 다 안 닿으면 [TrainTopology.undetermined]
///     (병행 지선 — 지나간 게 아니라 오지 않는 열차)
///  4. `탑승역 → 행선지` 도달 가능 → [TrainTopology.onRoute]
///  5. 그 외 → [TrainTopology.beyondTerminus]
TrainTopology classifyTrainTopology({
  required List<String> currentIds,
  required List<String> destinationIds,
  required String boardingId,
  required ReachFn reach,
}) {
  if (currentIds.isEmpty || destinationIds.isEmpty) {
    return TrainTopology.undetermined;
  }

  var anyPassed = false;
  var anyBeyond = false;
  var anyParallel = false;
  for (final cur in currentIds) {
    for (final dest in destinationIds) {
      if (!reach(cur, dest)) return TrainTopology.undetermined;
      if (!reach(cur, boardingId)) {
        // 역방향으로 닿아야 "지나친" 것이다. 둘 다 안 닿으면 병행 지선이라
        // 지나친 게 아니므로 passed 로 부르지 않는다(통과 결과는 같다).
        if (reach(boardingId, cur)) {
          anyPassed = true;
        } else {
          anyParallel = true;
        }
        continue;
      }
      if (reach(boardingId, dest)) return TrainTopology.onRoute;
      anyBeyond = true;
    }
  }
  // 모든 조합이 유령이 아님을 "한 번이라도 onRoute 면 즉시 반환"으로 처리했으므로
  // 여기 오면 조합은 passed/beyond 뿐이다. passed 가 섞이면 보수적으로 passed.
  if (anyPassed) return TrainTopology.passed;
  if (anyParallel) return TrainTopology.undetermined;
  if (anyBeyond) return TrainTopology.beyondTerminus;
  return TrainTopology.undetermined;
}

/// 탑승역 기준으로 도착정보 한 행의 [TrainTopology] 를 돌려주는 함수를 만든다.
///
/// [boardingStationId] 는 탑승역의 역 ID(경로 세그먼트의 첫 역), [lineId] 는
/// **base 노선 ID**(가상 급행 `9E` 가 아닌 `9`), [isDown] 은 탑승 방향이다.
///
/// 도달성은 [lineId] 의 비환승 연결로 만든 **방향 인접 리스트**
/// (`buildLineAdjacency`)에서 구하고, 출발점별 BFS 결과를 메모한다 — 같은 현재역의
/// 열차가 여러 대 오고 판정이 열차마다 같은 그래프를 재탐색할 이유가 없다.
///
/// 항상 [TrainTopology.undetermined] 를 돌려주는 경우(fail-open):
///  - [stations]/[connections] 미로딩
///  - 2호선 — 순환선이라 행선지(`bstatnNm`)가 실제 운행 범위를 뜻하지 않고
///    ("성수행" 입고), 순환 인접 리스트에서는 모든 역이 서로 도달 가능해 규칙이
///    성립하지 않는다. `route_branch.dart`·지도 유령 판정과 같은 제외 정책이다.
TrainTopology Function(ArrivalInfo arrival) makeTrainTopologyClassifier({
  required String boardingStationId,
  required String lineId,
  required bool isDown,
  required List<Station> stations,
  required List<Connection> connections,
}) {
  if (lineId == '2' ||
      boardingStationId.isEmpty ||
      stations.isEmpty ||
      connections.isEmpty) {
    return (_) => TrainTopology.undetermined;
  }

  final idsByName = <String, List<String>>{};
  for (final s in stations) {
    if (s.lineId != lineId) continue;
    idsByName.putIfAbsent(s.name, () => []).add(s.id);
  }

  final adjacency = buildLineAdjacency(
    connections: connections,
    lineId: lineId,
    isDown: isDown,
  );

  final reachCache = <String, Set<String>>{};
  Set<String> reachableFrom(String from) {
    return reachCache.putIfAbsent(from, () {
      final seen = <String>{from};
      final stack = <String>[from];
      while (stack.isNotEmpty) {
        final node = stack.removeLast();
        for (final next in adjacency[node] ?? const <String>[]) {
          if (seen.add(next)) stack.add(next);
        }
      }
      return seen;
    });
  }

  bool reach(String from, String to) => reachableFrom(from).contains(to);

  return (arrival) {
    return classifyTrainTopology(
      currentIds: idsByName[arrival.currentStationName] ?? const [],
      destinationIds: idsByName[arrival.destination] ?? const [],
      boardingId: boardingStationId,
      reach: reach,
    );
  };
}

/// 탑승역에 오지 않는 **유령 열차**(종착 너머 도착 예정)인지 판정하는 함수.
///
/// [makeTrainTopologyClassifier] 의 `== TrainTopology.beyondTerminus` 축약.
/// `passed`·`undetermined` 는 유령이 아니다.
bool Function(ArrivalInfo arrival) makeGhostTrainDetector({
  required String boardingStationId,
  required String lineId,
  required bool isDown,
  required List<Station> stations,
  required List<Connection> connections,
}) {
  final classify = makeTrainTopologyClassifier(
    boardingStationId: boardingStationId,
    lineId: lineId,
    isDown: isDown,
    stations: stations,
    connections: connections,
  );
  return (arrival) => classify(arrival) == TrainTopology.beyondTerminus;
}
