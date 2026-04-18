import '../../../core/utils/line_direction.dart';
import '../../../domain/entities/route_result.dart';

// 역 ID 쌍 기반 방향 판정(`isDownBetween`)은 core 레이어로 이동되었다.
// 본 파일은 RouteSegment 기반 세그먼트 단위 판정과 문자열 파싱만 담당한다.
export '../../../core/utils/line_direction.dart' show isDownBetween;

/// 방향 판별이 가능한 첫 번째 세그먼트를 반환한다 (역 2개 이상).
///
/// 환승역이 출발역인 경우 첫 세그먼트에 역이 1개만 포함될 수 있으므로,
/// 방향 판별에 필요한 최소 2역을 가진 세그먼트를 찾는다.
RouteSegment? findFirstDirectionalSegment(RouteResult routeResult) {
  for (final seg in routeResult.segments) {
    if (seg.stations.length >= 2) return seg;
  }
  return null;
}

/// RouteSegment의 역 ID 순서로 하행/외선 여부를 결정한다.
///
/// - 일반 노선: 숫자 ID가 증가하면 하행(index 1), 감소하면 상행(index 0)
/// - 2호선 순환: 첫 두 역 ID 비교 + 순환 경계(201↔243) 처리
/// - 4호선: 진접선(449-452) 방향 역전 특수 처리
bool isDownDirection(RouteSegment segment) {
  if (segment.stations.length < 2) return false;

  // 2호선은 순환선이라 첫 두 역 쌍으로 방향을 확정해야 한다.
  // 그 외 노선은 세그먼트의 첫/끝 역 ID만으로 충분.
  if (segment.lineId == '2') {
    return isDownBetween(
      segment.stations.first.id,
      segment.stations[1].id,
      segment.lineId,
    );
  }

  return isDownBetween(
    segment.stations.first.id,
    segment.stations.last.id,
    segment.lineId,
  );
}

/// ArrivalInfo.direction 문자열이 하행/외선인지 판별한다.
bool isDownDirectionString(String direction) {
  return direction == '하행' || direction == '외선';
}
