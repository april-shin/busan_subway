import 'package:collection/collection.dart';

import '../core/constants/dwell_time.dart';
import 'models/graph_edge.dart';
import 'subway_graph.dart';

class PathResult {
  final List<String> nodeIds;
  final List<GraphEdge> edges;
  final int totalTimeSeconds;
  final int totalDwellTimeSeconds;

  const PathResult({
    required this.nodeIds,
    required this.edges,
    required this.totalTimeSeconds,
    this.totalDwellTimeSeconds = 0,
  });
}

class ShortestPathFinder {
  final SubwayGraph graph;

  const ShortestPathFinder({required this.graph});

  /// Dijkstra 단일 출발-도착 최단 경로.
  ///
  /// [nodeFilter]가 주어지면 출발/도착/탐색 중간 노드 모두 필터를 통과해야 방문된다.
  /// 즉 필터 false인 노드는 그래프에서 제외된 것처럼 동작한다.
  /// 이 옵션은 "급행 단독(`_E` 노드만)" 또는 "완행 단독(base 노드만)" 경로 비교용이다.
  PathResult? findShortestPath(
    String fromNodeId,
    String toNodeId, {
    int transferPenalty = 0,
    bool Function(String nodeId)? nodeFilter,
  }) {
    if (!graph.containsNode(fromNodeId) || !graph.containsNode(toNodeId)) {
      return null;
    }
    if (nodeFilter != null &&
        (!nodeFilter(fromNodeId) || !nodeFilter(toNodeId))) {
      return null;
    }

    if (fromNodeId == toNodeId) {
      return PathResult(
        nodeIds: [fromNodeId],
        edges: [],
        totalTimeSeconds: 0,
      );
    }

    final distances = <String, int>{};
    final previous = <String, String?>{};
    final previousEdge = <String, GraphEdge?>{};
    final visited = <String>{};

    final queue = PriorityQueue<_QueueEntry>(
      (a, b) => a.distance.compareTo(b.distance),
    );

    for (final nodeId in graph.nodes.keys) {
      distances[nodeId] = _infinity;
      previous[nodeId] = null;
      previousEdge[nodeId] = null;
    }

    distances[fromNodeId] = 0;
    queue.add(_QueueEntry(nodeId: fromNodeId, distance: 0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();

      if (visited.contains(current.nodeId)) continue;
      visited.add(current.nodeId);

      if (current.nodeId == toNodeId) break;

      for (final edge in graph.getNeighbors(current.nodeId)) {
        if (visited.contains(edge.toNodeId)) continue;
        if (nodeFilter != null && !nodeFilter(edge.toNodeId)) continue;

        final penalty = (transferPenalty > 0 && edge.isTransfer)
            ? transferPenalty
            : 0;
        final newDistance =
            distances[current.nodeId]! + edge.weightSeconds + penalty;

        if (newDistance < distances[edge.toNodeId]!) {
          distances[edge.toNodeId] = newDistance;
          previous[edge.toNodeId] = current.nodeId;
          previousEdge[edge.toNodeId] = edge;
          queue.add(_QueueEntry(nodeId: edge.toNodeId, distance: newDistance));
        }
      }
    }

    if (distances[toNodeId] == _infinity) return null;

    final path = <String>[];
    final edges = <GraphEdge>[];
    String? current = toNodeId;

    while (current != null) {
      path.add(current);
      final edge = previousEdge[current];
      if (edge != null) edges.add(edge);
      current = previous[current];
    }

    return _assemblePath(path.reversed.toList(), edges.reversed.toList());
  }

  /// 복수 출발/도착 노드 Dijkstra (multi-source / multi-sink).
  ///
  /// 환승역은 같은 물리적 플랫폼 집합이므로, 출발/도착이 환승역이면
  /// 해당 역의 모든 노선 노드(`218_2`, `930_9` 등)를 **동시에 거리 0으로 시작**
  /// 하거나 "먼저 도달한" 도착 후보로 종료해야 한다. 그렇지 않으면 picker 가
  /// 저장한 대표 노선(`218_2`)에서 시작해 필요 노선(`930_9`)으로 넘어가는
  /// **가짜 환승**이 경로에 삽입되어 세그먼트/환승 카운트가 오염된다.
  ///
  /// 알고리즘:
  ///   1. [fromNodeIds] 의 모든 노드를 distance=0 으로 초기화하여 큐에 푸시.
  ///   2. 일반 Dijkstra 진행.
  ///   3. 큐에서 꺼낸 노드가 [toNodeIds] 에 속하면 그 노드를 종점으로 경로 복원.
  ///
  /// 결과 경로는 실제로 선택된 시작점 → 선택된 종점 1쌍의 최단 경로이며
  /// 환승 세그먼트는 "실제로 플랫폼을 이동한" 환승 edge 만 포함한다.
  PathResult? findShortestPathMulti(
    Set<String> fromNodeIds,
    Set<String> toNodeIds, {
    int transferPenalty = 0,
    bool Function(String nodeId)? nodeFilter,
  }) {
    final validFromIds = fromNodeIds.where((id) =>
        graph.containsNode(id) &&
        (nodeFilter == null || nodeFilter(id))).toSet();
    final validToIds = toNodeIds.where((id) =>
        graph.containsNode(id) &&
        (nodeFilter == null || nodeFilter(id))).toSet();
    if (validFromIds.isEmpty || validToIds.isEmpty) return null;

    // 출발·도착이 같은 물리역(예: 출발역=도착역)이면 거리 0.
    final overlap = validFromIds.intersection(validToIds);
    if (overlap.isNotEmpty) {
      final id = overlap.first;
      return PathResult(nodeIds: [id], edges: [], totalTimeSeconds: 0);
    }

    final distances = <String, int>{};
    final previous = <String, String?>{};
    final previousEdge = <String, GraphEdge?>{};
    final visited = <String>{};

    final queue = PriorityQueue<_QueueEntry>(
      (a, b) => a.distance.compareTo(b.distance),
    );

    for (final nodeId in graph.nodes.keys) {
      distances[nodeId] = _infinity;
      previous[nodeId] = null;
      previousEdge[nodeId] = null;
    }

    // 모든 시작점을 거리 0 으로 동시 시작.
    for (final fromId in validFromIds) {
      distances[fromId] = 0;
      queue.add(_QueueEntry(nodeId: fromId, distance: 0));
    }

    String? reachedToId;
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (visited.contains(current.nodeId)) continue;
      visited.add(current.nodeId);

      // 도착 후보 집합에 포함되면 종료.
      if (validToIds.contains(current.nodeId)) {
        reachedToId = current.nodeId;
        break;
      }

      for (final edge in graph.getNeighbors(current.nodeId)) {
        if (visited.contains(edge.toNodeId)) continue;
        if (nodeFilter != null && !nodeFilter(edge.toNodeId)) continue;

        final penalty = (transferPenalty > 0 && edge.isTransfer)
            ? transferPenalty
            : 0;
        final newDistance =
            distances[current.nodeId]! + edge.weightSeconds + penalty;

        if (newDistance < distances[edge.toNodeId]!) {
          distances[edge.toNodeId] = newDistance;
          previous[edge.toNodeId] = current.nodeId;
          previousEdge[edge.toNodeId] = edge;
          queue.add(_QueueEntry(nodeId: edge.toNodeId, distance: newDistance));
        }
      }
    }

    if (reachedToId == null) return null;

    final path = <String>[];
    final edges = <GraphEdge>[];
    String? current = reachedToId;
    while (current != null) {
      path.add(current);
      final edge = previousEdge[current];
      if (edge != null) edges.add(edge);
      current = previous[current];
    }

    return _assemblePath(path.reversed.toList(), edges.reversed.toList());
  }

