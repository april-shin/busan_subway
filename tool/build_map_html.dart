/// 원본 SVG를 HTML 템플릿에 인라인 삽입하여 WebView용 map.html을 생성하는 스크립트.
///
/// 입력: assets/svg/seoul_metro_map.svg
/// 출력: assets/html/map.html
///
/// SVG 최소 변환:
/// - width="100%" height="100%" → width="2416" height="1560"
/// - style="background: white;" 제거
///
/// 사용법: dart run tool/build_map_html.dart
///
/// ⛔ 실시간 열차 애니메이션 4원칙 — 변경 금지 (CLAUDE.md 최상위 정책)
///   이 파일의 `estimateTrainPosition`, `startTrainAnimation`, `showTrains`,
///   `expandPathWithSnap(stationIndices)` 는 4원칙을 구현하는 핵심 코드다.
///   수정 전 반드시 CLAUDE.md 의 "실시간 열차 애니메이션 4원칙" 섹션을 확인하고,
///   원칙을 유지한 채 필요한 최소 변경만 가해야 한다. 원칙 자체를 바꾸려면
///   사용자 승인이 필요하다.
///   - 원칙 1: 열차는 절대 뒤로 가지 않는다 — 카운트다운 숫자는 API 원본
///       (recptnDt 기반 realRemaining)을 그대로 쓰므로 재조회로 원본이 바뀌면
///       늘어날 수 있지만, 아이콘의 경로상 위치는 단조 전진만 허용한다.
///       표시용·위치용 모두 **API 원본 값이 바뀐 refresh 에서만** 기준쌍을
///       보정한다 — 표시용은 `baseArrival`/`baseReceivedAt`(`adoptDisplayBase`),
///       위치용은 `posBaseArrival`/`posBaseReceivedAt`(startTrainAnimation).
///       원본이 그대로인 반복 보고에서 recptnDt 만 채택하면 표시는 톱니파가,
///       위치는 무기한 정지가 된다. 위치에는 추가로 "경로 끝까지 남은 거리"
///       backstop 가드(`minDistToEnd`/`pathEndKey`)를 둔다.
///   - 원칙 2: estimateTrainPosition — 뒤에서부터 역산
///   - 원칙 3: stationIndices 기반 3-way 클램프 (현재역 ↔ 다음역 안에만 머뭄)
///   - 원칙 4: 열차는 순간이동하지 않는다 — 목표가 바뀌어도 현재 위치에서
///       매 프레임 부드럽게 다가간다(catch-up). 속도는 거리 기반 반감기:
///       가까우면(≤30px) 3초로 잔잔하게(지터 흡수), 멀면(>30px) 0.5초로 빨리
///       따라잡아 선로 이탈처럼 보이는 시간을 최소화. 0.5px 이내면 스냅 종료.
///       startTrainAnimation.step() 의 HALF_LIFE_NEAR_MS/HALF_LIFE_FAR_MS/
///       FAST_DIST_THRESHOLD/SNAP_PX 참조.
///
/// ⛔ 동명 역 매칭 — `findStationByName(name, px, py)` 시그니처 변경 금지
///   5호선 "양평"(svgX=624, svgY=712) 과 경의중앙선 "양평"(svgX=2112, svgY=576)
///   같이 같은 이름·다른 좌표인 역을 구분하기 위해, 탭한 좌표(px, py)와 가장 가까운
///   역을 반환해야 한다. 이름만으로 검색하는 옛 시그니처(`findStationByName(name)`)
///   로 회귀하면 "양평" 클릭 시 항상 stations 배열의 첫 매치(5호선)가 잡혀
///   경의중앙선 양평을 선택할 수 없게 된다. 호출부 `tapLayer.pointerup` 의
///   `findStationByName(t.name, svgX, svgY)` 도 함께 유지할 것.
library;

import 'dart:convert';
import 'dart:io';

void main() {
  const svgPath = 'assets/svg/seoul_metro_map.svg';
  const htmlPath = 'assets/html/map.html';

  final svgFile = File(svgPath);
  if (!svgFile.existsSync()) {
    stderr.writeln('입력 파일 없음: $svgPath');
    exit(1);
  }

  var svgContent = svgFile.readAsStringSync();

  // SVG 최소 변환
  svgContent = svgContent.replaceFirst(
    'width="100%" height="100%"',
    'width="2416" height="1560"',
  );
  svgContent = svgContent.replaceFirst(
    RegExp(r'\s*style="background:\s*white;"'),
    '',
  );

  // 열차 이미지 Base64 인코딩
  const trainImagePath = 'assets/images/train.webp';
  final trainImageFile = File(trainImagePath);
  if (!trainImageFile.existsSync()) {
    stderr.writeln('열차 이미지 없음: $trainImagePath');
    exit(1);
  }
  final trainImageBase64 = base64Encode(trainImageFile.readAsBytesSync());

  final html = _buildHtml(svgContent, trainImageBase64);

  final htmlFile = File(htmlPath);
  htmlFile.parent.createSync(recursive: true);
  htmlFile.writeAsStringSync(html);

  final svgSize = svgFile.lengthSync();
  final htmlSize = htmlFile.lengthSync();

  stdout.writeln('HTML 생성 완료');
  stdout.writeln('  SVG: ${(svgSize / 1024).toStringAsFixed(1)}KB');
  stdout.writeln('  HTML: ${(htmlSize / 1024).toStringAsFixed(1)}KB');
}

