import 'package:flutter/foundation.dart' show visibleForTesting;

/// 실시간 도착정보 API 역명 치환 맵.
///
/// 일부 역은 API 가 **부역명(병기역명)이 포함되거나 개명 전인 정식 등록명**으로만
/// 조회된다. 앱 내부 표시용 역명(`stations.json`)은 간결한/현행 이름을 쓰므로,
/// 표시명 그대로 질의하면 도착정보가 통째로 비어 버린다. 이 파일이 그 차이를 메운다.
///
/// ## 현재 상태 (부산 전환)
/// 서울 열린데이터 API 기준으로 실측해 채웠던 항목은 부산 노선과 무관해 **전부 비웠다.**
/// 실시간 기능은 `FeatureFlags.realtimeEnabled` 로 꺼져 있다. 부산 실시간 API 를
/// 연동할 때 그 API 의 등록명을 실측해 아래 맵을 다시 채운다. 구조(아웃바운드 치환 →
/// 인바운드 역맵 자동 생성 → 자유텍스트 경계 치환)는 그대로 재사용할 수 있게 남겨 둔다.
///
/// ## 방향성
/// - **아웃바운드(질의명)**: [resolveArrivalApiStationName] — 표시명 → API 등록명.
/// - **인바운드(응답명)**: [resolveDisplayStationName] — API 등록명 → 표시명(위 맵의 역).
///   응답의 현재역 이름이 API 등록명으로 오는데, 이를 표시명으로 되돌려야
///   `stations.json` 매칭(라이브맵 좌표 조회·도착시간 추정)이 성립한다.
///
/// ## 갱신 시 확인(필수)
/// (a) 표시명이 `stations.json` 에 실존하는지, (b) 같은 이름의 **타 노선 별개 역**
/// (동명이역 — 부산: 좌천(1호선/동해선), 동래(1·4호선/동해선))이 없는지 — 이 맵은
/// 이름만으로 치환하므로 동명이역은 등록하면 안 된다, (c) API 등록명(값)이 다른 역의
/// 표시명과 충돌하지 않는지, (d) API 등록명이 다른 역 표시명의 부분 문자열이면
/// [_boundedTextReplacementSuffixes] 에 경계 규칙을 등록할 것.
const Map<String, String> arrivalApiStationNameOverrides = {};

/// API 등록명 → 표시명 역치환용 맵. 값이 유일해야 단순 역맵으로 성립한다.
final Map<String, String> _displayNameByApiStationName = {
  for (final e in arrivalApiStationNameOverrides.entries) e.value: e.key,
};

/// 실시간 도착정보 API **질의**에 사용할 역명을 반환한다(아웃바운드).
///
/// [arrivalApiStationNameOverrides]에 등록된 표시명이면 API 등록명으로 치환하고,
/// 아니면 표시명을 그대로 반환한다.
String resolveArrivalApiStationName(String displayName) =>
    arrivalApiStationNameOverrides[displayName] ?? displayName;

/// 한 역의 API 등록명이 **노선별로 갈린 역**의 등록명 전체 목록.
///
/// 같은 물리 역이 노선에 따라 다른 이름으로 등록돼 있으면 한 번 조회로는 일부 노선이
/// 누락되므로, 데이터소스가 이 목록의 이름으로 각각 조회한 뒤 병합한다.
/// - **첫 원소는 [resolveArrivalApiStationName] 결과와 일치해야 한다.**
/// - 목록의 모든 이름은 인바운드([resolveDisplayStationName])로 표시명에 되돌아와야 한다.
/// - 등록한 역은 새로고침마다 API 를 목록 수만큼 호출하므로 실제로 갈린 역만 넣을 것.
///
/// 부산 전환으로 비어 있다(서울 항목 제거).
const Map<String, List<String>> arrivalApiSplitRegistrationNames = {};

