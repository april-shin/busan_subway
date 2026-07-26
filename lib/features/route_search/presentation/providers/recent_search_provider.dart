import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../domain/entities/station.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';

part 'recent_search_provider.g.dart';

/// 가장 최근에 검색한 출발→도착 1건의 Station ID 쌍을 보관한다.
///
/// 저장은 `SharedPreferences` 에 JSON(`{"d": 출발id, "a": 도착id}`)으로 이뤄지며,
/// 값이 없거나 파싱 실패 시 null.
///
/// [`Station.id`](../../../../domain/entities/station.dart) 는
/// `"{stationId}_{lineId}"` 포맷이므로 이름 대신 id 를 저장한다(환승역 노선
/// 특정 유지 + `stations.json` 변경 시 스냅샷 drift 방지 — `home_station_provider`
/// 와 동일 논리).
const String _prefKeyRecentSearch = 'pref_recent_search';

@Riverpod(keepAlive: true)
class RecentSearch extends _$RecentSearch {
  @override
  Future<({String departureId, String arrivalId})?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyRecentSearch);
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return null;
      final d = decoded['d'];
      final a = decoded['a'];
      if (d is! String || a is! String) return null;
      return (departureId: d, arrivalId: a);
    } on FormatException {
      return null;
    }
  }

  /// 최근 검색 1건을 기록한다(기존 값 덮어쓰기).
  ///
  /// fire-and-forget 으로 호출되므로(반환 Future 를 버림) 저장 실패가 unhandled
  /// async error 로 전파되지 않도록 내부에서 흡수한다. 이력 기록 실패는 핵심
  /// 기능(경로 탐색)에 영향이 없다.
  Future<void> record(String departureId, String arrivalId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKeyRecentSearch,
        json.encode({'d': departureId, 'a': arrivalId}),
      );
      state = AsyncData((departureId: departureId, arrivalId: arrivalId));
    } catch (_) {
      // 저장 실패는 조용히 무시(다음 검색이 다시 시도).
    }
  }
}

/// 최근 검색 id 쌍을 실제 `Station` 엔티티 쌍으로 resolve 한다.
///
/// 이력 없음, 또는 저장된 id 중 하나라도 현재 역 목록에서 매칭되지 않으면
/// (삭제/개명된 역) null 을 반환해 UI 가 이력 섹션을 숨기도록 한다. 다음 정상
/// 검색이 유효한 쌍으로 덮어쓰므로 자기치유된다.
@Riverpod(keepAlive: true)
Future<({Station departure, Station arrival})?> recentSearchStations(
  Ref ref,
) async {
  final ids = await ref.watch(recentSearchProvider.future);
  if (ids == null) return null;

  final stations = await ref.watch(allStationsProvider.future);
  Station? departure;
  Station? arrival;
  for (final s in stations) {
    if (s.id == ids.departureId) departure = s;
    if (s.id == ids.arrivalId) arrival = s;
  }
  if (departure == null || arrival == null) return null;
  return (departure: departure, arrival: arrival);
}
