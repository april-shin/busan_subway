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
        final dtos = await _remoteDataSource.getRealtimeArrival(stationName);
        final arrivals = dtos.map((dto) => dto.toEntity()).toList();

        await _cacheManager.cacheData(
          cacheKey,
          json.encode(arrivals.map((a) => a.toJson()).toList()),
        );

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
