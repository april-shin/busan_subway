import 'dart:convert';

import '../../core/network/network_info.dart';
import '../../core/utils/fallback_arrivals_from_positions.dart';
import '../../domain/entities/arrival_info.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
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

  @override
  Future<List<ArrivalInfo>> getTrainPositionArrivals({
    required String lineId,
    required String targetStationName,
    required List<Station> stations,
    required List<Connection> connections,
  }) async {
    // 폴백 경로이므로 실패해도 예외를 올리지 않는다 — 위치 정보가 없으면 열차가
    // 안 보이는 것으로 끝나야 하고, 도착정보 쪽 화면을 깨뜨려선 안 된다.
    // 캐시 키는 노선 단위(대상역과 무관한 원본 응답 단위)로 잡는다.
    final cacheKey = 'position_$lineId';

    List<ArrivalInfo> raw;
    if (await _networkInfo.isConnected) {
      try {
        final dtos = await _remoteDataSource.getRealtimePosition(lineId);
        raw = [for (final d in dtos) d.toArrivalInfo(targetStationName)];
        await _cacheManager.cacheData(
          cacheKey,
          json.encode([for (final a in raw) a.toJson()]),
        );
      } catch (_) {
        raw = await _cachedPositions(cacheKey, targetStationName);
      }
    } else {
      raw = await _cachedPositions(cacheKey, targetStationName);
    }

    return fallbackArrivalsFromPositions(
      rawPositions: raw,
      targetStationName: targetStationName,
      stations: stations,
      connections: connections,
    );
  }

  /// 캐시된 위치 응답. 캐시는 다른 대상역 기준으로 저장됐을 수 있으므로
  /// `stationName` 만 현재 대상역으로 바꿔 준다(나머지 필드는 대상역과 무관하다).
  Future<List<ArrivalInfo>> _cachedPositions(
    String cacheKey,
    String targetStationName,
  ) async {
    final cached = await _cacheManager.getCachedDataWithTimestamp(cacheKey);
    if (cached == null) return [];
    try {
      final decoded = json.decode(cached.data) as List<dynamic>;
      return [
        for (final e in decoded)
          ArrivalInfo.fromJson(e as Map<String, dynamic>)
              .copyWith(stationName: targetStationName),
      ];
    } catch (_) {
      return [];
    }
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
