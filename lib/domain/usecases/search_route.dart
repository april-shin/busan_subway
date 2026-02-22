import '../entities/route_result.dart';
import '../entities/station.dart';
import '../repositories/station_repository.dart';
import '../../graph/graph_builder.dart';
import '../../graph/shortest_path.dart';
import '../../core/constants/line_colors.dart';

class SearchRoute {
  final StationRepository _stationRepository;

  SearchRoute({required StationRepository stationRepository})
      : _stationRepository = stationRepository;

  Future<RouteResult?> execute(String fromStationId, String toStationId) async {
    final stations = await _stationRepository.getAllStations();
    final connections = await _stationRepository.getAllConnections();
    final transferTimes = await _stationRepository.getTransferTimes();

    final graph = GraphBuilder().build(
      stations: stations,
      connections: connections,
      transferTimes: transferTimes,
    );

    final stationMap = {for (final s in stations) s.id: s};

    final fromStation = stationMap[fromStationId];
    final toStation = stationMap[toStationId];
    if (fromStation == null || toStation == null) return null;

    final finder = ShortestPathFinder(graph: graph);
    final results = finder.findShortestPathBetweenStations(
      fromStation.name,
      toStation.name,
    );

    if (results.isEmpty) return null;

    final bestPath = results.first;
    final (:segments, :transferDurations) =
        _buildSegments(bestPath, graph, stationMap);

    return RouteResult(
      segments: segments,
      totalTimeSeconds: bestPath.totalTimeSeconds,
      transferCount: segments.length - 1,
      stationCount:
          segments.fold(0, (sum, seg) => sum + seg.stations.length) -
              (segments.length - 1),
      transferDurations: transferDurations,
    );
  }

  ({List<RouteSegment> segments, List<int> transferDurations}) _buildSegments(
    PathResult path,
    dynamic graph,
    Map<String, Station> stationMap,
  ) {
    if (path.edges.isEmpty) {
      return (segments: <RouteSegment>[], transferDurations: <int>[]);
    }

    final segments = <RouteSegment>[];
    final transferDurations = <int>[];
    var currentLineId = path.edges.first.lineId;
    var currentStations = <Station>[];
    var currentDurationSeconds = 0;

    for (var i = 0; i < path.edges.length; i++) {
      final edge = path.edges[i];

      if (edge.isTransfer) {
        if (currentStations.isNotEmpty) {
          segments.add(_createSegment(
            currentLineId,
            currentStations,
            currentDurationSeconds,
          ));
        }
        transferDurations.add(edge.weightSeconds);
        currentStations = [];
        currentDurationSeconds = 0;
        if (i + 1 < path.edges.length) {
          currentLineId = path.edges[i + 1].lineId;
        }
        continue;
      }

      if (edge.lineId != currentLineId && currentStations.isNotEmpty) {
        segments.add(_createSegment(
          currentLineId,
          currentStations,
          currentDurationSeconds,
        ));
        currentStations = [];
        currentDurationSeconds = 0;
        currentLineId = edge.lineId;
      }

      final fromNodeId = edge.fromNodeId;
      final stationId = fromNodeId.split('_').first;
      final station = stationMap[stationId];
      if (station != null && !currentStations.contains(station)) {
        currentStations.add(station);
      }

      currentDurationSeconds += edge.weightSeconds;

      if (i == path.edges.length - 1) {
        final toNodeId = edge.toNodeId;
        final toStationId = toNodeId.split('_').first;
        final toStation = stationMap[toStationId];
        if (toStation != null) {
          currentStations.add(toStation);
        }
      }
    }

    if (currentStations.isNotEmpty) {
      segments.add(_createSegment(
        currentLineId,
        currentStations,
        currentDurationSeconds,
      ));
    }

    return (
      segments: List.unmodifiable(segments),
      transferDurations: List.unmodifiable(transferDurations),
    );
  }

  RouteSegment _createSegment(
    String lineId,
    List<Station> stations,
    int durationSeconds,
  ) {
    final lineName = lineNames[lineId] ?? lineId;
    final lastStation = stations.isNotEmpty ? stations.last.name : '';

    return RouteSegment(
      lineId: lineId,
      lineName: lineName,
      stations: List.unmodifiable(stations),
      durationSeconds: durationSeconds,
      direction: '$lastStation 방면',
    );
  }
}
