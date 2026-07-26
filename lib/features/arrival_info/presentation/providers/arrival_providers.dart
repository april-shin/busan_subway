import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/network_info.dart';
import '../../../../data/local/cache_manager.dart';
import '../../../../data/remote/seoul_api_data_source.dart';
import '../../../../data/repositories/arrival_repository_impl.dart';
import '../../../../domain/entities/arrival_info.dart';
import '../../../../domain/repositories/arrival_repository.dart';

part 'arrival_providers.g.dart';

@riverpod
ApiClient apiClient(Ref ref) {
  return ApiClient();
}

@riverpod
SeoulApiDataSource seoulApiDataSource(Ref ref) {
  return SeoulApiDataSource(apiClient: ref.watch(apiClientProvider));
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
    remoteDataSource: ref.watch(seoulApiDataSourceProvider),
    cacheManager: ref.watch(cacheManagerProvider),
    networkInfo: ref.watch(networkInfoProvider),
  );
}

@riverpod
Future<List<ArrivalInfo>> arrivalInfo(Ref ref, String stationName) async {
  return ref.watch(arrivalRepositoryProvider).getArrivalInfo(stationName);
}
