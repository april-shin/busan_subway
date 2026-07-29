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

/// 경유역 최대 개수.
///
/// 경로 계산이 정차역 사이마다 Dijkstra 를 한 번씩 이어 붙이고, 검색바가 지도를
/// 과도하게 덮지 않아야 하므로 상한을 둔다.
const int maxWaypoints = 3;

class SelectedStationsNotifier extends StateNotifier<SelectedStations> {
  SelectedStationsNotifier() : super(const SelectedStations());

  void setDeparture(Station? station) {
    state = SelectedStations(
      departure: station,
      arrival: state.arrival,
      waypoints: state.waypoints,
    );
  }

  void setArrival(Station? station) {
    state = SelectedStations(
      departure: state.departure,
      arrival: station,
      waypoints: state.waypoints,
    );
  }

  /// 출발↔도착을 교환한다. 여정을 거꾸로 타는 것이므로 경유 순서도 뒤집는다.
  void swap() {
    state = SelectedStations(
      departure: state.arrival,
      arrival: state.departure,
      waypoints: List.unmodifiable(state.waypoints.reversed),
    );
  }

  /// 출발/도착을 한 번에 원자적으로 설정한다. **경유역은 초기화된다.**
  ///
  /// 최근 검색 이력 탭처럼 두 역을 동시에 세팅해야 하는 경우, setDeparture →
  /// setArrival 를 순차 호출하면 그 사이 중간 상태(이전 도착역과 새 출발역의
  /// stale 쌍)로 `isComplete` 가 성립해 지도 뷰어가 엉뚱한 경로를 계산/기록할
  /// 수 있다. 이를 막기 위해 단일 상태 전이로 갱신한다.
  ///
  /// 이력에는 출발/도착만 저장되므로 "여정 전체를 갈아끼우는" 이 진입점에서
  /// 이전 경유역을 남겨두면 사용자가 고르지 않은 제약이 섞인다 → 함께 비운다.
  void setBoth(Station? departure, Station? arrival) {
    state = SelectedStations(departure: departure, arrival: arrival);
  }

  /// 경유역을 맨 뒤(도착역 직전)에 추가한다.
  ///
  /// 상한([maxWaypoints]) 에 도달했으면 상태를 바꾸지 않고 false 를 반환한다.
  /// 호출부가 사용자에게 알릴 수 있도록 성공 여부를 돌려준다.
  bool addWaypoint(Station station) =>
      insertWaypoint(state.waypoints.length, station);

  /// [index] 자리에 경유역을 **끼워 넣는다**. 기존 [index] 이후 경유역은 한 칸씩
  /// 밀린다. 검색바의 + 버튼("이 필드 위에 경유칸 추가")이 쓰는 연산이다.
  ///
  /// [index] 는 삽입 지점이라 `0..waypoints.length` 가 유효하다(길이와 같으면
  /// 맨 뒤). 범위 밖이거나 상한 도달이면 상태를 바꾸지 않고 false.
  bool insertWaypoint(int index, Station station) {
    if (!state.canAddWaypoint) return false;
    if (index < 0 || index > state.waypoints.length) return false;
    final next = [...state.waypoints]..insert(index, station);
    state = SelectedStations(
      departure: state.departure,
      arrival: state.arrival,
      waypoints: List.unmodifiable(next),
    );
    return true;
  }

  /// [index] 슬롯의 경유역을 설정한다.
  ///
  /// - `index == waypoints.length`: 맨 뒤에 추가(상한 초과 시 무시).
  /// - 범위 안: 그 슬롯을 교체.
  /// - 그 외(음수/범위 초과): 무시.
  void setWaypoint(int index, Station station) {
    if (index == state.waypoints.length) {
      addWaypoint(station);
      return;
    }
    if (index < 0 || index >= state.waypoints.length) return;
    final next = [...state.waypoints];
    next[index] = station;
    state = SelectedStations(
      departure: state.departure,
      arrival: state.arrival,
      waypoints: List.unmodifiable(next),
    );
  }

  /// [index] 슬롯의 경유역을 제거한다. 범위 밖이면 무시.
  void removeWaypointAt(int index) {
    if (index < 0 || index >= state.waypoints.length) return;
    final next = [...state.waypoints]..removeAt(index);
    state = SelectedStations(
      departure: state.departure,
      arrival: state.arrival,
      waypoints: List.unmodifiable(next),
    );
  }

  void clear() {
    state = const SelectedStations();
  }
}

class SelectedStations {
  final Station? departure;
  final Station? arrival;

  /// 경유역 — 출발역 다음부터 도착역 직전까지 **이 순서대로** 방문한다.
  /// 길이는 항상 [maxWaypoints] 이하 (notifier 가 보장).
  final List<Station> waypoints;

  const SelectedStations({
    this.departure,
    this.arrival,
    this.waypoints = const [],
  });

  bool get isComplete => departure != null && arrival != null;

  /// 경유역을 더 추가할 수 있는지.
  bool get canAddWaypoint => waypoints.length < maxWaypoints;
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
