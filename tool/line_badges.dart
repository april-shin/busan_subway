/// 지도 노선 이름 pill 배지(P2-4) 생성 모듈 — `tool/build_map_html.dart` 가 호출한다.
///
/// 원본 SVG 에는 노선 이름 텍스트가 없다(모든 `<text>` 가 역명). 줌인하면 색만 남아
/// "이 갈색 선이 9호선인지 경의중앙인지" 구분이 안 되므로, 전 노선 24개의 양 종점에
/// 노선색 pill 배지(`[5호선]`)를 붙인다. 요구사항: `_workspace/18_requirements_line_badges.md`.
///
/// 입력: lines.json / connections.json / stations.json + 원본 SVG(경로·역 circle·라벨).
/// 출력: `#text-layer` 안에 삽입할 `<g id="line-badges">` SVG 조각 + 빌드 로그용 통계.
///
/// 설계 요지(상세: `_workspace/18_map-math_line_badges.md`):
/// - 종점 = 노선 그래프(connections)의 hop 지름 양 끝. 지선이 많아도 "본선 양 끝"이 잡힌다.
/// - 배지 앵커 = 종점 역 근처 **SVG polyline 의 자유 끝점**(선이 역 너머로 48~80 연장돼 있다),
///   바깥 방향 = 끝점 직전 구간의 진행 방향.
/// - **배지↔종점을 잇는 줄기(leader line)는 없다**(사용자 결정 2026-10-06). 줄기는 노선 선과 굵기·색이
///   같아 "존재하지 않는 지선"으로 읽혔다. 그래서 귀속 단서는 **pill 이 앵커(노선 선의 자유 끝점)에
///   붙어 있다는 것**(+ 색)뿐이고, 앵커↔pill 실제 최단 거리를 [_kMaxAnchorDist] 이내로 하드 제한한다.
/// - 위치는 16방향 × 7거리(4~16px) 후보를 비용(역명 라벨·역 circle·환승역 마커·다른 선·다른 배지 겹침 +
///   이탈 거리/각도)으로 평가해 고른다. 타 노선 선은 라벨급 고정 비용 + 3px 근접 링(상한 있음).
/// - 그래도 **하드 위반**(실제 겹침: 선·라벨·circle·환승역 마커·배지·캔버스 이탈·앵커에서 너무 멂)이 남으면
///   방향을 촘촘히 해(32방향) 다시 찾고, 그래도 남으면 그 허브(앵커 간 거리 [_BadgePlacer._kClusterRadius]
///   이내 클러스터)의 배지들을 **결합 완전 탐색**한다(한 장씩 탐욕적으로 놓으면 먼저 놓인 배지가 이웃의
///   유일한 자리를 막는다). 그래도 남으면 **빌드를 실패시킨다**(`unresolvedCount` > 0 → StateError).
///   조용히 어긋난 배지를 내보내지 않는다.
/// - **배지는 줌아웃 보정을 받지 않는다**(지도 좌표계 고정 크기, 사용자 결정 2026-10-06).
///   반면 환승역 라벨은 줌아웃 시 앵커 기준 최대 [kTextCompMax] 배로 커지므로, 배지(항상 1배)는
///   라벨을 1.0배·[kTextCompMax] 배 두 장면에서 비교한다(비대칭 평가).
/// - 색은 **SVG 선 색**(lines.json colorValue 와 다르다)을 쓴다. 글자색은 WCAG 대비로 고른다.
///
/// - **수동 위치 보정**(2026-10-06): `data/badge_offsets.json` 에 앵커 기준 오프셋이 있는 배지는 자동 배치기를
///   건너뛰고(다른 배지의 장애물로만 쓰인다) 그 자리에 놓인다. 하드 위반이어도 빌드를 실패시키지 않고
///   **경고만** 남긴다(사람이 고른 자리를 기계가 거부하면 기능이 무의미하다). 자동 배치 배지의 하드 실패
///   정책은 그대로다. 파일이 없거나 비어 있으면 산출물은 바이트 동일하다. 상세: `line_badges_offsets.dart`.
///
/// 구성: 이 파일 = 공개 API + 단계별 함수(검증 → 종점 → 앵커 → 배치 → 측정 → 렌더).
/// `line_badges_support.dart` = 자료구조·파싱·기하·글자색, `line_badges_offsets.dart` = 수동 보정 공개
/// 타입·파일 포맷·편집기 판정(`part`).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'map_constants.dart';

part 'line_badges_offsets.dart';
part 'line_badges_support.dart';

/// 앱 lineId → SVG `data-line` 코드. build_map_html.dart 의 JS `lineIdToDataLine`
/// 도 이 상수에서 생성한다(단일 소스). 값이 틀리면 [buildLineBadges] 의 검증이
/// 빌드를 실패시킨다.
const Map<String, String> kLineIdToDataLine = {
  '1': '2-1',
  '2': '3-2',
  '3': '4-3',
  '4': '5-4',
  '5': '6-5',
  '6': '7-6',
  '7': '8-7',
  '8': '9-8',
  '9': '10-9',
  'SB': 'S',
  '경의중앙': 'K',
  '경춘': 'G',
  '경강': 'KK',
  '공항철도': 'A',
  '수인분당': 'B',
  '신림': 'SL',
  '에버라인': 'E',
  '인천1': 'I',
  '인천2': 'I2',
  '김포골드': 'KP',
  '서해': 'SH',
  '의정부': 'U',
  '우이신설': 'W',
  'GTX-A': '1-GA',
};

/// 배지에 **축약해서** 적을 노선 문구(lineId → 문구). 여기 없는 노선은 lines.json `name` 그대로다.
///
/// 줄이는 이유는 폭이다 — pill 은 글자 수에 비례해(글자당 12px) 커지는데, 줄기가 없으므로 pill 은
/// 앵커 [_kMaxAnchorDist] 이내에 들어가야 한다. 양촌·신설동·청량리처럼 종점이 몇 px 차이로 몰린 허브에서는
/// 긴 pill 이 그 안에 들어갈 틈이 없다(2호선 "2호선" 44px 는 어디 놓아도 앵커에서 19.5px 이상 떨어진다 —
/// 36px 이하여야 8px). 그래서 **배치가 실제로 나아지는 노선만** 줄인다. 의정부경전철은 줄여도 배치가
/// 달라지지 않아 그대로 둔다(판단 근거: `_workspace/18_map-math_line_badges_fix3.md`, `..._fix5.md`).
///
/// ⛔ 하드 제약: 문구가 **실제 역명과 같아서는 안 된다**(배지가 역명 라벨로 오독된다 — 예: 의정부경전철을
/// "의정부"로 줄이면 의정부역 라벨처럼 보인다). [buildLineBadges] 의 `_verifyBadgeTexts` 가 stations.json 과
/// SVG 역명 라벨 전체와 대조해, 충돌하면 빌드를 실패시킨다(나중에 같은 이름의 역이 생겨도 마찬가지).
///
/// 항등 매핑이 아니다 — **키는 lineId**(`김포골드`), **값은 배지 표시명**(`김포골드`)이다. lines.json 의
/// `name` 은 "김포골드라인"(폭 84px)이라 이 항목을 지우면 배지가 다시 84px 로 커져 양촌에서 앵커 근처에
/// 자리가 없어진다(빌드 실패 — 테스트도 깨진다).
const Map<String, String> kLineBadgeNames = {
  // 키=lineId, 값=배지 표시명. 축약 사유는 둘로 나뉜다.
  //  (1) 배치 — 줄기가 없어 pill 이 앵커 [_kMaxAnchorDist] 이내에 들어가야 하는데 긴 pill 은 허브에서
  //      들어갈 틈이 없다(2026-10-06 줄기 제거 결정 이후).
  //  (2) 가독성 — 배지는 줌아웃 보정을 받지 않아 최대 줌아웃에서 12px→6px 가 된다.
  //      글자 수가 많을수록 불리하다.
  '김포골드': '김포골드', // (1) lines.json "김포골드라인" 84px → 60px. 양촌(4개 노선 밀집)
  '우이신설': '우이신설', // (2) "우이신설경전철" 7자(84px) → 4자(60px)
};

/// 노선 그래프가 둘 이상으로 끊겨 있어 hop 지름이 정의되지 않는 노선의 종점 역명.
/// GTX-A 는 운정중앙~서울역 / 수서~동탄 두 구간이 지도상 떨어져 있다. 서울역·수서는
/// 타 노선 종점과 겹치는 환승 허브라 각 구간의 바깥쪽 끝을 택한다.
///
/// 이 표는 **노선이 끊겨 있는 동안에만** 유효하다 — 노선이 연결되면(구간이 이어지면)
/// 빌드가 실패해 항목을 지우도록 강제한다. 또 두 역은 서로 다른 구간의 차수 1 역이어야 한다.
/// 여기 없는 분리 노선이 생겨도 빌드가 실패한다(조용히 틀리지 않도록).
const Map<String, List<String>> kBadgeTerminalOverrides = {
  'GTX-A': ['운정중앙', '동탄'],
};

// ---- 배지 크기 상수 (지도 좌표 단위 — 줌아웃 보정 없음) ----
/// 배지 글자 크기(px, 지도 좌표 단위). CSS `.lb text` 에 주입된다. 줌아웃 보정이 없으므로
/// 라벨의 [kTextBaseFontSize] 와 값이 같을 뿐 별개 상수다(scale≥1 에서 라벨과 같은 크기로 보임).
const double kBadgeFontPx = 12;
const double _kBadgeH = 18;
const double _kBadgePadX = 6;
const double _kMargin = 3; // 캔버스 가장자리 여유

/// 배지↔라벨 비교 장면: 라벨의 줌아웃 확대 배율 f(= 1/cs). 환승역 라벨만 f 배로 커진다.
/// 배지는 장면과 무관하게 항상 1배다.
const List<double> _kLabelScenes = [1.0, kTextCompMax];

/// 앵커로 쓸 자유 끝점의 종점 역↔끝점 호 길이 상한.
const double _kMaxStub = 100.0;

