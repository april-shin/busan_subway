import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import 'path_on_line.dart';

/// 열차가 사용자의 탑승 구간을 어디까지 태워주는지.
///
/// 노선 ID와 방향(하행/외선)이 같아도 열차가 구간을 완주하지 못하는 경우가
/// 두 가지 있고, 화면마다 다루는 방식이 다르다:
///  - 경로 결과의 출발 시각 — [full] 만 쓴다. 그 열차만 타서 하차역에 닿아야
///    하므로 나머지는 아예 후보가 아니다.
///  - 지도의 실시간 열차 — 아무것도 빼지 않고 [full] 이 아닌 열차를 흐리게
///    (유령) 표시한다. [earlyTerminus] 든 [diverged] 든 아이콘이 그려지는 구간
///    (현재역 → 출발역)에서는 실제로 같은 선로를 달리므로 — 갈라지거나 멈추는
///    지점은 출발역 이후다 — 숨기면 지도만 비어 보인다.
enum RouteCoverage {
  /// 하차역까지 완주한다.
  full,

  /// 같은 선로를 가지만 하차역 **앞에서** 운행을 끝낸다(중간 종착).
  /// 예) `내방 → 장암` 경로의 7호선 상행 "도봉산행".
  earlyTerminus,

  /// 도중에 다른 지선으로 갈라져 하차역 쪽 선로를 아예 타지 않는다.
  /// 예) `천호 → 굽은다리` 경로의 5호선 하행 "마천행"(강동에서 분기).
  diverged,
}

/// 열차의 운행 경로(`trainPathStationIds`)가 사용자의 탑승 구간
/// (`routeStationIds`)을 어디까지 태워주는지 분류한다.
///
/// 판정 규칙 — 경로의 역들이 열차 경로에 **순서대로** 나타나야 한다:
///  - 급행 세그먼트는 정차역만 담고 있어 열차 경로(전 역)의 부분수열이 되므로,
///    "부분수열" 규칙이어야 급행이 통째로 걸러지지 않는다.
///  - 경로 역을 못 찾았는데 열차 경로가 **아직 남아 있으면** 갈라진 것이다
///    → [RouteCoverage.diverged].
///  - 열차 경로가 **소진된 뒤** 남은 경로 역이 있으면 중간 종착이다
///    → [RouteCoverage.earlyTerminus].
///
/// 어느 한쪽이라도 비어 있으면 판정 불가로 보고 [RouteCoverage.full] 을
/// 반환한다(fail-open).
RouteCoverage classifyTrainPathCoverage({
  required List<String> routeStationIds,
  required List<String> trainPathStationIds,
}) {
  if (routeStationIds.isEmpty || trainPathStationIds.isEmpty) {
    return RouteCoverage.full;
  }

  var cursor = 0;
  for (final routeId in routeStationIds) {
    final found = trainPathStationIds.indexOf(routeId, cursor);
    if (found >= 0) {
      cursor = found + 1;
      continue;
    }
    // 열차 경로가 남아 있는데 경로 역이 없다 → 다른 지선으로 갈라졌다.
    if (cursor < trainPathStationIds.length) return RouteCoverage.diverged;
    // 열차 경로가 소진됐다 → 같은 선로를 가다 하차역 앞에서 끝난다.
    return RouteCoverage.earlyTerminus;
  }
  return RouteCoverage.full;
}

/// 열차 경로가 탑승 구간을 **끝까지** 태워주는지.
///
/// `classifyTrainPathCoverage(...) == RouteCoverage.full` 의 축약이다.
/// 중간 종착·지선 분기 둘 다 false — 그 열차만 타서는 하차역에 닿지 못한다.
bool trainPathCoversRoute({
  required List<String> routeStationIds,
  required List<String> trainPathStationIds,
}) =>
    classifyTrainPathCoverage(
      routeStationIds: routeStationIds,
      trainPathStationIds: trainPathStationIds,
    ) ==
    RouteCoverage.full;

