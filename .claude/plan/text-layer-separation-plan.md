# 텍스트 레이어 분리 — 줌아웃 시 역명 크기 유지

## 배경

현재 줌은 `#map-container` 전체에 CSS `transform: matrix(scale, ...)` 를 적용하므로, 스케일 < 1로 줌아웃하면 역 이름 텍스트도 함께 축소되어 가독성이 떨어진다. 텍스트를 별도 SVG 레이어로 분리하여 맵은 축소되지만 역명은 원래 크기를 유지하도록 한다.

## 수정 대상 파일

- `tool/build_map_html.dart` — SVG 분리 + HTML 구조 + JS 로직
- `test/tool/build_map_html_test.dart` — 테스트 업데이트

## 구현 계획

### 1단계: SVG에서 text 요소 추출 (`build_map_html.dart`)

`_buildHtml()` 내에서 SVG 콘텐츠를 두 부분으로 분리:

```dart
final textPattern = RegExp(r'<text[^>]*>.*?</text>', dotAll: true);
final textElements = textPattern.allMatches(svgContent).map((m) => m.group(0)!).join('\n');
final mapOnlyContent = svgContent.replaceAll(textPattern, '');
```

- 원본 SVG는 평탄 구조(g 태그 없음)이고 `<text ...>...</text>` 패턴으로 깔끔하게 추출 가능
- `tspan` 줄바꿈 역명도 `dotAll: true`로 처리됨

### 2단계: HTML 구조 변경

```html
<div id="map-container">          <!-- CSS transform(scale + translate) 적용 -->
  (path + circle + rect만 있는 SVG)
  <svg id="overlay">...</svg>
  <div id="tap-layer"></div>
</div>

<svg id="text-layer"              <!-- 별도 SVG, 화면 크기 고정 -->
  width="100%" height="100%"
  viewBox="0 0 2416 1560"
  style="position:absolute; top:0; left:0;
         pointer-events:none;">
  (654개 text 요소)
</svg>
```

- `#text-layer`는 `#map-container` 밖에 위치 → CSS transform 영향 받지 않음
- `pointer-events: none`으로 탭 이벤트는 기존 `#tap-layer`로 통과

### 3단계: JS `applyTransform()` 수정

viewBox + font-size 보상 하이브리드 방식:

```javascript
var textLayer = document.getElementById('text-layer');

function applyTransform() {
  container.style.transform = 'matrix(' + scale + ',0,0,' + scale + ',' + tx + ',' + ty + ')';

  // 텍스트 레이어: viewBox로 맵과 동일 영역 표시
  var vw = window.innerWidth, vh = window.innerHeight;
  var x0 = -tx / scale, y0 = -ty / scale;
  var vbW = vw / scale, vbH = vh / scale;
  textLayer.setAttribute('viewBox', x0 + ' ' + y0 + ' ' + vbW + ' ' + vbH);

  // 텍스트 크기 보상 (CSS 변수 1개로 일괄 적용)
  textLayer.style.fontSize = (12 / scale) + 'px';

  updateRouteToolbarPosition();
}
```

viewBox 축소로 인한 텍스트 축소를 font-size 확대로 정확히 상쇄. DOM 조작은 SVG 요소 1개의 속성 2개 변경뿐이라 성능 부담 없음.

### 4단계: CSS 수정

```css
#text-layer {
  position: absolute;
  top: 0; left: 0;
  width: 100%; height: 100%;
  pointer-events: none;
  overflow: hidden;
}
#text-layer text {
  stroke: white;
  stroke-width: var(--stroke-w, 2px);
  paint-order: stroke;
  stroke-linejoin: round;
  font-size: inherit;
}
```

기존 `svg text { ... }` 규칙은 `#text-layer text`로 이동 (원본 SVG에는 text가 없으므로).

### 5단계: stroke-width 보상

font-size를 키우면 stroke-width도 상대적으로 얇아 보이므로 함께 보상:

```javascript
textLayer.style.fontSize = (12 / scale) + 'px';
textLayer.style.setProperty('--stroke-w', (2 / scale) + 'px');
```

### 수정 불필요한 부분

- `buildTextTargets()` — `getBBox()`는 text-layer SVG 내 좌표계(2416×1560) 기준, 원본과 동일
- `highlightLines()` / `clearLineHighlight()` — `document.querySelectorAll` 사용, 문서 전체 탐색
- `showRouteToolbar()` / `updateRouteToolbarPosition()` — 이미 `#map-container` 밖
- `svg_web_view.dart` — JS API 인터페이스 변경 없음
- `panTo()` / `clampTranslation()` / `setInitialView()` — `applyTransform()` 통해 간접 적용

## 검증

1. `dart run tool/build_map_html.dart` 실행 → map.html 생성 확인
2. `flutter test test/tool/build_map_html_test.dart` 통과
3. 에뮬레이터에서 확인:
   - 스케일 1.0: 기존과 동일하게 보이는지
   - 줌아웃(0.5x): 맵은 축소되지만 역명 텍스트는 읽을 수 있는 크기 유지
   - 줌인(2x~5x): 기존과 동일
   - 탭 → 역 선택 정상 동작
   - 경로 하이라이트 + dimmed 정상 동작
   - 패닝 시 텍스트 위치 동기화
