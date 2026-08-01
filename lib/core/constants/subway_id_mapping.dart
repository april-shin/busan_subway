/// 서울 열린데이터 API의 호선 코드(subwayId)를 앱 내부 lineId로 변환하는 매핑
///
/// 2026-04-07 API 실측 기준으로 검증됨.
/// 인천1호선, 인천2호선, 의정부경전철, 김포골드라인, 에버라인(용인경전철)은
/// 서울 API 미제공.
///
/// 2026-07-30 정정: `1081` 은 에버라인이 아니라 **경강선**이다.
/// `realtimeStationArrival` 실측 — 이천·판교·성남·이매 모두 subwayId=1081 로
/// 응답하며 trainLineNm 이 "판교행"/"여주행"(경강선 종점). 에버라인 역(기흥)은
/// 1075(수인분당)만 응답하고 전대·에버랜드는 응답 자체가 없다.
/// 오매핑 상태에서는 경강선 실시간 도착·열차위치가 에버라인으로 흘러갔다.
const subwayIdToLineId = {
  '1001': '1',
  '1002': '2',
  '1003': '3',
  '1004': '4',
  '1005': '5',
  '1006': '6',
  '1007': '7',
  '1008': '8',
  '1009': '9',
  '1032': 'GTX-A',
  '1063': '경의중앙',
  '1065': '공항철도',
  '1067': '경춘',
  '1075': '수인분당',
  '1077': 'SB',
  '1081': '경강',
  '1092': '우이신설',
  '1093': '서해',
  '1094': '신림',
};

/// 앱 lineId → 실시간 열차 위치 API(`realtimePosition`)의 노선명 파라미터.
///
/// 도착정보 API 는 역명으로 조회하지만 위치 API 는 **노선명**으로 조회하며,
/// 표기 규칙이 노선마다 다르다(2026-07-31 전 노선 실측):
/// - 숫자 노선: `1호선` … `9호선`
/// - 광역·경전철: `수인분당선`·`경의중앙선`·`경춘선`·`경강선`·`우이신설선`·`서해선`·`신림선`
/// - 접미사 없음: `공항철도`, `GTX-A`
/// - 신분당선은 앱 lineId 가 `SB` 라 직접 대응이 필요하다.
///
/// 반환값이 null 이면 위치 API 로 조회할 수 없는 노선(도착 API 미제공 노선 등)이다.
String? positionApiLineName(String lineId) {
  if (lineId.isEmpty) return null;
  // 가상 급행 노선(`5E` 등)은 실제 노선명으로 정규화한다.
  final base = lineId.endsWith('E') || lineId.endsWith('M')
      ? lineId.substring(0, lineId.length - 1)
      : lineId;
  if (!subwayIdToLineId.containsValue(base)) return null;
  if (RegExp(r'^[1-9]$').hasMatch(base)) return '$base호선';
  switch (base) {
    case 'SB':
      return '신분당선';
    case '공항철도':
    case 'GTX-A':
      return base;
    default:
      return '$base선';
  }
}
