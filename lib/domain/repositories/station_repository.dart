import '../entities/station.dart';
import '../entities/line.dart';
import '../entities/connection.dart';
import '../entities/express_skip_edge.dart';
import '../entities/transfer_guide.dart';

abstract class StationRepository {
  Future<List<Station>> getAllStations();
  Future<List<Line>> getAllLines();
  Future<List<Connection>> getAllConnections();
  Future<List<Station>> searchStations(String query);
  Future<Station?> getStationById(String id);
  Future<List<Station>> getStationsByLine(String lineId);
  Future<Map<String, int>> getTransferTimes();
  Future<Map<String, TransferGuide>> getTransferGuides();
  Future<List<ExpressSkipEdge>> getExpressSkipEdges();
}
