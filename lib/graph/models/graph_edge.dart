class GraphEdge {
  final String fromNodeId;
  final String toNodeId;
  final String lineId;
  final int weightSeconds;
  final bool isTransfer;

  // 환승 edge의 "도보시간"(초)만 담는 필드. UI 표시 전용이며 Dijkstra 가중치에는
  // 절대 사용되지 않는다(라우팅 비용은 `weightSeconds` = 도보+대기 그대로 사용).
  // - 일반 환승 edge: transferTime(도보) 값.
  // - 모드전환(급행↔완행) edge: 0(같은 승강장, 도보 없음).
  // - 일반 구간 edge: 0(기본값).
  // 세그먼트 빌드 단계에서 `transferWalkDurations`로 수집되어, 결과 화면의
  // "환승 N분" 라벨을 대기 제외 도보시간만으로 표시하는 데 쓰인다.
  final int transferWalkSeconds;

  const GraphEdge({
    required this.fromNodeId,
    required this.toNodeId,
    required this.lineId,
    required this.weightSeconds,
    this.isTransfer = false,
    this.transferWalkSeconds = 0,
  });

  @override
  String toString() =>
      'GraphEdge($fromNodeId -> $toNodeId, ${weightSeconds}s, line=$lineId, transfer=$isTransfer, transferWalk=$transferWalkSeconds)';
}