/// 앵커(노선 선의 자유 끝점)에서 pill 사각형까지의 **실제(유클리드) 최단 거리** 상한(px) — 하드 위반.
/// 배지↔종점을 잇는 줄기(leader line)는 없다(사용자 결정 2026-10-06 — 줄기가 노선 선과 굵기·색이
/// 같아 "존재하지 않는 지선"으로 읽혔다). 줄기 없이 귀속을 보이려면 pill 이 앵커에 **붙어 있어야** 하므로
/// 후보 간격([_BadgePlacer._gaps])은 지지선(support line) 기준이라 대각선에서는 실제 거리가 더 크므로,
/// 격자 값이 아니라 **실제 거리**를 재서 막는다.
///
/// 값 24 의 근거: 처음엔 16 으로 잡았다(줄기 제거 직전 줄기 없이 놓이던 32개의 최대 15.3px 바로 위).
/// 그러려면 신설동·청량리 허브에서 pill 을 더 줄여야 해서 '2'→"2호", '수인분당'→"수인분당",
/// '우이신설'→"우이" 까지 축약했는데, **"2호" 는 다른 노선이 전부 "N호선" 인 가운데 혼자 표기가
/// 깨지고 실제로 쓰이지 않는 이름이라 철회**했다(배지 목적이 노선 식별인데 없는 이름을 만든다).
/// 상한을 24 로 올리면 공식 명칭 그대로도 미해결 0 이고, 실측 최대 22.5px·중앙값 8.0px 이며
/// 겹침은 오히려 좋아진다(타 노선 선 3px 스침 합계 53.5px → 3.5px, 최소 이격 1.08px → 2.62px).
/// ⛔ 배치가 빡빡하다고 [kLineBadgeNames] 를 임의로 늘리지 말 것 — 축약은 사용자 승인 사안이다.
const double _kMaxAnchorDist = 24.0;

// ---- 선 겹침 비용 (배치) ----
// 후보 비용의 다른 항: 라벨 겹침 4×면적(44×14 완전 겹침 ≈2,464), circle 250, 180° 회전 63,
// 최대 거리 54. 선 겹침은 px 당 1.5 였을 때 44px 관통도 ≈66 이라 "사실상 공짜"여서 배지가
// 타 노선 선 위에 얹혔다(김포골드 pill 이 9호선 선 위 → "9호선 라벨"로 오독).
// 그래서 **타 노선**은 걸리기만 해도 고정 비용을 물려 회전/거리 비용(≤63)을 확실히 넘기고,
// **자기 노선**은 pill 과 같은 색이라 귀속이 분명하므로 기존 가중치를 유지한다.
// 단위 주의: 이 고정 비용 60 은 **폴리라인 세그먼트당**이다(꼭짓점이 pill 안에 있으면 걸친 세그먼트마다
// 가산 — 세그먼트가 많을수록 더 나쁘다는 뜻이라 방향성은 맞다). 반면 근접 링([_kNearLineCap])은
// **노선 코드당** 1회다.
const double _kOtherLineFixed = 60.0;
const double _kOtherLinePerPx = 12.0;
const double _kOwnLinePerPx = 1.5;

/// 선 판정에 쓰는 사각형 패딩(px). 선 굵기 3 의 반 + 여유 — 선에 0.6px 밀착한 배치도
/// "약한 얹힘"으로 걸러진다(3호선/오금이 5호선 선에 붙은 경우).
const double _kLineProbePad = 3.0;

/// 하드 위반으로 보는 타 노선 선 겹침 길이(px). 수치 노이즈 여유.
const double _kHardLinePx = 0.05;

/// pill 과 **타 노선 선 중심선**의 최소 이격(px) — 하드 위반. 선은 폴리라인(중심선)으로만 비교하므로
/// pill 이 중심선에 0.0x px 로 붙어도 "겹침 0" 으로 통과하는데, 실제로는 선 굵기 3(반 1.5)가 pill 에 닿는다
/// (줄기 제거 후 후보 격자 사이에서 0.0px 밀착이 실제로 나왔다). 0.9 는 줄기 제거 직전(fix4) 산출물의
/// 최소 이격(0.90px, 경춘/청량리)과 같은 수준이다 — "기존 품질을 되돌리지 않는다". 1.0 이상으로 올리면
/// 청량리 수인분당 배지가 앵커 [_kMaxAnchorDist] 안에 자리를 못 찾는다(추가 축약 필요).
/// 타 노선 선은 pill 을 이만큼 부풀린 사각형으로 하드 판정한다.
const double _kMinLineClear = 0.9;

/// 확장 탐색에서 하드 위반 후보에 얹는 가산 비용. 캔버스 이탈(1e6)을 제외한 어떤 soft 비용 조합
/// (수천 대)보다 크다. 캔버스 이탈 후보는 그 자체도 하드 위반이라 1e6 + 1e5 로 여전히 최하위다.
const double _kHardViolationCost = 1e5;

/// 근접 링(타 노선 선이 pill 실제 사각형 밖 [_kLineProbePad] 이내를 지나는 구간) px 당 비용.
/// 겹침과 달리 **약한** 페널티다 — 신설동처럼 선이 빽빽한 허브에서는 3px 여유를 만족하는
/// 후보가 아예 없을 수 있어, 근접을 겹침급으로 막으면 오히려 실제 겹침을 고르게 된다.
const double _kNearLinePerPx = 6.0;

/// 근접 링 비용의 **노선 코드당 상한**. [_kOtherLineFixed](60) 미만이어야 "스침 < 겹침"이 구조적으로
/// 보장된다. 상한이 없으면 링 길이에 비례해 폭 ≥48 pill 의 긴 변 접선 스침(겹침 0)이 수직 관통(실제
/// 겹침)보다 비싸졌다(폭 60: 396 > 312). 이 상한은 3차 리뷰 MEDIUM-1 로 도입했고 48개 배치는 바뀌지
/// 않았다(하드 2패스가 이미 순서를 보정하던 것을 비용 수식이 직접 말하게 만든 것).
const double _kNearLineCap = 48.0;

// ---- 검증 임계 ----
/// 라벨 대조: 코드 C 의 `<text data-line=C>` 역명 중 매핑된 노선 역명에 속하는 비율 하한.
const double _kLabelHitMin = 0.8;

/// 기하 대조(보조): 선 위(≤3px) 역 비율 하한, 차점 코드 대비 배수.
const double _kGeoShareMin = 0.3;
const double _kGeoLeadMin = 1.5;

class LineBadgeResult {
  /// `#text-layer` 안에 삽입할 SVG 조각(`<g id="line-badges">…</g>`).
  final String svgFragment;
  final int badgeCount;

  /// lineId → 선택된 종점 역명 2개(검증·테스트용).
  final Map<String, List<String>> terminalNames;

  /// 배지 사각형 안을 지나는 **타 노선 선**의 총 길이(px, 48개 합). 0 이어야 한다 —
  /// 금색 김포골드 pill 이 9호선 선 위에 얹혀 "9호선 라벨"로 읽히는 식의 귀속 혼동을 막는 가드.
  final double otherLineOverlapPx;

  /// 위와 같되 사각형을 [_kLineProbePad] 만큼 부풀려 잰 값("밀착" 포함, 배치 비용과 같은 기준).
  final double otherLineNearPx;

  /// 배지 사각형 안을 지나는 **자기 노선 선**의 총 길이(px). 종점 바로 옆이라 허용된다(참고용).
  final double ownLineOverlapPx;

  /// 앵커(노선 선 끝점)↔pill 사각형 **실제 최단 거리**의 최댓값(px). [_kMaxAnchorDist] 이하여야 한다.
  /// 줄기가 없으므로 이 값이 "귀속 단서(인접성)"의 근거다.
  final double maxAnchorDistPx;

  /// 앵커↔pill 거리 분포(px, 48개 오름차순) — 빌드 보고·테스트용.
  final List<double> anchorDistsPx;

  /// 배지 사각형(패딩 없음)과 가장 가까운 **타 노선 선**의 이격(px) 최솟값. 0 이면 겹침(하드 위반).
  final double minOtherLineClearancePx;

  /// 배지 사각형과 겹치는 **환승역 마커(SVG `<rect>`)** 수. 0 이어야 한다(하드 위반).
  final int stationRectOverlapCount;

  /// 캔버스([kCanvasW]×[kCanvasH], 여백 [_kMargin])를 벗어난 배지 수. 0 이어야 한다(하드 위반).
  final int canvasEscapeCount;

  /// 하드 위반을 못 피한 **미해결 배지** 수. 0 이어야 한다. [buildLineBadges] 는 이 값이 0 보다 크면
  /// 결과를 돌려주지 않고 StateError 를 던지므로, 반환된 결과에서는 항상 0 이다(가드 테스트용으로 노출).
  final int unresolvedCount;

  /// 빌드 로그용 한 줄 요약들.
  final List<String> summary;

  /// 상세 감사 표(환경변수 LINE_BADGE_VERBOSE=1 일 때만 출력).
  final List<String> details;

  /// 확정된 48개 배지의 배치(편집기·테스트용). 렌더 순서와 같다.
  final List<BadgePlacement> placements;

  /// 수동 보정이 적용된 배지 수.
  final int manualCount;

  /// 오버라이드 입력 문제(값 오류·현재 배지에 없는 키) — 해당 배지는 자동 배치로 처리됐다.
  final List<String> offsetWarnings;

  /// 현재 배지 집합에 없는 오버라이드 키(노선 삭제·종점 변경 등).
  final List<String> staleOffsetKeys;

  /// 수동 배치가 하드 위반인 배지의 경고(노선·종점·위반 종류·수치). 빌드는 실패시키지 않는다.
  final List<String> manualWarnings;
  const LineBadgeResult({
    required this.svgFragment,
    required this.badgeCount,
    required this.terminalNames,
    required this.otherLineOverlapPx,
    required this.otherLineNearPx,
    required this.ownLineOverlapPx,
    required this.maxAnchorDistPx,
    required this.anchorDistsPx,
    required this.minOtherLineClearancePx,
    required this.stationRectOverlapCount,
    required this.canvasEscapeCount,
    required this.unresolvedCount,
    required this.summary,
    required this.details,
    this.placements = const [],
    this.manualCount = 0,
    this.offsetWarnings = const [],
    this.staleOffsetKeys = const [],
    this.manualWarnings = const [],
  });
}

