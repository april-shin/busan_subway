import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import 'path_on_line.dart';

/// 열차의 운행 경로(`trainPathStationIds`)가 사용자의 탑승 구간
/// (`routeStationIds`)을 실제로 태워주는지 판정한다.
///
/// 5호선처럼 지선이 있는 노선에서는 노선 ID와 방향(하행/외선)이 같아도 열차가
/// 사용자의 경로와 다른 지선으로 갈라진다. 예) `천호 → 굽은다리` 경로에서
/// 5호선 하행 "마천행"은 강동에서 갈라져 굽은다리를 지나지 않는다.
///
/// 판정 규칙 — 경로의 역들이 열차 경로에 **순서대로** 나타나야 한다:
///  - 급행 세그먼트는 정차역만 담고 있어 열차 경로(전 역)의 부분수열이 되므로,
///    "부분수열" 규칙이어야 급행이 통째로 걸러지지 않는다.
///  - 경로 역을 못 찾았는데 열차 경로가 **아직 남아 있으면** 갈라진 것이다 → false.
///  - 열차 경로가 **소진된 뒤** 남은 경로 역은 열차가 중간 종착일 뿐이다
///    (예: `천호 → 하남검단산` 경로의 "상일동행"). 같은 지선을 타고 가는
///    동안은 유효한 열차이므로 true.
///
/// 어느 한쪽이라도 비어 있으면 판정 불가로 보고 true(통과)를 반환한다.
bool trainPathCoversRoute({
  required List<String> routeStationIds,
  required List<String> trainPathStationIds,
}) {
  if (routeStationIds.isEmpty || trainPathStationIds.isEmpty) return true;

  var cursor = 0;
  for (final routeId in routeStationIds) {
    final found = trainPathStationIds.indexOf(routeId, cursor);
    if (found >= 0) {
      cursor = found + 1;
      continue;
    }
    // 열차 경로가 남아 있는데 경로 역이 없다 → 다른 지선으로 갈라졌다.
    if (cursor < trainPathStationIds.length) return false;
    // 열차 경로가 소진됐다 → 중간 종착. 여기까지는 같은 지선.
    return true;
  }
  return true;
}

/// 실시간 열차가 활성 경로와 같은 지선을 타는지 판정한다.
///
/// [destinationStationIds] 는 열차 행선지(종착역) 이름에 해당하는 **해당 노선의**
/// 역 ID 후보들이다. 행선지에서 노선 내 경로를 찾아 [trainPathCoversRoute] 로
/// 판정한다.
///
/// 판정에 필요한 데이터가 없으면(경로 역 부족, 행선지 미해석, 노선 내 경로
/// 탐색 실패) **통과(true)** 시킨다 — 지선 판정 실패로 정상 열차가 지도에서
/// 사라지는 것보다 낫다(fail-open).
bool trainStaysOnRouteBranch({
  required List<String> routeStationIds,
  required List<String> destinationStationIds,
  required String lineId,
  required List<Connection> connections,
  required bool isDown,
}) {
  if (routeStationIds.length < 2 || destinationStationIds.isEmpty) return true;

  var resolved = false;
  for (final destId in destinationStationIds) {
    final path = findStationIdPathOnLine(
      fromStationId: routeStationIds.first,
      toStationId: destId,
      lineId: lineId,
      connections: connections,
      isDown: isDown,
    );
    if (path == null) continue;
    resolved = true;
    // 동명 후보가 여러 개면 하나라도 경로를 태워주면 통과로 본다.
    if (trainPathCoversRoute(
      routeStationIds: routeStationIds,
      trainPathStationIds: path,
    )) {
      return true;
    }
  }

  // 행선지까지의 경로를 하나도 못 구했다 → 판정 불가 → 통과.
  return !resolved;
}

/// 실시간 도착정보의 **행선지 이름**으로 지선 통과 여부를 판정하는 함수를 만든다.
///
/// [trainStaysOnRouteBranch] 를 행선지별로 한 번만 호출하고 결과를 메모한다 —
/// 같은 행선지의 열차가 여러 대 오므로 판정(노선 인접리스트 구축 + BFS)을
/// 열차마다 반복할 이유가 없다.
///
/// [routeStationIds] 는 탑승 구간의 역 ID 목록(탑승역부터 순서대로), [lineId] 는
/// **base 노선 ID**(가상 급행 `9E` 가 아닌 `9`) 여야 한다. [stations] 에서 해당
/// 노선의 역만 골라 행선지 이름을 역 ID로 해석한다.
///
/// 판정 데이터가 부족하면(구간 역 2개 미만, [stations]/[connections] 미로딩,
/// 행선지 미해석) 항상 true 를 돌려준다 — fail-open. 지선 판정 실패로 정상
/// 열차가 사라지는 것보다 필터를 걸지 않는 편이 안전하다.
bool Function(String destination) makeDestinationBranchFilter({
  required List<String> routeStationIds,
  required String lineId,
  required bool isDown,
  required List<Station> stations,
  required List<Connection> connections,
}) {
  if (routeStationIds.length < 2 || stations.isEmpty || connections.isEmpty) {
    return (_) => true;
  }

  final idsByName = <String, List<String>>{};
  for (final s in stations) {
    if (s.lineId != lineId) continue;
    idsByName.putIfAbsent(s.name, () => []).add(s.id);
  }

  final cache = <String, bool>{};
  return (destination) {
    if (destination.isEmpty) return true;
    return cache.putIfAbsent(
      destination,
      () => trainStaysOnRouteBranch(
        routeStationIds: routeStationIds,
        destinationStationIds: idsByName[destination] ?? const [],
        lineId: lineId,
        connections: connections,
        isDown: isDown,
      ),
    );
  };
}
