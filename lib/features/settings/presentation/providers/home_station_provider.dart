import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../domain/entities/station.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';

part 'home_station_provider.g.dart';

/// 사용자가 지정한 지도 초기 중심역(홈 역) 의 Station ID 를 보관한다.
///
/// 저장은 `SharedPreferences` 에 문자열로 이뤄지며, 값이 없으면 null (기본값 =
/// 서울역, JS `INITIAL_CENTER_X/Y` 로 결정).
///
/// [`Station.id`](../../../../domain/entities/station.dart) 는
/// `"{stationId}_{lineId}"` 포맷이므로 노선 특정 없이 이름만 저장하면
/// 환승역에서 어느 노선 대표 레코드인지 잃어버리므로 id 를 저장한다.
const String _prefKeyHomeStationId = 'pref_home_station_id';

@Riverpod(keepAlive: true)
class HomeStationId extends _$HomeStationId {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyHomeStationId);
  }

  /// 홈 역을 설정하거나 null 을 넘겨 초기화한다.
  Future<void> setHomeStation(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_prefKeyHomeStationId);
    } else {
      await prefs.setString(_prefKeyHomeStationId, id);
    }
    state = AsyncData(id);
  }
}

/// 홈 역의 실제 `Station` 엔티티. id 미설정 또는 매칭 실패 시 null.
///
/// 지도 위 팬 이동에는 `svgX/svgY` 가 필요하므로 반드시 Station 으로 resolve
/// 한다. 호출자는 이 provider 를 watch 하면 홈 역 변경 시 자동 갱신된다.
@Riverpod(keepAlive: true)
Future<Station?> homeStation(Ref ref) async {
  final id = await ref.watch(homeStationIdProvider.future);
  if (id == null) return null;

  final stations = await ref.watch(allStationsProvider.future);
  for (final s in stations) {
    if (s.id == id) return s;
  }
  return null;
}