  /// 경유지를 포함한 다구간 최단 경로.
  ///
  /// [stops] 는 `[출발후보, 경유1후보, …, 도착후보]` 순서의 노드 후보 집합 목록이다.
  /// 각 원소는 한 물리 역의 노선별 노드 집합(환승역이면 소속 노선 노드 전부 + 가상
  /// 급행 노드)이며, 구성 규칙은 [findShortestPathMulti] 문서와 동일하다.
  ///
  /// 구간마다 [findShortestPathMulti] 를 호출해 이어 붙인다. 앞 구간이 도달한 노드를
  /// 다음 구간의 **유일한 출발 노드**로 고정하므로 edge 열에 빈틈이 없고, 경유역에서
  /// 노선을 바꿔야 하면 다음 구간 Dijkstra 가 그 역의 환승 edge 를 자연히 포함한다.
  /// 따라서 결과는 단일 경로와 완전히 같은 형태이며 세그먼트·환승 카운트 계산도
  /// 그대로 재사용할 수 있다.
  ///
  /// 경유역에서 **어느 노선 플랫폼에 서는지**는 그리디로 정하면 안 된다. 앞 구간
  /// 비용만 보고 가장 싸게 닿는 플랫폼에 고정하면, 뒤 구간이 그 플랫폼에서 출발해야
  /// 해서 훨씬 나쁜 경로가 나온다.
  ///
  /// > 실제 사례: 신논현 →[강남, 선릉]→ 왕십리.
  /// > 선릉에 가장 싸게 닿는 플랫폼은 2호선(강남에서 2정거장)이지만, 2호선 선릉에서
  /// > 왕십리로 가려면 순환선을 12정거장 돌아 37.7분이 된다. 선릉을 수인분당선
  /// > 플랫폼으로 잡으면(강남에서 2호선 2정거장 + 선릉 환승) 왕십리까지 5정거장,
  /// > 총 33.7분이다.
  ///
  /// 그래서 정차역마다 **모든 플랫폼 후보를 상태로 남기는 DP** 로 푼다.
  /// `dp[정차역 i][노드 X]` = "출발에서 경유 1..i 를 순서대로 지나 노드 X 에서 끝나는
  /// 최소비용 경로". 각 단계에서 (이전 상태 × 현재 후보) 쌍마다 구간 Dijkstra 를
  /// 돌려 최소를 취한다. 후보 수는 역당 소수(플랫폼 + 가상 급행 노드)이고 경유역
  /// 개수도 UI 에서 제한되므로 비용은 실측 기준 수십 ms 수준이다.
  ///
  /// 비용 척도는 구간 Dijkstra 가 최적화하는 것과 같게 맞춘다 —
  /// `구간 소요시간 + transferPenalty × 구간 내 환승 edge 수`. [transferPenalty] 가
  /// 0 인 기본(최단시간) 모드에서는 순수 소요시간이 되고, 최소환승 모드에서는
  /// 구간 경계를 넘어서도 환승 수가 우선된다.
  ///
  /// 경유지가 없으면([stops].length == 2) [findShortestPathMulti] 와 동일하게 위임한다.
  /// [stops] 가 2개 미만이거나 어느 한 구간이라도 경로가 없으면 null.
  PathResult? findShortestPathVia(
    List<Set<String>> stops, {
    int transferPenalty = 0,
    bool Function(String nodeId)? nodeFilter,
  }) {
    if (stops.length < 2) return null;
    if (stops.length == 2) {
      return findShortestPathMulti(
        stops.first,
        stops.last,
        transferPenalty: transferPenalty,
        nodeFilter: nodeFilter,
      );
    }

    /// 구간 하나의 DP 비용 — 구간 Dijkstra 의 목적함수와 동일한 형태.
    int legCost(PathResult leg) =>
        leg.totalTimeSeconds +
        (transferPenalty > 0
            ? transferPenalty * leg.edges.where((e) => e.isTransfer).length
            : 0);

    // 1단계: 출발 후보 집합(multi-source) → 첫 경유역의 각 플랫폼 후보.
    var dp = <String, _ViaState>{};
    for (final target in stops[1]) {
      final leg = findShortestPathMulti(
        stops.first,
        {target},
        transferPenalty: transferPenalty,
        nodeFilter: nodeFilter,
      );
      if (leg == null) continue;
      dp[leg.nodeIds.last] = _ViaState(
        cost: legCost(leg),
        nodeIds: leg.nodeIds,
        edges: leg.edges,
      );
    }
    if (dp.isEmpty) return null;

    // 2단계 이후: 이전 상태의 종점 노드에서 출발해 현재 정차역의 각 후보로.
    for (var i = 2; i < stops.length; i++) {
      final next = <String, _ViaState>{};
      for (final prev in dp.entries) {
        for (final target in stops[i]) {
          final leg = findShortestPathMulti(
            {prev.key},
            {target},
            transferPenalty: transferPenalty,
            nodeFilter: nodeFilter,
          );
          if (leg == null) continue;
          final endNode = leg.nodeIds.last;
          final cost = prev.value.cost + legCost(leg);
          final existing = next[endNode];
          if (existing != null && existing.cost <= cost) continue;
          next[endNode] = prev.value.append(leg, cost);
        }
      }
      if (next.isEmpty) return null;
      dp = next;
    }

    _ViaState? best;
    for (final state in dp.values) {
      if (best == null || state.cost < best.cost) best = state;
    }
    return _assemblePath(best!.nodeIds, best.edges);
  }

