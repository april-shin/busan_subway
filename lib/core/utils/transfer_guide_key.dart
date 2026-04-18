/// 환승 가이드 JSON(`assets/json/transfer_guides.json`)의 키 포맷을 조립한다.
///
/// 포맷: `{환승역명}_{도착노선ID}_{도착방향}_{목적노선ID}`
/// - 도착방향: `up` (상행/내선) 또는 `down` (하행/외선)
///
/// 같은 환승역이라도 도착 방향과 목적 노선에 따라 최적 객차·문이 달라지므로
/// 4-tuple 단위로 키를 구성한다.
///
/// 런타임(`SearchRoute._resolveTransferGuide`)과 도구 스크립트가 같은 포맷을
/// 공유하도록 이 함수를 단일 진입점으로 사용한다.
String buildTransferGuideKey({
  required String stationName,
  required String arrivalLineId,
  required bool isDown,
  required String destinationLineId,
}) {
  final direction = isDown ? 'down' : 'up';
  return '${stationName}_${arrivalLineId}_${direction}_$destinationLineId';
}