// ======================================================================
// 메인 진입점 — 조립만 한다
// ======================================================================

/// [lineCodes]/[terminalOverrides] 는 기본값이 프로덕션 상수이고, 검증 분기를
/// 테스트하려는 용도로만 바꾼다. [offsets] 는 수동 위치 보정(`data/badge_offsets.json`) —
/// 기본값(없음)이면 산출물은 보정 기능 도입 전과 같다.
LineBadgeResult buildLineBadges({
  required String svgContent,
  required List<dynamic> stationsJson,
  required List<dynamic> linesJson,
  required List<dynamic> connectionsJson,
  required Set<String> transferStationNames,
  Map<String, String> lineCodes = kLineIdToDataLine,
  Map<String, List<String>> terminalOverrides = kBadgeTerminalOverrides,
  Map<String, String> badgeNames = kLineBadgeNames,
  BadgeOffsets offsets = BadgeOffsets.empty,
}) =>
    solveLineBadges(
      svgContent: svgContent,
      stationsJson: stationsJson,
      linesJson: linesJson,
      connectionsJson: connectionsJson,
      transferStationNames: transferStationNames,
      lineCodes: lineCodes,
      terminalOverrides: terminalOverrides,
      badgeNames: badgeNames,
      offsets: offsets,
    ).result;

/// [buildLineBadges] 와 같되 배치 상태 핸들까지 돌려준다(편집기가 드래그 중 [LineBadgeSolution.check] 로
/// 즉시 판정). 빌드 경로와 편집기가 **같은 함수**를 거치므로 화면과 빌드 결과가 갈라지지 않는다.
LineBadgeSolution solveLineBadges({
  required String svgContent,
  required List<dynamic> stationsJson,
  required List<dynamic> linesJson,
  required List<dynamic> connectionsJson,
  required Set<String> transferStationNames,
  Map<String, String> lineCodes = kLineIdToDataLine,
  Map<String, List<String>> terminalOverrides = kBadgeTerminalOverrides,
  Map<String, String> badgeNames = kLineBadgeNames,
  BadgeOffsets offsets = BadgeOffsets.empty,
}) {
  final d = _parseInputs(svgContent, stationsJson, linesJson, connectionsJson,
      transferStationNames, lineCodes);
  final verifyLog = _verifyMapping(d, svgContent);
  final terminals = _pickTerminals(d, terminalOverrides);
  final texts = _verifyBadgeTexts(d, badgeNames);
  final badges = _buildBadges(d, terminals, texts);
  final offsetWarnings = [...offsets.warnings];
  final staleKeys = _applyOffsets(d, badges, offsets, offsetWarnings);
  final placer = _BadgePlacer(d);
  final unresolved = placer.placeAll(badges);
  if (unresolved.isNotEmpty) {
    // 잔여 하드 위반은 빌드 실패다(이 저장소의 관행: 조용히 틀리는 대신 빌드를 막는다).
    // 수동 보정 배지는 여기 오지 않는다 — 아래에서 경고만 남긴다.
    throw StateError(_unresolvedMessage(placer, badges, unresolved));
  }
  final (overlapSummary, conflictLog, lineStats) = _measureOverlaps(d, badges);

  final terminalNames = {
    for (final e in terminals.entries)
      e.key: [for (final sid in e.value) d.station(sid)['name'] as String],
  };
  final manual = [for (final b in badges) if (b.manual) b];
  final manualWarnings = _manualWarnings(d, placer, badges);
  final summary = [
    '노선 배지: ${badges.length}개 / ${d.lines.length}개 노선 (노선당 양 종점 2개)',
    _contrastSummary(d),
    ...overlapSummary,
    '미해결 배지: 0개 (하드 위반 없이 전부 배치 — 남으면 빌드 실패)',
    // 수동 보정이 없으면(파일 없음/빈 파일) 이 블록은 비어 있어 로그도 기존과 같다.
    ..._offsetSummary(manual, badges.length, offsetWarnings, manualWarnings),
  ];
  final details = [
    '매핑 검증: ${verifyLog.join(', ')}',
    ...conflictLog,
    for (final b in badges)
      '  ${b.lineId.padRight(6)} ${b.stationName.padRight(8)} '
          '앵커=(${_fmt(b.anchor.x)},${_fmt(b.anchor.y)}) 역↔끝점=${_fmt(b.anchorGap)} '
          '방향=(${b.dir.x.toStringAsFixed(2)},${b.dir.y.toStringAsFixed(2)}) '
          '선택: 거리+${_fmt(b.chosenGap)} 앵커↔pill=${_fmt(b.anchorDist)} 각도편차=${_fmt(b.chosenAngle)}°'
          '${b.manual ? ' [수동]' : ''}',
  ];
  final lineNameById = {
    for (final l in d.lines) l['id'] as String: l['name'] as String,
  };
  final placements = [
    for (var i = 0; i < badges.length; i++)
      BadgePlacement(
        index: i,
        key: badges[i].key,
        lineId: badges[i].lineId,
        lineName: lineNameById[badges[i].lineId]!,
        stationName: badges[i].stationName,
        text: badges[i].text,
        color: badges[i].color,
        textColor: badges[i].textColor,
        anchorX: badges[i].anchor.x,
        anchorY: badges[i].anchor.y,
        w: badges[i].w,
        h: _kBadgeH,
        ox: badges[i].ox,
        oy: badges[i].oy,
        anchorDist: badges[i].anchorDist,
        manual: badges[i].manual,
        violations: badges[i].manual ? placer._hard(badges[i], badges) : const [],
      ),
  ];
  final result = LineBadgeResult(
    svgFragment: _renderSvg(badges),
    badgeCount: badges.length,
    terminalNames: terminalNames,
    otherLineOverlapPx: lineStats.otherPx,
    otherLineNearPx: lineStats.otherNearPx,
    ownLineOverlapPx: lineStats.ownPx,
    maxAnchorDistPx: lineStats.anchorDists.isEmpty ? 0 : lineStats.anchorDists.last,
    anchorDistsPx: lineStats.anchorDists,
    minOtherLineClearancePx: lineStats.minClearance,
    stationRectOverlapCount: lineStats.rectOverlaps,
    canvasEscapeCount: lineStats.canvasEscapes,
    unresolvedCount: unresolved.length,
    summary: summary,
    details: details,
    placements: placements,
    manualCount: manual.length,
    offsetWarnings: offsetWarnings,
    staleOffsetKeys: staleKeys,
    manualWarnings: manualWarnings,
  );
  return LineBadgeSolution._(result, badges, placer);
}

/// 오버라이드를 배지에 적용한다: 키가 맞는 배지는 `manual` 로 표시하고 오프셋을 박는다(자동 배치기가 건너뜀).
/// 현재 배지에 없는 키(노선 삭제·종점 변경 등)는 **조용히 무시하지 않고** 경고를 남기고 그 항목을 버린다 —
/// 해당 배지는 자동 배치로 떨어진다. 반환: 현재 배지에 없는 키 목록.
List<String> _applyOffsets(
    _MapData d, List<_Badge> badges, BadgeOffsets offsets, List<String> warnings) {
  final byKey = <String, _Badge>{};
  for (final b in badges) {
    if (byKey.containsKey(b.key)) {
      // 한 노선의 두 종점이 같은 역명이면 키로 구분할 수 없다 — 보정이 엉뚱한 배지에 붙지 않게 막는다.
      if (offsets.byKey.isNotEmpty) {
        throw StateError('배지 키 "${b.key}" 가 둘 이상이다(한 노선의 두 종점 역명이 같다) — '
            '수동 보정 키로 구분할 수 없다');
      }
    }
    byKey[b.key] = b;
  }
  final stale = <String>[];
  for (final e in offsets.byKey.entries) {
    final b = byKey[e.key];
    if (b == null) {
      stale.add(e.key);
      final lineId = e.key.contains('|') ? e.key.substring(0, e.key.indexOf('|')) : e.key;
      final mine = [for (final x in badges) if (x.lineId == lineId) '"${x.key}"'];
      warnings.add(
        '수동 보정 키 "${e.key}" 가 현재 배지에 없다 — 이 항목은 무시하고 자동 배치한다'
        '${mine.isEmpty ? ' (노선 "$lineId" 가 없다 — 노선 삭제/개명?)' : ' (노선 "$lineId" 의 현재 키: ${mine.join(', ')} — 종점이 바뀌었나?)'}',
      );
      continue;
    }
    b
      ..manual = true
      ..ox = e.value.dx
      ..oy = e.value.dy;
  }
  return stale;
}

/// 수동 배치 배지의 하드 위반 경고 — 어느 노선·종점이 무엇과 겹치는지, 수치와 함께.
List<String> _manualWarnings(_MapData d, _BadgePlacer placer, List<_Badge> badges) {
  final lineNameById = {
    for (final l in d.lines) l['id'] as String: l['name'] as String,
  };
  final out = <String>[];
  for (final b in badges) {
    if (!b.manual) continue;
    final vs = placer._hard(b, badges);
    if (vs.isEmpty) continue;
    out.add('경고: 수동 보정 배지 노선 ${b.lineId}(${lineNameById[b.lineId]}) 종점 ${b.stationName} '
        '오프셋=(${_fmt(b.ox)},${_fmt(b.oy)}) 위반 ${vs.length}건 — '
        '${vs.map((v) => v.message).join(' / ')} (빌드는 계속한다)');
  }
  return out;
}

/// 수동 보정이 있을 때만 나오는 빌드 로그 블록(없으면 빈 목록 — 기존 로그 불변).
List<String> _offsetSummary(
    List<_Badge> manual, int total, List<String> offsetWarnings, List<String> manualWarnings) {
  if (manual.isEmpty && offsetWarnings.isEmpty) return const [];
  return [
    '수동 보정 배지: ${manual.length}개 [${manual.map((b) => b.key).join(', ')}] · 자동 배치 ${total - manual.length}개 '
        '(보정 파일 $kBadgeOffsetsPath) · 경고 ${offsetWarnings.length + manualWarnings.length}건',
    for (final w in offsetWarnings) '경고: $w',
    ...manualWarnings,
  ];
}

