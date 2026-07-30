import 'dart:math' as math;

import '../../domain/entities/station.dart';

/// 같은 물리 역으로 묶을 최대 이격 거리(m).
///
/// 실제 환승역의 노선별 레코드는 같은 좌표(0m)이거나 출입구 기준 차이로 최대
/// 약 305m(보라매 7호선·신림선) 떨어져 있다. 반면 이름만 같고 실제로는 다른 역인
/// 5호선 양평(서울 영등포구) ↔ 경의중앙선 양평(경기 양평군)은 약 53km 떨어져
/// 있다. 두 분포 사이 간격이 크므로 2km 를 경계로 잡으면 안전하다.
const double sameStationRadiusMeters = 2000;

/// 두 레코드가 같은 물리 역인지 — 이름이 같고 [sameStationRadiusMeters] 안.
///
/// 환승역은 노선마다 별도 [Station] 레코드로 존재하지만 같은 역이다. 반대로
/// 이름이 같아도 멀리 떨어진 동명이역은 서로 다른 역이다.
bool isSamePhysicalStation(Station a, Station b) =>
    a.name == b.name && distanceMeters(a, b) <= sameStationRadiusMeters;

/// 역 목록에서 같은 물리 역 레코드를 하나로 합친 목록을 반환한다.
///
/// 이름만으로 합치면 동명이역(5호선 양평 vs 경의중앙선 양평)의 뒤쪽 레코드가
/// 사라져 검색으로 선택할 방법이 없어진다. 그래서 이름이 같더라도 좌표가
/// [sameStationRadiusMeters] 보다 멀면 별개 항목으로 남긴다.
///
/// 대표 레코드는 입력 순서상 첫 등장 레코드다(입력이 노선 ID 오름차순 정렬이라는
/// 전제하에 결정적 — 같은 역이 다른 화면에서도 같은 Station ID 로 표시됨).
/// 환승역 레코드는 `transferLines` 에 소속 노선 전체를 담고 있어 어느 레코드를
/// 대표로 써도 환승 정보는 동일하다.
List<Station> uniqueStationsByLocation(List<Station> stations) {
  final representativesByName = <String, List<Station>>{};
  final result = <Station>[];

  for (final s in stations) {
    final sameName = representativesByName.putIfAbsent(s.name, () => []);
    if (sameName.any((rep) => isSamePhysicalStation(rep, s))) continue;
    sameName.add(s);
    result.add(s);
  }

  return result;
}

/// [target] 이 동명이역인 경우 **그 역에 실제로 속한 노선 ID 집합**을, 아니면
/// null 을 반환한다.
///
/// 역명 기반 조회(실시간 도착정보 API 등)는 이름이 같은 다른 역의 결과까지
/// 함께 돌려준다. 5호선 양평을 조회하면 53km 떨어진 경의중앙선 양평의 열차가
/// 섞여 들어와 환승 노선처럼 보인다. 이 집합으로 걸러내면 된다.
///
/// **null 은 "필터하지 말라"는 뜻**이다(동명이역이 아님 → 일반역이든 환승역이든
/// 응답 전체가 그 역의 것). 필터 조건을 좁게 유지해 데이터 누락으로 정상 정보가
/// 사라지는 쪽보다 안전한 방향(fail-open)을 택한다.
Set<String>? distinctSameNameLineIds({
  required Station target,
  required List<Station> stations,
}) {
  final sameName = stations.where((s) => s.name == target.name);
  final hasDistinctTwin =
      sameName.any((s) => !isSamePhysicalStation(target, s));
  if (!hasDistinctTwin) return null;

  return {
    for (final s in sameName)
      if (isSamePhysicalStation(target, s)) ...[s.lineId, ...s.transferLines],
  };
}

/// 두 역 사이의 대략적인 거리(m).
///
/// 수 km 규모에서는 등거리 원통도법 근사로 충분하다(오차 1% 미만).
double distanceMeters(Station a, Station b) {
  const metersPerDegreeLat = 111320.0;
  final meanLatRad = (a.latitude + b.latitude) / 2 * math.pi / 180;
  final dy = (a.latitude - b.latitude) * metersPerDegreeLat;
  final dx =
      (a.longitude - b.longitude) * metersPerDegreeLat * math.cos(meanLatRad);
  return math.sqrt(dx * dx + dy * dy);
}
