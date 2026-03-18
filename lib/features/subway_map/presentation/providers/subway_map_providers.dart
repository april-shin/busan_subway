import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/local/local_data_source.dart';
import '../../../../data/repositories/station_repository_impl.dart';
import '../../../../domain/entities/station.dart';
import '../../../../domain/repositories/station_repository.dart';

part 'subway_map_providers.g.dart';

@riverpod
LocalDataSource localDataSource(Ref ref) {
  return LocalDataSource();
}

@riverpod
StationRepository stationRepository(Ref ref) {
  return StationRepositoryImpl(
    localDataSource: ref.watch(localDataSourceProvider),
  );
}

@riverpod
Future<List<Station>> allStations(Ref ref) {
  return ref.watch(stationRepositoryProvider).getAllStations();
}

class SelectedStationsNotifier extends StateNotifier<SelectedStations> {
  SelectedStationsNotifier() : super(const SelectedStations());

  void setDeparture(Station? station) {
    state = SelectedStations(
      departure: station,
      arrival: state.arrival,
    );
  }

  void setArrival(Station? station) {
    state = SelectedStations(
      departure: state.departure,
      arrival: station,
    );
  }

  void swap() {
    state = SelectedStations(
      departure: state.arrival,
      arrival: state.departure,
    );
  }

  void clear() {
    state = const SelectedStations();
  }
}

class SelectedStations {
  final Station? departure;
  final Station? arrival;

  const SelectedStations({this.departure, this.arrival});

  bool get isComplete => departure != null && arrival != null;
}

final selectedStationsProvider =
    StateNotifierProvider<SelectedStationsNotifier, SelectedStations>(
  (ref) => SelectedStationsNotifier(),
);

final tappedStationProvider = StateProvider<Station?>((ref) => null);

/// 현재 활성 경로의 출발역 세그먼트 필터 정보.
///
/// 열차 방향 필터링에 사용된다. lineId와 isDown(하행/외선 여부)으로
/// 출발역에 도착하는 올바른 방향의 열차만 표시한다.
class ActiveRouteFilter {
  final String lineId;
  final bool isDown;

  const ActiveRouteFilter({required this.lineId, required this.isDown});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveRouteFilter &&
          lineId == other.lineId &&
          isDown == other.isDown;

  @override
  int get hashCode => Object.hash(lineId, isDown);
}

final activeRouteFilterProvider =
    StateProvider<ActiveRouteFilter?>((ref) => null);