// ======================================================================
// 2. 매핑 검증 — 조용히 틀린 배지를 내보내지 않는다
// ======================================================================

/// 검증 4종을 순서대로 돌리고, 로그용 한 줄들을 돌려준다.
List<String> _verifyMapping(_MapData d, String svgContent) {
  _verifyLineIds(d);
  _verifySvgCodes(d, svgContent);
  final labelLog = _verifyLabelNames(d);
  final geoLog = _verifyGeometry(d);
  return [...labelLog, ...geoLog];
}

/// (a) lines.json 노선 id 집합 == 매핑 키 집합.
void _verifyLineIds(_MapData d) {
  final lineIds = d.lines.map((l) => l['id'] as String).toSet();
  final keys = d.lineCodes.keys.toSet();
  if (lineIds.length != keys.length || !lineIds.containsAll(keys)) {
    throw StateError(
      'lines.json 노선 id 와 kLineIdToDataLine 불일치 — '
      'lines.json 에만 있음: ${lineIds.difference(keys)}, '
      '매핑에만 있음: ${keys.difference(lineIds)}',
    );
  }
}

/// (b) SVG 의 (흰색 내부선 제외) data-line 코드 집합 == 매핑 값 집합.
void _verifySvgCodes(_MapData d, String svgContent) {
  final svgCodes = <String>{};
  for (final m in RegExp(r'<path\b[^>]*>').allMatches(svgContent)) {
    final tag = m.group(0)!;
    final code = _attrStr(tag, 'data-line');
    if (code == null) continue;
    final stroke = _attrStr(tag, 'stroke');
    if (stroke == null) {
      throw StateError('data-line "$code" path 에 stroke 가 없다 — 노선색을 알 수 없음');
    }
    if (stroke.toLowerCase() != '#ffffff') svgCodes.add(code);
  }
  final codes = d.codes;
  if (!svgCodes.containsAll(codes) || !codes.containsAll(svgCodes)) {
    throw StateError(
      'SVG data-line 코드 집합이 매핑과 다르다 — SVG 에만: '
      '${svgCodes.difference(codes)}, 매핑에만: ${codes.difference(svgCodes)}',
    );
  }
}

/// (c) **비기하 대조(주 검증)** — 원본 SVG 의 `<text data-line="C" data-station="역명">`
/// 은 코드와 역명을 정확히 짝지어 준다. 코드 C 라벨의 역명이 매핑된 노선의 역명
/// 집합에 [_kLabelHitMin] 이상 포함돼야 한다. 맞는 매핑은 ~100%, 틀린 매핑은 환승역
/// 이름 몇 개만 겹친다 — 좌표 허용치(px)에 기대는 기하 검증보다 마진이 훨씬 넓다.
List<String> _verifyLabelNames(_MapData d) {
  final labelNamesByCode = <String, Set<String>>{};
  for (final lb in d.labels) {
    final code = lb.code;
    if (code != null) labelNamesByCode.putIfAbsent(code, () => {}).add(lb.name);
  }
  final log = <String>[];
  for (final line in d.lines) {
    final id = line['id'] as String;
    final code = d.lineCodes[id]!;
    final names = {
      for (final sid in (line['stationIds'] as List).cast<String>())
        _normName(d.station(sid)['name'] as String),
    };
    final lbl = labelNamesByCode[code] ?? const <String>{};
    final hit = lbl.where(names.contains).length;
    if (lbl.isEmpty || hit < lbl.length * _kLabelHitMin) {
      throw StateError(
        '노선 $id → data-line "$code" 라벨 대조 실패: SVG 라벨 ${lbl.length}개 중 '
        '노선 역명에 속하는 것 $hit개 — kLineIdToDataLine 이 틀렸거나 SVG/역 데이터가 바뀌었다',
      );
    }
    log.add('$id→$code(라벨 $hit/${lbl.length})');
  }
  return log;
}

/// (d) **기하 대조(보조)** — 노선 역들이 실제로 그 코드의 선 위(≤3px)에 있는가.
/// GTX-A 처럼 이중선(바깥 색선+안쪽 흰선)이라 구조적으로 마진이 얇은 노선이 있어,
/// 임계는 (c) 가 못 잡는 "선은 맞는데 라벨만 우연히 일치" 류만 거르도록 느슨하게 둔다.
List<String> _verifyGeometry(_MapData d) {
  final log = <String>[];
  final codes = d.codes;
  for (final line in d.lines) {
    final id = line['id'] as String;
    final ids = (line['stationIds'] as List).cast<String>();
    final counts = <String, int>{};
    for (final code in codes) {
      var n = 0;
      for (final sid in ids) {
        final (x, y) = d.xy(sid);
        if (d.segsByCode[code]!.any((g) => _distPtSeg(x, y, g) <= 3)) n++;
      }
      counts[code] = n;
    }
    final mapped = d.lineCodes[id]!;
    final mappedN = counts[mapped]!;
    final others = counts.entries.where((e) => e.key != mapped).map((e) => e.value);
    final secondN = others.isEmpty ? 0 : others.reduce(math.max);
    if (mappedN < ids.length * _kGeoShareMin || mappedN < secondN * _kGeoLeadMin) {
      throw StateError(
        '노선 $id → data-line "$mapped" 기하 검증 실패: 선 위 역 $mappedN/${ids.length}, '
        '차점 코드 $secondN — kLineIdToDataLine 이 틀렸거나 SVG 가 바뀌었다',
      );
    }
    log.add('$id→$mapped(선 위 $mappedN/${ids.length} vs $secondN)');
  }
  return log;
}

// ======================================================================
// 3. 종점 선정
// ======================================================================
Map<String, int> _bfs(Map<String, Set<String>> g, String src) {
  final dist = {src: 0};
  final q = [src];
  for (var i = 0; i < q.length; i++) {
    for (final v in g[q[i]]!) {
      if (!dist.containsKey(v)) {
        dist[v] = dist[q[i]]! + 1;
        q.add(v);
      }
    }
  }
  return dist;
}

/// lineId → 종점 stationId 2개.
Map<String, List<String>> _pickTerminals(
  _MapData d,
  Map<String, List<String>> overrides,
) {
  final lineIds = d.lines.map((l) => l['id'] as String).toSet();
  for (final k in overrides.keys) {
    if (!lineIds.contains(k)) {
      throw StateError('kBadgeTerminalOverrides 의 노선 $k 가 lines.json 에 없다 — 항목을 지울 것');
    }
  }
  final terminals = <String, List<String>>{};
  for (final line in d.lines) {
    final id = line['id'] as String;
    final g = d.adj[id];
    if (g == null || g.isEmpty) throw StateError('노선 $id 의 connections 가 없음');
    final nodes = g.keys.toList()..sort();
    final override = overrides[id];
    terminals[id] = override != null
        ? _overrideTerminals(d, id, g, nodes, override)
        : _diameterTerminals(d, id, g, nodes);
  }
  return terminals;
}

/// 끊긴 노선의 명시 종점. 노선이 연결돼 있거나, 두 역이 같은 구간이거나, 차수 1 이 아니면 실패.
List<String> _overrideTerminals(
  _MapData d,
  String id,
  Map<String, Set<String>> g,
  List<String> nodes,
  List<String> names,
) {
  if (_bfs(g, nodes.first).length == nodes.length) {
    throw StateError('노선 $id 는 이제 연결돼 있다 — kBadgeTerminalOverrides 에서 제거할 것');
  }
  if (names.length != 2) {
    throw StateError('종점 오버라이드 $id 는 역명 정확히 2개여야 한다: $names');
  }
  final picked = <String>[];
  for (final name in names) {
    final hits = nodes.where((n) => d.station(n)['name'] == name).toList();
    if (hits.length != 1) {
      throw StateError('종점 오버라이드 $id/$name 이 노선 역에서 정확히 1건이 아님: $hits');
    }
    if (g[hits.first]!.length != 1) {
      throw StateError('종점 오버라이드 $id/$name 은 더 이상 종점(차수 1)이 아니다');
    }
    picked.add(hits.first);
  }
  if (_bfs(g, picked[0]).containsKey(picked[1])) {
    throw StateError(
      '종점 오버라이드 $id 의 두 역(${names.join(', ')})이 같은 구간에 있다 — '
      '끊긴 두 구간의 바깥 끝을 각각 적을 것',
    );
  }
  return picked;
}

/// 연결된 노선의 hop 지름 양 끝(동률은 유클리드 거리). 차수 1 후보가 모자라면(순환 포함)
/// 모든 노드를 후보로 삼는다.
List<String> _diameterTerminals(
  _MapData d,
  String id,
  Map<String, Set<String>> g,
  List<String> nodes,
) {
  if (_bfs(g, nodes.first).length != nodes.length) {
    throw StateError(
      '노선 $id 가 둘 이상의 구간으로 끊겨 있다 — kBadgeTerminalOverrides 에 종점을 등록할 것',
    );
  }
  var cand = nodes.where((n) => g[n]!.length == 1).toList();
  if (cand.length < 2) cand = nodes; // 순환 포함(6호선 응암루프): 모든 노드를 후보로
  String? bestA, bestB;
  var bestHop = -1;
  var bestEuclid = -1.0;
  for (final a in cand) {
    final dist = _bfs(g, a);
    for (final b in cand) {
      if (a.compareTo(b) >= 0) continue;
      final hop = dist[b]!;
      final (ax, ay) = d.xy(a);
      final (bx, by) = d.xy(b);
      final eu = math.sqrt(math.pow(ax - bx, 2) + math.pow(ay - by, 2));
      if (hop > bestHop || (hop == bestHop && eu > bestEuclid)) {
        bestHop = hop;
        bestEuclid = eu;
        bestA = a;
        bestB = b;
      }
    }
  }
  return [bestA!, bestB!];
}

