import 'package:flutter/foundation.dart' show listEquals;
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

  /// 출발·경유·도착을 한 번의 상태 전이로 설정한다 — 즐겨찾기 태그 탭용.
  ///
  /// [setBoth] 와 같은 이유(중간 stale `isComplete` 방지)로 원자적이어야 하고,
  /// 즐겨찾기는 경유역까지 저장하므로 이전 경유역 대신 [waypoints] 로 갈아끼운다.
  /// [maxWaypoints] 를 넘는 뒤쪽 경유역은 버린다.
  void setRoute(
    Station departure,
    Station arrival, {
    List<Station> waypoints = const [],
  }) {
    state = SelectedStations(
      departure: departure,
      arrival: arrival,
      waypoints: List.unmodifiable(waypoints.take(maxWaypoints)),
    );
  }

  /// [index] 자리에 **빈 경유지 칸**을 끼워 넣는다. 기존 [index] 이후 경유지는
  /// 한 칸씩 밀린다. 검색바의 + 버튼이 쓰는 연산이다.
  ///
  /// + 는 화면 이동 없이 칸만 만든다. 역 선택은 사용자가 그 칸을 눌렀을 때
  /// 일어난다([setWaypoint]).
  ///
  /// [index] 는 삽입 지점이라 `0..waypoints.length` 가 유효하다(길이와 같으면
  /// 맨 뒤). 범위 밖이거나 상한 도달이면 상태를 바꾸지 않고 false.
  bool insertWaypointSlot(int index) {
    if (!state.canAddWaypoint) return false;
    if (index < 0 || index > state.waypoints.length) return false;
    final next = [...state.waypoints]..insert(index, null);
    state = SelectedStations(
      departure: state.departure,
      arrival: state.arrival,
      waypoints: List.unmodifiable(next),
    );
    return true;
  }

  /// 경유역을 채운다 — 지도 툴팁의 "경유" 액션용.
  ///
  /// **빈 칸이 있으면 그중 첫 칸을 채우고**, 없으면 맨 뒤에 새로 추가한다.
  /// 빈 칸을 두고 뒤에 덧붙이면 사용자가 만든 칸이 미아로 남기 때문이다
  /// (+ 로 칸을 만든 뒤 지도에서 역을 고르는 것이 자연스러운 흐름).
  ///
  /// 채울 칸도 없고 상한([maxWaypoints])에도 도달했으면 상태를 바꾸지 않고
  /// false 를 반환한다. 호출부가 사용자에게 알릴 수 있도록 성공 여부를 돌려준다.
  bool addWaypoint(Station station) {
    final emptySlot = state.waypoints.indexWhere((w) => w == null);
    if (emptySlot >= 0) {
      setWaypoint(emptySlot, station);
      return true;
    }
    if (!state.canAddWaypoint) return false;
    state = SelectedStations(
      departure: state.departure,
      arrival: state.arrival,
      waypoints: List.unmodifiable([...state.waypoints, station]),
    );
    return true;
  }

  /// [index] 칸의 경유역을 설정한다. 범위 밖([0, length))이면 무시.
  ///
  /// 빈 칸을 채울 때도, 이미 고른 역을 바꿀 때도 같은 연산이다.
  void setWaypoint(int index, Station station) {
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

  /// 경유지 칸 — 출발역 다음부터 도착역 직전까지 **이 순서대로** 방문한다.
  /// 길이는 항상 [maxWaypoints] 이하 (notifier 가 보장).
  ///
  /// `null` 원소는 **칸만 추가되고 아직 역을 고르지 않은 빈 칸**이다. 검색바의
  /// + 버튼이 빈 칸을 만들고, 사용자가 그 칸을 눌러 역을 고르면 채워진다.
  /// 경로 계산에는 빈 칸을 제외한 [waypointStationIds] 를 넘긴다.
  final List<Station?> waypoints;

  const SelectedStations({
    this.departure,
    this.arrival,
    this.waypoints = const [],
  });

  bool get isComplete => departure != null && arrival != null;

  /// 경유지 칸을 더 추가할 수 있는지. 빈 칸도 자리를 차지하므로 함께 센다.
  bool get canAddWaypoint => waypoints.length < maxWaypoints;

  /// 경로 계산에 넘길 경유역 ID 목록 — **빈 칸은 제외**하고 순서는 유지한다.
  ///
  /// 사용자가 칸만 만들고 역을 고르지 않았다면 그 칸은 제약이 아니므로 경로에
  /// 영향을 주지 않는다(빈 칸이 있어도 경로 검색은 그대로 동작).
  List<String> get waypointStationIds =>
      [for (final w in waypoints) if (w != null) w.id];
}

final selectedStationsProvider =
    StateNotifierProvider<SelectedStationsNotifier, SelectedStations>(
  (ref) => SelectedStationsNotifier(),
);

final tappedStationProvider = StateProvider<Station?>((ref) => null);

/// 홈 화면 검색 카드의 아래쪽 경계 y(논리 px = WebView CSS px, WebView 원점 기준).
///
/// 지도(WebView)는 카드가 떠 있다는 것을 모르므로 JS 의 `window.setSafeTop` 으로
/// 알려 경로 툴바가 카드 밑으로 들어가지 않게 한다. 홈 화면이 카드 높이를 측정해
/// 쓰고, `SvgWebView` 가 `ref.listen` 으로 읽는다(리빌드 없이 값 변경만 전달).
/// 카드가 없는 상태의 기본값은 0(= 기존 8px 마진 동작).
final mapSafeTopProvider = StateProvider<double>((ref) => 0);

/// 현재 활성 경로의 출발역 세그먼트 필터 정보.
///
/// 열차 방향 필터링에 사용된다. lineId와 isDown(하행/외선 여부)으로
/// 출발역에 도착하는 올바른 방향의 열차만 표시한다.
class ActiveRouteFilter {
  final String lineId;
  final bool isDown;

  /// 탑승 구간(첫 유효 세그먼트)의 역 ID 목록 — 출발역부터 순서대로.
  ///
  /// 노선+방향이 같아도 이 구간을 끝까지 태워주지 않는 열차 — 지선에서
  /// 갈라지는 열차(예: `천호 → 굽은다리` 경로의 5호선 하행 "마천행")와 하차역
  /// 앞에서 끝나는 중간 종착 열차(예: `내방 → 장암` 경로의 "도봉산행") — 를
  /// 걸러내는 데 쓴다. 판정이 불가능하거나 불필요하면 빈 목록이며, 그 경우
  /// 필터는 적용되지 않는다.
  final List<String> routeStationIds;

  const ActiveRouteFilter({
    required this.lineId,
    required this.isDown,
    this.routeStationIds = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveRouteFilter &&
          lineId == other.lineId &&
          isDown == other.isDown &&
          listEquals(routeStationIds, other.routeStationIds);

  @override
  int get hashCode =>
      Object.hash(lineId, isDown, Object.hashAll(routeStationIds));
}

final activeRouteFilterProvider =
    StateProvider<ActiveRouteFilter?>((ref) => null);