/// 실시간 열차의 **행선지**로 탑승 구간 완주 여부를 분류한다.
///
/// [destinationStationIds] 는 열차 행선지(종착역) 이름에 해당하는 **해당 노선의**
/// 역 ID 후보들이다. 탑승역 → 행선지의 노선 내 경로를 찾아
/// [classifyTrainPathCoverage] 로 판정한다.
///
/// 판정에 필요한 데이터가 없으면(경로 역 부족, 행선지 미해석, 노선 내 경로
/// 탐색 실패) [RouteCoverage.full] 을 반환한다 — 판정 실패로 정상 열차가
/// 지도에서 사라지는 것보다 낫다(fail-open).
RouteCoverage classifyDestinationCoverage({
  required List<String> routeStationIds,
  required List<String> destinationStationIds,
  required String lineId,
  required List<Connection> connections,
  required bool isDown,
}) {
  if (routeStationIds.length < 2 || destinationStationIds.isEmpty) {
    return RouteCoverage.full;
  }

  // 동명 후보가 여러 개면 가장 유리한 판정을 채택한다(하나라도 태워주면 통과).
  RouteCoverage? best;
  for (final destId in destinationStationIds) {
    final path = findStationIdPathOnLine(
      fromStationId: routeStationIds.first,
      toStationId: destId,
      lineId: lineId,
      connections: connections,
      isDown: isDown,
    );
    if (path == null) continue;
    final coverage = classifyTrainPathCoverage(
      routeStationIds: routeStationIds,
      trainPathStationIds: path,
    );
    if (coverage == RouteCoverage.full) return RouteCoverage.full;
    if (best == null || coverage.index < best.index) best = coverage;
  }

  // 행선지까지의 경로를 하나도 못 구했다 → 판정 불가 → fail-open.
  return best ?? RouteCoverage.full;
}

/// 실시간 도착정보의 **행선지 이름**으로 구간 완주 여부를 분류하는 함수를 만든다.
///
/// [classifyDestinationCoverage] 를 행선지별로 한 번만 호출하고 결과를 메모한다 —
/// 같은 행선지의 열차가 여러 대 오므로 판정(노선 인접리스트 구축 + BFS)을
/// 열차마다 반복할 이유가 없다.
///
/// [routeStationIds] 는 탑승 구간의 역 ID 목록(탑승역부터 순서대로), [lineId] 는
/// **base 노선 ID**(가상 급행 `{base}E` 가 아닌 base) 여야 한다. [stations] 에서 해당
/// 노선의 역만 골라 행선지 이름을 역 ID로 해석한다.
///
/// 판정 데이터가 부족하면(구간 역 2개 미만, [stations]/[connections] 미로딩,
/// 행선지 미해석) 항상 [RouteCoverage.full] 을 돌려준다 — fail-open. 판정 실패로
/// 정상 열차가 사라지는 것보다 필터를 걸지 않는 편이 안전하다.
///
/// (서울 시절에는 순환선 2호선을 판정에서 제외했다. 부산은 전 노선이 선형이라
/// 노선 예외가 없다.)
RouteCoverage Function(String destination) makeDestinationCoverageClassifier({
  required List<String> routeStationIds,
  required String lineId,
  required bool isDown,
  required List<Station> stations,
  required List<Connection> connections,
}) {
  if (routeStationIds.length < 2 ||
      stations.isEmpty ||
      connections.isEmpty) {
    return (_) => RouteCoverage.full;
  }

  final idsByName = <String, List<String>>{};
  for (final s in stations) {
    if (s.lineId != lineId) continue;
    idsByName.putIfAbsent(s.name, () => []).add(s.id);
  }

  final cache = <String, RouteCoverage>{};
  return (destination) {
    if (destination.isEmpty) return RouteCoverage.full;
    return cache.putIfAbsent(
      destination,
      () => classifyDestinationCoverage(
        routeStationIds: routeStationIds,
        destinationStationIds: idsByName[destination] ?? const [],
        lineId: lineId,
        connections: connections,
        isDown: isDown,
      ),
    );
  };
}

/// 행선지가 탑승 구간을 **끝까지** 태워주는 열차만 통과시키는 필터를 만든다.
///
/// 경로 결과의 출발 시각용 — 중간 종착 열차도 제외한다
/// ([makeDestinationCoverageClassifier] 의 `== RouteCoverage.full` 축약).
bool Function(String destination) makeDestinationBranchFilter({
  required List<String> routeStationIds,
  required String lineId,
  required bool isDown,
  required List<Station> stations,
  required List<Connection> connections,
}) {
  final classify = makeDestinationCoverageClassifier(
    routeStationIds: routeStationIds,
    lineId: lineId,
    isDown: isDown,
    stations: stations,
    connections: connections,
  );
  return (destination) => classify(destination) == RouteCoverage.full;
}
