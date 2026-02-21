class GraphNode {
  final String id;
  final String stationName;
  final String lineId;

  const GraphNode({
    required this.id,
    required this.stationName,
    required this.lineId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphNode &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GraphNode($id: $stationName [$lineId])';
}
