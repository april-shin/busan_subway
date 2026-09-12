/// 역 이름 검색 매칭 — 일반 부분일치 + 한글 초성 검색.
///
/// 검색어를 **한 글자씩** 역 이름과 대조하며, 검색어 글자가 한글 초성 자모
/// (`ㄱ`~`ㅎ`)이면 역 이름 글자의 **초성**과 비교한다. 그 외 글자는 그대로
/// 비교하므로, 초성이 섞이지 않은 검색어에 대해서는 기존 `String.contains`
/// 와 결과가 완전히 같다.
///
/// - `'강남'` → 강남 (기존 동작)
/// - `'ㄱㄴ'` → 강남, 광나루 등 초성이 맞는 역
/// - `'강ㄴ'` → 강남 (완성형 + 초성 혼합)
/// - `'ㅅㄷ'` → 총신대입구처럼 이름 **중간**에서 시작하는 매칭도 포함(부분일치)
///
/// 중성 자모(`ㅏ` 등)와 겹받침 전용 자모(`ㄳ`, `ㄺ` 등)는 초성이 될 수 없으므로
/// 리터럴로 비교한다 — 매칭되지 않는다.
///
/// ## 조합 중인 종성 분해 ([splitTrailingJamo])
///
/// 한글 IME 는 새 자음이 **앞 글자의 종성으로 붙을 수 있으면** 초성 자모를
/// 따로 내보내지 않고 합쳐 버린다. `사당` 을 치는 도중 `ㄷ` 을 누른 순간의
/// 검색어는 `ㄷ` 이 아니라 `삳` 이라, 그대로 비교하면 그 한 타 동안 결과가
/// 빈다(`강남` 처럼 앞 글자가 닫힌음절이면 `강ㄴ` 이 되어 문제가 없다).
///
/// [splitTrailingJamo] 를 켜면 **검색어 마지막 글자의 종성만** 떼어 다음
/// 글자의 초성 후보로 보고 한 번 더 대조한다 — `삳` → `사` + `ㄷ` → 사당.
/// 겹받침은 앞 자음을 종성으로 남기고 뒤 자음만 뗀다(`엯` → `역` + `ㅅ`).
///
/// 이 분해는 매칭 범위를 넓히므로(`강` → `가` + `ㅇ` 이라 `가양` 도 걸린다)
/// **기본은 꺼져 있다.** 호출부에서 엄격 매칭 결과가 비었을 때만 켜서 다시
/// 거르면, 평소에는 잡음이 없고 조합 중에만 결과가 살아남는다.
///
/// 분해 대상은 **마지막 한 글자뿐**이다 — 역 이름을 한 글자씩 끝까지 치는
/// 정상 입력에서는 애매한 글자가 언제나 커서 직전 하나뿐이라 이것으로 충분
/// 하다. 반면 완성형과 초성을 섞어 줄여 치다가 흡수가 일어나면(`가산디지털
/// 단지` → `가` + `ㅅㄷㅈ` 이 `갓ㄷㅈ` 이 되는 식) 그 뒤는 매칭되지 않는다.
/// 같은 이유로 열린음절이 자음 둘을 연달아 먹은 겹받침(`갌` = `가`+`ㄹ`+`ㅅ`)
/// 도 앞 자음까지는 되돌리지 않는다.
library;

/// 한글 음절 영역(가~힣).
const int _syllableFirst = 0xAC00;
const int _syllableLast = 0xD7A3;

/// 한 초성이 차지하는 음절 수 (중성 21 × 종성 28).
const int _syllablesPerChosung = 588;

/// 종성 가짓수(종성 없음 포함).
const int _jongseongCount = 28;

/// 한글 호환 자모 영역(`ㄱ`=0x3131 ~)의 초성 19자 → 초성 index.
///
/// 이 영역은 초성으로 쓸 수 없는 겹받침(`ㄳ`, `ㄵ`, …)이 사이사이 섞여 있어
/// 코드포인트 산술로 index 를 구할 수 없다. 표로 둔다.
const Map<int, int> _chosungIndexByCompatJamo = {
  0x3131: 0, // ㄱ
  0x3132: 1, // ㄲ
  0x3134: 2, // ㄴ
  0x3137: 3, // ㄷ
  0x3138: 4, // ㄸ
  0x3139: 5, // ㄹ
  0x3141: 6, // ㅁ
  0x3142: 7, // ㅂ
  0x3143: 8, // ㅃ
  0x3145: 9, // ㅅ
  0x3146: 10, // ㅆ
  0x3147: 11, // ㅇ
  0x3148: 12, // ㅈ
  0x3149: 13, // ㅉ
  0x314A: 14, // ㅊ
  0x314B: 15, // ㅋ
  0x314C: 16, // ㅌ
  0x314D: 17, // ㅍ
  0x314E: 18, // ㅎ
};

/// 조합용 초성 자모 영역(U+1100~U+1112). 이쪽은 19자가 초성 순서대로만
/// 늘어서 있어 산술로 index 가 나온다. 국내 IME 는 호환 자모를 내보내지만,
/// 외부에서 붙여넣은 텍스트 방어용.
const int _combiningChosungFirst = 0x1100;
const int _combiningChosungLast = 0x1112;