/// 도착정보 API 질의에 사용할 등록명 **전체**를 반환한다(아웃바운드).
///
/// 등록명이 노선별로 갈린 역([arrivalApiSplitRegistrationNames])이면 목록 전체를,
/// 아니면 [resolveArrivalApiStationName] 결과 한 개짜리 목록을 돌려준다.
/// 첫 원소는 항상 주 질의명이다.
List<String> resolveArrivalApiStationNames(String displayName) =>
    arrivalApiSplitRegistrationNames[displayName] ??
    <String>[resolveArrivalApiStationName(displayName)];

/// API **응답**의 역명(현재역 등)을 앱 표시용 역명으로 되돌린다(인바운드).
///
/// API 등록명이면 표시명으로 치환하고, 아니면 입력을 그대로 반환한다.
String resolveDisplayStationName(String apiStationName) =>
    _displayNameByApiStationName[apiStationName] ?? apiStationName;

/// 아웃바운드 질의명은 아니지만 API 응답 **텍스트**에 부가 표기로 섞여 오는 문자열 →
/// 표시명. 양방향 치환맵과 분리돼 왕복 불변식·값 유일성 대상이 아니다.
const Map<String, String> _inboundOnlyTextReplacements = {};

/// 자유텍스트 치환([resolveDisplayInText])을 **경계가 맞을 때만** 수행할 API 등록명과,
/// 그 이름이 실제로 그 역을 가리킬 때 **뒤따르는 문맥**(정규식 조각).
///
/// 다른 역 표시명의 부분 문자열인 API 등록명은 무조건 치환하면 엉뚱한 역명을
/// 만들어낸다. 두 문맥이 서로소임을 실측으로 확인한 경우에만 등록한다.
const Map<String, String> _boundedTextReplacementSuffixes = {};

/// [_boundedTextReplacementSuffixes]를 "이름 + 뒤따르는 문맥" 전방탐색 패턴으로 컴파일.
final Map<String, RegExp> _boundedTextPatterns = {
  for (final e in _boundedTextReplacementSuffixes.entries)
    e.key: RegExp('${RegExp.escape(e.key)}(?=${e.value})'),
};

/// 자유텍스트 치환 **후보** API 표기 전체 — 양방향 맵 값 + 인바운드 전용.
@visibleForTesting
final List<String> textReplacementCandidates = <String>[
  ..._displayNameByApiStationName.keys,
  ..._inboundOnlyTextReplacements.keys,
];

/// 무조건 치환할 API 표기를 긴 것부터 정렬 — 부분 문자열 겹침 방지.
/// 경계 규칙이 붙은 이름([_boundedTextReplacementSuffixes])은 여기서 빼고 따로 처리한다.
final List<String> _apiNamesByLengthDesc = textReplacementCandidates
    .where((n) => !_boundedTextReplacementSuffixes.containsKey(n))
    .toList()
  ..sort((a, b) => b.length.compareTo(a.length));

/// 자유텍스트 치환용 통합 역맵(API 표기 → 표시명).
final Map<String, String> _textReplacements = {
  ..._displayNameByApiStationName,
  ..._inboundOnlyTextReplacements,
};

/// 자유 텍스트(방면 라벨·도착 메시지 등)에 **부분 문자열로** 섞여 오는 API 등록명을
/// 표시용 역명으로 되돌린다(인바운드, 표시 전용).
///
/// [resolveDisplayStationName]은 문자열 전체가 역명일 때만 동작하므로, 역명이
/// 다른 텍스트에 끼어 오는 경우를 위해 별도 제공한다. 치환 맵이 비어 있으면 입력을
/// 그대로 돌려준다.
String resolveDisplayInText(String text) {
  if (text.isEmpty) return text;
  var out = text;

  // 경계 조건부 치환을 먼저 — 경계 문맥은 **원본 API 텍스트** 기준으로 실측하므로,
  // 다른 치환이 만들어낸 문자열 위에서 판정하지 않는다.
  _boundedTextPatterns.forEach((apiName, pattern) {
    if (out.contains(apiName)) {
      out = out.replaceAll(pattern, _textReplacements[apiName]!);
    }
  });

  for (final apiName in _apiNamesByLengthDesc) {
    if (out.contains(apiName)) {
      out = out.replaceAll(apiName, _textReplacements[apiName]!);
    }
  }
  return out;
}
