/// 환승 가이드 JSON(`assets/json/transfer_guides.json`)의 키 포맷을 조립·조회한다.
///
/// 포맷 v2 (5-tuple, 구체 키):
///   `{환승역명}_{도착노선ID}_{도착방향}_{목적노선ID}_{목적방향}`
/// 포맷 v1 (4-tuple, 폴백 키 — 목적 방향 무관):
///   `{환승역명}_{도착노선ID}_{도착방향}_{목적노선ID}`
///
/// - 방향: `up` (상행/내선) 또는 `down` (하행/외선)
///
/// 같은 환승역·같은 도착 방향이라도 **환승 후 타는 노선의 방향**에 따라 최적
/// 객차·문이 갈리는 곳이 있다(사당 4호선→2호선: 내선 4-1 / 외선 10-4 등).
/// 그런 환승만 5-tuple 로 등록하고, 방향과 무관한 대다수 환승은 4-tuple 로 둔다.
/// 조회는 항상 **구체 키 → 폴백 키** 순서의 2단이다([lookupTransferGuide]).
///
/// 런타임(`SearchRoute._resolveTransferGuide`)과 도구 스크립트
/// (`tool/import_transfer_guides.dart`)가 같은 포맷을 공유하도록 이 파일을
/// 단일 진입점으로 사용한다. 키 문자열을 다른 곳에서 직접 조립하지 말 것 —
/// 그 중복이 방향 스키마 불일치 버그의 원인이었다.
String buildTransferGuideKey({
  required String stationName,
  required String arrivalLineId,
  required bool isDown,
  required String destinationLineId,
  bool? destIsDown,
}) {
  final direction = isDown ? 'down' : 'up';
  final base = '${stationName}_${arrivalLineId}_${direction}_$destinationLineId';
  if (destIsDown == null) return base;
  return '${base}_${destIsDown ? 'down' : 'up'}';
}

/// 환승 가이드 맵에서 2단(구체 → 폴백) 조회를 수행한다.
///
/// [destIsDown] 이 주어지면 5-tuple 구체 키를 먼저 찾고, 없으면 4-tuple 폴백 키로
/// 재조회한다. [destIsDown] 이 null(= 목적 방향 산출 불가)이면 폴백 키만 쓴다.
///
/// 조회 대상 타입에 의존하지 않도록 제네릭으로 둔다(core 레이어가 domain 엔티티를
/// 알 필요가 없다). 런타임은 `Map<String, TransferGuide>` 로, 도구는 raw JSON 맵으로
/// 같은 함수를 쓸 수 있다.
T? lookupTransferGuide<T>(
  Map<String, T> guides, {
  required String stationName,
  required String arrivalLineId,
  required bool isDown,
  required String destinationLineId,
  bool? destIsDown,
}) {
  if (destIsDown != null) {
    final specific = guides[buildTransferGuideKey(
      stationName: stationName,
      arrivalLineId: arrivalLineId,
      isDown: isDown,
      destinationLineId: destinationLineId,
      destIsDown: destIsDown,
    )];
    if (specific != null) return specific;
  }
  return guides[buildTransferGuideKey(
    stationName: stationName,
    arrivalLineId: arrivalLineId,
    isDown: isDown,
    destinationLineId: destinationLineId,
  )];
}