  /// 노드/엣지 열로 [PathResult] 를 조립한다(이동시간 + 중간역 정차시간).
  ///
  /// 정차시간은 출발·도착 노드와 **환승 인접 노드**를 제외한 중간 노드 수 ×
  /// [dwellTimeSeconds]. 환승 인접 노드를 빼는 이유는 환승 edge 의 가중치가 이미
  /// 도보+대기 시간을 포함하므로 정차시간을 이중 계상하지 않기 위함이다.
  static PathResult _assemblePath(
    List<String> nodeIds,
    List<GraphEdge> edges,
  ) {
    final travelTime = edges.fold(0, (sum, edge) => sum + edge.weightSeconds);

    final transferAdjacentNodes = <int>{};
    for (var i = 0; i < edges.length; i++) {
      if (edges[i].isTransfer) {
        transferAdjacentNodes.add(i); // 환승 직전 노드
        transferAdjacentNodes.add(i + 1); // 환승 직후 노드
      }
    }
    var dwellCount = 0;
    for (var i = 1; i < nodeIds.length - 1; i++) {
      if (!transferAdjacentNodes.contains(i)) dwellCount++;
    }
    final dwellTime = dwellCount * dwellTimeSeconds;

    return PathResult(
      nodeIds: nodeIds,
      edges: edges,
      totalTimeSeconds: travelTime + dwellTime,
      totalDwellTimeSeconds: dwellTime,
    );
  }

