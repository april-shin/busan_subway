import '../../domain/entities/connection.dart';
import '../../domain/entities/station.dart';
import 'line_direction.dart';

/// 경로 확장 결과: 새 좌표 리스트 + 새 주행시간 리스트.
typedef ExpandedPath = ({
  List<({double x, double y})> points,
  List<int> durations,
});

/// 확장 안전 상한. 순환선 무한 루프 방어 + 성능 방어.
const _maxExpandSteps = 30;

/// 남은시간이 현재 `basePoints` 총시간보다 크면, `findPreviousStationId`로
/// 이전 역을 앞에 붙여 경로를 늘린다.
///
/// 기준 "총시간" = `durations` 합 (주행만). 중간역 정차시간은 포함하지 않는다
/// — JS 측 95% 클램프가 정차 시각화를 대신하므로 알고리즘 시간축에서 제외.
///
/// 안전 장치:
/// - 방문 역 `Set` 으로 순환선 무한 루프 차단
/// - 최대 [_maxExpandSteps] 칸까지만 확장
/// - 이전 역을 찾지 못하거나 Station 조회 실패 시 종료
///
/// 불변 패턴: 원본 `basePoints` / `baseDurations` 는 변경하지 않고, prepend 요소를
/// 역순 누적 후 새 리스트로 조립.
ExpandedPath expandPathBackward({
  required List<({double x, double y})> basePoints,
  required List<int> baseDurations,
  required String currentStationId,
  required String lineId,
  required bool isDown,
  required List<Connection> connections,
  required Map<String, List<Station>> stationsById,
  required int targetRemainingSeconds,
}) {
  // basePoints 가 비어있거나 단일 점이면 확장 대상 세그먼트 자체가 없다.
  // 단일 점은 "현재역 == 출발역(도착)" 이므로 그대로 반환.
  if (basePoints.length < 2) {
    return (points: basePoints, durations: baseDurations);
  }

  // 현재 총시간: 주행시간 합만 (정차 제외).
  var accumulatedTotal = baseDurations.fold<int>(0, (a, b) => a + b);

  if (targetRemainingSeconds <= accumulatedTotal) {
    return (points: basePoints, durations: baseDurations);
  }

  final visited = <String>{currentStationId};
  final reversedPrependPoints = <({double x, double y})>[];
  final reversedPrependDurations = <int>[];

  var headId = currentStationId;

  for (var guard = 0; guard < _maxExpandSteps; guard++) {
    if (targetRemainingSeconds <= accumulatedTotal) break;

    final prevId = findPreviousStationId(
      currentId: headId,
      lineId: lineId,
      isDown: isDown,
      connections: connections,
    );
    if (prevId == null) break;
    if (visited.contains(prevId)) break;

    // 이전 역의 Station 조회 (같은 lineId 우선)
    final candidates = stationsById[prevId];
    if (candidates == null || candidates.isEmpty) break;
    final prevStation = candidates.firstWhere(
      (s) => s.lineId == lineId,
      orElse: () => candidates.first,
    );

    // 주행시간 조회: prevId ↔ headId 무방향 매칭
    int travelSecs = defaultExpandFallbackSeconds;
    for (final c in connections) {
      if (c.lineId != lineId || c.isTransfer) continue;
      if ((c.fromStationId == prevId && c.toStationId == headId) ||
          (c.fromStationId == headId && c.toStationId == prevId)) {
        travelSecs = c.travelTimeSeconds;
        break;
      }
    }

    // 역순 누적
    reversedPrependPoints.add((x: prevStation.svgX, y: prevStation.svgY));
    reversedPrependDurations.add(travelSecs);

    // 증분: 주행시간만 (정차 제외)
    accumulatedTotal += travelSecs;

    visited.add(prevId);
    headId = prevId;
  }

  if (reversedPrependPoints.isEmpty) {
    return (points: basePoints, durations: baseDurations);
  }

  // 역순 누적된 prepend 를 정순으로 뒤집어 basePoints 앞에 붙인다.
  final newPoints = <({double x, double y})>[
    for (var i = reversedPrependPoints.length - 1; i >= 0; i--)
      reversedPrependPoints[i],
    ...basePoints,
  ];
  final newDurations = <int>[
    for (var i = reversedPrependDurations.length - 1; i >= 0; i--)
      reversedPrependDurations[i],
    ...baseDurations,
  ];

  return (points: newPoints, durations: newDurations);
}

/// 이전 역 주행시간 조회 실패 시 사용할 폴백. `path_on_line.dart` 의
/// `defaultSegmentTravelSeconds` 와 동일한 의도이지만, 순환 import 를 피하기 위해
/// 별도 상수를 둔다.
const defaultExpandFallbackSeconds = 120;
