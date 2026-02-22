import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/repositories/station_repository.dart';
import 'package:seoul_subway/domain/usecases/search_route.dart';

class MockStationRepository extends Mock implements StationRepository {}

void main() {
  late MockStationRepository mockRepo;
  late SearchRoute searchRoute;

  final testStations = [
    const Station(id: '201', name: '시청', lineId: '2', latitude: 37.56, longitude: 126.97),
    const Station(id: '202', name: '을지로입구', lineId: '2', latitude: 37.56, longitude: 126.98),
    const Station(id: '203', name: '을지로3가', lineId: '2', latitude: 37.56, longitude: 126.99, isTransfer: true, transferLines: ['2', '3']),
    const Station(id: '316', name: '을지로3가', lineId: '3', latitude: 37.56, longitude: 126.99, isTransfer: true, transferLines: ['2', '3']),
    const Station(id: '317', name: '충무로', lineId: '3', latitude: 37.56, longitude: 126.99),
  ];

  final testConnections = [
    const Connection(fromStationId: '201', toStationId: '202', lineId: '2', travelTimeSeconds: 90),
    const Connection(fromStationId: '202', toStationId: '203', lineId: '2', travelTimeSeconds: 90),
    const Connection(fromStationId: '316', toStationId: '317', lineId: '3', travelTimeSeconds: 90),
  ];

  final testTransferTimes = {'을지로3가_2_3': 180};

  setUp(() {
    mockRepo = MockStationRepository();
    searchRoute = SearchRoute(stationRepository: mockRepo);

    when(() => mockRepo.getAllStations()).thenAnswer((_) async => testStations);
    when(() => mockRepo.getAllConnections()).thenAnswer((_) async => testConnections);
    when(() => mockRepo.getTransferTimes()).thenAnswer((_) async => testTransferTimes);
  });

  group('SearchRoute', () {
    test('finds route on same line', () async {
      final result = await searchRoute.execute('201', '203');

      expect(result, isNotNull);
      expect(result!.totalTimeSeconds, 180); // 90 + 90
      expect(result.segments.length, 1);
      expect(result.segments.first.lineId, '2');
    });

    test('finds route with transfer', () async {
      final result = await searchRoute.execute('201', '317');

      expect(result, isNotNull);
      expect(result!.totalTimeSeconds, 450); // 90 + 90 + 180(환승) + 90(충무로)
      expect(result.transferCount, greaterThanOrEqualTo(1));
    });

    test('returns null for non-existent station', () async {
      final result = await searchRoute.execute('999', '201');
      expect(result, isNull);
    });

    test('returns route with correct station count', () async {
      final result = await searchRoute.execute('201', '203');

      expect(result, isNotNull);
      expect(result!.stationCount, greaterThanOrEqualTo(2));
    });

    test('same line route has empty transferDurations', () async {
      final result = await searchRoute.execute('201', '203');

      expect(result, isNotNull);
      expect(result!.transferDurations, isEmpty);
    });

    test('transfer route collects transferDurations', () async {
      final result = await searchRoute.execute('201', '317');

      expect(result, isNotNull);
      expect(result!.transferDurations, isNotEmpty);
      expect(result.transferDurations.length, result.transferCount);
      expect(result.transferDurations.first, 180);
    });
  });
}
