import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/same_station.dart';
import '../../../../domain/entities/station.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';

part 'recent_search_provider.g.dart';

/// 한 건의 최근 검색 — 출발→도착 Station ID 쌍.
typedef RecentSearchIds = ({String departureId, String arrivalId});

/// 최근 검색 한 건을 실제 `Station` 쌍으로 resolve 한 것.
typedef RecentSearchPair = ({Station departure, Station arrival});

/// 화면에 보여 줄 최근 검색 건수.
const int maxRecentSearches = 3;

/// 저장해 두는 최대 건수.
///
/// 표시 건수보다 넉넉히 둔다 — resolve 단계에서 삭제/개명된 역이나 같은 물리
/// 역 쌍(환승역의 노선별 id 차이)이 걸러져도 [maxRecentSearches] 건을 채울 수
/// 있어야 하기 때문이다.
const int _maxStoredRecentSearches = 10;

/// 최근에 검색한 출발→도착 Station ID 쌍 목록을 최신순으로 보관한다.
///
/// 저장은 `SharedPreferences` 에 JSON 배열(`[{"d": 출발id, "a": 도착id}, ...]`)로
/// 이뤄지며, 값이 없거나 파싱 실패 시 빈 목록. 1건만 저장하던 시절의 단일 객체
/// (`{"d":..,"a":..}`)도 1건짜리 목록으로 읽는다.
///
/// [`Station.id`](../../../../domain/entities/station.dart) 는
/// `"{stationId}_{lineId}"` 포맷이므로 이름 대신 id 를 저장한다(환승역 노선
/// 특정 유지 + `stations.json` 변경 시 스냅샷 drift 방지 — `home_station_provider`
/// 와 동일 논리).
const String _prefKeyRecentSearch = 'pref_recent_search';

@Riverpod(keepAlive: true)
class RecentSearch extends _$RecentSearch {
  @override
  Future<List<RecentSearchIds>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyRecentSearch);
    if (raw == null) return const [];
    try {
      final decoded = json.decode(raw);
      final entries = decoded is List ? decoded : [decoded];
      final result = <RecentSearchIds>[];
      for (final e in entries) {
        if (e is! Map) continue;
        final d = e['d'];
        final a = e['a'];
        if (d is! String || a is! String) continue;
        final ids = (departureId: d, arrivalId: a);
        if (!result.contains(ids)) result.add(ids);
      }
      return result.take(_maxStoredRecentSearches).toList();
    } on FormatException {
      return const [];
    }
  }

  /// 최근 검색 1건을 맨 앞에 기록한다.
  ///
  /// 같은 출발→도착 쌍이 이미 있으면 중복으로 쌓지 않고 맨 앞으로 옮긴다.
  ///
  /// fire-and-forget 으로 호출되므로(반환 Future 를 버림) 저장 실패가 unhandled
  /// async error 로 전파되지 않도록 내부에서 흡수한다. 이력 기록 실패는 핵심
  /// 기능(경로 탐색)에 영향이 없다.
  Future<void> record(String departureId, String arrivalId) async {
    try {
      final ids = (departureId: departureId, arrivalId: arrivalId);
      // 로드가 실패한 상태여도 이번 검색은 남긴다(다음 기록으로 자기치유).
      final previous =
          await future.catchError((_) => const <RecentSearchIds>[]);
      final next = [
        ids,
        for (final e in previous)
          if (e != ids) e,
      ].take(_maxStoredRecentSearches).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKeyRecentSearch,
        json.encode([
          for (final e in next) {'d': e.departureId, 'a': e.arrivalId},
        ]),
      );
      state = AsyncData(next);
    } catch (_) {
      // 저장 실패는 조용히 무시(다음 검색이 다시 시도).
    }
  }
}

/// 최근 검색 id 쌍들을 실제 `Station` 쌍으로 resolve 해 최신순으로 최대
/// [maxRecentSearches] 건 반환한다.
///
/// 저장된 id 중 하나라도 현재 역 목록에서 매칭되지 않는 건(삭제/개명된 역)은
/// 건너뛴다. 또 id 는 달라도 출발·도착이 각각 같은 물리 역인 건(환승역의 노선별
/// 레코드)은 화면에 똑같이 보이므로 최신 1건만 남긴다. 남는 건이 없으면 빈
/// 목록이라 UI 가 이력 섹션을 숨긴다.
@Riverpod(keepAlive: true)
Future<List<RecentSearchPair>> recentSearchStations(Ref ref) async {
  final history = await ref.watch(recentSearchProvider.future);
  if (history.isEmpty) return const [];

  final stations = await ref.watch(allStationsProvider.future);
  final byId = {for (final s in stations) s.id: s};

  final result = <RecentSearchPair>[];
  for (final ids in history) {
    final departure = byId[ids.departureId];
    final arrival = byId[ids.arrivalId];
    if (departure == null || arrival == null) continue;
    final duplicate = result.any(
      (p) =>
          isSamePhysicalStation(p.departure, departure) &&
          isSamePhysicalStation(p.arrival, arrival),
    );
    if (duplicate) continue;
    result.add((departure: departure, arrival: arrival));
    if (result.length == maxRecentSearches) break;
  }
  return result;
}
