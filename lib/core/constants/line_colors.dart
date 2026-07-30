import 'dart:ui';

const Map<String, Color> lineColors = {
  '1': Color(0xFF0052A4),
  '2': Color(0xFF00A84D),
  '3': Color(0xFFEF7C1C),
  '4': Color(0xFF00A5DE),
  '5': Color(0xFF996CAC),
  '6': Color(0xFFCD7C2F),
  '7': Color(0xFF747F00),
  '8': Color(0xFFE6186C),
  '9': Color(0xFFBDB092),
  'SB': Color(0xFFD31145),
  '신분당': Color(0xFFD31145),
  '경의중앙': Color(0xFF77C4A3),
  '경춘': Color(0xFF0C8E72),
  '경강': Color(0xFF004EA7),
  '공항철도': Color(0xFF0090D2),
  '수인분당': Color(0xFFFFD400),
  '신림': Color(0xFF6789CA),
  '에버라인': Color(0xFF36A805),
  '인천1': Color(0xFF6496DF),
  '인천2': Color(0xFFCF843C),
  '김포골드': Color(0xFFA18F57),
  '서해': Color(0xFF40A607),
  '의정부': Color(0xFFD9750D),
  '우이신설': Color(0xFF878787),
  'GTX-A': Color(0xFF9F6181),
};

const Map<String, String> lineNames = {
  '1': '1호선',
  '2': '2호선',
  '3': '3호선',
  '4': '4호선',
  '5': '5호선',
  '6': '6호선',
  '7': '7호선',
  '8': '8호선',
  '9': '9호선',
  'SB': '신분당선',
  '신분당': '신분당선',
  '경의중앙': '경의중앙선',
  '경춘': '경춘선',
  '경강': '경강선',
  '공항철도': '공항철도',
  '수인분당': '수인분당선',
  '신림': '신림선',
  '에버라인': '에버라인',
  '인천1': '인천1호선',
  '인천2': '인천2호선',
  '김포골드': '김포골드라인',
  '서해': '서해선',
  '의정부': '의정부경전철',
  '우이신설': '우이신설경전철',
  'GTX-A': 'GTX-A',
  // 급행 가상 노선 — base 노선과 같은 이름을 쓰고, "급행" 표시는 별도 배지로
  // 보여준다 (라벨 "1호선" + 빨간 "급행" 배지 = 시각적 일관성 확보).
  '1E': '1호선',
  '9E': '9호선',
  '경춘E': '경춘선',
  '수인분당E': '수인분당선',
};

/// `Colors.grey` 대체 — `dart:ui`만 의존하도록 직접 정의한다.
const Color _fallbackGrey = Color(0xFF9E9E9E);

/// 노선 색상을 안전하게 조회한다.
///
/// - [lineId]가 [lineColors]에 등록되어 있으면 해당 색상을 반환한다.
/// - 등록되지 않았고 `E`로 끝나면(급행 가상 노선) base lineId(`9E` → `9`)로
///   폴백 조회한다.
/// - 그래도 없으면 회색([_fallbackGrey])을 반환한다.
Color lineColorFor(String lineId) {
  final direct = lineColors[lineId];
  if (direct != null) return direct;
  if (lineId.endsWith('E')) {
    final base = lineId.substring(0, lineId.length - 1);
    final baseColor = lineColors[base];
    if (baseColor != null) return baseColor;
  }
  return _fallbackGrey;
}
