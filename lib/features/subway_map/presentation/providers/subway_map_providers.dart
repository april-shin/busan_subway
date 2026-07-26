import 'package:flutter_riverpod/legacy.dart'; // StateProvider/StateNotifier (riverpod 3 레거시)
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/local/local_data_source.dart';
import '../../../../data/repositories/station_repository_impl.dart';
import '../../../../domain/entities/connection.dart';
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

@riverpod
Future<List<Connection>> allConnections(Ref ref) {
  return ref.watch(stationRepositoryProvider).getAllConnections();
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

  /// 출발/도착을 한 번에 원자적으로 설정한다.
  ///
  /// 최근 검색 이력 탭처럼 두 역을 동시에 세팅해야 하는 경우, setDeparture →
  /// setArrival 를 순차 호출하면 그 사이 중간 상태(이전 도착역과 새 출발역의
  /// stale 쌍)로 `isComplete` 가 성립해 지도 뷰어가 엉뚱한 경로를 계산/기록할
  /// 수 있다. 이를 막기 위해 단일 상태 전이로 갱신한다.
  void setBoth(Station? departure, Station? arrival) {
    state = SelectedStations(departure: departure, arrival: arrival);
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
