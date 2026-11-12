import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../domain/entities/favorite_route.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';

part 'favorite_routes_provider.g.dart';

/// 즐겨찾기 최대 개수. 가득 차면 등록을 막는다(자동 밀어내기 없음).
const int maxFavoriteRoutes = 5;

/// 별칭 최대 글자 수. 입력 단계(TextField maxLength)에서 제한한다.
const int maxFavoriteAliasLength = 10;

/// 즐겨찾기 변경 연산의 결과. 실패도 예외가 아니라 값으로 돌려줘 UI 가 안내한다.
enum FavoriteSaveResult {
  /// 저장됨.
  success,

  /// 출발·경유·도착이 같은 즐겨찾기가 이미 있다.
  duplicate,

  /// [maxFavoriteRoutes] 개가 이미 차 있다.
  full,

  /// 대상 즐겨찾기를 찾지 못했다(다른 곳에서 이미 지워진 경우, 범위 밖 이동).
  notFound,

  /// 기기 저장소에 쓰지 못했다. 상태는 변경 전으로 되돌린다.
  saveFailed,
}

/// 저장 형식: JSON 배열. 배열 순서 = 표시 순서.
/// `[{"d": 출발id, "a": 도착id, "w": [경유id...], "n": 별칭}, ...]`
///
/// 최근 검색(`pref_recent_search`)과는 별개 키·별개 프로바이더다.
const String _prefKeyFavoriteRoutes = 'pref_favorite_routes';

/// 즐겨찾기가 읽고 쓰는 `SharedPreferences`.
///
/// 테스트가 저장 실패(`setString` 예외/false)를 주입할 수 있도록 프로바이더로
/// 둔다. 앱에서는 `SharedPreferences.getInstance()` 그대로다.
@Riverpod(keepAlive: true)
Future<SharedPreferences> favoritePreferences(Ref ref) =>
    SharedPreferences.getInstance();

/// 별칭 정리 — 앞뒤 공백 제거 + [maxFavoriteAliasLength] 글자(문자 단위) 상한.
///
/// 입력칸(`TextField.maxLength`)도 같은 글자 단위로 막지만, 저장값이 외부에서
/// 손상·편집됐을 때 긴 태그가 그대로 뜨지 않도록 로드·저장 때 한 번 더 자른다.
String normalizeFavoriteAlias(String alias) {
  final trimmed = alias.trim();
  final chars = trimmed.characters;
  if (chars.length <= maxFavoriteAliasLength) return trimmed;
  return chars.take(maxFavoriteAliasLength).toString().trim();
}

/// 즐겨찾기 경로 목록(저장 순서 그대로)을 보관한다.
///
/// 값이 없거나 JSON 자체가 깨졌으면 빈 목록, 일부 항목만 형식이 틀리면 그
/// 항목만 건너뛴다 — 저장값 손상으로 앱이 죽지 않게 한다. 같은 경로가 여러 번
/// 있으면 앞쪽 하나만, 최대 [maxFavoriteRoutes] 개까지 읽는다.
///
/// 변경 연산은 상태를 먼저 바꾸고 저장한다. `ReorderableListView` 는
/// `onReorderItem` 직후 프레임에 새 순서가 반영돼 있어야 항목이 원위치로 튀지
/// 않는다. 저장에 실패하면 상태를 되돌리고 [FavoriteSaveResult.saveFailed].
///
/// 동시 호출 안전: 각 연산은 [_current] 로 로드 완료를 기다린 **뒤** 최신 상태를
/// 다시 읽고, 거기서 `_commit` 의 `state =` 까지 중간 await 가 없다. 따라서 로드
/// 중 연타나 await 없이 이어진 호출도 앞선 변경을 덮어쓰지 않는다.
@Riverpod(keepAlive: true)
class FavoriteRoutes extends _$FavoriteRoutes {
  @override
  Future<List<FavoriteRoute>> build() async {
    final prefs = await ref.watch(favoritePreferencesProvider.future);
    final raw = prefs.getString(_prefKeyFavoriteRoutes);
    if (raw == null) return const [];
    final Object? decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];

