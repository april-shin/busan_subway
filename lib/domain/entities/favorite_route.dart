import 'package:freezed_annotation/freezed_annotation.dart';

import 'station.dart';

part 'favorite_route.freezed.dart';

/// 즐겨찾기한 경로 1건 — 출발·경유·도착 Station ID 와 사용자 별칭.
///
/// 역 이름이 아닌 id 를 저장한다(환승역 노선 특정 유지 + `stations.json` 변경
/// 시 스냅샷 drift 방지 — 최근 검색·홈 역과 같은 논리).
@freezed
abstract class FavoriteRoute with _$FavoriteRoute {
  const FavoriteRoute._();

  const factory FavoriteRoute({
    required String departureId,
    required String arrivalId,

    /// 경유역 id — 방문 순서. 빈 칸은 저장하지 않는다.
    @Default(<String>[]) List<String> waypointIds,

    /// 사용자 별칭. 빈 문자열이면 `출발→도착` 역명으로 표시한다.
    @Default('') String alias,
  }) = _FavoriteRoute;

  /// 출발·경유·도착 id 가 모두 같으면 같은 즐겨찾기다(별칭은 보지 않는다).
  bool hasSameRouteAs(FavoriteRoute other) =>
      departureId == other.departureId &&
      arrivalId == other.arrivalId &&
      _listEquals(waypointIds, other.waypointIds);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [FavoriteRoute] 의 id 를 현재 역 목록으로 resolve 한 것.
///
/// 역 목록에서 찾지 못한 id(삭제/개명된 역)는 null 로 남는다. 홈 태그는
/// [isComplete] 인 항목만 보여 주고, 설정 화면은 지울 수 있도록 전부 보여 준다.
@freezed
abstract class ResolvedFavoriteRoute with _$ResolvedFavoriteRoute {
  const ResolvedFavoriteRoute._();

  const factory ResolvedFavoriteRoute({
    required FavoriteRoute route,
    Station? departure,
    Station? arrival,
    @Default(<Station?>[]) List<Station?> waypoints,
  }) = _ResolvedFavoriteRoute;

  /// 출발·경유·도착이 모두 현재 역 목록에 있는지.
  bool get isComplete =>
      departure != null && arrival != null && waypoints.every((w) => w != null);

  /// 화면 표시 이름 — 별칭, 없으면 `출발→도착`.
  String get label => route.alias.isNotEmpty
      ? route.alias
      : defaultFavoriteLabel(departure, arrival);
}

/// 별칭이 없을 때 쓰는 기본 이름. 찾지 못한 역은 `?` 로 표시한다.
String defaultFavoriteLabel(Station? departure, Station? arrival) =>
    '${departure?.name ?? '?'}→${arrival?.name ?? '?'}';
