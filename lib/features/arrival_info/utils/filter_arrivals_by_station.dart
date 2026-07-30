import '../../../core/constants/subway_id_mapping.dart';
import '../../../core/utils/same_station.dart';
import '../../../domain/entities/arrival_info.dart';
import '../../../domain/entities/station.dart';

/// 동명이역인 경우 [stationId] 역에 실제로 속한 노선의 열차만 남긴다.
///
/// 서울 열린데이터 API 는 역명으로 조회하므로 5호선 양평을 조회하면 53km 떨어진
/// 경의중앙선 양평의 열차까지 함께 돌려준다. 그대로 두면 도착 정보 화면에 노선
/// 탭이 생겨 두 역이 환승역처럼 보인다.
///
/// 아래 경우는 필터하지 않고 [arrivals] 를 그대로 돌려준다(fail-open — 필터가
/// 과하게 걸려 정상 도착 정보가 사라지는 쪽이 더 나쁘다):
/// - [stationId] 가 null(URL 직접 진입 등)이거나 [stations] 에 없는 ID
/// - [stations] 미로딩(null)
/// - 동명이역이 아닌 역 — 일반역·환승역의 응답은 전부 그 역의 것이다
/// - [subwayIdToLineId] 에 없는 호선 코드 — 판단 근거가 없으므로 살려 둔다
List<ArrivalInfo> filterArrivalsToOwnLines({
  required List<ArrivalInfo> arrivals,
  required String? stationId,
  required List<Station>? stations,
}) {
  if (stationId == null || stations == null) return arrivals;

  Station? target;
  for (final s in stations) {
    if (s.id == stationId) {
      target = s;
      break;
    }
  }
  if (target == null) return arrivals;

  final ownLineIds = distinctSameNameLineIds(
    target: target,
    stations: stations,
  );
  if (ownLineIds == null) return arrivals;

  return arrivals.where((a) {
    final lineId = subwayIdToLineId[a.subwayId];
    return lineId == null || ownLineIds.contains(lineId);
  }).toList();
}
