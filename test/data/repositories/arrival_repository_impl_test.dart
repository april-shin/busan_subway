import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/core/network/network_info.dart';
import 'package:busan_subway/data/local/cache_manager.dart';
import 'package:busan_subway/data/remote/dto/arrival_info_dto.dart';
import 'package:busan_subway/data/remote/busan_api_data_source.dart';
import 'package:busan_subway/data/repositories/arrival_repository_impl.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';

class MockBusanApiDataSource extends Mock implements BusanApiDataSource {}

class MockCacheManager extends Mock implements CacheManager {}

class MockNetworkInfo extends Mock implements NetworkInfo {}

void main() {
  late MockBusanApiDataSource mockApi;
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
    mockApi = MockBusanApiDataSource();
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
          .thenAnswer((_) async => (arrivals: testDtos, isPartial: false));
      when(() => mockCache.cacheData(any(), any()))
          .thenAnswer((_) async {});

      final result = await repository.getArrivalInfo('강남');

      expect(result.length, 1);
      expect(result.first.stationName, '강남');
      expect(result.first.direction, '상행');
      verify(() => mockCache.cacheData(any(), any())).called(1);
    });

    test('부분 결과는 화면에 보여주되 캐시에 저장하지 않는다', () async {
      // 등록명이 노선별로 갈린 역에서 일부 질의만 실패한 경우. 노선이 빠진 스냅샷을
      // 저장하면 이후 전체 실패 시 폴백 화면까지 불완전해진다.
      when(() => mockNetwork.isConnected).thenAnswer((_) async => true);
      when(() => mockApi.getRealtimeArrival('서울역'))
          .thenAnswer((_) async => (arrivals: testDtos, isPartial: true));
      when(() => mockCache.cacheData(any(), any()))
          .thenAnswer((_) async {});

      final result = await repository.getArrivalInfo('서울역');

      expect(result.length, 1, reason: '부분 결과라도 화면에는 보여준다');
      verifyNever(() => mockCache.cacheData(any(), any()));
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
