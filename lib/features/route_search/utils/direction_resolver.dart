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
/// **판정 기준은 세그먼트의 첫 두 역**이다. 이 값이 답해야 하는 질문은
/// "출발역에서 어느 방향 열차를 타는가"(출발시각 조회·실시간 열차 필터)이므로,
/// 끝 역이 아니라 **탑승 직후 진행 방향**이 기준이어야 한다.
///
/// - 일반 노선: 숫자 ID가 증가하면 하행(index 1), 감소하면 상행(index 0)
/// - 2호선 순환: 순환 경계(201↔243) 처리 — 첫/끝 비교로는 방향이 뒤집힌다
/// - 4호선: 진접선(449-452) 방향 역전 특수 처리
///
/// 단조로운 세그먼트에서는 첫/끝 비교와 결과가 같다. 달라지는 경우는 세그먼트
/// 안에서 진행 방향이 **뒤집히는** 구간뿐이다 — 지선 dead-end 에서 출발해
/// 분기역을 지나 본선 반대편으로 가는 경로가 그렇다. 예) `광명(1A1, rank 166.5)
/// → 금천구청(166) → 독산(167)` 은 rank 가 166.5 → 166 → 167 로 꺾인다.
/// 첫/끝(166.5 vs 167)으로 보면 하행이지만 광명에서 실제로 타는 열차는
/// **상행**(영등포행 셔틀)이다. 하행으로 잡으면 광명의 하행 출발 시간표가
/// 없어(하행 종착역) 출발시각 선택이 통째로 비활성된다.
/// 회귀 가드: `test/core/utils/gwangmyeong_branch_direction_test.dart`.
bool isDownDirection(RouteSegment segment) {
  if (segment.stations.length < 2) return false;

  return isDownBetween(
    segment.stations.first.id,
    segment.stations[1].id,
    segment.lineId,
  );
}

/// ArrivalInfo.direction 문자열이 하행/외선인지 판별한다.
bool isDownDirectionString(String direction) {
  return direction == '하행' || direction == '외선';
}
