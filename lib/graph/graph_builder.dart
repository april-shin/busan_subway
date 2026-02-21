import '../domain/entities/station.dart';
import '../domain/entities/connection.dart';
import 'models/graph_edge.dart';
import 'models/graph_node.dart';
import 'subway_graph.dart';

class GraphBuilder {
  SubwayGraph build({
    required List<Station> stations,
    required List<Connection> connections,
    required Map<String, int> transferTimes,
  }) {
    final graph = SubwayGraph();

    _addStationNodes(graph, stations);
    _addConnectionEdges(graph, connections);
    _addTransferEdges(graph, stations, transferTimes);

    return graph;
  }

  void _addStationNodes(SubwayGraph graph, List<Station> stations) {
    for (final station in stations) {
      final nodeId = '${station.id}_${station.lineId}';
      graph.addNode(GraphNode(
        id: nodeId,
        stationName: station.name,
        lineId: station.lineId,
      ));
    }
  }

  void _addConnectionEdges(SubwayGraph graph, List<Connection> connections) {
    for (final connection in connections) {
      if (connection.isTransfer) continue;

      final fromNodeId = '${connection.fromStationId}_${connection.lineId}';
      final toNodeId = '${connection.toStationId}_${connection.lineId}';

      graph.addBidirectionalEdge(GraphEdge(
        fromNodeId: fromNodeId,
        toNodeId: toNodeId,
        lineId: connection.lineId,
        weightSeconds: connection.travelTimeSeconds,
      ));
    }
  }

  void _addTransferEdges(
    SubwayGraph graph,
    List<Station> stations,
    Map<String, int> transferTimes,
  ) {
    final transferStations = <String, List<Station>>{};

    for (final station in stations) {
      if (station.isTransfer) {
        transferStations.putIfAbsent(station.name, () => []).add(station);
      }
    }

    for (final entry in transferStations.entries) {
      final stationName = entry.key;
      final stationVariants = entry.value;

      for (var i = 0; i < stationVariants.length; i++) {
        for (var j = i + 1; j < stationVariants.length; j++) {
          final from = stationVariants[i];
          final to = stationVariants[j];

          final fromNodeId = '${from.id}_${from.lineId}';
          final toNodeId = '${to.id}_${to.lineId}';

          final transferKey = '${stationName}_${from.lineId}_${to.lineId}';
          final reverseKey = '${stationName}_${to.lineId}_${from.lineId}';

          final transferTime =
              transferTimes[transferKey] ?? transferTimes[reverseKey] ?? 180;

          graph.addBidirectionalEdge(GraphEdge(
            fromNodeId: fromNodeId,
            toNodeId: toNodeId,
            lineId: 'transfer',
            weightSeconds: transferTime,
            isTransfer: true,
          ));
        }
      }
    }
  }
}