/// 종성 index → (종성으로 남는 부분, 떼어낸 자음의 초성 index).
///
/// 종성 없음(0)은 뗄 것이 없어 제외. 겹받침은 앞 자음을 종성으로 남긴다
/// (`ㄳ` → 종성 `ㄱ` + 초성 `ㅅ`).
const Map<int, ({int rest, int chosung})> _jongseongSplit = {
  1: (rest: 0, chosung: 0), // ㄱ
  2: (rest: 0, chosung: 1), // ㄲ
  3: (rest: 1, chosung: 9), // ㄳ → ㄱ + ㅅ
  4: (rest: 0, chosung: 2), // ㄴ
  5: (rest: 4, chosung: 12), // ㄵ → ㄴ + ㅈ
  6: (rest: 4, chosung: 18), // ㄶ → ㄴ + ㅎ
  7: (rest: 0, chosung: 3), // ㄷ
  8: (rest: 0, chosung: 5), // ㄹ
  9: (rest: 8, chosung: 0), // ㄺ → ㄹ + ㄱ
  10: (rest: 8, chosung: 6), // ㄻ → ㄹ + ㅁ
  11: (rest: 8, chosung: 7), // ㄼ → ㄹ + ㅂ
  12: (rest: 8, chosung: 9), // ㄽ → ㄹ + ㅅ
  13: (rest: 8, chosung: 16), // ㄾ → ㄹ + ㅌ
  14: (rest: 8, chosung: 17), // ㄿ → ㄹ + ㅍ
  15: (rest: 8, chosung: 18), // ㅀ → ㄹ + ㅎ
  16: (rest: 0, chosung: 6), // ㅁ
  17: (rest: 0, chosung: 7), // ㅂ
  18: (rest: 17, chosung: 9), // ㅄ → ㅂ + ㅅ
  19: (rest: 0, chosung: 9), // ㅅ
  20: (rest: 0, chosung: 10), // ㅆ
  21: (rest: 0, chosung: 11), // ㅇ
  22: (rest: 0, chosung: 12), // ㅈ
  23: (rest: 0, chosung: 14), // ㅊ
  24: (rest: 0, chosung: 15), // ㅋ
  25: (rest: 0, chosung: 16), // ㅌ
  26: (rest: 0, chosung: 17), // ㅍ
  27: (rest: 0, chosung: 18), // ㅎ
};

/// [name] 이 [query] 에 부분일치하는가. [query] 가 비어 있으면 항상 참.
///
/// [splitTrailingJamo] 는 조합 중인 마지막 종성을 떼어 한 번 더 대조한다 —
/// 켜는 기준은 이 파일 상단 문서 참조.
bool matchesStationQuery(
  String name,
  String query, {
  bool splitTrailingJamo = false,
}) {
  if (query.isEmpty) return true;
  if (_scan(name, _tokenize(query))) return true;
  if (!splitTrailingJamo) return false;

  final split = _tokenizeWithTrailingSplit(query);
  return split != null && _scan(name, split);
}

/// 검색어 한 글자의 매칭 규칙.
///
/// [chosungIndex] 가 있으면 역 이름 글자의 초성과 비교하고, 없으면
/// [codeUnit] 과 그대로 비교한다.
class _QueryToken {
  final int codeUnit;
  final int? chosungIndex;

  const _QueryToken.literal(this.codeUnit) : chosungIndex = null;
  const _QueryToken.chosung(int index)
      : codeUnit = 0,
        chosungIndex = index;

  bool matches(int nameUnit) {
    final index = chosungIndex;
    if (index == null) return nameUnit == codeUnit;
    if (nameUnit < _syllableFirst || nameUnit > _syllableLast) return false;
    return (nameUnit - _syllableFirst) ~/ _syllablesPerChosung == index;
  }
}

List<_QueryToken> _tokenize(String query) {
  return [
    for (var i = 0; i < query.length; i++) _tokenOf(query.codeUnitAt(i)),
  ];
}

_QueryToken _tokenOf(int unit) {
  if (unit >= _combiningChosungFirst && unit <= _combiningChosungLast) {
    return _QueryToken.chosung(unit - _combiningChosungFirst);
  }
  final index = _chosungIndexByCompatJamo[unit];
  return index == null
      ? _QueryToken.literal(unit)
      : _QueryToken.chosung(index);
}

/// 마지막 글자의 종성을 떼어낸 토큰 열. 뗄 종성이 없으면 null.
List<_QueryToken>? _tokenizeWithTrailingSplit(String query) {
  final last = query.codeUnitAt(query.length - 1);
  if (last < _syllableFirst || last > _syllableLast) return null;

  final jongseong = (last - _syllableFirst) % _jongseongCount;
  final split = _jongseongSplit[jongseong];
  if (split == null) return null;

  return [
    ..._tokenize(query.substring(0, query.length - 1)),
    _QueryToken.literal(last - jongseong + split.rest),
    _QueryToken.chosung(split.chosung),
  ];
}

bool _scan(String name, List<_QueryToken> tokens) {
  if (tokens.length > name.length) return false;

  for (var start = 0; start + tokens.length <= name.length; start++) {
    var matched = true;
    for (var i = 0; i < tokens.length; i++) {
      if (!tokens[i].matches(name.codeUnitAt(start + i))) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}
