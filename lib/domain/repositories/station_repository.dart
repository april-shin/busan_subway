import '../entities/station.dart';
import '../entities/line.dart';
import '../entities/connection.dart';

abstract class StationRepository {
  Future<List<Station>> getAllStations();
  Future<List<Line>> getAllLines();
  Future<List<Connection>> getAllConnections();
  Future<List<Station>> searchStations(String query);
  Future<Station?> getStationById(String id);
  Future<List<Station>> getStationsByLine(String lineId);
  Future<Map<String, int>> getTransferTimes();
}