String _buildHtml(String svgContent, String trainImageBase64) {
  // text 요소를 별도 레이어로 분리 (줌아웃 시 역명 크기 유지)
  final textPattern = RegExp(r'<text[^>]*>.*?</text>', dotAll: true);
  final textElements =
      textPattern.allMatches(svgContent).map((m) => m.group(0)!).join('\n');
  final mapOnlyContent = svgContent.replaceAll(textPattern, '');

  return '''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body {
  width: 100%; height: 100%;
  overflow: hidden;
  background: #f5f5f5;
  -webkit-user-select: none;
  user-select: none;
  touch-action: none;
}
#map-container {
  position: absolute;
  transform-origin: 0 0;
  will-change: transform;
}
#overlay {
  position: absolute;
  top: 0; left: 0;
  pointer-events: none;
}
#tap-layer {
  position: absolute;
  top: 0; left: 0;
  width: 2416px; height: 1560px;
  pointer-events: auto;
}
.tooltip {
  position: absolute;
  background: white;
  border-radius: 12px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.2);
  padding: 12px;
  pointer-events: auto;
  z-index: 100;
  display: none;
  min-width: 140px;
}
.tooltip-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}
.line-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  color: white;
  font-size: 11px;
  font-weight: bold;
  white-space: nowrap;
}
.station-name {
  font-size: 16px;
  font-weight: bold;
  white-space: nowrap;
}
.close-btn {
  cursor: pointer;
  color: #999;
  font-size: 18px;
  margin-left: 4px;
  pointer-events: auto;
}
.transfer-lines {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
  margin-bottom: 8px;
}
.transfer-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 3px;
  color: white;
  font-size: 9px;
  white-space: nowrap;
}
.actions {
  display: flex;
  gap: 12px;
  justify-content: center;
}
.action-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  cursor: pointer;
  pointer-events: auto;
  border: none;
  background: none;
  padding: 4px;
}
.action-btn .icon {
  width: 20px; height: 20px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  margin-bottom: 2px;
}
.action-btn .label {
  font-size: 10px;
}
/* [래스터 기아 수정 v6, 2026-08] §10_map-math-engineer_pan-flicker-report.md
   §22.2 가 CDP 실측(LayerTree/DOM/Tracing)으로 확정한 근본 원인: `<svg>` 루트
   요소는 자기 자신의 인라인 `style.transform` 대입에 반응해 스스로를
   `InvalidateLayout` 하는 Blink 고유 동작을 가진다 — 동일하게 매 프레임
   `.style.transform` 을 받는 `<div>`(`#map-container`, backendNodeId 69)는
   이 무효화가 0건인 반면 `<svg>` 루트(`#text-layer`/`#train-layer`,
   backendNodeId 70/61)는 각각 15/43회(10초 팬) 걸렸고, `#text-layer` 는 자식
   655개(`<text>`)의 `SvgTextLayoutAlgorithm::Layout` 폭주(10초에 13,843회)로
   이어졌다. 자식 프로퍼티(커스텀 상속 `--stroke-w` 등, 실험 A) 어떤 조정으로도
   이 무효화 자체는 사라지지 않았다(§22.2) — 원인이 자식이 아니라 SVG 루트
   자신이기 때문이다.
   해결: 매 프레임 바뀌는 pan/zoom transform 을 `<svg>` 루트가 아니라 그 바깥의
   `<div>` 래퍼(`#text-layer-wrap`/`#train-layer-wrap`)가 받도록 구조를
   바꾼다 — `#map-container`(div)가 이미 증명한 안전 패턴과 동일하게 적용한다.
   내부 `<svg>` 루트(#text-layer/#train-layer) 는 이제 transform 을
   전혀 받지 않고 뷰포트(0,0)~(2416,1560)에 정적으로 고정된다(viewBox 1:1이라
   래퍼의 CSS matrix(scale,...,tx,ty) 만으로 이전과 동일한 화면 좌표를 만든다 —
   좌표 수학 불변, DOM 커밋 대상만 교체). */
#text-layer-wrap, #train-layer-wrap {
  position: absolute;
  top: 0; left: 0;
  width: 2416px; height: 1560px;
  transform-origin: 0 0;
  will-change: transform;
  pointer-events: none;
}
#text-layer, #train-layer {
  /* 래퍼 div 의 유일한 자식으로, transform 을 받지 않는 고정 뷰포트다.
     display:block 은 SVG 루트가 기본값(inline)일 때 생기는 인라인 베이스라인
     오프셋을 없애 래퍼 원점(0,0)에 정확히 맞춘다. */
  display: block;
  width: 2416px; height: 1560px;
  pointer-events: none;
  /* 레이어가 지도 캔버스(2416x1560)로 고정 치수화되면서 UA 기본값(hidden)이
     경계 밖으로 삐져나오는 콘텐츠(말단역 도착 말풍선, 화면 끝 라벨 등)를
     실제로 잘라내기 시작했다. visible로 되돌려 구버전(뷰포트 전체 크기 레이어)과
     동일하게 클리핑 없이 렌더링한다. (이 overflow 는 SVG 자신의 클리핑
     특성이라 위 래퍼 div 가 아니라 이 규칙에 있어야 한다.) */
  overflow: visible;
}
#text-layer text {
  font-size: inherit !important;
  font-weight: 800;
  stroke: white;
  /* [래스터 기아 실험 A, 2026-08-13 — 기각·원복] --stroke-w 커스텀 프로퍼티가
     Blink 의 "독립 상속 프로퍼티" 최적화 경로를 타지 못해 팬 중 라벨 655개
     전체가 매 프레임 스타일 재계산된다는 가설로, 네이티브 inherit(위
     font-size 와 동일 패턴)로 바꿔 CDP Tracing 으로 재검증했다(§10 보고서
     §20~§22). 결과: 개선 없음(같은 세션 내 통제 비교 13,184건 → 12,529건,
     노이즈 범위) — `InvalidateLayout` 이 자식의 상속 프로퍼티 메커니즘과
     무관하게 `#text-layer`/`#train-layer` **SVG 루트 자신**에 직접 걸리는
     것으로 확정됐다(비교: 동일하게 매 프레임 transform 을 받는 `<div>`
     `#map-container` 는 0건). 근본 원인이 아니므로 원복한다(v6 구조 변경으로
     이 SVG 루트 자체는 이제 transform 을 받지 않게 됐지만, 이 규칙은 자식
     상속 프로퍼티 실험의 기록이므로 그대로 둔다). */
  stroke-width: var(--stroke-w, 2px);
  paint-order: stroke;
  stroke-linejoin: round;
}
/* [래스터 기아 수정 v3, 2026-08] 열차 아이콘(#live-trains 의 개별 <g>)을 각각
   독립 컴포지터 레이어로 승격한다. step() 이 매 rAF 마다 위치를 갱신하는데(원칙 2·4),
   이 승격이 없으면 그 갱신이 #train-layer 전체의 공유 래스터 표면에 다시 그려져야
   한다 — v3 당시엔 #train-layer(<svg> 루트) 자신이 팬 중 매 프레임 CSS matrix 로
   이동했으므로, 같은 프레임에 "레이어 재배치(컴포지터 전용, 저비용)"와 "레이어
   내부 콘텐츠 리페인트(고비용)"가 겹쳤다. 최대 줌아웃(노출 면적 최대)에서 팬+실시간
   열차가 겹치면 안드로이드 래스터 스레드가 예산을 초과해 일부 타일이 새 프레임
   커밋에 늦게 반영되며 라벨/말풍선/툴바가 순간 소실되는 점멸로 이어졌다
   (§10_map-math-engineer_pan-flicker-report.md 격리 측정). 개별 레이어로 분리하면
   위치 갱신이 부모의 래스터를 건드리지 않는 순수 컴포지트 연산이 되어 이 경쟁이
   사라진다.
   [문서-코드 드리프트 정정, v6 이후] v6(§23~§25)가 #train-layer 를 <div> 래퍼
   (#train-layer-wrap)로 감싸면서, 팬/줌의 매 프레임 transform 은 이제 그 래퍼가
   받고 #train-layer(<svg> 루트) 자신은 더 이상 transform 을 받지 않는다 — 위
   문단의 "#train-layer 자체도 매 프레임 CSS matrix 로 이동"은 v3~v5 시절
   서술이며 현재는 사실이 아니다. 다만 이 will-change 승격의 존재 이유(열차
   위치 갱신을 #train-layer 의 공유 래스터 표면과 분리해 컴포지트 전용 경로를
   타게 하는 것)는 #train-layer-wrap 기준으로도 여전히 유효해 유지한다. */
#live-trains > g {
  will-change: transform;
}
path[data-line] { stroke-width: 5 !important; }
/* GTX-A 등 이중선 노선의 흰색 테두리(원본 1px)가 본체 색상을 덮지 않도록 유지 */
path[data-line][stroke="#ffffff"] { stroke-width: 1 !important; }
/* [래스터 기아 수정 v4, 2026-08-13 — 기각·원복, v7 재검증] `text[data-line]`
   (라벨 dim/undim)을 한때 이 셀렉터에서 뺐던 적이 있다. 당시 근본 원인은
   `<svg>` 루트(#text-layer/#train-layer) 자신이 매 프레임 `.style.transform`
   대입에 반응해 스스로 `InvalidateLayout` 하는 것이었고(§10_map-math-engineer_
   pan-flicker-report.md §22.2), `text[data-line]` 제외는 라벨 655개의 상속
   프로퍼티 재계산 부담을 줄여 그 증상을 완화하는 우회책이었을 뿐, will-change
   승격이 근본 원인은 아니었다 — 라벨 dim 전환이 트랜지션 없이 즉시 스냅되는
   UX 트레이드오프가 있었다.
   v6(§23~§30)가 `<svg>` 루트를 `<div>` 래퍼로 감싸 이 자기-무효화 경로 자체를
   제거했으므로(순수 팬에서 InvalidateLayout 0건, §26.2), 그 우회책의 전제가
   소멸했다고 보고 `text[data-line]` 를 이 트랜지션 셀렉터에 되돌렸다(v7).
   동일 조건(경로+열차+최대 줌아웃+팬) 재측정으로 EVENTS=0 유지를 확인한 뒤
   채택했다 — 수치는 §32 참조. */
path[data-line], text[data-line], circle, rect:not(#route-overlay-bg) {
  transition: opacity 0.3s;
}
.dimmed {
  opacity: 0.12;
}
.route-toolbar {
  position: absolute;
  /* [래스터 기아 수정 v4, 2026-08-13] top/left 는 0 에 고정하고 실제 화면 위치는
     항상 transform(translate)으로만 표현한다. #map-container/#text-layer-wrap/
     #train-layer-wrap 이 이미 쓰는 것과 동일한 "고정 원점 + transform" 관용구
     (위 #text-layer-wrap/#train-layer-wrap 규칙 참조). will-change 로 독립
     컴포지터 레이어로 승격해 updateRouteToolbarPosition()/드래그의 매 프레임
     위치 갱신이 레이아웃을 유발하지 않게 한다 — 아래 updateRouteToolbarPosition
     주석 참조. */
  top: 0;
  left: 0;
  will-change: transform;
  display: none;
  flex-direction: column;
  z-index: 99;
  pointer-events: auto;
  background: white;
  border-radius: 14px;
  box-shadow: 0 2px 12px rgba(0,0,0,0.18);
  padding: 4px;
  padding-top: 28px;
  gap: 2px;
  /* 드래그 핸들: 상단 28px 빈 바(X 버튼 왼쪽 영역)를 잡아 툴바 이동 */
  cursor: move;
  touch-action: none;
  -webkit-user-select: none;
  user-select: none;
}
.route-toolbar-btn {
  display: block;
  width: 100%;
  padding: 7px 16px;
  border-radius: 10px;
  border: none;
  background: none;
  font-size: 13px;
  font-weight: 500;
  color: #666;
  cursor: pointer;
  pointer-events: auto;
  transition: all 0.2s;
  white-space: nowrap;
  text-align: center;
}
.route-toolbar-btn.active {
  background: #2196F3;
  color: white;
  font-weight: 600;
}
.route-toolbar-btn.close-btn {
  position: absolute;
  top: 2px;
  right: 2px;
  width: auto;
  padding: 2px 8px;
  color: #999;
  font-size: 16px;
  font-weight: bold;
  border-radius: 10px;
}
</style>
</head>
<body>
<div id="map-container">
$mapOnlyContent
<svg id="overlay" xmlns="http://www.w3.org/2000/svg" width="2416" height="1560">
  <rect id="route-overlay-bg" width="2416" height="1560" fill="white" opacity="0" />
  <g id="route-lines"></g>
  <g id="route-markers"></g>
  <g id="selection-markers"></g>
</svg>
<div id="tap-layer"></div>
</div>

<div id="text-layer-wrap">
<svg id="text-layer" xmlns="http://www.w3.org/2000/svg"
  viewBox="0 0 2416 1560" width="2416" height="1560">
$textElements
</svg>
</div>

<div id="train-layer-wrap">
<svg id="train-layer" xmlns="http://www.w3.org/2000/svg"
  viewBox="0 0 2416 1560" width="2416" height="1560">
  <g id="live-trains"></g>
</svg>
</div>

<div id="tooltip" class="tooltip"></div>
<div id="route-toolbar" class="route-toolbar"></div>

<script>
(function() {
  'use strict';

  // ============================================================
  // 상수
  // ============================================================
  var CANVAS_W = 2416, CANVAS_H = 1560;
  var MIN_SCALE = 0.5, MAX_SCALE = 5.0;
  var TAP_RADIUS = 12;
  var TEXT_BASE_FONT_SIZE = 12;
  var TEXT_BASE_STROKE_W = 2;
  // 줌아웃 시 라벨을 화면상 완전 고정(12px)하면 최대 줌아웃에서 역명이 심하게
  // 겹친다. 보정 하한(COMP_FLOOR)을 두어 scale 이 이 값 아래로 내려가면 라벨을
  // 서서히 축소한다. 최대 줌아웃(scale=MIN_SCALE=0.5)에서의 화면 폰트 =
  // TEXT_BASE_FONT_SIZE * MIN_SCALE / COMP_FLOOR = 12 * 0.5 / (2/3) = 9px.
  var TEXT_COMP_FLOOR = 2 / 3;
  var INITIAL_SCALE = 1.0;
  var INITIAL_CENTER_X = 1040, INITIAL_CENTER_Y = 618;
  var TRAIN_IMG = 'data:image/webp;base64,$trainImageBase64';

  // ============================================================
  // 상태
  // ============================================================
  var scale = INITIAL_SCALE;
  var tx = 0, ty = 0;
  // text-layer 폰트/스트로크 보정을 마지막으로 적용한 **보정계수(cs)** — scale
  // 자체가 아니다. [P2, 2026-08 리뷰] cs = clamp(scale, TEXT_COMP_FLOOR, 1) 라
  // scale > 1(확대) 구간 전체에서 cs 는 항상 1 로 고정되고, scale < TEXT_COMP_FLOOR
  // (최대 축소) 구간에서도 cs 는 TEXT_COMP_FLOOR 로 고정된다. 캐시 키를 scale 로
  // 두면 이 두 구간에서 scale 이 계속 바뀌는데도(확대 제스처 지속, 휠 줌 반복 등)
  // 매번 "값이 다르다"고 오판해 실제로는 동일한 fontSize/strokeWidth 를 다시
  // 쓴다 — 결과가 같은 불필요한 DOM 쓰기이자 text-layer 재래스터 유발 요인.
  // cs 를 키로 쓰면 이런 정체 구간에서 진짜 no-op 이 된다. null 이면 최초 1회
  // 강제 계산.
  var lastCs = null;
  var stations = [];
  var connections = [];
  var lineColors = {};
  var lineNames = {};
  var stationLineMap = {};
  var stationMap = {};       // stationId → station 객체
  var waypointIndex = {};    // "fromId_toId" → [{x,y}, ...] (중간점 포함 좌표 배열)

  var rafPending = false;
  function scheduleTransform() {
    if (rafPending) return;
    rafPending = true;
    requestAnimationFrame(function() {
      rafPending = false;
      applyTransform();
    });
  }

  var container = document.getElementById('map-container');
  var tapLayer = document.getElementById('tap-layer');
  var tooltip = document.getElementById('tooltip');
  var routeToolbar = document.getElementById('route-toolbar');
  var toolbarSvgX = 0, toolbarSvgY = 0;
  var toolbarVisible = false;
  var cachedTbW = 0, cachedTbH = 0;
  // 앵커(출발역) 기준 툴바 배치 오프셋(px, 화면 좌표계). 툴바 좌상단 =
  // (앵커 화면좌표) + (toolbarDx, toolbarDy). showRouteToolbar 가 경로와 겹침이
  // 가장 적은 방향을 골라 설정하고, pan/zoom·드래그가 이 오프셋을 공유한다.
  var toolbarDx = 0, toolbarDy = 0;
  // 사용자가 툴바를 직접 드래그해 옮겼는지. true 면 스마트 재배치를 하지 않아
  // 사용자가 고른 위치를 존중한다.
  var toolbarUserMoved = false;
  // 현재 경로에 포함된 역 ID 집합(highlightRoute 가 채움). 툴바 스마트 배치에서
  // "밝은 라벨 - 경로역 = 출발역 상류 역" 을 구하는 데 쓴다.
  var currentRouteSet = {};
  // 상류 역 주변에 예약하는 여유 반경(px, 화면 좌표). 상류 구간에는 접근 중인
  // 열차 아이콘과 도착 말풍선("○○행 N분 후 도착", 폭 ~145px)이 그려지므로,
  // 역 좌표만 피하면 말풍선이 잘린다. 열차를 실제로 조회하지 않고도 그 공간을
  // 확보하기 위해 정적으로 반경을 둔다.
  var UPSTREAM_RESERVE_PX = 70;
  // 앵커에서 툴바까지 띄우는 간격(px, 화면 좌표). 역 마커·라벨·선로에서 툴바를
  // 떼어놓는 최소 여백. 8방향 후보 모두에 동일하게 적용된다(좌/우 대칭).
  var TOOLBAR_GAP = 28;
  var overlayBg = document.getElementById('route-overlay-bg');
  var routeLines = document.getElementById('route-lines');
  var routeMarkers = document.getElementById('route-markers');
  var selectionMarkers = document.getElementById('selection-markers');
  var liveTrainsGroup = document.getElementById('live-trains');
  var activeTrains = {};
  // 도착 처리된 열차. 값은 두 형태 중 하나다 (playArrivalEffect 참조).
  //   { final: true }  — 정상 도착. **절대 되살리지 않는다(요구사항).**
  //   { raw: N }       — 유령 도착 후보. API 원본이 N 에서 바뀌면 되살린다.
  var arrivedTrains = {};
  // 유령 도착 판정 임계(초). 도착 시점의 API 원본이 이보다 크면 "우리 추정만
  // 앞서갔다" 로 본다. refresh 주기(15초)의 2배 — 정상 접근 열차는 원본이 벽시계와
  // 함께 줄어 도착 순간엔 통상 refresh 주기 이하다.
  // 2026-08-04 실측 근거: 목표역 진입 열차가 `barvlDt=10, arvlCd=0`(방배 진입)으로
  // 오고, 사당 stall 열차는 `barvlDt=150` 에 고정된다 — 두 군이 뚜렷이 갈린다.
  var GHOST_ARRIVAL_MIN_SEC = 30;
  var SVG_NS = 'http://www.w3.org/2000/svg';
  var textLayer = document.getElementById('text-layer');
  var trainLayer = document.getElementById('train-layer');
  // [래스터 기아 수정 v6, 2026-08] pan/zoom 의 매 프레임 transform 은 이제
  // <svg> 루트(textLayer/trainLayer, 위에서 얻은 참조들) 가 아니라 이 두
  // <div> 래퍼에만 대입한다 — textLayer/trainLayer 변수는 여전히 querySelectorAll/
  // fontSize/stroke 등 "SVG 콘텐츠 조작" 용도로만 쓰인다(참조 지점은 그대로
  // 유효 — getBBox()/querySelectorAll 은 SVG 사용자 좌표계 기준이라 어느
  // 조상이 transform 을 갖든 영향받지 않는다). 아래 applyTransform 참조.
  var textLayerWrap = document.getElementById('text-layer-wrap');
  var trainLayerWrap = document.getElementById('train-layer-wrap');

  // ============================================================
  // 변환 적용
  // ============================================================
  function applyTransform() {
    // map-container / text-layer-wrap / train-layer-wrap 는 모두 뷰포트
    // 원점(0,0)에 고정된 <div> 이고, 팬/줌은 이 CSS transform matrix 하나로만
    // 표현된다. 셋 다 순수 컴포지터 레이어 이동/스케일이라 팬 중 메인스레드
    // 리페인트가 발생하지 않는다.
    //
    // [래스터 기아 수정, 2026-07-29] 이전에는 text-layer/train-layer가
    // width:100%/height:100% + 매 프레임 viewBox 재계산 방식이었다. viewBox
    // 변경은 SVG 뷰포트의 좌표 매핑 자체를 바꾸는 것이라 컴포지터 전용 연산이
    // 아니라 내부 콘텐츠(특히 text-layer의 역명 라벨 수백 개) 전체를 메인스레드
    // 에서 강제로 다시 레이아웃/페인트한다. 팬 제스처 동안 매 rAF(pointermove)
    // 마다 이 강제 리페인트가 반복되며 메인스레드를 점유해, map-container가
    // 새로 노출된 영역의 타일을 래스터링할 기회(커밋)를 밀어내 안드로이드에서
    // 노선이 잠깐(수 프레임) 완전히 사라지는 점멸이 발생했다(텍스트 라벨은
    // 새 위치에 정상 표시된 채로). CSS transform 방식으로 바꿔 팬 중 재페인트
    // 자체를 제거했었다.
    //
    // [래스터 기아 수정 v6, 2026-08] 그러나 CSS transform 방식으로도 점멸이
    // 완전히 사라지지 않았다 — CDP 실측(§10_map-math-engineer_pan-flicker-
    // report.md §22.2) 결과, transform 을 받는 주체가 <svg> 루트 자신이면
    // 그 자체로 매 프레임 InvalidateLayout 을 스스로에게 건다는 것이
    // 밝혀졌다(동일 조건의 <div> 는 0건). 그래서 transform 대입 대상을
    // text-layer/train-layer 의 <svg> 루트에서 그 바깥의 <div> 래퍼로
    // 옮겼다 — 아래 textLayerWrap/trainLayerWrap. 내부 <svg> 는 이제 이
    // 함수에서 전혀 건드리지 않는다(viewBox 1:1 고정 뷰포트).
    var matrixStr =
        'matrix(' + scale + ',0,0,' + scale + ',' + tx + ',' + ty + ')';
    container.style.transform = matrixStr;
    textLayerWrap.style.transform = matrixStr;
    trainLayerWrap.style.transform = matrixStr;

    // scale < 1일 때 텍스트 크기/stroke-width 보상 (줌인은 기존대로).
    // [2026-08 핀치 점멸 수정] 2-포인터 핀치 진행 중에는 이 보정을 미룬다.
    // updateTextCompensation() 주석 참조 — pointerup/pointercancel 이 핀치
    // 종료 시점에 명시적으로 flush 한다.
    if (getPointerCount() !== 2) {
      updateTextCompensation();
    }

    updateRouteToolbarPosition();
  }

  // scale < 1일 때 텍스트 크기/stroke-width 보상 (줌인은 기존대로).
  // 단, COMP_FLOOR 아래로는 완전 보상하지 않아 최대 줌아웃에서 라벨이 축소되도록.
  // [2026-07 리뷰 수정] 구 viewBox 구현도 element(vw×vh) : viewBox(vw/scale×vh/scale)
  // 비율로 이미 scale배 확대를 수행하고 있었다 — CSS transform(scale)과 수학적으로
  // 동일한 배율이다. 즉 로컬(SVG 사용자 단위) font-size/stroke-width 값은 구현을
  // 바꾸기 전과 후 모두 "그 위에 scale배가 곱해진다"는 전제가 같으므로, 여기서
  // 추가로 /scale 을 나눠 상쇄할 필요가 없다(그렇게 하면 scale배 보정이 이중으로
  // 취소되어 최종 화면 크기가 scale=0.5에서 2배, scale=2에서 1/2배로 어긋난다 —
  // 브라우저 A/B 실측으로 확인된 회귀). 최종 화면 크기 = 로컬값 × scale =
  // TEXT_BASE_FONT_SIZE/cs × scale, TEXT_BASE_STROKE_W/cs × scale 로 구버전과
  // 동일하게 유지된다. scale 이 실제로 바뀐 프레임에서만 재계산하고, 팬 전용
  // 프레임(scale 불변, tx/ty만 변경)에서는 건너뛰어 --stroke-w/font-size 변경으로
  // 인한 text-layer 리페인트를 추가로 만들지 않는다.
  //
  // [2026-08 핀치 점멸 수정] 2-포인터 핀치 동안은 pointermove 마다(최대 60fps)
  // scale 이 거의 매 프레임 달라져 이 함수가 매 프레임 호출되고, font-size 는
  // text-layer 의 모든 <text> 자식(수백 개)이 상속하는 속성이라 값이 바뀔 때마다
  // 전체 서브트리 레이아웃/페인트가 강제된다. 팬 중엔 이미 scale 불변으로 스킵되지만
  // 핀치 중엔 scale 자체가 계속 바뀌므로 이 캐시가 무력화되어, 핀치 제스처 내내
  // (최대 60Hz) text-layer 전체가 반복 리페인트됐다 — 실시간 열차 업데이트(같은
  // 프레임에 #train-layer 도 갱신)와 겹치면 안드로이드 래스터 스레드가 두 대형
  // 레이어를 동시에 감당하지 못해 일부 타일이 새 프레임 커밋에 늦게 반영되는
  // 순간 노출(라벨 타일 점멸)로 이어진다. 핀치 도중엔 라벨이 매트릭스 스케일을
  // 그대로 따라가도록 두고(지도 전체와 함께 커지고 작아짐 — 통상적인 핀치 시각
  // 효과이며 판독성 저하는 순간적), 핀치가 끝나는 순간(pointerup/pointercancel)
  // 한 번만 반영해 리페인트를 제스처당 1회로 줄인다.
  function updateTextCompensation() {
    var cs = Math.max(Math.min(scale, 1), TEXT_COMP_FLOOR);
    // [P2] scale 이 아니라 실제로 화면에 쓰일 보정계수(cs)로 no-op 판정한다 —
    // 위 lastCs 선언부 주석 참조.
    if (cs === lastCs) return;
    textLayer.style.fontSize = (TEXT_BASE_FONT_SIZE / cs) + 'px';
    textLayer.style.setProperty(
        '--stroke-w', (TEXT_BASE_STROKE_W / cs) + 'px');
    lastCs = cs;
  }

  function setInitialView() {
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    tx = vw / 2 - INITIAL_CENTER_X * scale;
    ty = vh / 2 - INITIAL_CENTER_Y * scale;
    applyTransform();
  }

  // ============================================================
  // 터치/마우스 이벤트 (줌/팬)
  // ============================================================
  var pointers = {};
  // [P1, 2026-08 리뷰] 팬/핀치 제스처가 진행 중인 동안(포인터 1개 이상 접촉)
  // true. 열차 도착 말풍선의 카운트다운 텍스트 DOM 쓰기(step() 참조)를 제스처
  // 동안 미루는 데만 쓰인다 — realRemaining/위치 계산(4원칙)에는 관여하지 않고,
  // 최종 DOM 반영 여부만 제어한다. step() 의 rAF 루프는 제스처 중에도 계속
  // 돌므로, 제스처가 끝나 이 값이 false 로 바뀌면 바로 다음 프레임이 스스로
  // 밀린 텍스트를 반영한다(폰트 보정과 달리 별도 flush 호출이 필요 없다).
  var gestureActive = false;
  var lastDist = 0;
  var lastMidX = 0, lastMidY = 0;
  var isDragging = false;
  var dragStartX = 0, dragStartY = 0;
  var dragStartTx = 0, dragStartTy = 0;
  var hasMoved = false;

  function getPointerCount() {
    return Object.keys(pointers).length;
  }

  function getMidpoint() {
    var keys = Object.keys(pointers);
    if (keys.length < 2) return null;
    var p1 = pointers[keys[0]], p2 = pointers[keys[1]];
    return { x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 };
  }

  function getDist() {
    var keys = Object.keys(pointers);
    if (keys.length < 2) return 0;
    var p1 = pointers[keys[0]], p2 = pointers[keys[1]];
    var dx = p2.x - p1.x, dy = p2.y - p1.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  // 좌·우·하단 오버스크롤 여백.
  var OVERSCROLL_PAD = 70;
  // 상단 여백만 크게 잡는다. 지도 위에는 검색바 카드가 떠 있어(HomeScreen 의
  // 상단 오버레이) 캔버스 최상단에 있는 역(연천·발곡 등)이 카드에 가려진다.
  // 기존 70px 로는 끝까지 내려도 카드 높이를 벗어나지 못해 라벨을 읽을 수 없었다.
  var OVERSCROLL_PAD_TOP = 170;

  // 한 축의 translation 을 정한다. 이 로직은 지도 pan/zoom 화면 배치 전용이며
  // 실시간 열차 애니메이션 4원칙(카운트다운/역산/3-way/보간)과 무관하다.
  // - 콘텐츠(맵)가 뷰포트보다 작으면 (예: iPad 세로에서 줌아웃 시) 가장자리에
  //   붙여 한쪽에 큰 여백이 생기지 않도록 **중앙 정렬**한다.
  //   (기존엔 항상 +pad 쪽에 붙어 하단/우측에 거대한 빈 공간이 생겼다.)
  // - 콘텐츠가 뷰포트보다 크면 기존대로 [viewport - content - pad, pad] 범위로
  //   클램프해 가장자리 pad 만큼의 오버스크롤 여백만 허용한다.
  // - padStart 는 시작 가장자리(좌/상), padEnd 는 끝 가장자리(우/하) 의 여백이다.
  //   상단만 따로 키워 검색바 카드 아래에 가려지는 영역을 벗어날 수 있게 한다.
  function clampAxis(t, viewport, content, padStart, padEnd) {
    if (content <= viewport) {
      return (viewport - content) / 2;
    }
    var minT = viewport - content - padEnd;
    return Math.min(padStart, Math.max(minT, t));
  }

  function clampTranslation() {
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    tx = clampAxis(tx, vw, CANVAS_W * scale, OVERSCROLL_PAD, OVERSCROLL_PAD);
    ty = clampAxis(ty, vh, CANVAS_H * scale, OVERSCROLL_PAD_TOP, OVERSCROLL_PAD);
  }

  document.addEventListener('pointerdown', function(e) {
    panAnimId++;
    gestureActive = true;
    pointers[e.pointerId] = { x: e.clientX, y: e.clientY };
    if (getPointerCount() === 1) {
      isDragging = true;
      hasMoved = false;
      dragStartX = e.clientX;
      dragStartY = e.clientY;
      dragStartTx = tx;
      dragStartTy = ty;
    } else if (getPointerCount() === 2) {
      isDragging = false;
      lastDist = getDist();
      var mid = getMidpoint();
      lastMidX = mid.x;
      lastMidY = mid.y;
    }
  });

  document.addEventListener('pointermove', function(e) {
    if (!pointers[e.pointerId]) return;
    pointers[e.pointerId] = { x: e.clientX, y: e.clientY };

    if (getPointerCount() === 1 && isDragging) {
      var dx = e.clientX - dragStartX;
      var dy = e.clientY - dragStartY;
      if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
        hasMoved = true;
        if (tooltip.style.display !== 'none') {
          tooltip.style.display = 'none';
          sendToFlutter({ action: 'dismiss' });
        }
      }
      tx = dragStartTx + dx;
      ty = dragStartTy + dy;
      clampTranslation();
      scheduleTransform();
    } else if (getPointerCount() === 2) {
      hasMoved = true;
      if (tooltip.style.display !== 'none') {
        tooltip.style.display = 'none';
        sendToFlutter({ action: 'dismiss' });
      }
      var dist = getDist();
      var mid = getMidpoint();
      if (lastDist > 0) {
        var newScale = scale * (dist / lastDist);
        newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, newScale));

        // 핀치 중심점 기준으로 줌
        var contentX = (mid.x - tx) / scale;
        var contentY = (mid.y - ty) / scale;
        scale = newScale;
        tx = mid.x - contentX * scale;
        ty = mid.y - contentY * scale;
      }
      // 팬
      tx += mid.x - lastMidX;
      ty += mid.y - lastMidY;

      lastDist = dist;
      lastMidX = mid.x;
      lastMidY = mid.y;

      clampTranslation();
      scheduleTransform();
    }
  });

  document.addEventListener('pointerup', function(e) {
    delete pointers[e.pointerId];
    if (getPointerCount() === 0) {
      isDragging = false;
      gestureActive = false;
    } else if (getPointerCount() === 1) {
      // 핀치 → 드래그 전환: 남은 포인터로 드래그 재시작
      var keys = Object.keys(pointers);
      var p = pointers[keys[0]];
      isDragging = true;
      dragStartX = p.x;
      dragStartY = p.y;
      dragStartTx = tx;
      dragStartTy = ty;
    }
    // [2026-08 핀치 점멸 수정] 핀치(2-포인터) 가 끝나 포인터 수가 2 밖으로
    // 벗어나면, applyTransform 에서 미뤄뒀던 폰트 보정을 여기서 한 번만 반영한다.
    // pointerup 자체는 scheduleTransform/applyTransform 을 부르지 않으므로
    // (드래그 계속 시엔 다음 pointermove 가 부르지만, 핀치가 완전히 끝나 포인터가
    // 0 이 되는 경우엔 아무도 applyTransform 을 다시 부르지 않아 flush 가 누락된다).
    if (getPointerCount() !== 2) {
      updateTextCompensation();
    }
  });

  document.addEventListener('pointercancel', function(e) {
    delete pointers[e.pointerId];
    if (getPointerCount() === 0) {
      gestureActive = false;
    }
    // 위 pointerup 과 동일한 이유로 flush.
    if (getPointerCount() !== 2) {
      updateTextCompensation();
    }
  });

  // 마우스 휠 줌
  document.addEventListener('wheel', function(e) {
    e.preventDefault();
    var factor = e.deltaY < 0 ? 1.1 : 0.9;
    var newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale * factor));

    var contentX = (e.clientX - tx) / scale;
    var contentY = (e.clientY - ty) / scale;
    scale = newScale;
    tx = e.clientX - contentX * scale;
    ty = e.clientY - contentY * scale;

    clampTranslation();
    scheduleTransform();
    // [M-1, 2026-08 리뷰] applyTransform 의 폰트 보정은 `getPointerCount() !== 2`
    // 로 게이트된다 — pointerup/pointercancel 유실로 `pointers` 에 유령 항목
    // 2개가 남으면 이 게이트가 영구히 닫혀 이후 모든 보정이 동결될 수 있다.
    // 휠 줌은 터치 포인터 상태와 무관한 별개 입력 경로이므로(scale 을 바꾸는
    // 곳은 이 휠 핸들러와 2-포인터 핀치 두 곳뿐 — panTo/resize 는 scale 을
    // 바꾸지 않아 영향 없음), 여기서 게이트를 우회해 직접 flush한다. 핀치
    // 억제 로직(applyTransform 내부)은 건드리지 않아 그쪽 검증 결과에
    // 영향이 없다 — 실패 전파 범위를 이 핸들러 안으로만 좁힌다.
    updateTextCompensation();
  }, { passive: false });

  // ============================================================
  // 탭 감지 (텍스트 라벨 + circle 좌표 하이브리드)
  // ============================================================
  var svgTextTargets = []; // SVG text 요소의 바운딩 박스 (기준 폰트 12px 시점 측정)
  var TAP_TEXT_PAD = 6;    // 라벨 주변 터치 슬롭 (textTargetRect 에서 배율 적용)

  function buildTextTargets() {
    svgTextTargets = [];
    // 기준 폰트(12px)로 고정한 뒤 측정한다. 페이지 로드 직후에는 applyTransform
    // 의 폰트 역보정이 아직 적용되기 전이라 상속 폰트(16px) 기준으로 bbox 가
    // 33% 크게 측정되고, 이 인플레이션이 줌아웃 확장 배율과 곱해져 탭 박스가
    // 인접 역 라벨을 침범한다. (이후 setInitialView→applyTransform 이 현재
    // 줌에 맞는 값으로 다시 설정하므로 임시 고정은 무해.)
    textLayer.style.fontSize = TEXT_BASE_FONT_SIZE + 'px';
    // 위에서 fontSize를 직접 덮어썼으므로, updateTextCompensation의 lastCs 캐시가
    // "이미 현재 cs에 맞게 계산됐다"고 오인해 재계산을 건너뛰지 않도록 무효화한다.
    // 현재는 buildTextTargets가 최초 applyTransform 이전(lastCs=null인 시점)
    // 에만 호출되어 무해하지만, 향후 재측정 목적으로 재호출될 경우를 대비한 안전장치.
    lastCs = null;
    var texts = textLayer.querySelectorAll('text[data-station]');
    for (var i = 0; i < texts.length; i++) {
      var el = texts[i];
      var name = el.getAttribute('data-station').split('\\n').join('').split('\\r').join('');
      try {
        var bbox = el.getBBox();
        // 앵커점(x,y 속성)을 함께 저장한다. applyTransform 이 scale<1 에서
        // 폰트를 1/cs 배로 역보정하면 라벨은 이 앵커점을 고정점으로 확대되므로
        // (text-anchor start/end 모두), 탭 판정 박스도 같은 고정점 기준으로
        // 확장해야 화면에 보이는 라벨과 탭 영역이 일치한다.
        var ax = parseFloat(el.getAttribute('x'));
        var ay = parseFloat(el.getAttribute('y'));
        if (isNaN(ax)) ax = bbox.x + bbox.width / 2;
        if (isNaN(ay)) ay = bbox.y + bbox.height / 2;
        svgTextTargets.push({
          name: name,
          ax: ax,
          ay: ay,
          dx0: bbox.x - ax,
          dy0: bbox.y - ay,
          w: bbox.width,
          h: bbox.height
        });
      } catch(e) {}
    }
  }

  // 현재 줌 배율에서 라벨의 실제 탭 판정 박스를 계산한다.
  // scale<1 이면 폰트 역보정으로 라벨이 SVG 좌표계 기준 1/cs 배 커져 있으므로,
  // 저장해 둔 기준 bbox 를 앵커점 고정으로 동일 배율 확장한다. scale>=1 이면
  // f=1 로 기존 판정과 동일. 슬롭(TAP_TEXT_PAD)도 배율을 곱해 화면 px 기준
  // 일정한 여유를 유지한다.
  function textTargetRect(t) {
    var f = 1 / Math.min(scale, 1);
    var pad = TAP_TEXT_PAD * f;
    var x0 = t.ax + t.dx0 * f - pad;
    var y0 = t.ay + t.dy0 * f - pad;
    return {
      x0: x0,
      y0: y0,
      x1: x0 + t.w * f + pad * 2,
      y1: y0 + t.h * f + pad * 2
    };
  }

  // SVG 렌더링 후 텍스트 타겟 구축
  buildTextTargets();

  // 동명 역(예: 5호선 "양평" vs 경의중앙선 "양평") 구분을 위해 좌표 근접도로 선택한다.
  // px/py가 주어지면 이름 일치 역 중 그 좌표에 가장 가까운 역을 반환하고,
  // 없으면(기존 호환) 첫 매치를 반환한다.
  function findStationByName(name, px, py) {
    var best = null;
    var bestDistSq = Infinity;
    for (var i = 0; i < stations.length; i++) {
      if (stations[i].name !== name) continue;
      if (px == null || py == null) return stations[i];
      var dx = stations[i].svgX - px;
      var dy = stations[i].svgY - py;
      var d = dx * dx + dy * dy;
      if (d < bestDistSq) {
        bestDistSq = d;
        best = stations[i];
      }
    }
    return best;
  }

  tapLayer.addEventListener('pointerup', function(e) {
    if (hasMoved) return;

    // 화면 좌표 → SVG 좌표
    var rect = container.getBoundingClientRect();
    var svgX = (e.clientX - rect.left) / scale;
    var svgY = (e.clientY - rect.top) / scale;

    var nearest = null;

    // 1차: SVG 텍스트 라벨 영역 매칭 (사용자가 보는 역명 기준).
    // 판정 박스는 현재 줌 배율의 폰트 역보정을 반영해 매번 계산한다.
    // 줌아웃 시 인접 역명 박스가 겹칠 수 있으므로, 매치된 박스 중
    // 중심이 탭 지점에서 가장 가까운 라벨을 선택한다 (문서 순서 우선 금지).
    var bestBoxDistSq = Infinity;
    for (var i = 0; i < svgTextTargets.length; i++) {
      var t = svgTextTargets[i];
      var r = textTargetRect(t);
      if (svgX >= r.x0 && svgX <= r.x1 && svgY >= r.y0 && svgY <= r.y1) {
        var mx = (r.x0 + r.x1) / 2 - svgX;
        var my = (r.y0 + r.y1) / 2 - svgY;
        var d = mx * mx + my * my;
        if (d >= bestBoxDistSq) continue;
        // 탭 위치(svgX, svgY)에 가까운 동명 역을 선택 — 5호선/경의중앙선 양평 구분
        var cand = findStationByName(t.name, svgX, svgY);
        if (cand) {
          bestBoxDistSq = d;
          nearest = cand;
        }
      }
    }

    // 2차: circle 좌표 기반 근접 매칭 (폴백)
    if (!nearest) {
      var nearestDistSq = TAP_RADIUS * TAP_RADIUS;
      for (var i = 0; i < stations.length; i++) {
        var s = stations[i];
        var dx = s.svgX - svgX;
        var dy = s.svgY - svgY;
        var distSq = dx * dx + dy * dy;
        if (distSq < nearestDistSq) {
          nearestDistSq = distSq;
          nearest = s;
        }
      }
    }

    if (nearest) {
      sendToFlutter({
        action: 'stationTapped',
        stationId: nearest.id,
        stationName: nearest.name
      });
    } else {
      sendToFlutter({ action: 'dismiss' });
    }
  });

  // ============================================================
  // Flutter 통신
  // ============================================================
  function sendToFlutter(data) {
    try {
      if (window.StationChannel) {
        window.StationChannel.postMessage(JSON.stringify(data));
      }
    } catch (err) {
      // 채널 미등록 시 무시
    }
  }

  // ============================================================
  // Flutter에서 호출할 API
  // ============================================================

  // 역/연결 데이터 초기화
  window.initStations = function(stationsJson, connectionsJson, colorsJson, namesJson) {
    stations = JSON.parse(stationsJson);
    connections = JSON.parse(connectionsJson);
    lineColors = JSON.parse(colorsJson);
    lineNames = JSON.parse(namesJson);

    // stationMap 구축 (모듈 스코프)
    stationMap = {};
    for (var i = 0; i < stations.length; i++) {
      stationMap[stations[i].id] = stations[i];
    }

    // 역명 → 소속 노선 lineId 집합 캐시 (환승역 text/circle 매칭용)
    stationLineMap = {};
    for (var i = 0; i < stations.length; i++) {
      var sn = stations[i].name;
      if (!stationLineMap[sn]) stationLineMap[sn] = {};
      stationLineMap[sn][stations[i].lineId] = true;
    }

    // SVG path에서 waypoint 인덱스 구축
    buildWaypointIndex();
  };

  // 경로 하이라이트
  window.highlightRoute = function(routeStationIdsJson) {
    var routeIds = JSON.parse(routeStationIdsJson);
    var routeSet = {};
    // 툴바 스마트 배치가 "밝은 라벨 중 경로가 아닌 역 = 출발역 상류 역"을
    // 판별하는 데 사용한다.
    currentRouteSet = routeSet;
    for (var i = 0; i < routeIds.length; i++) {
      routeSet[routeIds[i]] = true;
    }

    // 오버레이 배경 활성화 (노선을 더 흐리게 덮어 경로 대비 강화)
    overlayBg.setAttribute('opacity', '0.72');

    // 기존 경로 초기화
    routeLines.replaceChildren();
    routeMarkers.replaceChildren();

    // 경로 구간 그리기
    for (var i = 0; i < connections.length; i++) {
      var conn = connections[i];
      if (conn.isTransfer) continue;

      var from = stationMap[conn.fromStationId];
      var to = stationMap[conn.toStationId];
      if (!from || !to) continue;

      if (!routeSet[from.id] || !routeSet[to.id]) continue;

      var color = lineColors[conn.lineId] || '#999';

      // waypointIndex에서 중간점 조회
      var key = conn.fromStationId + '_' + conn.toStationId;
      var revKey = conn.toStationId + '_' + conn.fromStationId;
      var wp = waypointIndex[key] || waypointIndex[revKey];

      if (wp && wp.length > 2) {
        // 중간점이 있으면 polyline으로 렌더링
        var pts = '';
        for (var wi = 0; wi < wp.length; wi++) {
          if (wi > 0) pts += ' ';
          pts += wp[wi].x + ',' + wp[wi].y;
        }
        var polyline = document.createElementNS(SVG_NS, 'polyline');
        polyline.setAttribute('points', pts);
        polyline.setAttribute('stroke', color);
        polyline.setAttribute('stroke-width', '5');
        polyline.setAttribute('stroke-linecap', 'round');
        polyline.setAttribute('stroke-linejoin', 'round');
        polyline.setAttribute('fill', 'none');
        routeLines.appendChild(polyline);
      } else {
        // 중간점 없으면 기존 직선 폴백
        var line = document.createElementNS(SVG_NS, 'line');
        line.setAttribute('x1', from.svgX);
        line.setAttribute('y1', from.svgY);
        line.setAttribute('x2', to.svgX);
        line.setAttribute('y2', to.svgY);
        line.setAttribute('stroke', color);
        line.setAttribute('stroke-width', '5');
        line.setAttribute('stroke-linecap', 'round');
        routeLines.appendChild(line);
      }
    }

    // 경로 위 역 마커
    var routeKeys = Object.keys(routeSet);
    for (var ri = 0; ri < routeKeys.length; ri++) {
      var id = routeKeys[ri];
      var s = stationMap[id];
      if (!s) continue;

      var color = lineColors[s.lineId] || '#999';
      var r = s.isTransfer ? 5 : 3.5;

      if (s.isTransfer) {
        var bg = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        bg.setAttribute('cx', s.svgX);
        bg.setAttribute('cy', s.svgY);
        bg.setAttribute('r', r);
        bg.setAttribute('fill', 'white');
        bg.setAttribute('stroke', color);
        bg.setAttribute('stroke-width', '2');
        bg.setAttribute('data-overlay', '');
        routeMarkers.appendChild(bg);
      } else {
        var dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        dot.setAttribute('cx', s.svgX);
        dot.setAttribute('cy', s.svgY);
        dot.setAttribute('r', r);
        dot.setAttribute('fill', color);
        dot.setAttribute('data-overlay', '');
        routeMarkers.appendChild(dot);
      }
    }
  };

  // 경로 하이라이트 제거
  window.clearRoute = function() {
    currentRouteSet = {};
    overlayBg.setAttribute('opacity', '0');
    routeLines.replaceChildren();
    routeMarkers.replaceChildren();
  };

  // 출발/경유/도착 마커 설정.
  // type: 'departure' | 'arrival' | 'waypoint-{index}' (경유 슬롯별 개별 마커)
  window.setMarker = function(type, svgX, svgY) {
    var markerId = 'marker-' + type;
    var existing = document.getElementById(markerId);
    if (existing) existing.remove();

    var color = type === 'departure' ? '#2196F3'
      : type === 'arrival' ? '#F44336'
      : '#FF9800';
    var g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.setAttribute('id', markerId);

    // 반투명 배경 원
    var bg = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    bg.setAttribute('cx', svgX);
    bg.setAttribute('cy', svgY);
    bg.setAttribute('r', '12');
    bg.setAttribute('fill', color);
    bg.setAttribute('opacity', '0.2');
    bg.setAttribute('data-overlay', '');
    g.appendChild(bg);

    // 테두리 링
    var ring = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    ring.setAttribute('cx', svgX);
    ring.setAttribute('cy', svgY);
    ring.setAttribute('r', '9');
    ring.setAttribute('fill', 'none');
    ring.setAttribute('stroke', color);
    ring.setAttribute('stroke-width', '2.5');
    ring.setAttribute('data-overlay', '');
    g.appendChild(ring);

    selectionMarkers.appendChild(g);
  };

  // 마커 제거
  window.clearMarkers = function() {
    selectionMarkers.replaceChildren();
  };

  // 툴팁 표시 (DOM API로 XSS 방지)
  window.showTooltip = function(stationJson) {
    var s = JSON.parse(stationJson);

    // 기존 내용 제거
    tooltip.textContent = '';

    // 헤더: 역명 + X 만 (호선 배지는 모두 하단으로 이동)
    var header = document.createElement('div');
    header.className = 'tooltip-header';

    var nameEl = document.createElement('span');
    nameEl.className = 'station-name';
    nameEl.textContent = s.name;
    header.appendChild(nameEl);

    var closeBtn = document.createElement('span');
    closeBtn.className = 'close-btn';
    closeBtn.textContent = '\u00d7';
    closeBtn.addEventListener('click', function() { window._dismissTooltip(); });
    header.appendChild(closeBtn);

    tooltip.appendChild(header);

    // 노선 배지: 현재 노선 + 환승 노선 모두 역명 하단에 동일 형식으로 표시
    var linesDiv = document.createElement('div');
    linesDiv.className = 'transfer-lines';

    var displayLines = [s.lineId];
    if (s.transferLines && s.transferLines.length) {
      for (var i = 0; i < s.transferLines.length; i++) {
        if (s.transferLines[i] !== s.lineId) displayLines.push(s.transferLines[i]);
      }
    }

    for (var i = 0; i < displayLines.length; i++) {
      var lid = displayLines[i];
      var b = document.createElement('span');
      b.className = 'transfer-badge';
      b.style.background = lineColors[lid] || '#999';
      b.textContent = lineNames[lid] || lid;
      linesDiv.appendChild(b);
    }
    tooltip.appendChild(linesDiv);

    // 액션 버튼
    var actions = document.createElement('div');
    actions.className = 'actions';

    function makeBtn(icon, label, labelColor, handler) {
      var btn = document.createElement('button');
      btn.className = 'action-btn';
      var iconDiv = document.createElement('div');
      iconDiv.className = 'icon';
      iconDiv.style.color = labelColor;
      iconDiv.textContent = icon;
      btn.appendChild(iconDiv);
      var labelDiv = document.createElement('div');
      labelDiv.className = 'label';
      labelDiv.style.color = labelColor;
      labelDiv.textContent = label;
      btn.appendChild(labelDiv);
      btn.addEventListener('click', handler);
      return btn;
    }

    actions.appendChild(makeBtn('\u25c9', '출발', '#2196F3', function() { window._setDeparture(s.id); }));
    actions.appendChild(makeBtn('⬦', '경유', '#FF9800', function() { window._addWaypoint(s.id); }));
    actions.appendChild(makeBtn('\u26b2', '도착', '#F44336', function() { window._setArrival(s.id); }));
    actions.appendChild(makeBtn('\u23f0', '도착정보', '#4CAF50', function() { window._viewArrivalInfo(s.name); }));

    tooltip.appendChild(actions);
    tooltip.style.display = 'block';

    // 툴팁 위치 (화면 좌표)
    var screenX = s.svgX * scale + tx;
    var screenY = s.svgY * scale + ty;
    var tooltipW = tooltip.offsetWidth;

    var left = screenX - tooltipW / 2;
    left = Math.max(8, Math.min(window.innerWidth - tooltipW - 8, left));
    var top = screenY - tooltip.offsetHeight - 16;
    if (top < 8) top = screenY + 16;

    tooltip.style.left = left + 'px';
    tooltip.style.top = top + 'px';
  };

  // 툴팁 숨기기
  window.hideTooltip = function() {
    tooltip.style.display = 'none';
  };

  // 내부 액션 핸들러
  window._dismissTooltip = function() {
    window.hideTooltip();
    sendToFlutter({ action: 'dismiss' });
  };

  window._setDeparture = function(stationId) {
    window.hideTooltip();
    sendToFlutter({ action: 'setDeparture', stationId: stationId });
  };

  window._setArrival = function(stationId) {
    window.hideTooltip();
    sendToFlutter({ action: 'setArrival', stationId: stationId });
  };

  // 경유역 추가. 상한(경유 최대 개수)은 Flutter 쪽 상태가 알고 있으므로
  // 여기선 항상 보내고, 초과 시 Flutter 가 스낵바로 알린다.
  window._addWaypoint = function(stationId) {
    window.hideTooltip();
    sendToFlutter({ action: 'addWaypoint', stationId: stationId });
  };

  window._viewArrivalInfo = function(stationName) {
    window.hideTooltip();
    sendToFlutter({ action: 'viewArrivalInfo', stationName: stationName });
  };

  // ============================================================
  // 노선 강조/흐림 처리
  // ============================================================

  // 앱 lineId → SVG data-line 코드 매핑
  var lineIdToDataLine = {
    '1': ['2-1'],
    '2': ['3-2'],
    '3': ['4-3'],
    '4': ['5-4'],
    '5': ['6-5'],
    '6': ['7-6'],
    '7': ['8-7'],
    '8': ['9-8'],
    '9': ['10-9'],
    'SB': ['S'],
    '경의중앙': ['K'],
    '경춘': ['G'],
    '경강': ['KK'],
    '공항철도': ['A'],
    '수인분당': ['B'],
    '신림': ['SL'],
    '에버라인': ['E'],
    '인천1': ['I'],
    '인천2': ['I2'],
    '김포골드': ['KP'],
    '서해': ['SH'],
    '의정부': ['U'],
    '우이신설': ['W'],
    'GTX-A': ['1-GA']
  };

  // ============================================================
  // SVG path 파싱 및 waypoint 인덱스 구축
  // ============================================================

  // SVG path d 속성에서 좌표 배열 추출 (M/L 명령어만 사용하는 SVG)
  function parseSvgPath(d) {
    var coords = [];
    var re = /([ML])\\s*([\\d.]+)\\s+([\\d.]+)/g;
    var m;
    while ((m = re.exec(d)) !== null) {
      coords.push({ x: parseFloat(m[2]), y: parseFloat(m[3]) });
    }
    return coords;
  }

  // 좌표 배열에서 (x,y)에 가장 가까운 인덱스를 찾되, **동률(±2px)인 정점을 모두**
  // 반환한다 (tolerance 이내, 없으면 빈 배열).
  //
  // ⚠️ "가장 가까운 하나"만 골라선 안 된다. 하나의 SVG path 가 같은 역 좌표를 두 번
  // 지나는 경우가 있다 — 2호선 본선 path 는 신정지선 끝에서 시작해 신도림(index 6)
  // 에서 순환선에 진입한 뒤 한 바퀴 돌아 다시 신도림(마지막 index 72)에서 끝난다.
  // 이때 대림(69)↔신도림 구간이 앞쪽 신도림(6)과 짝지어지면 slice 가 순환선을
  // 거꾸로 한 바퀴 감싸(64개 정점, 3316px) 하이라이트가 2호선 전체에 칠해진다.
  // 후보를 모두 모은 뒤 호출부에서 인덱스 거리가 최소인 조합을 고른다.
  //
  // 동률(TIE_EPS)로 제한하는 이유: tolerance(20px) 이내 정점을 전부 후보로 삼으면
  // 역 근처 곡선 꺾임점까지 후보가 되어, 최소 인덱스 거리 조합이 실제 구간보다
  // 짧은 인접 정점 쌍으로 잡히고 곡선 중간점이 사라진다(약 50개 구간 소실).
  function findNearestIdxs(path, x, y, tolerance) {
    var TIE_EPS = 4; // 거리제곱 허용오차 = 2px
    var bestDist = tolerance * tolerance;
    for (var i = 0; i < path.length; i++) {
      var dx = path[i].x - x;
      var dy = path[i].y - y;
      var d2 = dx * dx + dy * dy;
      if (d2 < bestDist) bestDist = d2;
    }
    if (bestDist >= tolerance * tolerance) return [];
    var idxs = [];
    for (var i = 0; i < path.length; i++) {
      var dx2 = path[i].x - x;
      var dy2 = path[i].y - y;
      if (dx2 * dx2 + dy2 * dy2 <= bestDist + TIE_EPS) idxs.push(i);
    }
    return idxs;
  }

  // 모든 connection의 waypoints를 사전 계산하여 waypointIndex에 저장
  function buildWaypointIndex() {
    waypointIndex = {};
    var TOLERANCE = 20;

    // data-line 코드별 SVG path 좌표 캐시
    var pathsByDl = {};
    var svgPaths = document.querySelectorAll('path[data-line]');
    for (var i = 0; i < svgPaths.length; i++) {
      var dl = svgPaths[i].getAttribute('data-line');
      var d = svgPaths[i].getAttribute('d');
      if (!d) continue;
      var coords = parseSvgPath(d);
      if (coords.length < 2) continue;
      if (!pathsByDl[dl]) pathsByDl[dl] = [];
      pathsByDl[dl].push(coords);
    }

    for (var ci = 0; ci < connections.length; ci++) {
      var conn = connections[ci];
      if (conn.isTransfer) continue;

      var from = stationMap[conn.fromStationId];
      var to = stationMap[conn.toStationId];
      if (!from || !to) continue;

      var dlCodes = lineIdToDataLine[conn.lineId];
      if (!dlCodes) continue;

      var found = false;
      for (var di = 0; di < dlCodes.length && !found; di++) {
        var paths = pathsByDl[dlCodes[di]];
        if (!paths) continue;
        for (var pi = 0; pi < paths.length && !found; pi++) {
          var path = paths[pi];
          var fIdxs = findNearestIdxs(path, from.svgX, from.svgY, TOLERANCE);
          var tIdxs = findNearestIdxs(path, to.svgX, to.svgY, TOLERANCE);
          if (fIdxs.length === 0 || tIdxs.length === 0) continue;

          // 인접 두 역이므로 path 상에서도 가장 가까운 조합이 실제 구간이다.
          // (같은 역이 두 번 등장하는 순환선 대응 — findNearestIdxs 주석 참조)
          var fi = -1;
          var ti = -1;
          var bestSpan = Infinity;
          for (var fj = 0; fj < fIdxs.length; fj++) {
            for (var tj = 0; tj < tIdxs.length; tj++) {
              var span = Math.abs(fIdxs[fj] - tIdxs[tj]);
              if (span > 0 && span < bestSpan) {
                bestSpan = span;
                fi = fIdxs[fj];
                ti = tIdxs[tj];
              }
            }
          }
          if (fi < 0) continue;

          var lo = Math.min(fi, ti);
          var hi = Math.max(fi, ti);
          var segment = path.slice(lo, hi + 1);
          if (fi > ti) segment.reverse();

          // Sanity: slice 총 길이가 두 역 직선거리의 3배를 넘으면 분기/지선
          // 오매칭으로 보고 탈락(다른 path 를 계속 탐색). 저장하지 않으면
          // 렌더러가 직선 폴백으로 그리므로 최소한 엉뚱한 곳을 칠하지 않는다.
          // (열차 스냅 경로 getSnappedSlice 와 동일 기준)
          var straightDist = Math.sqrt(
              (to.svgX - from.svgX) * (to.svgX - from.svgX) +
              (to.svgY - from.svgY) * (to.svgY - from.svgY));
          var sliceLen = 0;
          for (var k = 0; k < segment.length - 1; k++) {
            var sdx = segment[k + 1].x - segment[k].x;
            var sdy = segment[k + 1].y - segment[k].y;
            sliceLen += Math.sqrt(sdx * sdx + sdy * sdy);
          }
          if (straightDist > 0 && sliceLen > straightDist * 3) continue;

          // 중간점이 있는 경우만 저장 (2개 = 직선이므로 불필요)
          if (segment.length > 2) {
            var key = conn.fromStationId + '_' + conn.toStationId;
            waypointIndex[key] = segment;
          }
          found = true;
        }
      }
    }
  }

  // 특정 노선만 강조, 나머지 흐림 처리
  // highlightLines(lineIdsJson, keepNamesJson)
  //  - lineIdsJson: 경로가 지나는 전체 노선 ID. 노선 path/역 circle 강조 대상.
  //  - keepNamesJson: 역 이름 라벨을 밝게 유지할 역 이름(경로 역 ∪ 출발역 상류
  //      역). 강조 노선에 속한 역이라도 이 집합에 없으면 흐리게 처리한다.
  //  keepNamesJson 이 비어 있으면(구 호출 형태) 기존 동작(강조 노선 전체 라벨
  //  강조)과 동일하게 동작한다.
  window.highlightLines = function(lineIdsJson, keepNamesJson) {
    if (!lineColors || Object.keys(lineColors).length === 0) return;
    var lineIds = JSON.parse(lineIdsJson);
    var keepNamesArr = keepNamesJson ? JSON.parse(keepNamesJson) : [];

    // lineId → data-line 코드 집합 변환
    var codeSet = {};
    for (var i = 0; i < lineIds.length; i++) {
      var codes = lineIdToDataLine[lineIds[i]];
      if (codes) {
        for (var j = 0; j < codes.length; j++) {
          codeSet[codes[j]] = true;
        }
      }
    }

    // 유지할 역 이름 집합(라벨 매칭용). 비어 있으면 라벨 이름필터 비활성.
    var keepNameSet = {};
    var hasKeepNameFilter = keepNamesArr.length > 0;
    for (var i = 0; i < keepNamesArr.length; i++) {
      keepNameSet[keepNamesArr[i].replace(/[\\n\\r]/g, '')] = true;
    }

    // ⚠️ 흐림 처리 쿼리는 반드시 원본 지도(container)·라벨 레이어(textLayer)로
    // 스코프를 제한한다. document 전역으로 조회하면 #train-layer 안의 실시간
    // 열차 요소까지 잡힌다 — 도착 말풍선 배경(rect, 노선색)·급행 배지·디버그
    // 박스가 .dimmed(opacity 0.12) 되어 흰색 말풍선 글씨만 남아 안 보이게 된다.
    // (경로 모드 최단경로↔최소환승 전환처럼 열차가 이미 그려진 뒤 재호출될 때 발생)

    // path[data-line] 요소 처리
    var paths = container.querySelectorAll('path[data-line]');
    for (var i = 0; i < paths.length; i++) {
      var dl = paths[i].getAttribute('data-line');
      if (codeSet[dl]) {
        paths[i].classList.remove('dimmed');
      } else {
        paths[i].classList.add('dimmed');
      }
    }

    // lineId 집합 (text의 역명→노선 확인용, circle 좌표 매칭용)
    var lineIdSet = {};
    for (var i = 0; i < lineIds.length; i++) {
      lineIdSet[lineIds[i]] = true;
    }

    // text[data-line] 요소(역 이름 라벨) 처리
    //  - 강조 노선에 속하고 keepNameSet 에 있는 역: 밝게 유지
    //  - 강조 노선에 속하지만 keepNameSet 에 없는 역(경로 밖·하류): 흐리게
    //  - 강조 노선에 속하지 않는 역: 기존대로 흐리게
    var texts = textLayer.querySelectorAll('text[data-line]');
    for (var i = 0; i < texts.length; i++) {
      var dl = texts[i].getAttribute('data-line');
      var sName = (texts[i].getAttribute('data-station') || '').replace(/[\\n\\r]/g, '');
      var sLines = stationLineMap[sName];

      // 강조(경로 경유) 노선 소속 여부 (data-line 우선, 환승역은 역명 소속으로 재확인)
      var onHighlightLine = !!codeSet[dl];
      if (!onHighlightLine && sLines) {
        for (var lid in sLines) {
          if (lineIdSet[lid]) { onHighlightLine = true; break; }
        }
      }

      // 유지 이름 필터가 있으면 keepNameSet 에 있는 역만, 없으면(구 호출) 전체 유지
      var keep = onHighlightLine &&
          (hasKeepNameFilter ? !!keepNameSet[sName] : true);

      if (keep) {
        texts[i].classList.remove('dimmed');
      } else {
        texts[i].classList.add('dimmed');
      }
    }

    // 강조 노선에 속하는 역의 SVG 좌표 집합 (circle 매칭용)
    var highlightCoords = {};
    var highlightCoordsList = [];
    for (var si = 0; si < stations.length; si++) {
      var s = stations[si];
      if (lineIdSet[s.lineId]) {
        var px = parseFloat(s.svgX), py = parseFloat(s.svgY);
        highlightCoords[px + ',' + py] = true;
        highlightCoordsList.push([px, py]);
      }
    }

    // circle 요소 처리 (좌표 매칭, overlay 제외)
    var circles = container.querySelectorAll('circle:not([data-overlay])');
    for (var i = 0; i < circles.length; i++) {
      var c = circles[i];
      var coordKey = parseFloat(c.getAttribute('cx')) + ',' + parseFloat(c.getAttribute('cy'));
      if (highlightCoords[coordKey]) {
        c.classList.remove('dimmed');
      } else {
        c.classList.add('dimmed');
      }
    }

    // rect 요소 처리 (환승역 연결선, 확장 영역 매칭)
    // 여유값 8px: 환승역 circle 반지름(r=5) + 3px 마진
    var RECT_MATCH_MARGIN = 8;
    var rects = container.querySelectorAll('rect:not(#route-overlay-bg)');
    for (var i = 0; i < rects.length; i++) {
      var r = rects[i];
      var rx = parseFloat(r.getAttribute('x') || '0');
      var ry = parseFloat(r.getAttribute('y') || '0');
      var rw = parseFloat(r.getAttribute('width') || '0');
      var rh = parseFloat(r.getAttribute('height') || '0');
      var matched = false;
      for (var k = 0; k < highlightCoordsList.length; k++) {
        var sx = highlightCoordsList[k][0];
        var sy = highlightCoordsList[k][1];
        if (sx >= rx - RECT_MATCH_MARGIN && sx <= rx + rw + RECT_MATCH_MARGIN &&
            sy >= ry - RECT_MATCH_MARGIN && sy <= ry + rh + RECT_MATCH_MARGIN) {
          matched = true;
          break;
        }
      }
      if (matched) {
        r.classList.remove('dimmed');
      } else {
        r.classList.add('dimmed');
      }
    }
  };

  // 강조 해제, 모든 요소 원래 opacity로 복원
  window.clearLineHighlight = function() {
    var dimmed = document.querySelectorAll('.dimmed');
    for (var i = 0; i < dimmed.length; i++) {
      dimmed[i].classList.remove('dimmed');
    }
  };

  // ============================================================
  // 부드러운 카메라 이동
  // ============================================================
  var panAnimId = 0;

  // SVG 좌표(svgX, svgY)를 화면 중앙에 배치하도록 부드럽게 이동
  window.panTo = function(svgX, svgY, durationMs) {
    // `durationMs || 400` 은 0 을 falsy 로 삼켜 "즉시 이동(0ms)" 요청을
    // 400ms 애니메이션으로 바꿔버린다. `== null` 로 "인자 생략"(undefined/null)
    // 과 "값이 0" 을 구분한다.
    var dur = (durationMs == null) ? 400 : durationMs;
    var vw = window.innerWidth;
    var vh = window.innerHeight;

    var targetTx = vw / 2 - svgX * scale;
    var targetTy = vh / 2 - svgY * scale;

    // clamp 적용 (clampTranslation 과 동일 규칙: 콘텐츠가 뷰포트보다 작으면 중앙 정렬)
    targetTx = clampAxis(targetTx, vw, CANVAS_W * scale,
                         OVERSCROLL_PAD, OVERSCROLL_PAD);
    targetTy = clampAxis(targetTy, vh, CANVAS_H * scale,
                         OVERSCROLL_PAD_TOP, OVERSCROLL_PAD);

    // durationMs <= 0 이면 애니메이션 없이 즉시 이동. 진행 중인 팬이 있으면
    // panAnimId 를 올려 무효화해 늦게 도착하는 프레임이 스냅 위치를 덮어쓰지
    // 못하게 한다. (dur 로 나누는 진행도 계산의 0 division 도 회피)
    if (dur <= 0) {
      ++panAnimId;
      tx = targetTx;
      ty = targetTy;
      applyTransform();
      return;
    }

    var startTx = tx, startTy = ty;
    var startTime = performance.now();
    var animId = ++panAnimId;

    function easeInOut(t) {
      return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
    }

    function step(now) {
      if (animId !== panAnimId) return;
      var elapsed = now - startTime;
      var progress = Math.min(1, elapsed / dur);
      var ease = easeInOut(progress);

      tx = startTx + (targetTx - startTx) * ease;
      ty = startTy + (targetTy - startTy) * ease;
      applyTransform();

      if (progress < 1) {
        requestAnimationFrame(step);
      }
    }

    requestAnimationFrame(step);
  };

  // ============================================================
  // 실시간 열차 표시 (애니메이션)
  // ============================================================

  // [디버그용] 열차 아이콘의 녹색 디버그 정보 박스 표시 여부.
  // false 로 두면 buildDebugGroup/updateTrainDebugInfo 호출과 1초 setInterval
  // 갱신이 모두 스킵된다. 함수 정의 자체는 남겨두어 필요 시 true 로 복구 가능.
  var SHOW_TRAIN_DEBUG = false;

  // 행선지 레이블 박스의 최소 너비(px). 열차 아이콘(-18~+18, 36px)과 동일하게
  // 설정해 짧은 행선(예: "김포공항") 은 기존과 동일 모양으로 보이도록 한다.
  // ============================================================
  // 도착 말풍선 (2줄: "{행선}행" / "N초 후 도착")
  // ============================================================
  // [원칙 1 준수] 카운트다운 줄은 오직 startTrainAnimation.step() 이 계산하는
  // realRemaining 만을 입력으로 받는다. 이 파일 어디에도 별도의 카운트다운
  // 변수를 신설하지 않는다 — 기존 setInterval 의 `lastArrivalSeconds - elapsed`
  // 방식과 절대 혼용하지 않는다. (숫자 자체는 API 재조회로 늘어날 수 있다.
  // 뒤로 가지 않아야 하는 것은 아이콘의 위치이지 숫자가 아니다.)
  var BUBBLE_KO_CHAR_W = 9;      // 한글/CJK 전각 1자 근사 너비(px, font-size 9 기준)
  var BUBBLE_NARROW_CHAR_W = 4.5; // 숫자·공백·영문·괄호 등 반각 1자 근사 너비(px)
  var BUBBLE_PADDING = 8;       // 좌우 여백 합계(최장 문구도 배경 내 수용)
  var BUBBLE_MIN_WIDTH = 34;
  var BUBBLE_LINE_H = 14;      // 줄 1개 높이
  var BUBBLE_HEIGHT = BUBBLE_LINE_H * 2; // 2줄(행선/카운트다운)
  var BUBBLE_Y = -20 - BUBBLE_HEIGHT;    // 열차 아이콘(image y=-6.5) 위에 배치
  var BUBBLE_TAIL_H = 5;

  // ============================================================
  // 유령 열차 (중간 종착)
  // ============================================================
  // 탑승 구간을 완주하지 못하는 중간 종착 열차(Dart 의 `isGhost`)는 실제로 같은
  // 선로를 달리므로 지도에 남기되, 흐리게 그려 "탈 수 있는 열차"와 구분한다.
  // (지선으로 갈라지는 열차는 Dart 단계에서 아예 제외돼 여기 오지 않는다.)
  //
  // 반드시 **inline opacity 속성**으로만 다룬다. CSS 클래스로 처리하면 도착
  // 이펙트(playArrivalEffect)가 쓰는 inline 속성을 CSS 가 이겨서 페이드아웃이
  // 먹지 않는다 (SVG presentation attribute < CSS 규칙).
  // 0.4 — 실 열차(1.0)와 한눈에 구분되면서, 말풍선의 "{행선}행" 글씨는 읽을 수
  // 있는 선. 더 낮추면 왜 흐린지(= 중간 종착) 사용자가 알 수 없다.
  var GHOST_OPACITY = 0.4;

  function trainBaseOpacity(train) {
    return train && train.isGhost ? GHOST_OPACITY : 1;
  }

  // 열차 그룹의 기본 투명도를 현재 유령 여부에 맞춘다. refresh 로 행선지가
  // 바뀌면 유령 여부도 뒤집히므로 갱신 경로에서도 호출해야 한다.
  // 도착 이펙트가 곱셈 기준으로 쓰도록 trainState 에도 보관한다.
  function applyTrainGhostState(trainState, train) {
    var base = trainBaseOpacity(train);
    trainState.baseOpacity = base;
    if (trainState.element) {
      trainState.element.setAttribute('opacity', String(base));
    }
  }

  // 기준 시각(receivedAt = API recptnDt) 대비 남은시간.
  //
  // 경과시간에 0 하한을 둔다. 일부 노선(신분당선 등)은 recptnDt 를 실제보다 수 분
  // 앞선 시각으로 보내는데, 그대로 빼면 경과가 음수가 되어 남은시간이 **부풀어**
  // 오른다. 특히 arrivalSeconds=0("그 역에 있음" 상태)이 양수 카운트다운으로
  // 둔갑해, 이미 도착역에 있는 열차가 "N초 후 도착" 말풍선을 단 채 그 역에
  // 붙박이로 남는다.
  //
  // 같은 (baseArrival, receivedAt) 쌍 안에서는 시간이 지날수록 줄어들기만 한다.
  // 값 자체는 API 재조회로 **원본이 바뀐** 새 쌍이 오면 늘어날 수 있으며, 이는
  // 원칙 1 이 허용한다 (뒤로 가면 안 되는 것은 아이콘의 위치).
  // Dart 측에도 같은 0 하한이 있다: arrival_card.dart 의 `_liveSeconds`,
  // enrich_arrival_info.dart 의 elapsed 하한. 단 **기준쌍 stale 필터(원칙 1-a)는
  // 이 파일(지도 말풍선)에만 있다** — arrival_card 는 refresh 마다 `receivedAt`
  // 을 그대로 채택하므로 도착정보 화면에는 톱니파가 남아 있다(의도적 미적용:
  // ArrivalInfo 는 refresh 마다 새로 생성돼 열차별 기준쌍을 둘 자리가 없다).
  function remainingFromReceivedAt(baseArrival, receivedAtMs, nowMs) {
    var elapsed = Math.max(0, (nowMs - receivedAtMs) / 1000);
    return Math.max(0, (baseArrival || 0) - elapsed);
  }

  // [원칙 1-a] **표시용 기준쌍**(baseArrival/baseReceivedAt) 갱신.
  //
  // 갱신 규칙은 위치용 기준쌍(posBaseArrival/posBaseReceivedAt)과 동일하다 —
  // **API 원본 남은시간(arrivalSeconds)이 실제로 바뀐 refresh 에서만** 채택하고,
  // 값이 그대로면(= 같은 값이 2회 이상 반복 보고된 것) 이전 쌍을 유지해
  // **recptnDt 의 새 값도 보지 않는다.**
  //
  // 이유: 2호선 사당 정차 구간 등에서 API 가 barvlDt 를 고정한 채 recptnDt 만
  // 갱신해 반복 보고한다(2026-08-04 실측: barvlDt=150 이 1분 이상 고정). 매
  // refresh 마다 recptnDt 를 채택하면 경과시간이 리셋돼 말풍선 숫자가
  // "15초 감소 → 원위치" 톱니파를 그린다. 기준쌍을 고정하면 같은 원본값 안에서
  // 카운트다운이 매끄럽게 이어진다.
  //
  // 표시 숫자는 여전히 API 원본 기반이다 — 값을 깎는 clamp 가 아니라 "어느 쌍을
  // 새 측정치로 볼 것인가"의 문제이며, 원본이 바뀌면 늘어난 값도 그대로 채택한다.
  // 회귀 테스트: test/core/utils/train_forward_guard_test.dart
  function adoptDisplayBase(trainState, train, nowMs) {
    var raw = train.arrivalSeconds;
    if (trainState.baseArrival == null
        || trainState.lastDisplayRawArrival !== raw) {
      trainState.baseArrival = raw;
      trainState.baseReceivedAt = train.receivedAtEpochMs || nowMs;
    }
    trainState.lastDisplayRawArrival = raw;
  }

  // realRemaining(초) → 표시 문구.
  function formatArrivalBubbleText(remainingSeconds) {
    var sec = Math.ceil(remainingSeconds);
    // 30초 이하는 "곧 도착"으로 표시. 31초부터 "N초 후 도착".
    if (sec <= 30) return '곧 도착';
    if (sec < 60) return sec + '초 후 도착';
    var min = Math.floor(sec / 60);
    var rem = sec % 60;
    // 정확히 분 단위면 "N분 후 도착"으로 축약(예 120초 → "2분 후 도착").
    return rem === 0 ? (min + '분 후 도착') : (min + '분 ' + rem + '초 후 도착');
  }

  // 행선지 → 1줄("{destination}행"). destination 이 비면 빈 문자열.
  function formatDestinationLine(destination) {
    return destination ? (destination + '행') : '';
  }

  // 문자열의 근사 렌더링 너비를 글자 종류별로 추정한다.
  // CJK(한글 등, code point > 0x2E80)는 전각 폭, 그 외(숫자·공백·영문·괄호 등)는 반각 폭.
  function textWidthApprox(s) {
    s = s || '';
    var w = 0;
    for (var i = 0; i < s.length; i++) {
      w += (s.charCodeAt(i) > 0x2E80) ? BUBBLE_KO_CHAR_W : BUBBLE_NARROW_CHAR_W;
    }
    return w;
  }

  // 두 줄 중 더 긴 줄 기준으로 말풍선 너비를 계산한다.
  function computeBubbleWidth(line1, line2) {
    var w = Math.max(textWidthApprox(line1), textWidthApprox(line2));
    return Math.max(BUBBLE_MIN_WIDTH, w + BUBBLE_PADDING);
  }

  // 말풍선(둥근 사각형 배경 + 아래쪽 꼬리 + 2줄 텍스트) DOM 을 생성해 g 에
  // 부착한다. 배경/꼬리는 노선색(color)으로 채색하고 텍스트는 흰색 유지.
  // 1줄: "{destination}행", 2줄: 카운트다운("N초 후 도착" 등).
  function createArrivalBubble(g, destination, countdownText, color) {
    destination = destination || '';
    countdownText = countdownText || '';
    var destLine = formatDestinationLine(destination);

    var bubble = document.createElementNS(SVG_NS, 'g');
    bubble.setAttribute('class', 'train-arrival-bubble');

    var w = computeBubbleWidth(destLine, countdownText);
    var bg = document.createElementNS(SVG_NS, 'rect');
    bg.setAttribute('x', String(-w / 2));
    bg.setAttribute('y', String(BUBBLE_Y));
    bg.setAttribute('width', String(w));
    bg.setAttribute('height', String(BUBBLE_HEIGHT));
    bg.setAttribute('rx', '4');
    bg.setAttribute('fill', color || '#333');
    bg.setAttribute('opacity', '0.9');
    bubble.appendChild(bg);

    // 말풍선 꼬리: 배경 하단 중앙에서 아래로 향하는 작은 삼각형.
    var tailY0 = BUBBLE_Y + BUBBLE_HEIGHT;
    var tail = document.createElementNS(SVG_NS, 'polygon');
    tail.setAttribute('points',
      (-4) + ',' + tailY0 + ' ' +
      4 + ',' + tailY0 + ' ' +
      0 + ',' + (tailY0 + BUBBLE_TAIL_H));
    tail.setAttribute('fill', color || '#333');
    tail.setAttribute('opacity', '0.9');
    bubble.appendChild(tail);

    var destText = document.createElementNS(SVG_NS, 'text');
    destText.setAttribute('class', 'bubble-dest');
    destText.setAttribute('x', '0');
    destText.setAttribute('y', String(BUBBLE_Y + BUBBLE_LINE_H / 2 + 3.2));
    destText.setAttribute('text-anchor', 'middle');
    destText.setAttribute('font-size', '9');
    destText.setAttribute('font-weight', 'bold');
    destText.setAttribute('fill', '#fff');
    destText.setAttribute('font-family', 'sans-serif');
    destText.textContent = destLine;
    bubble.appendChild(destText);

    var countText = document.createElementNS(SVG_NS, 'text');
    countText.setAttribute('class', 'bubble-count');
    countText.setAttribute('x', '0');
    countText.setAttribute('y', String(BUBBLE_Y + BUBBLE_LINE_H + BUBBLE_LINE_H / 2 + 3.2));
    countText.setAttribute('text-anchor', 'middle');
    countText.setAttribute('font-size', '9');
    countText.setAttribute('font-weight', 'bold');
    countText.setAttribute('fill', '#fff');
    countText.setAttribute('font-family', 'sans-serif');
    countText.textContent = countdownText;
    bubble.appendChild(countText);

    g.appendChild(bubble);
    return { group: bubble, bg: bg, destText: destText, countText: countText };
  }

  // 말풍선 배경 너비를 현재 두 줄 텍스트 기준으로 재계산한다.
  function resizeArrivalBubble(trainGroup) {
    var bubble = trainGroup.querySelector('.train-arrival-bubble');
    if (!bubble) return;
    var destEl = bubble.querySelector('.bubble-dest');
    var countEl = bubble.querySelector('.bubble-count');
    var bg = bubble.querySelector('rect');
    if (!bg) return;
    var w = computeBubbleWidth(
      destEl ? destEl.textContent : '',
      countEl ? countEl.textContent : ''
    );
    bg.setAttribute('x', String(-w / 2));
    bg.setAttribute('width', String(w));
  }

  // 카운트다운 줄(.bubble-count)만 갱신한다 (원칙 1: realRemaining 표시 전용).
  function updateArrivalBubbleText(trainGroup, displayText) {
    var textEl = trainGroup.querySelector('.train-arrival-bubble .bubble-count');
    if (!textEl) return;
    textEl.textContent = displayText;
    resizeArrivalBubble(trainGroup);
  }

  // 행선지 줄(.bubble-dest)만 갱신한다 (refresh 시 행선 변경 반영).
  function updateArrivalBubbleDestination(trainGroup, destination) {
    var textEl = trainGroup.querySelector('.train-arrival-bubble .bubble-dest');
    if (!textEl) return;
    textEl.textContent = formatDestinationLine(destination);
    resizeArrivalBubble(trainGroup);
  }

  function createTrainIcon(train, color) {
    var g = document.createElementNS(SVG_NS, 'g');

    var img = document.createElementNS(SVG_NS, 'image');
    img.setAttribute('href', TRAIN_IMG);
    img.setAttribute('x', '-18');
    img.setAttribute('y', '-6.5');
    img.setAttribute('width', '36');
    img.setAttribute('height', '13');
    g.appendChild(img);

    // 급행 딱지: trainType이 '급행'이면 열차 아이콘 우측에 빨간 "급" 배지
    if (train.trainType === '급행') {
      var badgeBg = document.createElementNS(SVG_NS, 'rect');
      badgeBg.setAttribute('x', '18');
      badgeBg.setAttribute('y', '-6');
      badgeBg.setAttribute('width', '12');
      badgeBg.setAttribute('height', '12');
      badgeBg.setAttribute('rx', '2');
      badgeBg.setAttribute('fill', '#E53935');
      g.appendChild(badgeBg);

      var badgeText = document.createElementNS(SVG_NS, 'text');
      badgeText.setAttribute('x', '24');
      badgeText.setAttribute('y', '3');
      badgeText.setAttribute('text-anchor', 'middle');
      badgeText.setAttribute('font-size', '8.5');
      badgeText.setAttribute('font-weight', 'bold');
      badgeText.setAttribute('fill', '#fff');
      badgeText.setAttribute('font-family', 'sans-serif');
      badgeText.textContent = '급';
      g.appendChild(badgeText);
    }

    // [디버그용] 열차 위치 결정 요소 표시 (SHOW_TRAIN_DEBUG=false 면 생성 스킵)
    if (SHOW_TRAIN_DEBUG) {
      g.appendChild(buildDebugGroup(train));
    }

    // 도착 말풍선(2줄: 행선/카운트다운): 초기 표시는 arrivalSeconds 기반
    // (원칙 1의 realRemaining 과 동일 포맷 함수 사용). step() 이 시작되면
    // realRemaining 기준으로 카운트다운 줄만 갱신됨. 배경은 노선색(color).
    var initialBubbleText = formatArrivalBubbleText(train.arrivalSeconds || 0);
    createArrivalBubble(g, train.destination, initialBubbleText, color);

    // initialProgress 반영: 첫 세그먼트 내 보간 위치에 배치
    var startX = train.fromSvgX;
    var startY = train.fromSvgY;
    var path = train.pathToTarget;
    if (train.initialProgress > 0 && path && path.length >= 2) {
      var p = train.initialProgress;
      startX = path[0].x + (path[1].x - path[0].x) * p;
      startY = path[0].y + (path[1].y - path[0].y) * p;
    }

    // [래스터 기아 수정 v3] SVG `transform` 속성 대신 CSS `style.transform` 을
    // 쓴다 — 위 `#live-trains > g { will-change: transform }` 주석 참조.
    // viewBox(2416x1560)와 width/height 가 1:1 이므로 'px' 단위 translate 가
    // SVG 사용자 단위 기준 attribute-transform 과 동일한 결과를 낸다.
    g.style.transform = 'translate(' + startX + 'px,' + startY + 'px)';
    // 중간 종착 열차는 흐리게(유령). 갱신 경로는 applyTrainGhostState 가 담당.
    g.setAttribute('opacity', String(trainBaseOpacity(train)));
    return g;
  }

  // [디버그용] 열차 위치 결정 요소를 멀티라인 텍스트로 생성한다.
  function buildDebugGroup(train) {
    var dg = document.createElementNS(SVG_NS, 'g');
    dg.setAttribute('class', 'train-debug-info');

    var lines = [
      '#' + (train.trainNo || '?'),
      '방향: ' + (train.direction || '?'),
      '행선: ' + (train.destination || '?'),
      '현재역: ' + (train.currentStation || '?'),
      'code: ' + (train.arrivalCode != null ? train.arrivalCode : '?'),
      '상태: ' + (train.positionStatus || '?'),
      'prog: ' + (train.initialProgress != null ? train.initialProgress.toFixed(2) : '?'),
      '초: ' + (train.arrivalSeconds != null ? train.arrivalSeconds : '?'),
      'msg: ' + (train.message || '?'),
      '경유: ' + (train.pathToTarget ? train.pathToTarget.length : '0'),
      '구간: [' + (train.segmentDurations ? train.segmentDurations.join(',') : '') + ']',
    ];

    var bgW = 90;
    var bgH = lines.length * 9 + 4;
    var bg = document.createElementNS(SVG_NS, 'rect');
    bg.setAttribute('x', String(-bgW / 2));
    bg.setAttribute('y', '8');
    bg.setAttribute('width', String(bgW));
    bg.setAttribute('height', String(bgH));
    bg.setAttribute('rx', '2');
    bg.setAttribute('fill', 'rgba(0,0,0,0.75)');
    dg.appendChild(bg);

    for (var i = 0; i < lines.length; i++) {
      var t = document.createElementNS(SVG_NS, 'text');
      t.setAttribute('x', String(-bgW / 2 + 3));
      t.setAttribute('y', String(8 + 9 + i * 9));
      t.setAttribute('font-size', '6');
      t.setAttribute('fill', '#0f0');
      t.setAttribute('font-family', 'monospace');
      if (lines[i].indexOf('\uCD08: ') === 0) t.setAttribute('class', 'debug-seconds');
      t.textContent = lines[i];
      dg.appendChild(t);
    }

    return dg;
  }

  // [디버그용] 기존 열차 아이콘의 디버그 정보 텍스트를 갱신한다.
  // SHOW_TRAIN_DEBUG=false 면 갱신/생성 없이 즉시 반환 (기존 박스도 남기지 않음).
  function updateTrainDebugInfo(element, train) {
    if (!SHOW_TRAIN_DEBUG) return;
    var old = element.querySelector('.train-debug-info');
    if (old) old.remove();
    element.appendChild(buildDebugGroup(train));
  }

  // ============================================================
  // SVG 선로 스냅 시스템
  // ============================================================
  // 열차 애니메이션은 pathToTarget(역 좌표 배열)을 받아 각 역 쌍을 직선 보간한다.
  // SVG 선로가 꺾이는 구간(예: 분당선 강남구청↔선정릉)에서는 직선이 선로를 벗어나
  // 탈선해 보이므로, 페이지 로드 시 각 노선 path의 좌표를 파싱해두고
  // 열차 경로의 각 역 쌍을 실제 선로 위 좌표 시퀀스로 확장한다.
  // segmentDurations는 확장된 subseg의 거리 비율로 재분배한다.

  var pathSnapPolylines = {}; // data-line 코드 → [polyline, polyline, ...]
  var pathSnapReady = false;
  var SNAP_THRESHOLD_PX = 12; // 역 중심과 선로 간 허용 오차(px)

  function parseSvgPathD(d) {
    if (!d) return [];
    // 허용 문자(M, L, 숫자, 지수, 공백, 쉼표, 부호, 소수점) 외가 있으면 스냅 비대상.
    // H/V/C/S/Q/T/A/Z 등 미지원 명령이나 소문자 상대좌표(m/l 등)가 섞여 있으면
    // silent-fail 대신 빈 배열을 반환해 직선 fallback을 유도한다.
    if (/[^MLeE0-9.,\\s+\\-]/.test(d)) return [];
    var pts = [];
    var tokens = d.replace(/,/g, ' ').split(/\\s+/);
    var i = 0;
    while (i < tokens.length) {
      var tk = tokens[i];
      if (tk === 'M' || tk === 'L') {
        i++;
        while (i + 1 < tokens.length) {
          var x = parseFloat(tokens[i]);
          var y = parseFloat(tokens[i + 1]);
          if (isNaN(x) || isNaN(y)) break;
          pts.push({ x: x, y: y });
          i += 2;
        }
      } else {
        i++;
      }
    }
    return pts;
  }

  function buildPathSnapLookup() {
    if (pathSnapReady) return;
    var paths = document.querySelectorAll('path[data-line]');
    for (var i = 0; i < paths.length; i++) {
      var dl = paths[i].getAttribute('data-line');
      if (!dl) continue;
      // 흰색 이중선 테두리(예: 1-GA-1)는 본체와 동일 좌표이므로 제외.
      // 대소문자/축약형(#FFF, white)도 방어.
      var stroke = (paths[i].getAttribute('stroke') || '').toLowerCase();
      if (stroke === '#ffffff' || stroke === '#fff' || stroke === 'white') continue;
      var pts = parseSvgPathD(paths[i].getAttribute('d'));
      if (pts.length < 2) continue;
      if (!pathSnapPolylines[dl]) pathSnapPolylines[dl] = [];
      pathSnapPolylines[dl].push(pts);
    }
    pathSnapReady = true;
  }

  function projectOnPolyline(px, py, polyline) {
    var bestIdx = -1, bestT = 0, bestDist = Infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      var ax = polyline[i].x, ay = polyline[i].y;
      var bx = polyline[i + 1].x, by = polyline[i + 1].y;
      var dx = bx - ax, dy = by - ay;
      var lenSq = dx * dx + dy * dy;
      var t = lenSq > 0
        ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        : 0;
      var cx = ax + t * dx, cy = ay + t * dy;
      var d = Math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      if (d < bestDist) { bestDist = d; bestIdx = i; bestT = t; }
    }
    return { segIdx: bestIdx, t: bestT, dist: bestDist };
  }

  // 역 A(ax,ay) → 역 B(bx,by)를 lineId의 SVG 선로 위 좌표 시퀀스로 반환.
  // 후보 polyline들 중 투영 거리 합이 최소인 것을 선택하고, slice 길이가
  // 직선 거리의 3배를 넘으면 오매칭으로 간주해 탈락시킨다. 모두 탈락하면 null.
  function getSnappedSlice(ax, ay, bx, by, lineId) {
    if (!pathSnapReady) buildPathSnapLookup();
    var dataLines = lineIdToDataLine[lineId];
    if (!dataLines) return null;

    var straightDist = Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    var bestSlice = null;
    var bestScore = Infinity;

    for (var di = 0; di < dataLines.length; di++) {
      var polylines = pathSnapPolylines[dataLines[di]];
      if (!polylines) continue;
      for (var pi = 0; pi < polylines.length; pi++) {
        var poly = polylines[pi];
        var pa = projectOnPolyline(ax, ay, poly);
        if (pa.dist > SNAP_THRESHOLD_PX) continue;
        var pb = projectOnPolyline(bx, by, poly);
        if (pb.dist > SNAP_THRESHOLD_PX) continue;

        var candidate;
        if (pa.segIdx === pb.segIdx) {
          candidate = [{ x: ax, y: ay }, { x: bx, y: by }];
        } else {
          candidate = [{ x: ax, y: ay }];
          if (pa.segIdx < pb.segIdx) {
            for (var j = pa.segIdx + 1; j <= pb.segIdx; j++) {
              candidate.push({ x: poly[j].x, y: poly[j].y });
            }
          } else {
            for (var j = pa.segIdx; j >= pb.segIdx + 1; j--) {
              candidate.push({ x: poly[j].x, y: poly[j].y });
            }
          }
          candidate.push({ x: bx, y: by });
        }

        // Sanity: slice 총 길이가 직선거리의 3배를 넘으면 분기/지선 오매칭으로 탈락
        var sliceLen = 0;
        for (var k = 0; k < candidate.length - 1; k++) {
          var sdx = candidate[k + 1].x - candidate[k].x;
          var sdy = candidate[k + 1].y - candidate[k].y;
          sliceLen += Math.sqrt(sdx * sdx + sdy * sdy);
        }
        if (straightDist > 0 && sliceLen > straightDist * 3) continue;

        var score = pa.dist + pb.dist;
        if (score < bestScore) {
          bestScore = score;
          bestSlice = candidate;
        }
      }
    }
    return bestSlice;
  }

  // pathToTarget을 SVG 선로 좌표 시퀀스로 확장. segmentDurations는 subseg 거리 비율로 분배.
  // `stationIndices`: 원본 path 의 각 역이 newPath 에서 어느 index 에 있는지 매핑.
  // 예: 원본 [A,B,C] 가 확장 후 [A,c1,c2,B,c3,C] 면 stationIndices=[0,3,5].
  // 3-way 클램프가 "원래 역" 기준으로 범위 판정할 수 있도록 추가.
  function expandPathWithSnap(path, segDurations, lineId) {
    if (!path || path.length < 2 || !lineId) {
      var stIdx = [];
      var len = path ? path.length : 0;
      for (var k = 0; k < len; k++) stIdx.push(k);
      return {
        path: path ? path.slice() : [],
        durations: segDurations ? segDurations.slice() : [],
        stationIndices: stIdx
      };
    }
    var newPath = [{ x: path[0].x, y: path[0].y }];
    var newDurations = [];
    var stationIndices = [0];
    for (var i = 0; i < path.length - 1; i++) {
      var a = path[i], b = path[i + 1];
      var slice = getSnappedSlice(a.x, a.y, b.x, b.y, lineId);
      if (!slice) slice = [a, b];
      var origDur = (segDurations && segDurations[i] != null) ? segDurations[i] : 0;

      var subDists = [];
      var totalDist = 0;
      for (var j = 0; j < slice.length - 1; j++) {
        var dx = slice[j + 1].x - slice[j].x;
        var dy = slice[j + 1].y - slice[j].y;
        var d = Math.sqrt(dx * dx + dy * dy);
        subDists.push(d);
        totalDist += d;
      }
      for (var j = 1; j < slice.length; j++) {
        newPath.push({ x: slice[j].x, y: slice[j].y });
      }
      if (totalDist > 0) {
        for (var j = 0; j < subDists.length; j++) {
          newDurations.push(origDur * subDists[j] / totalDist);
        }
      } else if (slice.length > 1) {
        var n = slice.length - 1;
        for (var j = 0; j < n; j++) newDurations.push(origDur / n);
      }
      // slice 끝 = 원본 path[i+1] 의 확장 path 상 위치
      stationIndices.push(newPath.length - 1);
    }
    return { path: newPath, durations: newDurations, stationIndices: stationIndices };
  }

  // [원칙 2] 매 frame 남은시간 역산으로 위치 결정. dwell=0 전제.
  // - remaining 이 세그먼트 i 안에서 남은 시간이면 progress=(s[i]-t)/s[i]
  // - 모든 세그먼트 다 소진하고 t>0 남으면 outOfPath (경로 시작점보다 더 뒤)
  function estimateTrainPosition(remaining, segTravel) {
    if (!segTravel || segTravel.length === 0) {
      return { outOfPath: false, segmentIndex: 0, progress: 0 };
    }
    if (remaining <= 0) {
      return {
        outOfPath: false,
        segmentIndex: segTravel.length - 1,
        progress: 1
      };
    }
    var t = remaining;
    for (var i = segTravel.length - 1; i >= 0; i--) {
      if (t <= segTravel[i]) {
        return {
          outOfPath: false,
          segmentIndex: i,
          progress: (segTravel[i] - t) / segTravel[i]
        };
      }
      t -= segTravel[i];
    }
    return { outOfPath: true, segmentIndex: 0, progress: 0 };
  }

  function startTrainAnimation(trainState, trainData) {
    // SVG 선로 스냅: pathToTarget을 실제 선로 위 좌표 시퀀스로 확장 (꺾임 구간 탈선 방지)
    var _snap = expandPathWithSnap(
      trainData.pathToTarget,
      trainData.segmentDurations,
      trainData.lineId
    );
    var path = _snap.path;
    if (!path || path.length < 2) {
      if (path && path.length === 1) {
        // 단일 점 path = "현재역 == 출발역" 케이스 (예: arvlMsg2='진입'/'도착').
        //
        // [원칙 1] 이 분기는 rAF 를 타지 않으므로 전진 상태를 직접 다뤄야 하는데,
        // **실제 도착(arrivalSeconds<=0)일 때만** 최전진(distToEnd=0)으로 고정한다.
        // 양수인데도 고정하면 API 가 '진입'을 한 번만 오보고해도 minDistToEnd=0 이
        // 박혀, 다음 refresh 에 정상 다구간 경로가 와도(끝점이 같아 pathEndKey
        // 리셋도 안 탄다) 가드가 모든 target 을 기각해 열차가 목표역에 **영구
        // 고정**된다. 아이콘을 그대로 두면 후퇴도 없고 영구 고정도 없다.
        var singlePointArrived = (trainData.arrivalSeconds || 0) <= 0;
        if (singlePointArrived) {
          // [래스터 기아 수정 v3] style.transform 사용 — createTrainIcon 주석 참조.
          trainState.element.style.transform =
            'translate(' + path[0].x + 'px,' + path[0].y + 'px)';
          trainState.currentPos = { x: path[0].x, y: path[0].y };
          trainState.pathEndKey =
            Math.round(path[0].x) + ',' + Math.round(path[0].y);
          trainState.minDistToEnd = 0;
          // posBase 쌍과 lastRawArrival 은 항상 같은 값에서 유도돼야 한다
          // (어긋나면 다음 refresh 가 stale 로 오판해 posRemaining=0 을 물려받는다).
          trainState.posBaseArrival = 0;
          trainState.posBaseReceivedAt = Date.now();
          trainState.lastRawArrival = 0;
          trainState.catchingUp = false;
        }
        // 양수면 아직 도착 전이므로 이펙트 없이 그 자리에 머물러 표시한다
        // (그대로 사라지면 사용자가 '열차 누락'으로 오인 — 5호선 양평/영등포 등
        // 짧은 잔여시간 train 이 화면에서 사라지던 회귀를 차단). 신규 열차는
        // createTrainIcon 이 이미 fromSvgX/Y(= 이 단일 점)에 그려 뒀다.
        //
        // rAF 루프(step)를 타지 않는 경로이므로 말풍선을 1회만 표시한다.
        // arrivalSeconds<=0 이면 formatArrivalBubbleText 가 "곧 도착"을 반환.
        // 2줄(행선/카운트다운) 모두 세팅 — refresh 로 재호출될 수 있으므로
        // 행선 줄도 매번 갱신한다.
        var singlePointSec = Math.ceil(trainData.arrivalSeconds || 0);
        updateArrivalBubbleDestination(trainState.element, trainData.destination);
        updateArrivalBubbleText(trainState.element,
          formatArrivalBubbleText(trainData.arrivalSeconds || 0));
        trainState.lastShownSec = singlePointSec;
        if (singlePointArrived) {
          playArrivalEffect(trainState, trainData.trainNo);
        }
      }
      return;
    }

    var segDurations = _snap.durations;
    if (!segDurations || segDurations.length !== path.length - 1) {
      // 데이터 불일치 — 아이콘을 **움직이지 않고** 그대로 둔다 (이펙트 없이 return).
      // [원칙 1] 과거엔 path[0] 으로 고정했으나 path[0] 은 경로의 맨 뒤(시작점)라
      // 전진해 있던 열차가 뒤로 순간이동했다. 뒤로 보내느니 그 자리에 두는 것이
      // 원칙에 맞다. 신규 열차라면 createTrainIcon 이 이미 초기 좌표를 세팅해 뒀다.
      return;
    }

    // [원칙 1-a] 위치 기준쌍의 입력은 **표시 기준쌍**(showTrains 의
    // adoptDisplayBase 가 이미 골라 둔 쌍)이다. trainData 원본을 쓰면 표시는
    // 낡은 recptnDt 를, 위치는 새 recptnDt 를 물어 아이콘이 카운트다운보다
    // 뒤처진다 — 말풍선이 "곧 도착"인데 열차는 아직 오는 중인 그림이 된다.
    // (표시 쌍은 stale 반복 보고에서 고정되므로 두 도메인이 같은 시각에 0 이 된다.)
    var receivedAt = (trainState.baseReceivedAt != null)
      ? trainState.baseReceivedAt
      : ((trainData.receivedAtEpochMs != null)
          ? trainData.receivedAtEpochMs : Date.now());
    var baseArrival = (trainState.baseArrival != null)
      ? trainState.baseArrival : (trainData.arrivalSeconds || 0);

    // [원칙 1] 단조 전진 가드 준비 — "경로 끝까지 남은 거리(px)".
    //
    // path 의 앞부분은 refresh 마다 늘거나(expandPathBackward) 줄지만(역 통과),
    // 끝점은 목표역으로 고정이다. 따라서 refresh 사이에 비교 가능한 유일한
    // 전진 척도는 **끝에서부터 잰 거리**다. 이 값이 이전 최소값보다 커지는
    // target(= 뒤로 가는 target)은 채택하지 않고 최전진 지점에 붙잡아 둔다.
    //
    // 누적 길이 테이블은 refresh 당 1회만 만들면 되므로 step() 밖에서 계산한다.
    var cumLen = [0];
    for (var ci = 1; ci < path.length; ci++) {
      var cdx = path[ci].x - path[ci - 1].x;
      var cdy = path[ci].y - path[ci - 1].y;
      cumLen.push(cumLen[ci - 1] + Math.sqrt(cdx * cdx + cdy * cdy));
    }
    var pathTotalLen = cumLen[cumLen.length - 1];

    // 끝점(목표역) 좌표가 바뀌면 다른 경로 = 전진 기억이 무의미하므로 리셋한다.
    // (경로 스코프 변경 시 열차는 대부분 제거되지만, 같은 trainNo 가 살아남는
    //  경우를 대비한 방어. 소수점 흔들림은 반올림으로 흡수.)
    var _endPt = path[path.length - 1];
    var pathEndKey = Math.round(_endPt.x) + ',' + Math.round(_endPt.y);
    if (trainState.pathEndKey !== pathEndKey) {
      trainState.pathEndKey = pathEndKey;
      trainState.minDistToEnd = null;
      trainState.posBaseArrival = null;
      trainState.posBaseReceivedAt = null;
      trainState.lastRawArrival = null;
    }

    // [원칙 1] **위치 역산용 기준쌍은 표시용과 따로 둔다.**
    //
    // 갱신 규칙: 직전 응답의 원본 남은시간(lastRawArrival)을 기억해 두고,
    // **API 원본 값이 실제로 바뀌었을 때만** 기준쌍을 새 값으로 보정한다.
    //   - 값이 그대로면(= recptnDt 만 갱신된 stale 반복 보고. 신분당선 등
    //     arvlMsg2 라운딩) 이전 기준쌍을 유지한다. 여기서 갱신해버리면 남은시간이
    //     매 cycle 원복해 **열차가 무기한 정지**한다.
    //   - 값이 바뀌었으면 새 측정치이므로 그대로 채택한다. 그 결과 목표 위치가
    //     뒤로 가더라도 아이콘은 아래 minDistToEnd 백스톱이 붙잡으므로 뒤로 가지
    //     않는다 (뒤로 가는 대신 멈춰 기다렸다가 재개).
    //
    // 입력(baseArrival/receivedAt)이 이미 표시 기준쌍이므로 이 층은 사실상
    // "표시 쌍이 바뀌었을 때만 위치 쌍도 바꾼다" 와 동치다. 남겨 두는 이유는
    // pathEndKey 리셋 뒤 재채택 경로와 방어선을 유지하기 위함이다.
    // 회귀 테스트: test/core/utils/train_forward_guard_test.dart
    if (trainState.posBaseArrival == null
        || trainState.lastRawArrival !== baseArrival) {
      trainState.posBaseArrival = baseArrival;
      trainState.posBaseReceivedAt = receivedAt;
    }
    trainState.lastRawArrival = baseArrival;

    // 경로 시작점부터 len(px) 떨어진 지점의 좌표.
    function pointAtLength(len) {
      if (!(len > 0)) return { x: path[0].x, y: path[0].y };
      if (len >= pathTotalLen) return { x: _endPt.x, y: _endPt.y };
      for (var pi = 1; pi < cumLen.length; pi++) {
        if (len <= cumLen[pi]) {
          var segLen = cumLen[pi] - cumLen[pi - 1];
          var r = (segLen > 0) ? (len - cumLen[pi - 1]) / segLen : 0;
          return {
            x: path[pi - 1].x + (path[pi].x - path[pi - 1].x) * r,
            y: path[pi - 1].y + (path[pi].y - path[pi - 1].y) * r
          };
        }
      }
      return { x: _endPt.x, y: _endPt.y };
    }

    // [원칙 3] 역 index → 확장 path 상 index 매핑.
    // `currentStationIndex` 는 원본 pathToTarget 기준 "현재역(arvlMsg3)" 위치.
    // SVG 곡선 스냅으로 path 가 세분화됐을 수 있으니 stationIndices 를 경유해
    // 확장 후 newPath 에서의 "현재역"/"다음역" 위치로 변환한다.
    var stationIndices = _snap.stationIndices || [];
    var origCurIdx = trainData.currentStationIndex || 0;
    if (origCurIdx < 0) origCurIdx = 0;
    if (stationIndices.length > 0 && origCurIdx > stationIndices.length - 2) {
      origCurIdx = Math.max(0, stationIndices.length - 2);
    }
    var curIdx = (stationIndices.length > origCurIdx)
      ? stationIndices[origCurIdx] : origCurIdx;
    var nextIdx = (stationIndices.length > origCurIdx + 1)
      ? stationIndices[origCurIdx + 1] : path.length - 1;

    // [원칙 4] 점프 방지 — target 을 지수 감쇠로 catch-up.
    // refresh 로 target 이 갑자기 이동해도 currentPos 는 부드럽게 따라잡는다.
    // frame rate 에 독립적이도록 실제 경과 ms 기반 반감기로 수렴.
    //
    // 거리 기반 dynamic 반감기:
    //   - 작은 흔들림 (dist <= 30px): 3000ms 반감기 — 정상 catch-up.
    //     API 지터/라운딩 노이즈 흡수, 동일 cycle 내 forward animation.
    //   - 큰 점프 (dist > 30px): 500ms 반감기 — 빠르게 수렴.
    //     역 전환·path 축소 등으로 stale currentPos 가 새 target 에서 멀리
    //     떨어진 상황에서, 시각적으로 ~1.5s 안에 정착해 "탈선" 인상 방지.
    //   거리가 줄어들면서 자동으로 짧은 반감기 → 긴 반감기로 전환됨.
    //
    // 임계치 미만 즉시 클램프 정책은 시각적 점프를 유발하므로 사용 안 함.
    // 충분히 가까워지면(< SNAP_PX) target 으로 스냅 (마지막 0.5px 잔여 정리).
    var SNAP_PX = 0.5;
    var HALF_LIFE_FAR_MS = 500;   // dist > 30px
    var HALF_LIFE_NEAR_MS = 3000; // dist <= 30px
    var FAST_DIST_THRESHOLD = 30;

    // refresh 시 매번 step 재시작되므로 lastFrameMs 를 리셋하여 첫 frame 에서
    // 거대한 deltaMs 로 순간 수렴해버리는 현상을 방지.
    trainState.lastFrameMs = null;

    function step() {
      // realRemaining = arrivalSeconds - (now - recptnDt)
      // (미래 recptnDt 방어를 위해 경과시간 0 하한 — remainingFromReceivedAt 주석 참조)
      //
      // [원칙 1-a] 입력은 showTrains 에서 adoptDisplayBase 로 고른 **표시용
      // 기준쌍**이다. trainData 원본을 직접 쓰면 stale 반복 보고 때 recptnDt 만
      // 갱신돼 카운트다운이 매 refresh 원복하는 톱니파가 된다.
      var realRemaining = remainingFromReceivedAt(
        trainState.baseArrival, trainState.baseReceivedAt, Date.now());

      // 도착 말풍선: realRemaining 을 API 원본 그대로 정수화해 표시(원칙 1 —
      // 숫자는 재조회로 늘어날 수 있다). 별도 카운트다운 변수를 두지 않고,
      // 정수 초가 바뀔 때만 DOM 을 갱신해 매 frame(~60fps) textContent 쓰기를 피한다.
      // [P1, 2026-08 리뷰] 팬/핀치 제스처 진행 중엔 이 DOM 쓰기(및 뒤따르는
      // resizeArrivalBubble 의 rect 폭 재계산)를 미룬다. realRemaining 계산
      // 자체(원칙 1-a)는 그대로 매 프레임 수행하고 lastShownSec 갱신만 보류하므로,
      // 제스처가 끝나면 바로 다음 rAF 프레임에서 값이 달라진 것으로 감지돼
      // 스스로 flush 된다(폰트 보정과 달리 별도 flush 호출이 불필요 — 이 루프
      // 자체가 제스처 중에도 계속 돈다). 표시가 최대 한 제스처 길이만큼
      // 늦어질 뿐 값이 틀리거나 멈추지 않는다.
      var shownSec = Math.ceil(realRemaining);
      if (!gestureActive && trainState.lastShownSec !== shownSec) {
        trainState.lastShownSec = shownSec;
        updateArrivalBubbleText(trainState.element,
          formatArrivalBubbleText(realRemaining));
      }

      // [원칙 1] 위치 역산 입력은 위에서 고른 **위치용 기준쌍**으로 계산한다.
      // (말풍선 숫자는 바로 위에서 API 원본 그대로 이미 표시했다.)
      var posRemaining = remainingFromReceivedAt(
        trainState.posBaseArrival, trainState.posBaseReceivedAt, Date.now());

      // [원칙 2] 역산 (입력은 위치용 단조 감소 값)
      var res = estimateTrainPosition(posRemaining, segDurations);

      // [원칙 3] 3-way 클램프 (확장 path 상 "역" index 기준).
      // 현재역-다음역 사이 서브세그먼트(curIdx..nextIdx-1) 에서는 정상 보간,
      // 그 외 범위 세그먼트는 현재역/다음역 좌표에 고정.
      var target;
      var targetLen; // 경로 시작점부터 target 까지의 거리(px)
      if (res.outOfPath || res.segmentIndex < curIdx) {
        target = path[curIdx];
        targetLen = cumLen[curIdx];
      } else if (res.segmentIndex >= nextIdx) {
        target = path[nextIdx];
        targetLen = cumLen[nextIdx];
      } else {
        var p0 = path[res.segmentIndex];
        var p1 = path[res.segmentIndex + 1];
        target = {
          x: p0.x + (p1.x - p0.x) * res.progress,
          y: p0.y + (p1.y - p0.y) * res.progress
        };
        targetLen = cumLen[res.segmentIndex] +
          (cumLen[res.segmentIndex + 1] - cumLen[res.segmentIndex]) * res.progress;
      }

      // [원칙 1] 단조 전진 가드 — 열차는 절대 뒤로 가지 않는다.
      // API 재조회로 남은시간이 늘어나거나(숫자 역행은 허용) 현재역 정보가
      // 뒤로 흔들려 target 이 후퇴하면, 그 target 을 버리고 지금까지의
      // 최전진 지점(minDistToEnd)에 붙잡아 둔다. 남은시간이 다시 줄어들어
      // target 이 최전진 지점을 넘어서면 그때부터 다시 전진한다.
      // (posRemaining 단조 감소로 대부분의 후퇴는 이미 차단된다. 이 가드는
      //  현재역 후퇴·경로 재스냅처럼 시간과 무관한 후퇴까지 막는 backstop.)
      var distToEnd = pathTotalLen - targetLen;
      if (!isFinite(distToEnd)) {
        // 퇴화 데이터(segDurations 에 0 → progress=NaN)로 NaN 이 흘러들면
        // 비교가 항상 false 가 되어 기억이 NaN 으로 오염되고 가드가 조용히 꺼진다.
        // 기억은 건드리지 않고 최전진 지점만 유지한다.
        if (trainState.minDistToEnd != null) {
          target = pointAtLength(pathTotalLen - trainState.minDistToEnd);
        }
      } else if (trainState.minDistToEnd != null && distToEnd > trainState.minDistToEnd) {
        target = pointAtLength(pathTotalLen - trainState.minDistToEnd);
      } else {
        trainState.minDistToEnd = distToEnd;
      }

      // [원칙 4] currentPos → target 지수 감쇠 보간.
      // 첫 frame 에는 target 으로 즉시 초기화(점프 없음).
      if (!trainState.currentPos) {
        trainState.currentPos = { x: target.x, y: target.y };
      }
      var nowPerf = (typeof performance !== 'undefined' && performance.now)
        ? performance.now() : Date.now();
      var deltaMs = (trainState.lastFrameMs != null)
        ? Math.min(nowPerf - trainState.lastFrameMs, 100) : 16.67;
      trainState.lastFrameMs = nowPerf;

      var cp = trainState.currentPos;
      var dx = target.x - cp.x;
      var dy = target.y - cp.y;
      var dist = Math.sqrt(dx * dx + dy * dy);

      // 항상 지수 감쇠 적용 — 작은 차이도 즉시 클램프하지 않아 점프를 차단.
      if (dist < SNAP_PX) {
        cp.x = target.x;
        cp.y = target.y;
        trainState.catchingUp = false;
      } else {
        // dist 가 SNAP_PX 이상이면 catch-up 진행 중으로 표시 (도착 가드용).
        trainState.catchingUp = true;
        // [원칙 4 dynamic] 거리 클수록 짧은 반감기로 빨리 수렴.
        var halfLife = (dist > FAST_DIST_THRESHOLD)
          ? HALF_LIFE_FAR_MS : HALF_LIFE_NEAR_MS;
        var factor = Math.pow(0.5, deltaMs / halfLife);
        cp.x = target.x + (cp.x - target.x) * factor;
        cp.y = target.y + (cp.y - target.y) * factor;
        if (Math.abs(target.x - cp.x) < SNAP_PX &&
            Math.abs(target.y - cp.y) < SNAP_PX) {
          cp.x = target.x;
          cp.y = target.y;
          trainState.catchingUp = false;
        }
      }
      var pos = cp;

      // [래스터 부하 절감] 좌표가 직전 프레임과 동일하면 DOM 쓰기를 생략한다.
      // 3-way 클램프(원칙 3)나 단조 전진 backstop(원칙 1)이 target 을 같은
      // 지점에 붙잡아 두는 동안(예: 정차 중 표시 기준쌍이 stale 반복 보고로
      // 고정돼 있을 때) 매 프레임 동일한 좌표를 다시 쓰면 #train-layer 를
      // 불필요하게 계속 무효화한다. 위치 계산(4원칙)은 그대로 매 프레임
      // 수행하고, 최종 DOM 반영만 "실제로 달라졌을 때"로 제한한다 — 시각적
      // 결과는 동일하다.
      //
      // [래스터 기아 수정 v3] SVG `transform` 속성 대신 CSS `style.transform`
      // 을 쓴다. 이 step() 은 팬 제스처와 무관하게 매 rAF 계속 도는데(원칙 2·4),
      // attribute 기반 transform 은 #live-trains > g 가 승격 레이어라도 매번
      // Blink 의 "SVG attribute 변경" 무효화 경로를 타 스타일 재계산을 유발한다.
      // style.transform 은 이미 승격된 레이어의 컴포지터 전용 갱신 경로를 타므로
      // 팬 중 map-container/text-layer-wrap/train-layer-wrap 재배치와 경쟁하지
      // 않는다(§10_map-math-engineer_pan-flicker-report.md 참조).
      if (trainState.lastRenderedX !== pos.x || trainState.lastRenderedY !== pos.y) {
        trainState.element.style.transform =
          'translate(' + pos.x + 'px,' + pos.y + 'px)';
        trainState.lastRenderedX = pos.x;
        trainState.lastRenderedY = pos.y;
      }

      // 도착 이펙트는 catch-up 이 끝난 뒤에 발동 (달리다 중간에 사라지는 현상 방지).
      //
      // [원칙 1-a] 발동 기준은 **표시 숫자(realRemaining)** 다. 기준쌍이 고정된
      // 동안 카운트다운이 0 까지 내려가면 열차도 그 시각에 도착해야 한다 —
      // 말풍선이 "곧 도착"인데 아이콘만 남아 있으면 안 된다. 매 refresh 갱신되는
      // API 원본으로 발동을 막는 게이트를 두면 이 동기화가 깨지므로 두지 않는다.
      //
      // 실제 도착이 아니었을 때의 복구는 `arrivedTrains` 가 담당한다 — 도착 시점의
      // 원본값을 기억해 두고, API 가 **다른 값**을 보고하면 아직 달리는 열차로
      // 보아 다시 그린다(showTrains 참조).
      //
      // 단 **위치 일관성 조건**은 함께 본다: 원칙 3 클램프가 아이콘을 중간역
      // (`nextIdx`)에 붙잡고 있는 동안 숫자만 0 이 되면, 열차가 목표역이 아닌
      // 엉뚱한 역에서 사라진다. 이는 API 원본으로 발동을 막는 게이트가 아니라
      // "아이콘이 목표역까지 왔는가" 를 확인하는 것이라 위 동기화를 깨지 않는다
      // (정상 케이스에서는 항상 참). 거짓이면 사라지는 대신 "곧 도착" 말풍선을
      // 단 채 대기한다.
      var atFinalLeg = (nextIdx === path.length - 1);
      if (realRemaining <= 0 && atFinalLeg && !trainState.catchingUp) {
        playArrivalEffect(trainState, trainData.trainNo);
        return;
      }
      trainState.animationId = requestAnimationFrame(step);
    }

    trainState.animationId = requestAnimationFrame(step);
  }

  function playArrivalEffect(trainState, trainNo) {
    // [H-1, 2026-08 리뷰] 아래 페이드 애니메이션(animate())은 매 프레임
    // el.style.transform = currentTransform + ' scale(...)' 로
    // transform 을 **직접** 덮어쓴다. step() 의 조건부 쓰기 최적화가 쓰는
    // lastRenderedX/Y 캐시는 이 우회 경로를 모른 채 페이드 시작 시점 값에
    // 머물러 있으므로, 페이드(0.6초) 도중 유령 도착이 부활해 startTrainAnimation
    // 이 재시작되면 stall 열차의 원칙 1 가드가 target 을 최전진 지점(직전
    // 렌더 좌표와 비트 동일)에 고정해 첫 step() 프레임부터 캐시가 "변화 없음"
    // 으로 오판, DOM 쓰기가 스킵돼 페이드 마지막 프레임의 확대(scale) 잔재가
    // 위치가 실제로 바뀔 때까지(수 분 가능) 고착된다. transform 을 우회
    // 기록하기 시작하는 이 지점에서 캐시를 무효화해, 부활 시 step() 의 첫
    // 프레임이 반드시 clean translate 를 다시 쓰도록 강제한다.
    trainState.lastRenderedX = null;
    trainState.lastRenderedY = null;

    // [원칙 1-a] 도착 시점의 **API 원본** 남은시간을 함께 기억한다.
    //
    // 표시 기준쌍이 고정된 동안 카운트다운은 0 까지 내려가므로, API 가 원본을
    // 그 초 수보다 오래 고정하면(장시간 정차·간격조정) 아직 전역에 있는 열차가
    // 도착 처리될 수 있다. 그때 `true` 만 박아 두면 API 가 계속 보고하는 한
    // 정리 루프(`!trainNoSet[id]`)가 지우지 못해 열차가 **영구히 사라진다.**
    // 원본값을 기억해 두면 showTrains 가 "다른 값이 왔다 = 아직 달리는 중"을
    // 구분해 다시 그릴 수 있다. 값이 그대로면 도착 상태를 유지한다.
    var rawAtArrival = (trainState.lastArrivalSeconds != null)
      ? trainState.lastArrivalSeconds : 0;
    // **정상 도착은 영구 확정 — 절대 살아나지 않는다(요구사항).**
    //
    // 두 도착을 도착 시점의 API 원본으로 구분한다.
    //  - 정상 도착: 원본이 벽시계와 함께 줄어들어 이 순간엔 이미 작다(refresh
    //    주기가 15초이므로 통상 그 이하). → { final: true }, 부활 대상 아님.
    //  - 유령 도착: stall 로 원본이 큰 값에 고정된 채 우리 추정만 0 에 닿았다.
    //    → 그 원본값을 기록해 두고, 값이 바뀌면(= 새 측정치) 아직 달리는
    //      열차이므로 되살린다.
    // 임계는 refresh 주기의 2배. 이 판정은 **도착 발동이 아니라 부활 가능성**만
    // 가르므로 "숫자 0 = 도착" 동기화(원칙 1-a)를 깨지 않는다.
    arrivedTrains[trainNo] = (rawAtArrival > GHOST_ARRIVAL_MIN_SEC)
      ? { raw: rawAtArrival }
      : { final: true };
    // 페이드아웃(0.6초) 진행 중임을 표시한다. 이 창에서 부활 판정이 통과하면
    // `animationId` 가 주행이 아니라 **페이드**의 rAF id 라, 조기 continue 분기가
    // 이를 살아있는 주행으로 오인해 페이드를 그대로 두면 열차가 소리 없이 사라진다.
    trainState.arrivalPlaying = true;
    var el = trainState.element;
    // [래스터 기아 수정 v3] 위치를 style.transform 으로 쓰므로 여기서도
    // style.transform 을 읽어야 마지막 translate 값을 얻는다(getAttribute는
    // 더 이상 갱신되지 않는 값을 반환한다).
    var currentTransform = el.style.transform || '';

    // 펄스 확대 + 페이드아웃 애니메이션 (0.6초)
    var duration = 600;
    var startTime = performance.now();

    function animate(now) {
      var elapsed = now - startTime;
      var progress = Math.min(elapsed / duration, 1.0);

      // easeOutCubic
      var eased = 1 - Math.pow(1 - progress, 3);

      var scale = 1 + eased;
      // 유령 열차는 이미 흐리므로 그 투명도에서부터 페이드아웃한다
      // (1 에서 시작하면 도착 순간 갑자기 진해진다).
      var base = (trainState.baseOpacity != null) ? trainState.baseOpacity : 1;
      var opacity = (1 - eased) * base;

      el.style.transform = currentTransform + ' scale(' + scale + ')';
      el.setAttribute('opacity', opacity);

      if (progress < 1.0) {
        trainState.animationId = requestAnimationFrame(animate);
      } else {
        trainState.animationId = null;
        if (el.parentNode) {
          el.parentNode.removeChild(el);
        }
        delete activeTrains[trainNo];
      }
    }

    trainState.animationId = requestAnimationFrame(animate);

    sendToFlutter({ action: 'trainArrived', trainNo: trainNo, destination: trainState.destination || '' });
  }

  function cancelTrainAnimation(trainState) {
    if (trainState.animationId) {
      cancelAnimationFrame(trainState.animationId);
      trainState.animationId = null;
    }
  }

  // 열차 아이콘·상태를 도착 이펙트 없이 즉시 정리한다.
  // (경로 스코프 변경 / silent 제거의 공통 경로)
  function removeTrainSilently(trainState, trainNo) {
    cancelTrainAnimation(trainState);
    if (trainState.element && trainState.element.parentNode) {
      trainState.element.parentNode.removeChild(trainState.element);
    }
    delete activeTrains[trainNo];
  }

  // 겹침 우선순위: 앞선 열차(남은시간이 적은 = 출발역에 더 가까운 열차)의
  // 아이콘·말풍선이 항상 위에 보이도록 #live-trains 의 자식 순서를 재배치한다.
  // SVG 는 문서 순서대로 페인트하므로 마지막 자식이 최상위다.
  //
  // 같은 스코프(노선+방향)의 열차만 표시되므로 "남은시간이 적다 = 물리적으로
  // 앞서 있다" 가 성립한다. 남은시간은 두 열차 모두 같은 속도로 줄어들어 상대
  // 순서가 refresh 사이에 뒤집히지 않으므로, 매 frame 이 아니라 showTrains
  // (API 갱신) 시점에만 정렬해도 충분하다.
  //
  // 한계: 정렬 기준은 **표시용 기준쌍**이다(원칙 1-a — adoptDisplayBase 가 고른 쌍).
  // 원칙 1 가드가 발동해 열차가 붙잡혀 있는 동안에는 "숫자 순서 ≠ 화면상 순서"
  // 가 될 수 있다. z-order 만의 문제라 위치 정확도에는 영향이 없다.
  function reorderTrainsByRemaining() {
    var nowMs = Date.now();
    var items = [];
    for (var id in activeTrains) {
      var st = activeTrains[id];
      if (!st.element || st.element.parentNode !== liveTrainsGroup) continue;
      // 기준값이 없는 열차는 Infinity 로 두어 가장 아래에 깔린다.
      var rem = (st.baseArrival != null && st.baseReceivedAt != null)
        ? remainingFromReceivedAt(st.baseArrival, st.baseReceivedAt, nowMs)
        : Infinity;
      items.push({ el: st.element, rem: rem });
    }
    if (items.length < 2) return;
    // 남은시간 내림차순 → 앞선 열차(작은 값)가 마지막에 붙어 최상위가 된다.
    items.sort(function(a, b) { return b.rem - a.rem; });

    // [래스터 부하 절감] 이미 원하는 순서와 같으면 DOM 이동을 생략한다.
    // appendChild 를 통한 재배치는 자식이 이동하지 않아도 #train-layer 의
    // 페인트 순서가 바뀐 것으로 취급돼 리페인트를 유발할 수 있다. 열차가
    // 1~2개뿐이거나 상대 순서가 이미 안정된(대부분의) refresh 에서는 실제로
    // 옮길 노드가 없으므로, 그 경우엔 DOM 에 손대지 않는다.
    var current = liveTrainsGroup.children;
    var alreadyOrdered = current.length === items.length;
    if (alreadyOrdered) {
      for (var ci = 0; ci < items.length; ci++) {
        if (current[ci] !== items[ci].el) { alreadyOrdered = false; break; }
      }
    }
    if (alreadyOrdered) return;

    for (var i = 0; i < items.length; i++) {
      // 이미 자식인 노드의 appendChild 는 복제가 아니라 "맨 뒤로 이동" 이다.
      liveTrainsGroup.appendChild(items[i].el);
    }
  }

  window.showTrains = function(trainsJson, routeScopeKey) {
    var trains = JSON.parse(trainsJson);
    // 이 payload 가 속한 활성 경로 스코프('{lineId}|down' 등). Flutter 가
    // activeRouteFilter 로부터 만들어 넘긴다. 스코프가 바뀌면 이전 스코프의
    // 열차는 "API 가 누락(jitter)" 이 아니라 "경로 변경으로 무효" 이므로
    // grace 없이 즉시 제거해야 한다(아래 toRemove 루프 (B) 참조).
    var scopeKey = (typeof routeScopeKey === 'string') ? routeScopeKey : '';
    var newTrainIds = {};

    for (var i = 0; i < trains.length; i++) {
      var t = trains[i];
      // [원칙 1-a] 도착 처리된 열차라도 API 가 **다른 원본값**을 보고하면
      // 아직 달리는 중이므로 도착 표시를 풀고 다시 그린다(유령 도착 복구).
      // 같은 값이면 stall 이 이어지는 것이 아니라 실제 도착 후의 잔여 보고이므로
      // 그대로 건너뛴다.
      var arrivedRec = arrivedTrains[t.trainNo];
      if (arrivedRec) {
        // 정상 도착은 영구 확정 — 이후 API 가 무엇을 보고하든 되살리지 않는다.
        // (목표역 진입 열차가 `barvlDt=10` 같은 **양수**로 다시 오는 것이 실제로
        //  관측된다 — 2026-08-04 방배 실측. 값 비교만으로는 막지 못한다.)
        if (arrivedRec.final) continue;
        // 유령 도착 후보: 원본이 그대로면 stall 이 이어지는 중이므로 계속 숨긴다.
        if (arrivedRec.raw === t.arrivalSeconds) continue;
        // 원본이 바뀌었다 = 새 측정치 = 아직 달리는 중 → 되살린다.
        delete arrivedTrains[t.trainNo];
      }
      newTrainIds[t.trainNo] = true;
      var color = lineColors[t.lineId] || '#999';

      if (activeTrains[t.trainNo]) {
        var existing = activeTrains[t.trainNo];
        var nowMs = Date.now();
        // 현재 스코프에서 다시 보고된 열차 → 스코프 갱신(경로 모드 전환 등으로
        // 같은 열차가 새 스코프에 그대로 포함되는 경우도 정상 처리).
        existing.scopeKey = scopeKey;

        // [원칙 1] 남은시간(숫자)은 API 원본을 그대로 쓴다 — 원본이 바뀌어
        // 늘어났다면 늘어난 대로 표시한다(값을 깎는 clamp 재도입 금지).
        // 다만 원본이 그대로인 반복 보고에서는 adoptDisplayBase 가 기준쌍을
        // 유지해 recptnDt 만의 갱신을 무시한다(원칙 1-a).
        // 열차가 뒤로 가지 않는 것은 startTrainAnimation 의 단조 전진
        // 가드(minDistToEnd)가 위치 레벨에서 보장한다.

        // 도착 임박 열차는 기존 애니메이션 유지 (15초 갱신에서 끊김 방지)
        // 단, 이미 도착역에 있는 열차(pathToTarget 1점)는 즉시 도착 처리.
        // `arrivalPlaying` 이면 animationId 가 페이드아웃의 것이라 "유지" 대상이
        // 아니다 — 아래 일반 경로로 내려보내 cancel 후 재시작시킨다.
        if (t.arrivalSeconds <= 2 && (t.initialProgress || 0) >= 0.7 && existing.animationId
            && !existing.arrivalPlaying
            && t.pathToTarget && t.pathToTarget.length >= 2) {
          existing.destination = t.destination || '';
          existing.lastArrivalSeconds = t.arrivalSeconds;
          existing.lastUpdateTime = nowMs;
          adoptDisplayBase(existing, t, nowMs);
          // 행선지는 말풍선의 .bubble-dest 줄(class 기반)로 갱신 —
          // 길이 변화에 맞춰 말풍선 너비도 재계산(짧아질 때도 재축소).
          updateArrivalBubbleDestination(existing.element, t.destination);
          applyTrainGhostState(existing, t);
          updateTrainDebugInfo(existing.element, t);
          // 여기서 existing.lastRawArrival(위치용 추적자)을 갱신하지 않는 것은
          // 의도적이다. 이 분기는 startTrainAnimation 을 부르지 않아 위치
          // 기준쌍도 그대로인데, lastRawArrival 만 앞서 갱신하면 다음 refresh 가
          // 같은 값을 stale 로 오판해 (낡은 쌍을 물고) 보정 기회를 놓친다.
          // 짝을 맞춰 함께 둔다.
          // 반면 표시용 추적자(lastDisplayRawArrival)는 바로 위 adoptDisplayBase
          // 가 기준쌍과 짝을 맞춰 갱신하므로 같은 오판이 생기지 않는다.
          continue;
        }
        // [jitter grace] train 이 다시 보고됨 → 누락 카운트 리셋.
        existing.missedCycles = 0;
        cancelTrainAnimation(existing);
        // 페이드아웃을 끊고 주행을 재시작하는 경로 — 도착 상태를 푼다.
        // (opacity 는 바로 아래 applyTrainGhostState 가 원복한다.)
        existing.arrivalPlaying = false;
        existing.destination = t.destination || '';
        existing.lastArrivalSeconds = t.arrivalSeconds;
        existing.lastUpdateTime = nowMs;
        adoptDisplayBase(existing, t, nowMs);
        updateArrivalBubbleDestination(existing.element, t.destination);
        applyTrainGhostState(existing, t);
        // [디버그용] 기존 열차의 디버그 정보 갱신
        updateTrainDebugInfo(existing.element, t);
        startTrainAnimation(existing, t);
      } else {
        var nowMs2 = Date.now();
        var g = createTrainIcon(t, color);
        liveTrainsGroup.appendChild(g);
        activeTrains[t.trainNo] = {
          element: g, animationId: null, destination: t.destination || '',
          lastArrivalSeconds: t.arrivalSeconds,
          lastUpdateTime: nowMs2,
          // 표시용 기준쌍. 이후 갱신은 adoptDisplayBase 가 원본 변화 시에만 수행.
          baseArrival: t.arrivalSeconds,
          baseReceivedAt: t.receivedAtEpochMs || nowMs2,
          lastDisplayRawArrival: t.arrivalSeconds,
          // 이 열차가 속한 활성 경로 스코프. 스코프가 바뀌면 즉시 제거된다.
          scopeKey: scopeKey,
          // 유령(중간 종착) 여부에 따른 기본 투명도. 도착 이펙트가 곱셈 기준으로 쓴다.
          baseOpacity: trainBaseOpacity(t)
        };
        startTrainAnimation(activeTrains[t.trainNo], t);
      }
    }

    var toRemove = [];
    for (var id in activeTrains) {
      if (!newTrainIds[id]) {
        toRemove.push(id);
      }
    }
    // [도착/필터변경/jitter 분리 가드]
    // toRemove 는 "API 응답에서 더 이상 보이지 않는 train". 세 가지 원인.
    //   (A) 진짜 도착: API 가 보고 안 함 → 도착 애니메이션 발동 ✓
    //   (B) routeFilter 변경: 다른 노선/방향 → scopeKey 불일치로 즉시 silent 제거
    //   (C) API jitter: Seoul 공공 API 가 same-cycle 에 train 을 일관성 없이 누락
    //       (다음 cycle 에 다시 보고됨). 즉시 제거 시 train 이 화면에서 증발 후
    //       재등장 → 사용자 인식 "탈선/증발". (5호선 영등포구청 이슈 원인)
    //
    // 처리:
    //   - ETA = lastArrivalSeconds - (now - lastUpdateTime)/1000
    //   - ETA > GRACE_S (예: 60s): 아직 도착 안 했고 jitter 일 가능성 높음 → 한 cycle
    //     grace. activeTrains 에 유지하고 다음 cycle 까지 기다림. 연속 누락 카운트 증가.
    //   - 누락 카운트 >= MAX_MISS (2): 진짜 사라진 것으로 판단해 제거.
    //   - ETA <= GRACE_S: 도착 임박 또는 도착 → 기존 처리 (도착 이펙트 / silent).
    var SILENT_REMOVE_THRESHOLD_S = 60;
    var JITTER_GRACE_S = 60;
    // 8 cycle ≈ 2분 grace. step() 이 자체적으로 ETA<=0 시 도착 처리하므로
    // 운행 종료 train 도 자연스럽게 정리됨. 짧게 잡으면 jitter 로 사라졌다 재등장
    // 패턴 발생 (5호선 영등포구청 케이스).
    var MAX_MISS_CYCLES = 8;
    for (var i = 0; i < toRemove.length; i++) {
      var id = toRemove[i];
      var trainState = activeTrains[id];

      // (B) 경로 스코프 변경 — 이 열차는 더 이상 활성 경로의 노선·방향이 아니다.
      // API jitter 와 무관하므로 grace 를 주지 않고 즉시 제거한다. 도착한 게
      // 아니므로 도착 펄스/trainArrived(스낵바)도 발동하지 않는다.
      // (도착역 변경으로 경로 노선이 바뀌었는데 이전 노선 열차가 흐려진 지도 위에
      //  최대 MAX_MISS_CYCLES 만큼 남아있던 문제 방지)
      if (scopeKey && trainState.scopeKey && trainState.scopeKey !== scopeKey) {
        removeTrainSilently(trainState, id);
        continue;
      }

      var last = trainState.lastArrivalSeconds;
      var lastUpdate = trainState.lastUpdateTime;
      var eta = (last != null && lastUpdate != null)
        ? Math.max(0, last - (Date.now() - lastUpdate) / 1000)
        : 0;

      // ETA 양수 + 누락 카운트 한도 미만 → grace (애니메이션 유지, 제거 보류).
      if (eta > JITTER_GRACE_S) {
        trainState.missedCycles = (trainState.missedCycles || 0) + 1;
        if (trainState.missedCycles < MAX_MISS_CYCLES) {
          // 다음 cycle 까지 활성 유지. cancel/remove 안 함.
          continue;
        }
      }

      cancelTrainAnimation(trainState);
      if (last != null && last > SILENT_REMOVE_THRESHOLD_S) {
        // silent 제거: 도착 펄스 / trainArrived 이벤트 발동 안 함
        removeTrainSilently(trainState, id);
        continue;
      }
      playArrivalEffect(trainState, id);
    }

    // API에서 더 이상 보고하지 않는 열차는 arrivedTrains에서도 제거
    // 단, 아직 도착 애니메이션이 진행 중인(activeTrains에 남아있는) 열차는 유지
    var trainNoSet = {};
    for (var i = 0; i < trains.length; i++) trainNoSet[trains[i].trainNo] = true;
    for (var id in arrivedTrains) {
      if (!trainNoSet[id] && !activeTrains[id]) delete arrivedTrains[id];
    }

    // 신규 추가·제거가 끝난 뒤 겹침 우선순위 재정렬 (앞선 열차가 위).
    reorderTrainsByRemaining();
  };

  window.clearTrains = function() {
    for (var id in activeTrains) {
      cancelTrainAnimation(activeTrains[id]);
    }
    activeTrains = {};
    arrivedTrains = {};
    liveTrainsGroup.replaceChildren();
  };

  // 1초마다 디버그 남은시간 카운트다운 (SHOW_TRAIN_DEBUG=false 면 즉시 스킵)
  setInterval(function() {
    if (!SHOW_TRAIN_DEBUG) return;
    var now = Date.now();
    for (var id in activeTrains) {
      var train = activeTrains[id];
      if (train.lastArrivalSeconds == null || train.lastUpdateTime == null) continue;
      var elapsed = Math.floor((now - train.lastUpdateTime) / 1000);
      var remaining = Math.max(0, train.lastArrivalSeconds - elapsed);
      var secEl = train.element.querySelector('.debug-seconds');
      if (secEl) secEl.textContent = '\uCD08: ' + remaining;
    }
  }, 1000);

  // ============================================================
  // 경로 선택 툴바
  // ============================================================

  // [래스터 기아 수정 v4, 2026-08-13] 이 함수는 팬 중 매 rAF(scheduleTransform
  // → applyTransform → updateRouteToolbarPosition)마다 호출된다. 이전에는
  // routeToolbar.style.left/top 을 직접 썼는데, left/top 은 레이아웃을
  // 유발하는 속성이라 팬 제스처 내내 이 툴바 하나 때문에 매 프레임 메인스레드
  // 레이아웃 패스가 강제됐다. #map-container/#text-layer-wrap/#train-layer-wrap
  // 는 이미 매 프레임 컴포지터 전용 CSS transform 으로 이동하는데, 이 툴바만
  // 유일하게 레이아웃 경로를 타고 있었다 — 팬 중 유일한 non-transform 프레임별
  // DOM 쓰기.
  //
  // v3(will-change + style.transform 전환 for #live-trains > g)가 최대
  // 줌아웃+팬+실시간 열차 조합에서 재측정해도 점멸을 없애지 못한 사실
  // (§10_map-math-engineer_pan-flicker-report.md §12, 교정된 하네스로 E1/E2
  // 재분석 시 각 3건의 점멸 이벤트 잔존 확인)과, 점멸 순간 SVG 밖의 HTML
  // 오버레이(경로 툴바, div)까지 함께 사라진다는 관측(§11_requirements-review-v3.md
  // §2-6/§3)은 "#train-layer 내부 attribute 쓰기"만으로는 설명되지 않았다.
  // 이 툴바는 SVG 밖 HTML 요소이면서도 팬 중 유일하게 레이아웃을 유발하는
  // 프레임별 쓰기였으므로, 같은 문서(WebView 렌더러)의 레이아웃/페인트를
  // 지연시켜 그 프레임에 새로 노출된 라벨/열차/툴바 타일이 함께 커밋에서
  // 빠지는 현상과 정합적이다. 아래처럼 transform(translate)로 바꿔 이
  // 프레임별 쓰기를 컴포지터 전용으로 만든다(툴바 CSS 의 top:0/left:0 고정
  // + will-change 참조).
  function updateRouteToolbarPosition() {
    if (!toolbarVisible) return;
    // toolbarSvgX/Y가 앵커(출발역 또는 사용자가 드래그한 위치의 SVG 좌표)를
    // 나타내므로 항상 맵 pan/zoom에 맞춰 화면 좌표로 재계산한다.
    // 결과: 툴바가 맵에 부착된 것처럼 카메라 이동과 함께 따라 움직임.
    var screenX = toolbarSvgX * scale + tx;
    var screenY = toolbarSvgY * scale + ty;

    // 배치 오프셋(toolbarDx/Dy)은 showRouteToolbar 의 스마트 배치 또는 사용자
    // 드래그가 정한 값. 앵커 화면좌표에 더해 툴바 좌상단을 구한다.
    var left = screenX + toolbarDx;
    var top = screenY + toolbarDy;

    // 앵커역이 화면 밖(특히 위쪽)으로 벗어나도 툴바가 잘리지 않도록 뷰포트
    // 안으로 클램프한다. 드래그 클램프와 동일한 8px 가장자리 마진 규칙.
    var maxLeft = Math.max(8, window.innerWidth - cachedTbW - 8);
    var maxTop = Math.max(8, window.innerHeight - cachedTbH - 8);
    left = Math.max(8, Math.min(maxLeft, left));
    top = Math.max(8, Math.min(maxTop, top));

    // CSS top/left(레이아웃 유발) 대신 transform(컴포지터 전용)으로 배치.
    // 툴바 CSS 의 top:0/left:0 이 고정 원점이고, 실제 화면 위치는 이
    // translate 값이 전부 결정한다.
    routeToolbar.style.transform = 'translate(' + left + 'px,' + top + 'px)';
  }

  // 툴바가 가리면 안 되는 요소들의 화면 좌표 사각형 목록. 겹침 점수 계산용.
  //  - 경로 오버레이: route-lines 의 polyline/line, route-markers 의 circle
  //  - 밝게 유지된 역 이름 라벨: text-layer 의 dimmed 아닌 라벨.
  //
  // 라벨 하이라이트 정책상 밝게 남는 라벨은 "경로 역 + 출발역 상류 역" 뿐이다.
  // 따라서 이 라벨들만 회피하면 출발역 상류 구간(= 열차가 들어오는 방향)이
  // 가려지지 않는다. 실시간 열차 위치를 조회할 필요 없이 정적 기하만으로
  // 해결되므로 열차 데이터에 의존하지 않는다.
  // text-layer-wrap 은 map-container 와 동일한 CSS transform(matrix(scale,...))을
  // 쓰므로(v6, §22.2 — 내부 <svg> 루트(text-layer) 자신은 transform 을 받지
  // 않는다) SVG 사용자 좌표 → 화면 좌표 환산 공식(scale/tx/ty)이 여전히 같다.
  function collectAvoidScreenRects() {
    var rects = [];
    function pushBBox(el) {
      // getBBox() 는 SVG 사용자 좌표 → scale/tx/ty 로 화면 좌표 환산.
      var b;
      try { b = el.getBBox(); } catch (_) { return; }
      if (!b || (b.width === 0 && b.height === 0)) return;
      rects.push({
        left: b.x * scale + tx,
        top: b.y * scale + ty,
        right: (b.x + b.width) * scale + tx,
        bottom: (b.y + b.height) * scale + ty
      });
    }
    var lines = routeLines.children;
    for (var i = 0; i < lines.length; i++) pushBBox(lines[i]);
    var marks = routeMarkers.children;
    for (var j = 0; j < marks.length; j++) pushBBox(marks[j]);
    var brightNames = {};
    var brightTexts = textLayer.querySelectorAll('text[data-line]:not(.dimmed)');
    for (var t = 0; t < brightTexts.length; t++) {
      pushBBox(brightTexts[t]);
      var bn = (brightTexts[t].getAttribute('data-station') || '')
        .replace(/[\\n\\r]/g, '');
      if (bn) brightNames[bn] = true;
    }

    // 출발역 상류 역 주변 여유 영역. "밝은 라벨 - 경로역"이 상류 역이며,
    // 이 구간에 접근 열차 아이콘·도착 말풍선이 그려지므로 반경을 예약한다.
    for (var s = 0; s < stations.length; s++) {
      var st = stations[s];
      if (!brightNames[st.name] || currentRouteSet[st.id]) continue;
      var cx = parseFloat(st.svgX) * scale + tx;
      var cy = parseFloat(st.svgY) * scale + ty;
      rects.push({
        left: cx - UPSTREAM_RESERVE_PX,
        top: cy - UPSTREAM_RESERVE_PX,
        right: cx + UPSTREAM_RESERVE_PX,
        bottom: cy + UPSTREAM_RESERVE_PX
      });
    }
    return rects;
  }

  // 두 사각형의 교차 면적(px^2). 겹치지 않으면 0.
  function rectOverlapArea(a, b) {
    var w = Math.min(a.right, b.right) - Math.max(a.left, b.left);
    var h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
    if (w <= 0 || h <= 0) return 0;
    return w * h;
  }

  // 앵커 주변 8방향 후보 중 "가리면 안 되는 요소"(경로·상류 라벨·상류 여유
  // 영역)와 겹침이 가장 적은 배치 오프셋을 고른다.
  //
  // 후보는 대각 4방향(좌상/우상/좌하/우하) + 정방향 4방향(상/하/좌/우).
  // 각 후보에 대해 (1) 회피 요소들과의 교차 면적 합, (2) 뷰포트 밖으로 잘리는
  // 면적을 더해 점수화하고 최소 점수를 선택한다. 동점이면 후보 순서를 유지하며,
  // 대각을 먼저 두어 기존 기본값(좌상)과 일관성을 지킨다. 정방향은 선로가
  // 앵커를 수직/수평으로 관통할 때(대각이 모두 선로에 걸릴 때) 유리하다.
  //
  // 반환: {dx, dy} — 앵커 화면좌표 기준 툴바 좌상단 오프셋.
  function pickToolbarOffset(screenX, screenY, tbW, tbH) {
    var G = TOOLBAR_GAP;
    var candidates = [
      // 대각 4방향 (기존 동작 유지: 좌상이 최우선 동점 승자)
      {dx: -tbW - G, dy: -tbH - G}, // 좌상
      {dx: G, dy: -tbH - G}, // 우상
      {dx: -tbW - G, dy: G}, // 좌하
      {dx: G, dy: G}, // 우하
      // 정방향 4방향 (앵커 기준 가운데 정렬)
      {dx: -tbW / 2, dy: -tbH - G}, // 상
      {dx: -tbW / 2, dy: G}, // 하
      {dx: -tbW - G, dy: -tbH / 2}, // 좌
      {dx: G, dy: -tbH / 2} // 우
    ];
    var routeRects = collectAvoidScreenRects();
    var vw = window.innerWidth, vh = window.innerHeight;

    var best = null, bestScore = Infinity;
    for (var i = 0; i < candidates.length; i++) {
      var c = candidates[i];
      var box = {
        left: screenX + c.dx,
        top: screenY + c.dy,
        right: screenX + c.dx + tbW,
        bottom: screenY + c.dy + tbH
      };

      var score = 0;
      for (var r = 0; r < routeRects.length; r++) {
        score += rectOverlapArea(box, routeRects[r]);
      }

      // 뷰포트 밖 잘림 면적을 가산 — 화면을 벗어나는 배치는 회피한다.
      // (클램프되면 앵커에서 멀어져 어차피 경로를 가릴 수 있음)
      var visW = Math.max(0, Math.min(box.right, vw - 8) - Math.max(box.left, 8));
      var visH = Math.max(0, Math.min(box.bottom, vh - 8) - Math.max(box.top, 8));
      score += (tbW * tbH) - (visW * visH);

      if (score < bestScore) { bestScore = score; best = c; }
    }
    return best || candidates[0];
  }

  window.showRouteToolbar = function(svgX, svgY, hasTwoRoutes) {
    toolbarSvgX = svgX;
    toolbarSvgY = svgY;

    routeToolbar.textContent = '';

    var closeBtn = document.createElement('button');
    closeBtn.className = 'route-toolbar-btn close-btn';
    closeBtn.textContent = '\u00d7';
    closeBtn.addEventListener('click', function() {
      sendToFlutter({ action: 'routeToolbarSelect', mode: 'cancel' });
    });
    routeToolbar.appendChild(closeBtn);

    var modes = [{key: 'fastest', label: '최단경로'}];
    if (hasTwoRoutes) {
      modes.push({key: 'leastTransfer', label: '최소환승'});
    }
    modes.push({key: 'result', label: '경로 검색결과'});

    for (var i = 0; i < modes.length; i++) {
      var m = modes[i];
      var btn = document.createElement('button');
      btn.className = 'route-toolbar-btn';
      btn.textContent = m.label;
      btn.setAttribute('data-mode', m.key);
      if (m.key === 'fastest') btn.classList.add('active');

      btn.addEventListener('click', (function(mode) {
        return function() {
          if (mode !== 'result') {
            var btns = routeToolbar.querySelectorAll('.route-toolbar-btn:not(.close-btn)');
            for (var j = 0; j < btns.length; j++) {
              btns[j].classList.remove('active');
            }
            this.classList.add('active');
          }
          sendToFlutter({ action: 'routeToolbarSelect', mode: mode });
        };
      })(m.key));

      routeToolbar.appendChild(btn);
    }

    toolbarVisible = true;
    toolbarUserMoved = false; // 새로 띄우면 스마트 배치 재적용 허용
    routeToolbar.style.display = 'flex';
    cachedTbW = routeToolbar.offsetWidth;
    cachedTbH = routeToolbar.offsetHeight;

    repickToolbarOffset();

    // 툴바는 출발역 카메라 팬(panTo, 400ms)이 시작되기 전/도중에 표시된다.
    // 겹침 판정은 앵커와 회피 요소가 같은 tx/ty 로 이동하므로 팬 중에도
    // 유효하지만, "뷰포트 밖 잘림" 항은 절대 화면 위치에 의존해 팬이 끝나기
    // 전에는 왜곡된다. 팬이 정착한 뒤 한 번 더 골라 배치를 확정한다.
    setTimeout(repickToolbarOffset, 500);
  };

  // 스마트 배치를 (재)적용한다. 사용자가 직접 드래그해 옮긴 뒤에는 그 선택을
  // 존중해 아무것도 하지 않는다.
  function repickToolbarOffset() {
    if (!toolbarVisible || toolbarUserMoved) return;
    var anchorScreenX = toolbarSvgX * scale + tx;
    var anchorScreenY = toolbarSvgY * scale + ty;
    var off = pickToolbarOffset(
      anchorScreenX, anchorScreenY, cachedTbW, cachedTbH);
    toolbarDx = off.dx;
    toolbarDy = off.dy;
    updateRouteToolbarPosition();
  }

  window.hideRouteToolbar = function() {
    routeToolbar.style.display = 'none';
    toolbarVisible = false;
  };

  // 경로 결과 툴바 드래그 이동: 상단 빈 바 영역(padding-top:28px)을 잡아서
  // 끌면 툴바 위치를 옮긴다. 선로/열차를 가릴 때 사용자가 치울 수 있도록 한다.
  // .route-toolbar-btn(X 포함)은 드래그 시작 대상에서 제외해 클릭 동작 보존.
  // 드래그 종료 시 툴바의 화면 위치를 SVG 좌표로 역변환해 앵커(toolbarSvgX/Y)로
  // 저장하므로, 이후 맵 pan/zoom 시 툴바가 맵에 부착된 듯 함께 이동한다.
  //
  // 중요: 지도 팬 핸들러가 document의 pointerdown/pointermove에 등록돼 있으므로
  // 반드시 같은 Pointer Events 계열로 구현하고, 드래그 시작 시 stopPropagation()으로
  // document 핸들러 전파를 끊어야 툴바 드래그와 지도 팬이 겹치지 않는다.
  (function initRouteToolbarDrag() {
    var dragState = null;

    function onDragStart(e) {
      if (e.target.closest('.route-toolbar-btn')) return; // 버튼 영역 제외
      if (e.target !== routeToolbar) return; // 상단 빈 바(컨테이너 자체)만 드래그 핸들

      // document의 지도 pan 핸들러로 이벤트 전파 차단
      e.stopPropagation();
      e.preventDefault();

      // 맵 pan state를 강제 초기화: 동시에 맵 pan이 진행 중이거나
      // 이전 터치 잔재가 남아있지 않도록 보장
      for (var __k in pointers) if (pointers.hasOwnProperty(__k)) delete pointers[__k];
      isDragging = false;
      // [M-2, 2026-08 리뷰] gestureActive 도 함께 초기화한다. pointers 를
      // 전량 비우면서 이 플래그를 빠뜨리면, 지도 쪽 pointerup/pointercancel
      // 유실로 gestureActive 가 이미 true 로 걸려 있던 경우 여기서 회복할
      // 기회를 놓쳐 세션 내내(툴바 드래그 이후 포함) 열차 카운트다운 DOM
      // 쓰기가 영구 동결된다. isDragging 과 동일한 "팬 상태 강제 초기화"
      // 관용구의 일부로 취급한다.
      gestureActive = false;

      var rect = routeToolbar.getBoundingClientRect();
      dragState = {
        pointerId: e.pointerId,
        startX: e.clientX,
        startY: e.clientY,
        toolbarLeft: rect.left,
        toolbarTop: rect.top
      };
    }

    function onDragMove(e) {
      if (!dragState || e.pointerId !== dragState.pointerId) return;
      e.stopPropagation();
      e.preventDefault();

      var dx = e.clientX - dragState.startX;
      var dy = e.clientY - dragState.startY;
      var newLeft = dragState.toolbarLeft + dx;
      var newTop = dragState.toolbarTop + dy;

      // 화면 경계 clamp: 툴바가 화면 밖으로 나가 못 되돌리는 상황 방지
      var tw = routeToolbar.offsetWidth;
      var th = routeToolbar.offsetHeight;
      newLeft = Math.max(8, Math.min(window.innerWidth - tw - 8, newLeft));
      newTop = Math.max(8, Math.min(window.innerHeight - th - 8, newTop));

      // updateRouteToolbarPosition 과 동일한 이유로 transform 사용(레이아웃
      // 유발 left/top 대신 컴포지터 전용). getBoundingClientRect() 는 transform
      // 을 반영한 실제 렌더 위치를 반환하므로 onDragStart/onDragEnd 의 rect 계산은
      // 변경 없이 그대로 유효하다.
      routeToolbar.style.transform =
          'translate(' + newLeft + 'px,' + newTop + 'px)';
    }

    function onDragEnd(e) {
      if (!dragState) return;
      if (e && e.pointerId !== dragState.pointerId) return;
      // 혹시 어디서 capture가 걸려 있다면 해제 (방어)
      if (routeToolbar.hasPointerCapture &&
          routeToolbar.hasPointerCapture(dragState.pointerId) &&
          routeToolbar.releasePointerCapture) {
        try { routeToolbar.releasePointerCapture(dragState.pointerId); } catch (_) {}
      }
      // 드래그로 옮긴 툴바 위치를 "앵커 기준 오프셋"으로 저장한다. 앵커
      // (toolbarSvgX/Y = 출발역)는 그대로 두고 오프셋만 갱신하므로, 이후 맵
      // pan/zoom 시 updateRouteToolbarPosition 이 툴바를 맵에 부착된 듯 함께
      // 옮기면서 사용자가 고른 상대 위치도 유지된다.
      // updateRouteToolbarPosition 의 기준: left = anchorScreenX + toolbarDx,
      // top = anchorScreenY + toolbarDy.
      var rect = routeToolbar.getBoundingClientRect();
      var anchorScreenX = toolbarSvgX * scale + tx;
      var anchorScreenY = toolbarSvgY * scale + ty;
      toolbarDx = rect.left - anchorScreenX;
      toolbarDy = rect.top - anchorScreenY;
      toolbarUserMoved = true; // 이후 스마트 재배치가 덮어쓰지 않도록 고정
      dragState = null;
      // 맵 pan state 완전 클리어: 다음 맵 터치가 깨끗하게 pan을 시작하도록 보장
      for (var __k in pointers) if (pointers.hasOwnProperty(__k)) delete pointers[__k];
      isDragging = false;
      // [M-2, 2026-08 리뷰] 위 onDragStart 와 동일한 이유로 gestureActive 도
      // 함께 초기화한다.
      gestureActive = false;
    }

    routeToolbar.addEventListener('pointerdown', onDragStart);
    document.addEventListener('pointermove', onDragMove);
    document.addEventListener('pointerup', onDragEnd);
    document.addEventListener('pointercancel', onDragEnd);
  })();

  // ============================================================
  // 디버그: 탭 영역 시각화
  // ============================================================
  window.debugTapTargets = function(show) {
    var svg = document.querySelector('svg');
    var existing = document.getElementById('debug-tap-overlay');
    if (existing) existing.remove();
    if (show === false) return;

    var ns = 'http://www.w3.org/2000/svg';
    var g = document.createElementNS(ns, 'g');
    g.id = 'debug-tap-overlay';

    // 텍스트 바운딩 박스 (1차 탭 영역, 파란색) — 현재 줌 배율 기준
    for (var i = 0; i < svgTextTargets.length; i++) {
      var t = svgTextTargets[i];
      var r = textTargetRect(t);
      var rect = document.createElementNS(ns, 'rect');
      rect.setAttribute('x', r.x0);
      rect.setAttribute('y', r.y0);
      rect.setAttribute('width', r.x1 - r.x0);
      rect.setAttribute('height', r.y1 - r.y0);
      rect.setAttribute('fill', 'rgba(0,100,255,0.25)');
      rect.setAttribute('stroke', 'rgba(0,100,255,0.6)');
      rect.setAttribute('stroke-width', '0.5');
      g.appendChild(rect);
    }

    // circle 좌표 기반 TAP_RADIUS (2차 폴백, 빨간색)
    for (var i = 0; i < stations.length; i++) {
      var s = stations[i];
      var circle = document.createElementNS(ns, 'circle');
      circle.setAttribute('cx', s.svgX);
      circle.setAttribute('cy', s.svgY);
      circle.setAttribute('r', TAP_RADIUS);
      circle.setAttribute('fill', 'rgba(255,50,50,0.2)');
      circle.setAttribute('stroke', 'rgba(255,50,50,0.5)');
      circle.setAttribute('stroke-width', '0.5');
      g.appendChild(circle);
    }

    svg.appendChild(g);
  };

  // ============================================================
  // 초기화
  // ============================================================
  setInitialView();
  window.addEventListener('resize', function() {
    clampTranslation();
    scheduleTransform();
  });
})();
</script>
</body>
</html>''';
}
