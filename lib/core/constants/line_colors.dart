import 'dart:ui';

/// 부산 도시철도 노선 색상. 키는 앱 lineId(`lines.json` 의 `id`).
///
/// 값은 `assets/json/lines.json` 의 `colorValue` 와 일치해야 한다(유일 소스:
/// `tool/build_busan_data.py`). 노선을 추가·변경하면 두 쪽을 함께 고칠 것.
const Map<String, Color> lineColors = {
  '1': Color(0xFFF66130),
  '2': Color(0xFF1FAC14),
  '3': Color(0xFFB58941),
  '4': Color(0xFF286CD3),
  '동해': Color(0xFF6ECFF6),
  '부산김해': Color(0xFFAF49CC),
};

/// 부산 도시철도 노선 표시명. 키는 앱 lineId.
///
/// 가상 급행 노선(`{base}E`)은 여기 두지 않는다 — [lineNameFor] 가 base 노선 이름으로
/// 폴백한다(급행 표시는 별도 배지). 부산 데이터에는 현재 급행이 없다.
const Map<String, String> lineNames = {
  '1': '1호선',
  '2': '2호선',
  '3': '3호선',
  '4': '4호선',
  '동해': '동해선',
  '부산김해': '부산김해경전철',
};

/// `Colors.grey` 대체 — `dart:ui`만 의존하도록 직접 정의한다.
const Color _fallbackGrey = Color(0xFF9E9E9E);

/// 가상 급행 노선 ID(`{base}E`)면 base 를, 아니면 null 을 돌려준다.
String? _expressBase(String lineId) => lineId.endsWith('E')
    ? lineId.substring(0, lineId.length - 1)
    : null;

/// 노선 색상을 안전하게 조회한다.
///
/// - [lineId]가 [lineColors]에 등록되어 있으면 해당 색상을 반환한다.
/// - 등록되지 않았고 `E`로 끝나면(급행 가상 노선) base lineId 로 폴백 조회한다.
/// - 그래도 없으면 회색([_fallbackGrey])을 반환한다.
Color lineColorFor(String lineId) {
  final direct = lineColors[lineId];
  if (direct != null) return direct;
  final base = _expressBase(lineId);
  if (base != null) {
    final baseColor = lineColors[base];
    if (baseColor != null) return baseColor;
  }
  return _fallbackGrey;
}

/// 노선 표시명을 안전하게 조회한다. [lineColorFor] 와 같은 폴백 규칙
/// (직접 → 급행 base → lineId 그대로)을 쓴다.
String lineNameFor(String lineId) {
  final direct = lineNames[lineId];
  if (direct != null) return direct;
  final base = _expressBase(lineId);
  if (base != null) {
    final baseName = lineNames[base];
    if (baseName != null) return baseName;
  }
  return lineId;
}