  /// 두 역 사이의 최단 경로(들)를 반환한다.
  ///
  /// [nodeFilter]가 주어지면 시작/도착 후보 노드뿐 아니라 Dijkstra가 방문하는
  /// **모든 노드**를 필터링한다. 즉 필터 false인 노드는 그래프에서 제외된 것처럼
  /// 동작한다. "급행 단독(_E 노드만)" 또는 "완행 단독(base 노드만)" 경로 비교용이다.
  ///
  /// 예) `nodeFilter: (id) => id.endsWith('E')` — 가상 급행 노선(`{base}E`) 노드만 사용.
  ///     시작역 또는 도착역에 `_E` 노드가 없으면 결과는 빈 리스트.
  List<PathResult> findShortestPathBetweenStations(
    String fromStationName,
    String toStationName, {
    bool Function(String nodeId)? nodeFilter,
  }) {
    final fromNodeIds = graph
        .getNodeIdsForStation(fromStationName)
        .where((id) => nodeFilter == null || nodeFilter(id))
        .toList();
    final toNodeIds = graph
        .getNodeIdsForStation(toStationName)
        .where((id) => nodeFilter == null || nodeFilter(id))
        .toList();

    if (fromNodeIds.isEmpty || toNodeIds.isEmpty) return [];

    final results = <PathResult>[];

    for (final fromId in fromNodeIds) {
      for (final toId in toNodeIds) {
        final result = findShortestPath(
          fromId,
          toId,
          nodeFilter: nodeFilter,
        );
        if (result != null) results.add(result);
      }
    }

    results.sort((a, b) => a.totalTimeSeconds.compareTo(b.totalTimeSeconds));
    return results;
  }

  /// 환승 횟수를 최소화한 경로를 반환한다.
  /// 환승 엣지에 큰 페널티를 부여하여 환승을 피하도록 유도하고,
  /// 동일 환승 횟수 내에서는 시간이 짧은 경로를 선택한다.
  ///
  /// [nodeFilter] 동작은 [findShortestPathBetweenStations]와 동일.
  List<PathResult> findMinTransferPathBetweenStations(
    String fromStationName,
    String toStationName, {
    bool Function(String nodeId)? nodeFilter,
  }) {
    final fromNodeIds = graph
        .getNodeIdsForStation(fromStationName)
        .where((id) => nodeFilter == null || nodeFilter(id))
        .toList();
    final toNodeIds = graph
        .getNodeIdsForStation(toStationName)
        .where((id) => nodeFilter == null || nodeFilter(id))
        .toList();

    if (fromNodeIds.isEmpty || toNodeIds.isEmpty) return [];

    final results = <PathResult>[];

    for (final fromId in fromNodeIds) {
      for (final toId in toNodeIds) {
        final result = findShortestPath(
          fromId,
          toId,
          transferPenalty: _transferPenalty,
          nodeFilter: nodeFilter,
        );
        if (result != null) results.add(result);
      }
    }

    results.sort((a, b) {
      final transferA =
          a.edges.where((e) => e.isTransfer).length;
      final transferB =
          b.edges.where((e) => e.isTransfer).length;
      final cmp = transferA.compareTo(transferB);
      if (cmp != 0) return cmp;
      return a.totalTimeSeconds.compareTo(b.totalTimeSeconds);
    });
    return results;
  }

  static const int _transferPenalty = 100000;
  static const int _infinity = 999999999;
}

/// [ShortestPathFinder.findShortestPathVia] 의 DP 상태.
///
/// "출발에서 여기까지 이어붙인 경로"를 누적 비용과 함께 들고 다닌다. `nodeIds` 의
/// 마지막 원소가 이 상태의 종점(= 다음 구간의 출발 노드)이다.
class _ViaState {
  final int cost;
  final List<String> nodeIds;
  final List<GraphEdge> edges;

  const _ViaState({
    required this.cost,
    required this.nodeIds,
    required this.edges,
  });

  /// 이 상태 뒤에 [leg] 를 이어붙인 새 상태.
  ///
  /// [leg] 의 첫 노드는 이 상태의 종점과 같으므로 빼고 잇는다. 경유역이 직전
  /// 정차역과 같아 0-edge 구간이 되면 아무것도 추가되지 않는다.
  _ViaState append(PathResult leg, int newCost) => _ViaState(
        cost: newCost,
        nodeIds: [...nodeIds, ...leg.nodeIds.skip(1)],
        edges: [...edges, ...leg.edges],
      );
}

class _QueueEntry {
  final String nodeId;
  final int distance;

  const _QueueEntry({required this.nodeId, required this.distance});
}
