import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/feature_flags.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/network_info.dart';
import '../../../../data/local/cache_manager.dart';
import '../../../../data/remote/busan_api_data_source.dart';
import '../../../../data/repositories/arrival_repository_impl.dart';
import '../../../../domain/entities/arrival_info.dart';
import '../../../../domain/repositories/arrival_repository.dart';

part 'arrival_providers.g.dart';

@riverpod
ApiClient apiClient(Ref ref) {
  return ApiClient();
}

@riverpod
BusanApiDataSource busanApiDataSource(Ref ref) {
  return BusanApiDataSource(apiClient: ref.watch(apiClientProvider));
}

@riverpod
CacheManager cacheManager(Ref ref) {
  return CacheManager();
}

@riverpod
NetworkInfo networkInfo(Ref ref) {
  return NetworkInfo();
}

@riverpod
ArrivalRepository arrivalRepository(Ref ref) {
  return ArrivalRepositoryImpl(
    remoteDataSource: ref.watch(busanApiDataSourceProvider),
    cacheManager: ref.watch(cacheManagerProvider),
    networkInfo: ref.watch(networkInfoProvider),
  );
}

/// 역의 실시간 도착정보. [FeatureFlags.realtimeEnabled] 가 false 면 API 를 부르지
/// 않고 빈 목록을 돌려준다(호출부는 시간표 폴백으로 동작한다).
@riverpod
Future<List<ArrivalInfo>> arrivalInfo(Ref ref, String stationName) async {
  if (!FeatureFlags.realtimeEnabled) return const [];
  return ref.watch(arrivalRepositoryProvider).getArrivalInfo(stationName);
}