    final result = <FavoriteRoute>[];
    for (final e in decoded) {
      final route = _parseEntry(e);
      if (route == null) continue;
      if (result.any(route.hasSameRouteAs)) continue;
      result.add(route);
      if (result.length == maxFavoriteRoutes) break;
    }
    return List.unmodifiable(result);
  }

  /// 즐겨찾기를 맨 뒤에 추가한다.
  Future<FavoriteSaveResult> add(FavoriteRoute route) async {
    final current = await _current();
    final normalized = route.copyWith(
      alias: normalizeFavoriteAlias(route.alias),
    );
    if (current.any(normalized.hasSameRouteAs)) {
      return FavoriteSaveResult.duplicate;
    }
    if (current.length >= maxFavoriteRoutes) return FavoriteSaveResult.full;
    return _commit(current, [...current, normalized]);
  }

  /// [target] 과 같은 경로의 즐겨찾기를 지운다.
  Future<FavoriteSaveResult> remove(FavoriteRoute target) async {
    final current = await _current();
    final index = current.indexWhere(target.hasSameRouteAs);
    if (index < 0) return FavoriteSaveResult.notFound;
    return _commit(current, [...current]..removeAt(index));
  }

  /// [original] 을 [updated] 로 같은 자리에서 바꾼다(별칭·경로 수정).
  ///
  /// 바뀐 경로가 **다른** 즐겨찾기와 같으면 저장하지 않고 duplicate.
  Future<FavoriteSaveResult> replace(
    FavoriteRoute original,
    FavoriteRoute updated,
  ) async {
    final current = await _current();
    final index = current.indexWhere(original.hasSameRouteAs);
    if (index < 0) return FavoriteSaveResult.notFound;
    final normalized = updated.copyWith(
      alias: normalizeFavoriteAlias(updated.alias),
    );
    for (var i = 0; i < current.length; i++) {
      if (i != index && current[i].hasSameRouteAs(normalized)) {
        return FavoriteSaveResult.duplicate;
      }
    }
    final next = [...current];
    next[index] = normalized;
    return _commit(current, next);
  }

  /// [from] 위치의 항목을 [to] 위치로 옮긴다. 두 index 모두 **이동 후 목록
  /// 기준**의 최종 위치다(`ReorderableListView.onReorderItem` 과 같은 규약).
  /// 범위 밖이면 상태를 바꾸지 않고 notFound, 같은 자리면 success.
  Future<FavoriteSaveResult> move(int from, int to) async {
    final current = await _current();
    if (from < 0 || from >= current.length) return FavoriteSaveResult.notFound;
    if (to < 0 || to >= current.length) return FavoriteSaveResult.notFound;
    if (from == to) return FavoriteSaveResult.success;
    final next = [...current];
    final item = next.removeAt(from);
    next.insert(to, item);
    return _commit(current, next);
  }

  /// 로드 완료를 기다린 뒤 **그 시점의 최신 상태**를 돌려준다.
  ///
  /// `await future` 의 반환값을 쓰면 같은 스냅샷을 잡은 두 연산 중 뒤쪽이
  /// 앞쪽 변경을 덮어쓴다. 로드가 실패한 상태면 빈 목록으로 진행한다(앱이
  /// 죽지 않게 — 이어지는 저장도 실패하면 saveFailed 로 안내된다).
  Future<List<FavoriteRoute>> _current() async {
    try {
      await future;
    } catch (_) {
      // 로드 실패 — 아래에서 빈 목록으로 진행.
    }
    return state.value ?? const [];
  }

  Future<FavoriteSaveResult> _commit(
    List<FavoriteRoute> previous,
    List<FavoriteRoute> next,
  ) async {
    final committed = List<FavoriteRoute>.unmodifiable(next);
    state = AsyncData(committed);
    var saved = false;
    try {
      final prefs = await ref.read(favoritePreferencesProvider.future);
      saved = await prefs.setString(
        _prefKeyFavoriteRoutes,
        json.encode([
          for (final r in committed)
            {
              'd': r.departureId,
              'a': r.arrivalId,
              'w': r.waypointIds,
              'n': r.alias,
            },
        ]),
      );
    } catch (_) {
      saved = false;
    }
    if (saved) return FavoriteSaveResult.success;
    // 그 사이 다른 연산이 상태를 또 바꿨다면 그 변경을 지우지 않는다.
    if (identical(state.value, committed)) {
      state = AsyncData(List.unmodifiable(previous));
    }
    return FavoriteSaveResult.saveFailed;
  }

  static FavoriteRoute? _parseEntry(Object? e) {
    if (e is! Map) return null;
    final d = e['d'];
    final a = e['a'];
    if (d is! String || a is! String || d.isEmpty || a.isEmpty) return null;
    final w = e['w'] ?? const <Object?>[];
    if (w is! List || !w.every((x) => x is String && x.isNotEmpty)) return null;
    if (w.length > maxWaypoints) return null;
    final n = e['n'] ?? '';
    if (n is! String) return null;
    return FavoriteRoute(
      departureId: d,
      arrivalId: a,
      waypointIds: List.unmodifiable(w.cast<String>()),
      alias: normalizeFavoriteAlias(n),
    );
  }
}

/// 즐겨찾기 id 를 현재 역 목록으로 resolve 한 목록(저장 순서 그대로).
///
/// 찾지 못한 역은 null 로 남긴다 — 홈 태그는 [ResolvedFavoriteRoute.isComplete]
/// 인 항목만 보여 주고, 설정 화면은 지울 수 있도록 전부 보여 준다.
@Riverpod(keepAlive: true)
Future<List<ResolvedFavoriteRoute>> resolvedFavoriteRoutes(Ref ref) async {
  final favorites = await ref.watch(favoriteRoutesProvider.future);
  if (favorites.isEmpty) return const [];

  final stations = await ref.watch(allStationsProvider.future);
  final byId = {for (final s in stations) s.id: s};
  return [
    for (final f in favorites)
      ResolvedFavoriteRoute(
        route: f,
        departure: byId[f.departureId],
        arrival: byId[f.arrivalId],
        waypoints: [for (final id in f.waypointIds) byId[id]],
      ),
  ];
}
