/// 실시간 API 의 호선 코드(subwayId)를 앱 내부 lineId 로 변환하는 매핑.
///
/// 부산 전환으로 **비어 있다.** 서울 열린데이터 API 코드(1001~1094)는 부산 노선과
/// 무관해 제거했고, 실시간 기능은 `FeatureFlags.realtimeEnabled` 로 꺼져 있다.
/// 부산 실시간 API 를 연동할 때 그 API 의 노선 코드 → 앱 lineId(`'1'`~`'4'`,
/// `'동해'`, `'부산김해'`)를 실측해 채운다.
///
/// 맵이 비어 있는 동안 모든 도착 행의 노선은 "알 수 없음"(null)으로 해석되어
/// 노선 필터를 통과하지 못한다.
const Map<String, String> subwayIdToLineId = {};

/// 앱 lineId → 실시간 열차 위치 API 의 노선명 파라미터.
///
/// 도착정보 API 는 역명으로 조회하지만 위치 API 는 **노선명**으로 조회한다.
/// 반환값이 null 이면 위치 API 로 조회할 수 없는 노선이다 — [subwayIdToLineId] 에
/// 없는 노선은 실시간 미제공으로 보고 null 을 돌려준다(현재는 전 노선 null).
String? positionApiLineName(String lineId) {
  if (lineId.isEmpty) return null;
  if (!subwayIdToLineId.containsValue(lineId)) return null;
  if (RegExp(r'^[1-9]$').hasMatch(lineId)) return '$lineId호선';
  return '$lineId선';
}
