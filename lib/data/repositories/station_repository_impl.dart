import '../../domain/entities/station.dart';
import '../../domain/entities/line.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/transfer_guide.dart';
import '../../domain/repositories/station_repository.dart';
import '../local/local_data_source.dart';

class StationRepositoryImpl implements StationRepository {
  final LocalDataSource _localDataSource;

  StationRepositoryImpl({required LocalDataSource localDataSource})
      : _localDataSource = localDataSource;

  @override
  Future<List<Station>> getAllStations() => _localDataSource.loadStations();

  @override
  Future<List<Line>> getAllLines() => _localDataSource.loadLines();

  @override
  Future<List<Connection>> getAllConnections() =>
      _localDataSource.loadConnections();

  @override
  Future<Map<String, int>> getTransferTimes() =>
      _localDataSource.loadTransferTimes();

  @override
  Future<Map<String, TransferGuide>> getTransferGuides() =>
      _localDataSource.loadTransferGuides();

  @override
  Future<List<Station>> searchStations(String query) async {
    if (query.isEmpty) return [];

    final stations = await _localDataSource.loadStations();
    final lowerQuery = query.toLowerCase();

    return stations
        .where((station) => station.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  @override
  Future<Station?> getStationById(String id) async {
    final stations = await _localDataSource.loadStations();
    try {
      return stations.firstWhere((station) => station.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Station>> getStationsByLine(String lineId) async {
    final stations = await _localDataSource.loadStations();
    return stations
        .where((station) => station.lineId == lineId)
        .toList();
  }
}
