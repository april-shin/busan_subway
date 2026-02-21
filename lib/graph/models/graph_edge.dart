class GraphEdge {
  final String fromNodeId;
  final String toNodeId;
  final String lineId;
  final int weightSeconds;
  final bool isTransfer;

  const GraphEdge({
    required this.fromNodeId,
    required this.toNodeId,
    required this.lineId,
    required this.weightSeconds,
    this.isTransfer = false,
  });

  @override
  String toString() =>
      'GraphEdge($fromNodeId -> $toNodeId, ${weightSeconds}s, line=$lineId, transfer=$isTransfer)';
}
