class GraphEdge {
  final String fromNodeId;
  final String toNodeId;
  final String lineId;
  final int weightSeconds;
  final bool isTransfer;
  // 급행 운영 구간이면 양 끝역 간 급행 소요시간(초). 양쪽 모두 급행 정차역일 때만 채워진다.
  // null이면 해당 구간은 급행 미운영 → 완행 시간 사용.
  // Dijkstra 가중치에는 사용되지 않으며, 세그먼트 빌드 단계에서 급행 환산 시간 계산에만 쓰인다.
  final int? expressWeightSeconds;

  const GraphEdge({
    required this.fromNodeId,
    required this.toNodeId,
    required this.lineId,
    required this.weightSeconds,
    this.isTransfer = false,
    this.expressWeightSeconds,
  });

  @override
  String toString() =>
      'GraphEdge($fromNodeId -> $toNodeId, ${weightSeconds}s, line=$lineId, transfer=$isTransfer, expressWeight=$expressWeightSeconds)';
}
