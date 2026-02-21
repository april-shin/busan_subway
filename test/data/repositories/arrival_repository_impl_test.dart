import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/core/network/network_info.dart';
import 'package:seoul_subway/data/local/cache_manager.dart';
import 'package:seoul_subway/data/remote/dto/arrival_info_dto.dart';
import 'package:seoul_subway/data/remote/seoul_api_data_source.dart';
import 'package:seoul_subway/data/repositories/arrival_repository_impl.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';

class MockSeoulApiDataSource extends Mock implements SeoulApiDataSource {}

class MockCacheManager extends Mock implements CacheManager {}

class MockNetworkInfo extends Mock implements NetworkInfo {}

void main() {
  late MockSeoulApiDataSource mockApi;
  late MockCacheManager mockCache;
  late MockNetworkInfo mockNetwork;
  late ArrivalRepositoryImpl repository;

  final testDtos = [
    const ArrivalInfoDto(
      subwayId: '1002',
      updnLine: '상행',
      trainLineNm: '성수행',
      statnNm: '강남',
      bstatnNm: '성수',
      barvlDt: '120',
      btrainSttus: '일반',
      arvlMsg2: '전역 도착',
      recptnDt: '2024-01-01 12:00:00',
    ),
  ];

  setUp(() {
    mockApi = MockSeoulApiDataSource();
    mockCache = MockCacheManager();
    mockNetwork = MockNetworkInfo();
    repository = ArrivalRepositoryImpl(
      remoteDataSource: mockApi,
      cacheManager: mockCache,
      networkInfo: mockNetwork,
    );
  });

  group('ArrivalRepositoryImpl', () {
    test('returns API data when online', () async {
      when(() => mockNetwork.isConnected).thenAnswer((_) async => true);
      when(() => mockApi.getRealtimeArrival('강남'))
          .thenAnswer((_) async => testDtos);
      when(() => mockCache.cacheData(any(), any()))
          .thenAnswer((_) async {});

      final result = await repository.getArrivalInfo('강남');

      expect(result.length, 1);
      expect(result.first.stationName, '강남');
      expect(result.first.direction, '상행');
      verify(() => mockCache.cacheData(any(), any())).called(1);
    });

    test('falls back to cache when API fails', () async {
      final now = DateTime.now();
      final cachedArrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '강남',
          trainLineNm: '성수행',
          direction: '상행',
          arrivalMessage: '캐시 데이터',
          destination: '성수',
          trainType: '일반',
          receivedAt: now,
        ),
      ];
      final cachedJson =
          json.encode(cachedArrivals.map((a) => a.toJson()).toList());

      when(() => mockNetwork.isConnected).thenAnswer((_) async => true);
      when(() => mockApi.getRealtimeArrival('강남'))
          .thenThrow(Exception('API 오류'));
      when(() => mockCache.getCachedDataWithTimestamp('arrival_강남'))
          .thenAnswer((_) async => CachedEntry(
                data: cachedJson,
                cachedAt: DateTime.now(),
              ));

      final result = await repository.getArrivalInfo('강남');

      expect(result.length, 1);
      expect(result.first.arrivalMessage, '캐시 데이터');
    });

    test('uses cache when offline', () async {
      final now = DateTime.now();
      final cachedArrivals = [
        ArrivalInfo(
          subwayId: '1002',
          stationName: '강남',
          trainLineNm: '신도림행',
          direction: '하행',
          arrivalMessage: '오프라인 캐시',
          destination: '신도림',
          trainType: '일반',
          receivedAt: now,
        ),
      ];
      final cachedJson =
          json.encode(cachedArrivals.map((a) => a.toJson()).toList());

      when(() => mockNetwork.isConnected).thenAnswer((_) async => false);
      when(() => mockCache.getCachedDataWithTimestamp('arrival_강남'))
          .thenAnswer((_) async => CachedEntry(
                data: cachedJson,
                cachedAt: DateTime.now(),
              ));

      final result = await repository.getArrivalInfo('강남');

      expect(result.length, 1);
      expect(result.first.arrivalMessage, '오프라인 캐시');
      verifyNever(() => mockApi.getRealtimeArrival(any()));
    });

    test('throws when offline and no cache', () async {
      when(() => mockNetwork.isConnected).thenAnswer((_) async => false);
      when(() => mockCache.getCachedDataWithTimestamp('arrival_강남'))
          .thenAnswer((_) async => null);

      expect(
        () => repository.getArrivalInfo('강남'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when API fails and no cache', () async {
      when(() => mockNetwork.isConnected).thenAnswer((_) async => true);
      when(() => mockApi.getRealtimeArrival('강남'))
          .thenThrow(Exception('서버 오류'));
      when(() => mockCache.getCachedDataWithTimestamp('arrival_강남'))
          .thenAnswer((_) async => null);

      expect(
        () => repository.getArrivalInfo('강남'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