// ======================================================================
// 4. 앵커·방향·크기
// ======================================================================

/// pts(끝점이 마지막)에서 (sx,sy) 의 수선발 → 끝점까지 호 길이. 선 위가 아니면 null.
double? _arcToEnd(List<_P> pts, double sx, double sy) {
  var bestD = double.infinity;
  var bestI = -1;
  var bestT = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    final dx = pts[i + 1].x - pts[i].x, dy = pts[i + 1].y - pts[i].y;
    final l2 = dx * dx + dy * dy;
    final t = l2 == 0
        ? 0.0
        : (((sx - pts[i].x) * dx + (sy - pts[i].y) * dy) / l2).clamp(0.0, 1.0);
    final dist = math.sqrt(
        math.pow(sx - pts[i].x - t * dx, 2) + math.pow(sy - pts[i].y - t * dy, 2));
    if (dist < bestD - 1e-9) {
      bestD = dist;
      bestI = i;
      bestT = t;
    }
  }
  if (bestD > 6) return null;
  var arc = (1 - bestT) * _segLen(pts[bestI], pts[bestI + 1]);
  for (var i = bestI + 1; i + 1 < pts.length; i++) {
    arc += _segLen(pts[i], pts[i + 1]);
  }
  return arc;
}

/// 종점 역에서 polyline 을 따라 "끝점까지 남은 호 길이(arc)"가 [_kMaxStub] 이하인 자유
/// 끝점을 앵커로 쓴다. 유클리드 거리만 보면 6호선 응암루프처럼 선이 되돌아와 끝나는 경우
/// (끝점이 루프 밖 응암 접합부) 엉뚱한 끝점을 잡는다 — 호 길이는 루프를 돌아가야 해서 크다.
///
/// 반환: (앵커, 바깥 방향 단위벡터, 종점 역↔끝점 호 길이).
(_P, _P, double) _anchorFor(_MapData d, String lineId, String code, String sid) {
  final (sx, sy) = d.xy(sid);
  List<_P>? bestPts;
  var bestD = double.infinity;
  for (final pts in d.orientedByCode[code]!) {
    final arc = _arcToEnd(pts, sx, sy);
    if (arc != null && arc < bestD) {
      bestD = arc;
      bestPts = pts;
    }
  }
  if (bestPts != null && bestD <= _kMaxStub) {
    final end = bestPts.last;
    // 끝점에서 경로를 따라 20 이상 되돌아간 지점 — 급한 꺾임에 덜 민감한 방향 추정.
    var acc = 0.0;
    var prev = bestPts[bestPts.length - 2];
    for (var i = bestPts.length - 1; i > 0; i--) {
      acc += _segLen(bestPts[i], bestPts[i - 1]);
      prev = bestPts[i - 1];
      if (acc >= 20) break;
    }
    final dx = end.x - prev.x, dy = end.y - prev.y;
    final l = math.sqrt(dx * dx + dy * dy);
    return (end, _P(dx / l, dy / l), bestD);
  }
  // 자유 끝점이 없는 종점(6호선 응암루프 끝 등): 역 좌표 + 이웃 역 반대 방향.
  final nb = d.adj[lineId]![sid]!.map(d.xy).toList();
  final mx = nb.map((e) => e.$1).reduce((a, b) => a + b) / nb.length;
  final my = nb.map((e) => e.$2).reduce((a, b) => a + b) / nb.length;
  var dx = sx - mx, dy = sy - my;
  final l = math.sqrt(dx * dx + dy * dy);
  if (l < 1e-6) {
    dx = 0;
    dy = -1;
  } else {
    dx /= l;
    dy /= l;
  }
  return (_P(sx, sy), _P(dx, dy), 0.0);
}

/// 배지 문구 검증 + 확정: lineId → 배지에 적을 문구.
///
/// (1) [badgeNames] 의 키는 lines.json 노선이어야 하고 문구는 비어 있지 않아야 한다(죽은 항목 방지).
/// (2) **어떤 배지 문구도 실제 역명과 같을 수 없다** — stations.json 전체와 원본 SVG 역명 라벨 전체를
/// 공백 제거 후 대조한다. 축약하지 않은 노선(`name` 그대로)도 같은 검사를 받는다.
/// (3) **배지 문구끼리도 유일해야 한다** — 두 노선이 같은 문구로 축약되면 노선 식별이라는 배지의
/// 존재 이유가 깨진다.
Map<String, String> _verifyBadgeTexts(_MapData d, Map<String, String> badgeNames) {
  final lineIds = d.lines.map((l) => l['id'] as String).toSet();
  for (final e in badgeNames.entries) {
    if (!lineIds.contains(e.key)) {
      throw StateError('kLineBadgeNames 키 "${e.key}" 가 lines.json 에 없다 — 죽은 항목을 지울 것');
    }
    if (e.value.trim().isEmpty) {
      throw StateError('kLineBadgeNames["${e.key}"] 문구가 비어 있다');
    }
  }
  String squash(String s) => _normName(s).replaceAll(RegExp(r'\s+'), '');
  // 공백 제거한 역명 → 출처(충돌 메시지용: 어느 역/라벨과 같은지).
  final stationNames = <String, String>{};
  for (final e in d.stations.entries) {
    stationNames.putIfAbsent(squash(e.value['name'] as String),
        () => 'stations.json 역 "${e.value['name']}"(id ${e.key}, 노선 ${e.value['lineId']})');
  }
  for (final lb in d.labels) {
    stationNames.putIfAbsent(
        squash(lb.name), () => 'SVG 역명 라벨 "${lb.name}"(data-line ${lb.code})');
  }
  final texts = <String, String>{};
  final owner = <String, String>{}; // squash(문구) → 그 문구를 쓰는 lineId
  for (final line in d.lines) {
    final id = line['id'] as String;
    final text = (badgeNames[id] ?? line['name'] as String).trim();
    final key = squash(text);
    final clash = stationNames[key];
    if (clash != null) {
      throw StateError(
        '노선 $id 배지 문구 "$text" 가 실제 역명과 같다($clash) — 배지가 역명 라벨로 오독된다. '
        'kLineBadgeNames 에서 역명과 겹치지 않는 문구를 쓸 것',
      );
    }
    final dup = owner[key];
    if (dup != null) {
      throw StateError(
        '노선 $dup 와 노선 $id 의 배지 문구가 같다("$text") — 두 노선을 구분할 수 없다. '
        'kLineBadgeNames 에서 서로 다른 문구를 쓸 것',
      );
    }
    owner[key] = id;
    texts[id] = text;
  }
  return texts;
}

/// 미해결 배지(하드 위반을 못 피한 배지)로 빌드를 실패시킬 때의 메시지: 어느 노선·어느 종점이
/// 무엇을 위반했는지, 그리고 조치 방법.
String _unresolvedMessage(_BadgePlacer placer, List<_Badge> all, List<_Badge> unresolved) {
  final lineNameById = {
    for (final l in placer.d.lines) l['id'] as String: l['name'] as String,
  };
  final sb = StringBuffer('미해결 배지 ${unresolved.length}개 — 기본 격자·확장 격자·허브 결합 탐색 어디에도 '
      '하드 위반 없이 앵커 ${_kMaxAnchorDist.toStringAsFixed(0)}px 이내에 놓을 자리가 없다:');
  for (final b in unresolved) {
    sb.write('\n  - 노선 ${b.lineId}(${lineNameById[b.lineId]}) 종점 ${b.stationName} '
        '앵커=(${_fmt(b.anchor.x)},${_fmt(b.anchor.y)}) 문구 "${b.text}"(폭 ${_fmt(b.w)}px): '
        '${placer.hardViolations(b, all).join(' / ')}');
  }
  sb.write('\n조치: 문구를 줄이거나(kLineBadgeNames — 폭이 좁을수록 좁은 자리에 들어간다), 해당 종점 주변 '
      '배치 데이터(SVG·역명 라벨)를 확인할 것. 앵커에서 멀리 보내거나 줄기(연결선)를 되살리는 것은 금지다 — '
      '줄기는 노선 선과 같은 색이라 존재하지 않는 지선처럼 읽히고, 연결선 없이 멀리 띄우면 귀속이 모호해진다.');
  if (all.any((b) => b.manual)) {
    sb.write('\n수동 보정 배지가 자리를 막고 있을 수 있다 — $kBadgeOffsetsPath 에서 해당 배지 항목을 지우거나 옮길 것'
        '(수동 보정: ${[for (final b in all) if (b.manual) b.key].join(', ')}).');
  }
  return sb.toString();
}

List<_Badge> _buildBadges(
    _MapData d, Map<String, List<String>> terminals, Map<String, String> texts) {
  final badges = <_Badge>[];
  for (final line in d.lines) {
    final id = line['id'] as String;
    final code = d.lineCodes[id]!;
    final color = d.colorByCode[code]!;
    final text = texts[id]!;
    final w = (_textWidth(text, kBadgeFontPx) + _kBadgePadX * 2).ceilToDouble();
    for (final sid in terminals[id]!) {
      final (anchor, dir, gap) = _anchorFor(d, id, code, sid);
      badges.add(_Badge(
        lineId: id,
        code: code,
        text: text,
        color: color,
        textColor: badgeTextColorFor(color),
        stationName: d.station(sid)['name'] as String,
        anchor: anchor,
        anchorGap: gap,
        dir: dir,
        w: w,
      ));
    }
  }
  if (badges.length != d.lines.length * 2) {
    throw StateError('배지 수 ${badges.length} != 노선 ${d.lines.length} × 2');
  }
  return badges;
}

