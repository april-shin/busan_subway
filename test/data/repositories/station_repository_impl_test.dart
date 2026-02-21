import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/entities/line.dart';
import 'package:seoul_subway/domain/entities/connection.dart';

class MockLocalDataSource extends Mock implements LocalDataSource {}

void main() {
  late MockLocalDataSource mockDataSource;
  late StationRepositoryImpl repository;

  final testStations = [
    const Station(id: '201', name: '시청', lineId: '2', latitude: 37.56, longitude: 126.97),
    const Station(id: '216', name: '강남', lineId: '2', latitude: 37.49, longitude: 127.02, isTransfer: true, transferLines: ['2', '신분당']),
    const Station(id: '301', name: '대화', lineId: '3', latitude: 37.67, longitude: 126.75),
  ];

  setUp(() {
    mockDataSource = MockLocalDataSource();
    repository = StationRepositoryImpl(localDataSource: mockDataSource);
    when(() => mockDataSource.loadStations()).thenAnswer((_) async => testStations);
  });

  group('StationRepositoryImpl', () {
    test('getAllStations returns all stations', () async {
      final stations = await repository.getAllStations();
      expect(stations.length, 3);
    });

    test('searchStations filters by name', () async {
      final results = await repository.searchStations('강남');
      expect(results.length, 1);
      expect(results.first.name, '강남');
    });

    test('searchStations returns empty for no match', () async {
      final results = await repository.searchStations('없는역');
      expect(results, isEmpty);
    });

    test('searchStations returns empty for empty query', () async {
      final results = await repository.searchStations('');
      expect(results, isEmpty);
    });

    test('getStationById returns correct station', () async {
      final station = await repository.getStationById('216');
      expect(station, isNotNull);
      expect(station!.name, '강남');
    });

    test('getStationById returns null for non-existent id', () async {
      final station = await repository.getStationById('999');
      expect(station, isNull);
    });

    test('getStationsByLine filters by lineId', () async {
      final stations = await repository.getStationsByLine('2');
      expect(stations.length, 2);
      expect(stations.every((s) => s.lineId == '2'), true);
    });

    test('getAllLines delegates to data source', () async {
      final testLines = [
        const Line(id: '2', name: '2호선', colorValue: 43053, stationIds: ['201', '216']),
      ];
      when(() => mockDataSource.loadLines()).thenAnswer((_) async => testLines);

      final lines = await repository.getAllLines();
      expect(lines.length, 1);
      expect(lines.first.name, '2호선');
    });

    test('getAllConnections delegates to data source', () async {
      final testConnections = [
        const Connection(fromStationId: '201', toStationId: '202', lineId: '2', travelTimeSeconds: 90),
      ];
      when(() => mockDataSource.loadConnections()).thenAnswer((_) async => testConnections);

      final connections = await repository.getAllConnections();
      expect(connections.length, 1);
    });

    test('getTransferTimes delegates to data source', () async {
      final testTimes = {'교대_2_3': 180};
      when(() => mockDataSource.loadTransferTimes()).thenAnswer((_) async => testTimes);

      final times = await repository.getTransferTimes();
      expect(times['교대_2_3'], 180);
    });
  });
}
