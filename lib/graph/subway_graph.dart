import 'models/graph_edge.dart';
import 'models/graph_node.dart';

class SubwayGraph {
  final Map<String, GraphNode> _nodes = {};
  final Map<String, List<GraphEdge>> _adjacencyList = {};

  Map<String, GraphNode> get nodes => Map.unmodifiable(_nodes);

  void addNode(GraphNode node) {
    _nodes[node.id] = node;
    _adjacencyList.putIfAbsent(node.id, () => []);
  }

  void addEdge(GraphEdge edge) {
    _adjacencyList.putIfAbsent(edge.fromNodeId, () => []);
    _adjacencyList[edge.fromNodeId]!.add(edge);
  }

  void addBidirectionalEdge(GraphEdge edge) {
    addEdge(edge);
    addEdge(GraphEdge(
      fromNodeId: edge.toNodeId,
      toNodeId: edge.fromNodeId,
      lineId: edge.lineId,
      weightSeconds: edge.weightSeconds,
      isTransfer: edge.isTransfer,
    ));
  }

  List<GraphEdge> getNeighbors(String nodeId) {
    return _adjacencyList[nodeId] ?? [];
  }

  GraphNode? getNode(String nodeId) => _nodes[nodeId];

  bool containsNode(String nodeId) => _nodes.containsKey(nodeId);

  int get nodeCount => _nodes.length;

  int get edgeCount =>
      _adjacencyList.values.fold(0, (sum, edges) => sum + edges.length);

  List<String> getNodeIdsForStation(String stationName) {
    return _nodes.values
        .where((node) => node.stationName == stationName)
        .map((node) => node.id)
        .toList();
  }
}