/// 글자색 전환 요약(빌드 로그): 어느 노선이 짙은 글씨로 바뀌었는지와 그 대비비.
String _contrastSummary(_MapData d) {
  final dark = <String>[];
  var keptBelowAa = 0;
  for (final line in d.lines) {
    final color = d.colorByCode[d.lineCodes[line['id']]!]!;
    final white = contrastRatio(color, kBadgeLightText);
    if (badgeTextColorFor(color) == kBadgeDarkText) {
      dark.add('${line['name']}(흰 글씨 ${white.toStringAsFixed(2)}:1 → '
          '짙은 글씨 ${contrastRatio(color, kBadgeDarkText).toStringAsFixed(2)}:1)');
    } else if (white < 4.5) {
      keptBelowAa++;
    }
  }
  return '배지 글자색: 흰 글씨 대비 ${kBadgeMinWhiteContrast.toStringAsFixed(1)}:1 미만 → 짙은 글씨 전환 '
      '${dark.length}개 노선 [${dark.join(', ')}] · 흰 글씨 유지(AA 4.5:1 미달이나 '
      '$kBadgeMinWhiteContrast 이상, 관습 유지) $keptBelowAa개';
}

// ======================================================================
// 5. 배치 — 후보 비용 탐색
// ======================================================================
class _BadgePlacer {
  final _MapData d;
  _BadgePlacer(this.d);

  // 후보: 16방향 × 7거리(4~16px, 앵커 기준 지지선 거리). 비용 = 충돌 + 이탈 거리 + 이탈 각도.
  static const _gaps = [4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0];
  static const _nAng = 16;
  // 확장 격자(기본 격자가 하드 위반을 못 피할 때만): **방향만** 32개로 촘촘히 한다. 거리는 기본 격자와
  // 같다 — 앵커 [_kMaxAnchorDist] 이내가 하드 조건이라 더 멀리 보내는 선택지는 없다(조용히 멀리 보내지 않고
  // 빌드를 실패시킨다: `placeAll` 이 미해결 배지를 돌려주고 [buildLineBadges] 가 StateError). 조치 1순위는
  // 문구 축약([kLineBadgeNames]). 기본 후보를 모두 포함(22.5° 배수는 11.25° 격자에 포함)하므로 최저 비용이
  // 기본 결과보다 나빠지지 않는다. 그래도 남는 허브는 [_solveClusters] 가 결합 탐색한다.
  static const _wideGaps = _gaps;
  static const _wideNAng = 32;
  static const _refinePasses = 4;

  /// 배지는 줌아웃 보정이 없어 항상 1배([_Badge.rect]). 라벨만 [_kLabelScenes] 두 배율로 본다.
  double collisionCost(_Badge self, List<_Badge> placed) {
    var cost = 0.0;
    final rc = self.rect;
    // 캔버스 이탈은 사실상 금지.
    if (rc.x0 < _kMargin ||
        rc.y0 < _kMargin ||
        rc.x1 > kCanvasW - _kMargin ||
        rc.y1 > kCanvasH - _kMargin) {
      cost += 1e6;
    }
    // 줄기가 없으므로 앵커에서 떨어진 후보는 귀속 단서(인접성)를 잃는다 — 하드 위반급 가산.
    if (self.anchorDist > _kMaxAnchorDist) cost += _kHardViolationCost;
    for (final f in _kLabelScenes) {
      for (final lb in d.labels) {
        for (final r in lb.at(f)) {
          cost += 4 * rc.overlapArea(r);
        }
      }
    }
    for (final r in d.stationRects) {
      cost += 3 * rc.overlapArea(r);
    }
    for (final c in d.circles) {
      if (_circleHitsRect(c, rc)) cost += 250;
    }
    final probe = rc.inflate(_kLineProbePad);
    for (final e in d.segsByCode.entries) {
      if (e.key == self.code) {
        for (final s in e.value) {
          cost += _kOwnLinePerPx * _segLenInRect(s, rc);
        }
        continue;
      }
      var ring = 0.0;
      for (final s in e.value) {
        final l = _segLenInRect(s, rc);
        if (l > 0) cost += _kOtherLineFixed + _kOtherLinePerPx * l;
        // 근접 링: 패딩 사각형에는 걸리나 실제 사각형에는 안 걸리는 구간만(이중 계산 방지).
        ring += _segLenInRect(s, probe) - l;
      }
      // 코드(노선)당 1회, 상한 [_kNearLineCap] — 긴 변을 따라 스쳐도 겹침 최소 비용([_kOtherLineFixed])을
      // 넘지 않는다(상한이 없으면 폭 ≥48 pill 의 접선 스침이 수직 관통보다 비싸진다).
      if (ring > 0) cost += math.min(_kNearLinePerPx * ring, _kNearLineCap);
    }
    for (final o in placed) {
      if (identical(o, self)) continue;
      cost += 6 * rc.overlapArea(o.rect);
    }
    return cost;
  }

  /// 하드 위반: 타 노선 선 위·역명 라벨·역 circle·환승역 마커·다른 배지와의 실제 겹침, 캔버스 이탈,
  /// 또는 앵커에서 [_kMaxAnchorDist] 초과. [self] 의 ox/oy 가 평가 대상 후보여야 한다.
  /// 비용(soft)은 이 항목들 사이의 교환도 허용하지만, 요구사항은 "전부 0" 이므로 기본 격자의
  /// 최저 비용 후보가 위반을 안고 있으면 [place] 가 탐색 격자를 촘촘히 해 위반 없는 후보를 찾는다.
  bool violatesHard(_Badge self, List<_Badge> placed) => _hard(self, placed, firstOnly: true).isNotEmpty;

  /// [violatesHard] 의 사유 문장 목록(빌드 실패 메시지용).
  List<String> hardViolations(_Badge self, List<_Badge> placed) =>
      [for (final v in _hard(self, placed)) v.message];

  /// 하드 위반 판정의 **단일 구현** — 자동 배치 탐색·빌드 실패 메시지·수동 배치 경고·편집기 즉시 판정이
  /// 모두 이 함수를 쓴다. [firstOnly] 이면 첫 사유에서 멈춘다(탐색 핫패스).
  List<BadgeViolation> _hard(_Badge self, List<_Badge> placed, {bool firstOnly = false}) {
    final out = <BadgeViolation>[];
    final rc = self.rect;
    if (rc.x0 < _kMargin ||
        rc.y0 < _kMargin ||
        rc.x1 > kCanvasW - _kMargin ||
        rc.y1 > kCanvasH - _kMargin) {
      out.add(BadgeViolation(
          'canvas', '캔버스 이탈(${_fmt(rc.x0)},${_fmt(rc.y0)})-(${_fmt(rc.x1)},${_fmt(rc.y1)})'));
      if (firstOnly) return out;
    }
    final rcLine = rc.inflate(_kMinLineClear);
    for (final e in d.segsByCode.entries) {
      if (e.key == self.code) continue;
      var px = 0.0;
      for (final s in e.value) {
        final l = _segLenInRect(s, rcLine);
        if (l > _kHardLinePx) {
          px += l;
          if (firstOnly) return [...out, BadgeViolation('otherLine', '타 노선(${e.key}) 선 위')];
        }
      }
      if (px > 0) {
        out.add(BadgeViolation('otherLine', '타 노선(${e.key}) 선 위 ${px.toStringAsFixed(1)}px'));
      }
    }
    // 라벨은 장면(f=1.0 / 줌아웃 f=1.5)별로 따로 비교하되, 같은 라벨이 두 장면에서 걸리면 한 건으로 합친다.
    for (final lb in d.labels) {
      final hitScenes = <String>[];
      _R? hitRect;
      var hitArea = 0.0;
      for (final f in _kLabelScenes) {
        for (final r in lb.at(f)) {
          final area = rc.overlapArea(r);
          if (area > 1) {
            if (firstOnly) {
              return [...out, BadgeViolation('label', '역명 라벨 "${lb.name}" 겹침')];
            }
            hitScenes.add(f.toString());
            if (area > hitArea) {
              hitArea = area;
              hitRect = r;
            }
            break;
          }
        }
      }
      if (hitRect != null) {
        out.add(BadgeViolation(
            'label', '역명 라벨 "${lb.name}" 겹침 ${hitArea.toStringAsFixed(0)}px²(f=${hitScenes.join('·')})',
            x0: hitRect.x0, y0: hitRect.y0, x1: hitRect.x1, y1: hitRect.y1));
      }
    }
    for (final c in d.circles) {
      if (_circleHitsRect(c, rc)) {
        out.add(BadgeViolation('circle', '역 circle(${_fmt(c.cx)},${_fmt(c.cy)}) 겹침',
            x0: c.cx - c.r, y0: c.cy - c.r, x1: c.cx + c.r, y1: c.cy + c.r));
        if (firstOnly) return out;
      }
    }
    for (final r in d.stationRects) {
      final area = rc.overlapArea(r);
      if (area > 1) {
        out.add(BadgeViolation('rect', '환승역 마커(${_fmt(r.x0)},${_fmt(r.y0)}) 겹침 ${area.toStringAsFixed(0)}px²',
            x0: r.x0, y0: r.y0, x1: r.x1, y1: r.y1));
        if (firstOnly) return out;
      }
    }
    for (final o in placed) {
      if (identical(o, self)) continue;
      final area = rc.overlapArea(o.rect);
      if (area > 1) {
        final orc = o.rect;
        out.add(BadgeViolation(
            'badge',
            '다른 배지 ${o.lineId}/${o.stationName}${o.manual ? '(수동 보정)' : ''} 겹침 ${area.toStringAsFixed(0)}px²',
            otherKey: o.key,
            x0: orc.x0,
            y0: orc.y0,
            x1: orc.x1,
            y1: orc.y1));
        if (firstOnly) return out;
      }
    }
    if (self.anchorDist > _kMaxAnchorDist) {
      out.add(BadgeViolation('anchor',
          '앵커에서 너무 멂 ${_fmt(self.anchorDist)}px > ${_fmt(_kMaxAnchorDist)}px'));
    }
    return out;
  }

