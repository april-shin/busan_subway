import 'dart:collection';

import '../../domain/entities/connection.dart';
import 'line_direction.dart';

/// 출발역 상류 하이라이트 기본 상한(정거장 수).
///
/// 실시간 도착 API 는 배차에 따라 2번째 접근 열차를 최대 ~7정거장(≈9.5분) 전까지
/// 보고하는 것이 관측됐다. 여유(+margin)를 두어 10정거장으로 잡는다. 이 상한이
/// 없으면 순환선(2호선)에서 상류 BFS 가 루프 보완 호 전체(≈노선 전체)를 수집해
/// 사실상 노선 전체가 밝아진다. 상한을 두면 접근 열차 라벨은 유지하면서 먼
/// 루프 구간은 흐려진다.
const int kDefaultUpstreamMaxHops = 10;

/// 출발 노선에서 출발역 **상류**(경로 진행 방향의 반대, 즉 출발역으로 열차가
/// 들어오는 쪽) 역 ID 집합을 반환한다.
///
/// 지도에서 출발역 상류 역 이름 라벨을 밝게 유지하기 위한 용도다. 출발역으로
/// 다가오는 실시간 열차의 위치를 라벨로 파악할 수 있어야 하기 때문이며, 실시간
/// 도착 API 는 배차에 따라 6~7정거장 전 열차까지 보고할 수 있으므로 상류는
/// 홉 수로 제한하지 않고 노선 끝(또는 경로 경계)까지 확장한다.
///
/// 알고리즘:
///  1. `routeNextId` 로 경로 진행 방향([isDownBetween])을 구하고, 그 **반대**
///     방향의 단방향 인접 리스트를 만든다. (경로 방향 엣지는 넣지 않으므로
///     출발역에서 하류로 새어나가지 않는다.)
///  2. `routeStationIds`(경로에 포함된 역)와 출발역을 `visited` 에 선점한 뒤
///     출발역에서 상류 방향 BFS. 경로역을 만나면 멈춘다.
///
/// `routeStationIds` 선점은 **순환선(2호선)** 에서 상류 BFS 가 루프를 한 바퀴
/// 돌아 경로 구간 너머까지 수집하는 것을 막는 경계 역할을 한다. 선형 노선에서는
/// 경로역이 모두 하류라 상류 BFS 가 도달하지 않으므로 영향이 없다.
///
/// 방향 판정에 [isDownBetween] 을 재사용하므로 2호선 순환 경계, 급행 가상 노선
/// (`{base}E`) base 정규화, 9호선/공항철도 라벨 반전 규칙이 경로 방향·엣지 방향
/// 양쪽에 동일하게 적용되어 상쇄된다(= 노선 특수 규칙과 무관하게 항상 올바른
/// 상류 방향).
///
/// [lineId] 는 base 노선 ID(예: `'2'`, `'9'`) 여야 한다. [connections] 는 전체
/// 연결 목록을 넘겨도 되며, 해당 노선의 비환승 연결만 사용한다.
Set<String> departureUpstreamStationIds({
  required List<Connection> connections,
  required String lineId,
  required String departureId,
  required String routeNextId,
  required Set<String> routeStationIds,
  int maxHops = kDefaultUpstreamMaxHops,
}) {
  if (maxHops <= 0) return const {};

  final routeIsDown = isDownBetween(departureId, routeNextId, lineId);
  final upstreamIsDown = !routeIsDown;

  // 상류 방향 단방향 인접 리스트 구성.
  final adjacency = <String, List<String>>{};
  for (final c in connections) {
    if (c.isTransfer) continue;
    if (c.lineId != lineId) continue;
    final edgeIsDown = isDownBetween(c.fromStationId, c.toStationId, lineId);
    if (edgeIsDown == upstreamIsDown) {
      adjacency.putIfAbsent(c.fromStationId, () => []).add(c.toStationId);
    } else {
      adjacency.putIfAbsent(c.toStationId, () => []).add(c.fromStationId);
    }
  }

  final upstream = <String>{};
  // 경로역 + 출발역 선점: 하류 유출 차단 + 순환선에서 경로 구간 재유입 차단.
  final visited = <String>{...routeStationIds, departureId};
  // BFS 로 출발역에서 홉 수를 세며 상류 방향으로 확장. [maxHops] 홉까지만 수집해
  // 순환선(2호선)에서 루프 보완 호 전체가 밝아지는 것을 막는다. (홉 수 = 정거장 수)
  final queue = Queue<(String id, int hops)>()..add((departureId, 0));
  while (queue.isNotEmpty) {
    final (id, hops) = queue.removeFirst();
    if (hops >= maxHops) continue;
    for (final nb in adjacency[id] ?? const <String>[]) {
      if (!visited.add(nb)) continue;
      upstream.add(nb);
      queue.add((nb, hops + 1));
    }
  }
  return upstream;
}
