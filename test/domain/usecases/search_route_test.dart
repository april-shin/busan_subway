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
      // 이동시간 180 + 정차시간 30 (중간역 을지로입구 × 30초)
      expect(result!.totalTimeSeconds, 210);
      expect(result.segments.length, 1);
      expect(result.segments.first.lineId, '2');
    });

    test('finds route with transfer', () async {
      final result = await searchRoute.execute('201', '317');

      expect(result, isNotNull);
      // 이동시간 450 + 정차시간 30 (중간역 을지로입구 × 30초)
      expect(result!.totalTimeSeconds, 480);
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

    test('executeAll returns fastest and leastTransfer', () async {
      final result = await searchRoute.executeAll('201', '317');

      expect(result.fastest, isNotNull);
      // 이동시간 450 + 정차시간 30
      expect(result.fastest!.totalTimeSeconds, 480);
      // 이 그래프에서는 경로가 하나뿐이므로 leastTransfer는 null (동일 경로)
      expect(result.leastTransfer, isNull);
    });

    test('executeAll returns null for non-existent station', () async {
      final result = await searchRoute.executeAll('999', '201');

      expect(result.fastest, isNull);
      expect(result.leastTransfer, isNull);
    });

    test('executeAll same-line route has null leastTransfer', () async {
      final result = await searchRoute.executeAll('201', '203');

      expect(result.fastest, isNotNull);
      expect(result.fastest!.segments.length, 1);
      // 환승 없는 같은 노선 경로 → leastTransfer null
      expect(result.leastTransfer, isNull);
    });

    test('환승역이 이전 세그먼트의 마지막 역에 포함된다', () async {
      // 201(시청) → 317(충무로): 2호선 → 을지로3가 환승 → 3호선
      final result = await searchRoute.execute('201', '317');

      expect(result, isNotNull);
      expect(result!.segments.length, 2);

      // 2호선 세그먼트: 시청, 을지로입구, 을지로3가 (환승역 포함)
      final firstSegment = result.segments[0];
      expect(firstSegment.lineId, '2');
      expect(firstSegment.stations.length, 3);
      expect(firstSegment.stations.last.name, '을지로3가');

      // 3호선 세그먼트: 을지로3가, 충무로
      final secondSegment = result.segments[1];
      expect(secondSegment.lineId, '3');
      expect(secondSegment.stations.length, 2);
      expect(secondSegment.stations.first.name, '을지로3가');
      expect(secondSegment.stations.last.name, '충무로');
    });
  });
}