  /// 격자 [gaps] × [nAng] 방향을 훑어 최저 비용 후보를 [b] 에 기록하고, 그 후보가 하드 위반인지 돌려준다.
  /// [strict] 이면 하드 위반 후보에 큰 가산(비용 격차로 위반 없는 후보가 항상 이긴다)을 준다.
  bool _search(_Badge b, List<_Badge> placed, List<double> gaps, int nAng,
      {bool strict = false}) {
    final baseAng = math.atan2(b.dir.y, b.dir.x);
    var bestCost = double.infinity;
    var bestOx = 0.0, bestOy = 0.0, bestGap = 0.0, bestDeg = 0.0, bestAbs = 0.0;
    for (var k = 0; k < nAng; k++) {
      // k=0 이 선 연장 방향. 이후 ±step 씩 번갈아 퍼진다(동률 시 연장 방향 우선).
      final off = ((k + 1) ~/ 2) * (k.isOdd ? 1 : -1) * (2 * math.pi / nAng);
      final ang = baseAng + off;
      final ux = math.cos(ang), uy = math.sin(ang);
      final ext = b.w / 2 * ux.abs() + _kBadgeH / 2 * uy.abs();
      final angDeg = off.abs() * 180 / math.pi;
      for (final g in gaps) {
        b.ox = ux * (g + ext);
        b.oy = uy * (g + ext);
        b.chosenGap = g;
        var cost = collisionCost(b, placed) +
            1.5 * (g - _gaps.first) +
            0.35 * angDeg;
        if (strict && violatesHard(b, placed)) cost += _kHardViolationCost;
        if (cost < bestCost - 1e-9) {
          bestCost = cost;
          bestOx = b.ox;
          bestOy = b.oy;
          bestGap = g;
          bestDeg = angDeg;
          bestAbs = ang;
        }
      }
    }
    b.ox = bestOx;
    b.oy = bestOy;
    b.chosenGap = bestGap;
    b.chosenAngle = bestDeg;
    b.chosenAbsAng = bestAbs;
    return violatesHard(b, placed);
  }

  /// [b] 를 배치하고 **하드 위반이 남았는지**(미해결) 돌려준다.
  bool place(_Badge b, List<_Badge> placed) {
    if (!_search(b, placed, _gaps, _nAng)) {
      _polish(b, placed);
      return false;
    }
    // 기본 격자(16방향 × 4~16px)의 최저 비용 후보가 하드 위반이다 — 허브 밀집 구간. 방향을 더 촘촘하게
    // (32방향) 다시 찾는다. 이 결과도 위반이면 미해결이다(거리는 더 늘리지 않는다 — [_wideGaps] 주석).
    return _search(b, placed, _wideGaps, _wideNAng, strict: true);
  }

  /// 격자가 놓친 좁은 틈을 줍는 **국소 미세 조정**(충돌 비용이 0 이 아닌 배지만): 이미 하드 위반 없는 [b] 주변(±15°, 간격 ±4px)을
  /// 0.5° · 0.5px 단위로 다시 훑어 비용이 더 낮은 하드-유효 후보로 옮긴다. 하드 유효성은 그대로 지키므로
  /// 겹침을 만들지 않고, 비용은 늘지 않는다. 줄기가 없어 pill 이 앵커에 붙어야 하는 허브에서, 16방향
  /// 격자 사이(예: 김포공항 pill 이 5호선 선에서 3px 이상 떨어지는 30° 부근의 좁은 틈)를 찾는 용도다.
  /// 간격은 [_gaps] 최소값 아래로 내리지 않는다(내리면 비용식의 `1.5*(g-first)` 항이 음수라 멀쩡한 배지들이
  /// 전부 선 끝으로 끌려간다).
  void _polish(_Badge b, List<_Badge> placed) {
    // 충돌 비용이 0 인 배지(선 끝 연장 방향에 깨끗이 놓인 대부분)는 건드리지 않는다 — 각도 편차를 소수점
    // 단위로 줄이려고 멀쩡한 배치를 흔들 이유가 없고, 격자 전수(수천 회 비용 평가)가 빌드 시간을 3배로 늘린다.
    if (collisionCost(b, placed) <= 1e-9) return;
    final baseAng = math.atan2(b.dir.y, b.dir.x);
    double costOf(double g, double ang, double devDeg) {
      final ux = math.cos(ang), uy = math.sin(ang);
      final ext = b.w / 2 * ux.abs() + _kBadgeH / 2 * uy.abs();
      b.ox = ux * (g + ext);
      b.oy = uy * (g + ext);
      b.chosenGap = g;
      return collisionCost(b, placed) + 1.5 * (g - _gaps.first) + 0.35 * devDeg;
    }

    double devOf(double ang) {
      var dev = (ang - baseAng) % (2 * math.pi);
      if (dev > math.pi) dev -= 2 * math.pi;
      return dev.abs() * 180 / math.pi;
    }

    final cur = (b.ox, b.oy, b.chosenGap, b.chosenAngle, b.chosenAbsAng);
    var bestCost = costOf(cur.$3, cur.$5, devOf(cur.$5));
    var best = cur;
    for (var da = -15.0; da <= 15.0; da += 0.5) {
      final ang = cur.$5 + da * math.pi / 180;
      final dev = devOf(ang);
      for (var g = math.max(_gaps.first, cur.$3 - 4); g <= math.min(_kMaxAnchorDist, cur.$3 + 4); g += 0.5) {
        final c = costOf(g, ang, dev);
        if (c < bestCost - 1e-9 && !violatesHard(b, placed)) {
          bestCost = c;
          best = (b.ox, b.oy, g, dev, ang);
        }
      }
    }
    b.ox = best.$1;
    b.oy = best.$2;
    b.chosenGap = best.$3;
    b.chosenAngle = best.$4;
    b.chosenAbsAng = best.$5;
  }

  /// 순차 배치(앞서 확정된 배지만 장애물) → 개선 패스(다른 배지가 모두 확정된 상태에서 재선택) →
  /// 그래도 미해결이 남은 허브는 [_solveClusters] 로 **결합 탐색**.
  /// 모든 배지가 확정된 최종 상태에서 하드 위반이 남은 배지(**미해결**)를 돌려준다. 순차·개선 중간의
  /// 반환값이 아니라 최종 상태로 판정한다 — 나중에 배치된 배지가 앞 배지를 침범할 수 있기 때문이다.
  List<_Badge> placeAll(List<_Badge> badges) {
    // 수동 보정 배지는 풀지 않고(고정 위치) 장애물로만 쓴다 — 먼저 `placed` 에 넣어 자동 배지가 피하게 한다.
    // 수동이 없으면 `placed` 는 빈 목록에서 시작해 기존과 같은 순서로 채워진다(산출물 바이트 동일).
    final placed = <_Badge>[for (final b in badges) if (b.manual) b];
    for (final b in badges) {
      if (b.manual) continue;
      place(b, placed);
      placed.add(b);
    }
    for (var pass = 0; pass < _refinePasses; pass++) {
      for (final b in badges) {
        if (b.manual) continue;
        place(b, placed);
      }
    }
    // 미해결 판정은 **자동 배치 배지만**: 수동 배지의 하드 위반은 빌드 실패가 아니라 경고다.
    var unresolved = [
      for (final b in badges)
        if (!b.manual && violatesHard(b, badges)) b,
    ];
    if (unresolved.isNotEmpty) {
      _solveClusters(badges, unresolved);
      unresolved = [
        for (final b in badges)
          if (!b.manual && violatesHard(b, badges)) b,
      ];
    }
    return unresolved;
  }

  // ---- 허브 결합 탐색 -------------------------------------------------------------------------
  // 줄기가 없으면 배지는 앵커 [_kMaxAnchorDist] 이내에 붙어야 하는데, 종점이 몇 px 차이로 몰린 허브
  // (신설동: 2호선·우이신설, 청량리: 경춘·수인분당 …)에서는 **배지를 한 장씩 탐욕적으로** 놓으면
  // 먼저 놓인 배지가 이웃의 유일한 자리를 막는다(각각은 자리가 있는데 합치면 없다). 그래서 미해결
  // 배지가 있는 클러스터(앵커 간 거리 [_kClusterRadius] 이내 연결 성분)는 배지별 **유효 후보 전부**
  // (360방향 × 0.5px 간격, 단독으로 하드 위반 없는 것)를 모아 서로 겹치지 않는 조합을 완전 탐색(분기한정)한다.
  static const _kClusterRadius = 130.0;
  static const _kJointDirs = 360;
  static const _kJointTopK = 1500;

