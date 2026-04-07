---
name: subway-map-math
description: "서울 지하철 지도의 SVG 렌더링, 좌표 변환, 줌/팬 수학, 경로 보간, 열차 애니메이션, CSS transform 행렬 계산을 수행. 지도 화면 수정, 애니메이션 개선, 줌/팬 동작 변경, 마커/툴팁 배치, 열차 이동 표현, 좌표계 변환, WebView JS 코드 수정 요청 시 이 스킬을 사용. map.html, svg_web_view.dart, subway_map_viewer.dart, live_train_provider.dart 관련 작업에 모두 적용."
---

# Subway Map Math

서울 지하철 지도의 수학적 렌더링 가이드. SVG 좌표계, CSS 변환 행렬, 경로 보간, 열차 애니메이션의 수학적 기반.

## 좌표계

### SVG 원본 좌표
- 캔버스 크기: 2416 × 1560
- 원점: 좌상단 (0, 0)
- 단위: SVG 사용자 단위 (px와 1:1)
- 중심점: (1040, 618) — 초기 뷰

### 화면 좌표 ↔ SVG 좌표 변환
```javascript
// 화면 → SVG
svgX = (screenX - translateX) / scale
svgY = (screenY - translateY) / scale

// SVG → 화면
screenX = svgX * scale + translateX
screenY = svgY * scale + translateY
```

### CSS Transform Matrix
```
transform: matrix(scale, 0, 0, scale, translateX, translateY)
```

## 줌/팬 수학

### 핀치 줌 (중심점 유지)
```javascript
// focalPoint = 핀치 중심의 화면 좌표
newScale = clamp(oldScale * pinchDelta, 0.5, 5.0)

// 줌 중심 유지 공식
newTranslateX = focalX - (focalX - oldTranslateX) * (newScale / oldScale)
newTranslateY = focalY - (focalY - oldTranslateY) * (newScale / oldScale)
```

### 스무스 팬 (panTo)
```javascript
// 대상 SVG 좌표를 화면 중앙에 배치
targetTranslateX = viewportWidth/2 - svgX * scale
targetTranslateY = viewportHeight/2 - svgY * scale

// CSS transition으로 부드러운 이동
transition: transform {duration}ms ease-in-out
```

### 줌 범위
- 최소: 0.5x (전체 보기)
- 최대: 5.0x (역 상세)
- 기본: 1.0x

## 경로 보간 (열차 애니메이션)

### 세그먼트 기반 이동
```
pathToTarget: [(x₀,y₀), (x₁,y₁), ..., (xₙ,yₙ)]  // SVG 좌표 시퀀스
segmentDurations: [d₀, d₁, ..., dₙ₋₁]              // 각 구간 소요시간(초)
initialProgress: p₀                                   // 첫 세그먼트 내 위치 (0.0~1.0)
```

### 선형 보간 (LERP)
```javascript
function lerp(a, b, t) {
  return a + (b - a) * t  // t ∈ [0, 1]
}

// 현재 위치 계산
currentX = lerp(path[i].x, path[i+1].x, progress)
currentY = lerp(path[i].y, path[i+1].y, progress)
```

### 초기 진행률 (initialProgress)
| arrivalCode | 의미 | progress |
|-------------|------|----------|
| 1 | 도착 | 0.0 |
| 2 | 출발 | 0.15 |
| 0 | 진입 | 0.85 |
| 3,4,5 | 이전역 | positionStatus 기반 |

### 애니메이션 타임라인
```
시간 0 → d₀초:  세그먼트 0, progress p₀ → 1.0
시간 d₀ → d₀+d₁: 세그먼트 1, progress 0.0 → 1.0
...
시간 Σdᵢ:        최종 도착
```

## 오버랩 처리

같은 위치에 여러 열차가 있을 때:
```javascript
// N개 열차의 Y 오프셋
offset_i = (i - (N - 1) / 2) × 12  // px
```

## Flutter ↔ JS 브릿지

### Flutter → JS (주요 함수)
| 함수 | 파라미터 | 용도 |
|------|---------|------|
| `highlightRoute(json)` | stationIds JSON | 경로 역 강조 |
| `highlightLines(json)` | lineIds JSON | 노선 강조 |
| `panTo(x, y, ms)` | SVG좌표, 지속시간 | 카메라 이동 |
| `setMarker(type, x, y)` | 'departure'/'arrival' | 출발/도착 마커 |
| `showTrains(json)` | LiveTrain[] JSON | 열차 표시/애니메이션 |
| `showTooltip(json)` | Station JSON | 역 정보 팝업 |
| `showRouteToolbar(x, y, two)` | SVG좌표, 2경로여부 | 경로 선택 UI |

### JS → Flutter (JavaScriptChannel)
| action | 데이터 | 트리거 |
|--------|--------|--------|
| stationTapped | stationId | 역 원 클릭 |
| setDeparture | stationId | 출발역 설정 |
| setArrival | stationId | 도착역 설정 |
| viewArrivalInfo | stationName | 도착정보 보기 |
| routeToolbarSelect | mode | 경로 선택 |
| trainArrived | destination | 열차 도착 이벤트 |

## SVG 파이프라인

SVG 수정 후 반드시 3단계 순서대로 실행:
```bash
dart run tool/extract_svg_stations.dart    # SVG → svg_station_coords.json
dart run tool/generate_station_data.dart   # coords → stations.json
dart run tool/build_map_html.dart          # SVG → map.html
```

## 성능 최적화 원칙

1. CSS transform으로 줌/팬 (레이아웃 재계산 없음)
2. `requestAnimationFrame`으로 애니메이션 루프
3. DOM 조작 최소화 (배치 업데이트)
4. 뷰포트 밖 열차는 렌더링 스킵
5. `will-change: transform` CSS 힌트 사용
