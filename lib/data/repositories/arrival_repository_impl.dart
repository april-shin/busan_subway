import 'dart:convert';

import '../../core/network/network_info.dart';
import '../../domain/entities/arrival_info.dart';
import '../../domain/repositories/arrival_repository.dart';
import '../local/cache_manager.dart';
import '../remote/seoul_api_data_source.dart';

class ArrivalRepositoryImpl implements ArrivalRepository {
  final SeoulApiDataSource _remoteDataSource;
  final CacheManager _cacheManager;
  final NetworkInfo _networkInfo;

  ArrivalRepositoryImpl({
    required SeoulApiDataSource remoteDataSource,
    required CacheManager cacheManager,
    required NetworkInfo networkInfo,
  })  : _remoteDataSource = remoteDataSource,
        _cacheManager = cacheManager,
        _networkInfo = networkInfo;

  @override
  Future<List<ArrivalInfo>> getArrivalInfo(String stationName) async {
    final cacheKey = 'arrival_$stationName';

    if (await _networkInfo.isConnected) {
      try {
        final fetched = await _remoteDataSource.getRealtimeArrival(stationName);
        final arrivals =
            fetched.arrivals.map((dto) => dto.toEntity()).toList();

        // 등록명이 노선별로 갈린 역(서울역·올림픽공원)에서 일부 질의만 실패한 결과는
        // 화면에는 보여주되 캐시에는 남기지 않는다. 노선이 빠진 스냅샷을 저장하면
        // 이후 전체 실패 시 폴백 화면까지 불완전해지기 때문이다.
        if (!fetched.isPartial) {
          await _cacheManager.cacheData(
            cacheKey,
            json.encode(arrivals.map((a) => a.toJson()).toList()),
          );
        }

        return arrivals;
      } catch (e) {
        return _getFromCacheOrThrow(cacheKey, e);
      }
    }

    return _getFromCacheOrThrow(
      cacheKey,
      Exception('네트워크에 연결할 수 없습니다'),
    );
  }

  Future<List<ArrivalInfo>> _getFromCacheOrThrow(
    String cacheKey,
    Object originalError,
  ) async {
    final cached = await _cacheManager.getCachedDataWithTimestamp(cacheKey);
    if (cached != null) {
      final List<dynamic> decoded =
          json.decode(cached.data) as List<dynamic>;
      return decoded
          .map((e) => ArrivalInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw originalError;
  }
}