  void _solveClusters(List<_Badge> badges, List<_Badge> unresolved) {
    // 앵커 거리 기준 연결 성분.
    final comp = <_Badge, int>{};
    var nComp = 0;
    for (final b in badges) {
      if (comp.containsKey(b)) continue;
      final stack = [b];
      comp[b] = nComp;
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        for (final o in badges) {
          if (comp.containsKey(o)) continue;
          final dx = o.anchor.x - cur.anchor.x, dy = o.anchor.y - cur.anchor.y;
          if (dx * dx + dy * dy <= _kClusterRadius * _kClusterRadius) {
            comp[o] = nComp;
            stack.add(o);
          }
        }
      }
      nComp++;
    }
    final targets = {for (final u in unresolved) comp[u]!};
    for (final c in targets) {
      // 수동 보정 배지는 변수가 아니라 고정 장애물이다(`fixed` 에 들어간다).
      final cluster = [for (final b in badges) if (comp[b] == c && !b.manual) b];
      _solveCluster(badges, cluster);
    }
  }

  void _solveCluster(List<_Badge> all, List<_Badge> cluster) {
    final fixed = [for (final b in all) if (!cluster.contains(b)) b];
    final saved = [for (final b in cluster) (b.ox, b.oy, b.chosenGap, b.chosenAngle)];
    void restore() {
      for (var i = 0; i < cluster.length; i++) {
        final (ox, oy, g, a) = saved[i];
        cluster[i]
          ..ox = ox
          ..oy = oy
          ..chosenGap = g
          ..chosenAngle = a;
      }
    }

    // 배지별 유효 후보(단독 하드 위반 없음) — 비용 오름차순 상위 K.
    final cands = <List<_Cand>>[];
    for (final b in cluster) {
      final baseAng = math.atan2(b.dir.y, b.dir.x);
      final list = <_Cand>[];
      for (var k = 0; k < _kJointDirs; k++) {
        final ang = 2 * math.pi * k / _kJointDirs;
        final ux = math.cos(ang), uy = math.sin(ang);
        final ext = b.w / 2 * ux.abs() + _kBadgeH / 2 * uy.abs();
        var dev = (ang - baseAng) % (2 * math.pi);
        if (dev > math.pi) dev -= 2 * math.pi;
        final angDeg = dev.abs() * 180 / math.pi;
        for (var g = 1.0; g <= _kMaxAnchorDist; g += 0.5) {
          b.ox = ux * (g + ext);
          b.oy = uy * (g + ext);
          b.chosenGap = g;
          if (violatesHard(b, fixed)) continue;
          list.add(_Cand(b.ox, b.oy, g, angDeg,
              collisionCost(b, fixed) + 1.5 * g + 0.35 * angDeg, b.rect));
        }
      }
      list.sort((a, c) => a.cost.compareTo(c.cost));
      cands.add(list.length > _kJointTopK ? list.sublist(0, _kJointTopK) : list);
    }
    if (cands.any((l) => l.isEmpty)) return restore(); // 단독으로도 자리가 없다 → 미해결로 남는다
    // 후보가 적은 배지부터(분기 축소).
    final order = List<int>.generate(cluster.length, (i) => i)
      ..sort((a, c) => cands[a].length.compareTo(cands[c].length));
    var best = double.infinity;
    List<_Cand>? bestPick;
    final pick = List<_Cand?>.filled(cluster.length, null);
    // 남은 배지들의 최저 비용 합(하한) — 분기한정.
    final lower = List<double>.filled(order.length + 1, 0);
    for (var d = order.length - 1; d >= 0; d--) {
      lower[d] = lower[d + 1] + cands[order[d]].first.cost;
    }
    void dfs(int depth, double acc) {
      if (acc + lower[depth] >= best) return;
      if (depth == order.length) {
        best = acc;
        bestPick = [for (final p in pick) p!];
        return;
      }
      final i = order[depth];
      for (final c in cands[i]) {
        var ok = true;
        for (var d = 0; d < depth; d++) {
          if (pick[order[d]]!.rect.overlapArea(c.rect) > 1) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        pick[i] = c;
        dfs(depth + 1, acc + c.cost);
        pick[i] = null;
        if (acc + c.cost + lower[depth + 1] >= best) break; // 비용 오름차순이라 이후 후보도 불리
      }
    }

    dfs(0, 0);
    final chosen = bestPick;
    if (chosen == null) return restore();
    for (var i = 0; i < cluster.length; i++) {
      final b = cluster[i], c = chosen[i];
      b.ox = c.ox;
      b.oy = c.oy;
      b.chosenGap = c.gap;
      b.chosenAngle = c.angDeg;
    }
  }
}

/// 결합 탐색의 후보 한 칸(배지 중심 오프셋·간격·비용·사각형).
class _Cand {
  final double ox, oy, gap, angDeg, cost;
  final _R rect;
  const _Cand(this.ox, this.oy, this.gap, this.angDeg, this.cost, this.rect);
}

// ======================================================================
// 6. 겹침 측정 (빌드 로그용)
// ======================================================================
class _LineStats {
  final double otherPx, otherNearPx, ownPx;
  final int rectOverlaps, canvasEscapes;

  /// 앵커↔pill 실제 최단 거리(px), 오름차순.
  final List<double> anchorDists;

  /// 타 노선 선과의 최소 이격(px).
  final double minClearance;
  const _LineStats(this.otherPx, this.otherNearPx, this.ownPx, this.rectOverlaps,
      this.canvasEscapes, this.anchorDists, this.minClearance);
}

(List<String>, List<String>, _LineStats) _measureOverlaps(
    _MapData d, List<_Badge> badges) {
  final conflictLog = <String>[];
  // 배지 자체(항상 1배)와 장면 무관 장애물: 배지↔배지, 배지↔역 circle, 배지↔환승역 마커(rect), 캔버스 이탈.
  var bb = 0, bc = 0, br = 0, ce = 0;
  for (var i = 0; i < badges.length; i++) {
    final ri = badges[i].rect;
    if (ri.x0 < _kMargin ||
        ri.y0 < _kMargin ||
        ri.x1 > kCanvasW - _kMargin ||
        ri.y1 > kCanvasH - _kMargin) {
      conflictLog.add('  ${badges[i].lineId}/${badges[i].stationName} 캔버스 이탈');
      ce++;
    }
    for (final r in d.stationRects) {
      if (ri.overlapArea(r) > 1) {
        conflictLog.add('  ${badges[i].lineId}/${badges[i].stationName} ↔ 환승역 마커 '
            '(${_fmt(r.x0)},${_fmt(r.y0)}) 겹침 ${ri.overlapArea(r).toStringAsFixed(0)}px²');
        br++;
      }
    }
    for (var j = i + 1; j < badges.length; j++) {
      if (ri.overlapArea(badges[j].rect) > 1) bb++;
    }
    for (final c in d.circles) {
      if (_circleHitsRect(c, ri)) {
        conflictLog.add('  ${badges[i].lineId}/${badges[i].stationName} ↔ 역circle '
            '(${_fmt(c.cx)},${_fmt(c.cy)})');
        bc++;
      }
    }
  }
  final summary = [
    '배지 겹침(배지 1배 고정): 배지↔배지 $bb쌍 · 배지↔역circle $bc건 · '
        '배지↔환승역마커(rect) $br건 · 캔버스 이탈 $ce건',
  ];
  // 라벨은 줌아웃 시 환승역만 f 배로 커진다 — 장면별로 따로 센다.
  for (final f in _kLabelScenes) {
    var bl = 0;
    for (final badge in badges) {
      final ri = badge.rect;
      for (final lb in d.labels) {
        for (final r in lb.at(f)) {
          if (ri.overlapArea(r) > 1) {
            conflictLog.add('  라벨 f=$f ${badge.lineId}/${badge.stationName} ↔ 라벨 "${lb.name}" '
                '(겹침 ${ri.overlapArea(r).toStringAsFixed(0)}px²)');
            bl++;
            break;
          }
        }
      }
    }
    summary.add(
      '배지↔역명라벨 (라벨 f=${f.toStringAsFixed(1)}): $bl건 '
      '(대조: 라벨↔라벨 ${_labelPairOverlaps(d.labels, f)}쌍)',
    );
  }
  // 선 겹침 — 타 노선(귀속 혼동, 0 이어야 함) / 자기 노선(허용, 참고).
  var other = 0.0, otherNear = 0.0, own = 0.0, minClear = double.infinity;
  for (final b in badges) {
    final rc = b.rect, probe = rc.inflate(_kLineProbePad);
    for (final e in d.segsByCode.entries) {
      var px = 0.0, near = 0.0;
      for (final s in e.value) {
        px += _segLenInRect(s, rc);
        near += _segLenInRect(s, probe);
      }
      if (e.key == b.code) {
        own += px;
      } else {
        other += px;
        otherNear += near;
        for (final s in e.value) {
          minClear = math.min(minClear, _segRectDist(s, rc));
        }
        if (near > 0) {
          conflictLog.add('  선 ${b.lineId}/${b.stationName} ↔ 타노선(${e.key}) 선 '
              '겹침 ${px.toStringAsFixed(1)}px (패딩 ${_kLineProbePad.toStringAsFixed(0)}px 포함 '
              '${near.toStringAsFixed(1)}px)');
        }
      }
    }
  }
  summary.add(
    '배지↔타노선 선: ${other.toStringAsFixed(1)}px '
    '(패딩 ${_kLineProbePad.toStringAsFixed(0)}px 포함 ${otherNear.toStringAsFixed(1)}px) · '
    '배지↔타노선 선 최소 이격 ${minClear.toStringAsFixed(2)}px · 참고: 배지↔자기노선 선 ${own.toStringAsFixed(1)}px(허용)',
  );
  final dists = [for (final b in badges) b.anchorDist]..sort();
  summary.add(
    '줄기(배지↔종점 연결선): 없음 · 앵커↔pill 실제 최단 거리 최대 ${dists.last.toStringAsFixed(1)}px '
    '(상한 ${_kMaxAnchorDist.toStringAsFixed(0)}px, 중앙값 ${dists[dists.length ~/ 2].toStringAsFixed(1)}px)',
  );
  return (summary, conflictLog, _LineStats(other, otherNear, own, br, ce, dists, minClear));
}

/// 대조군: 기존 라벨↔라벨 겹침 쌍(배지와 무관한 SVG 원본 배치의 한계).
int _labelPairOverlaps(List<_Label> labels, double f) {
  var ll = 0;
  for (var i = 0; i < labels.length; i++) {
    for (var j = i + 1; j < labels.length; j++) {
      var hit = false;
      for (final a in labels[i].at(f)) {
        for (final b in labels[j].at(f)) {
          if (a.overlapArea(b) > 1) hit = true;
        }
      }
      if (hit) ll++;
    }
  }
  return ll;
}

// ======================================================================
// 7. SVG 조각
// ======================================================================
String _renderSvg(List<_Badge> badges) {
  final sb = StringBuffer('<g id="line-badges">\n');
  for (final b in badges) {
    final x0 = b.ox - b.w / 2, y0 = b.oy - _kBadgeH / 2;
    final tx = b.ox, ty = b.oy;
    final color = _xmlEscape(b.color);
    sb.writeln(
      '<g class="lb" data-badge-line="${_xmlEscape(b.lineId)}" data-code="${_xmlEscape(b.code)}" '
      'transform="translate(${_fmt(b.anchor.x)},${_fmt(b.anchor.y)})">'
      '<rect x="${_fmt(x0)}" y="${_fmt(y0)}" width="${_fmt(b.w)}" height="${_fmt(_kBadgeH)}" '
      'rx="${_fmt(_kBadgeH / 2)}" fill="$color"/>'
      '<text x="${_fmt(tx)}" y="${_fmt(ty)}" dy=".35em" text-anchor="middle" '
      'fill="${_xmlEscape(b.textColor)}">${_xmlEscape(b.text)}</text>'
      '</g>',
    );
  }
  sb.write('</g>');
  return sb.toString();
}
