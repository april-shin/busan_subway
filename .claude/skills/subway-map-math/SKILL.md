---
name: subway-map-math
description: "서울 지하철 지도의 SVG 렌더링, 좌표 변환, 줌/팬 수학, 경로 보간, 열차 애니메이션, CSS transform 행렬 계산을 수행. 지도 화면 수정, 애니메이션 개선, 줌/팬 동작 변경, 마커/툴팁 배치, 열차 이동 표현, 좌표계 변환, WebView JS 코드 수정 요청 시 이 스킬을 사용. map.html, svg_web_view.dart, subway_map_viewer.dart, live_train_provider.dart 관련 작업에 모두 적용."
---

# Subway Map Math

서울 지하철 지도의 수학적 렌더링 가이드. SVG 좌표계, CSS 변환 행렬, 경로 보간, 열차 애니메이션의 수학적 기반.

## ⛔ 실시간 열차 애니메이션 4원칙 — 최상위 정책

`tool/build_map_html.dart`(HTML 생성 유일 소스) 또는 `live_train_provider.dart`를 수정하기 전, **CLAUDE.md의 "실시간 열차 애니메이션 4원칙" 섹션을 먼저 읽는다.** 이 4원칙은 일반 수정·버그 수정으로 깨뜨릴 수 없고, 원칙 자체를 바꾸려면 사용자 승인이 필요하다.

1. **열차는 절대 뒤로 가지 않는다 (경로상 단조 전진)**: 표시용 숫자(`realRemaining`)는 API 원본 그대로 — 재조회로 늘어나도 보정하지 않는다(옛 clamp·`trainSlotMemory` 재도입 금지). 위치는 두 층으로 지킨다 — (a) 역산 입력은 표시용과 분리된 기준쌍(`posBaseArrival`/`posBaseReceivedAt`)을 쓰되 **API 원본 값이 바뀐 refresh 에서만** 보정(값이 그대로면 stale 반복 보고 → 유지, 갱신하면 열차 정지), (b) target 의 `distToEnd`(경로 끝까지 남은 px)가 `minDistToEnd` 보다 크면 `pointAtLength(pathTotalLen − minDistToEnd)` 에 고정. `pathEndKey` 변경 시 둘 다 리셋. 동작 회귀 테스트는 Dart 미러 `test/core/utils/train_forward_guard_test.dart`.
2. **매 frame 역산 위치 결정**: `estimateTrainPosition(remaining, segTravel)`이 **뒤에서부터** 세그먼트 주행시간을 차감하며 위치를 찾는다. 아래 "경로 보간" 섹션의 LERP은 좌표 계산용이며, **progress를 구하는 방법이 아니다** — `path[0]`에서 경과시간 비례로 전방 계산하는 방식은 원칙 2 위반이므로 사용 금지.
3. **현재역 기준 3-way 클램프**: `arvlMsg3`(현재역) 기준 현재역↔다음역 한 구간 밖으로 못 나간다. `expandPathWithSnap`의 `stationIndices` 매핑으로 확장 path 상 위치를 재계산해야 한다.
4. **열차는 순간이동하지 않는다 (catch-up)**: target이 이동해도 현재 위치에서 매 프레임 지수 감쇠(`factor = 0.5^(deltaMs/halfLife)`)로 다가간다. 반감기는 거리 기반 — 가까우면(≤30px) `HALF_LIFE_NEAR_MS=3000`(지터 흡수), 멀면(>30px) `HALF_LIFE_FAR_MS=500`(빠른 따라잡기), `SNAP_PX=0.5` 이내면 스냅 종료. deltaMs 상한 100ms.

적용 순서(한 프레임): 원칙 2(역산) → 원칙 3(3-way 클램프) → 원칙 1(단조 전진 가드) → 원칙 4(catch-up) → transform.

회귀 테스트: 원칙 1 `test/core/utils/train_forward_guard_test.dart`, 원칙 2 `test/core/utils/estimate_train_position_test.dart`, 생성 JS 형태 `test/tool/build_map_html_test.dart`. 깨지면 원칙 위반을 먼저 의심한다. JS 애니메이션 로직은 WebView 안이라 단위 테스트가 불가능하므로 `lib/core/utils/` 의 **Dart 미러**로 검증한다 — JS 를 고치면 미러도 함께 고칠 것.

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

### 세그먼트 구조
```
pathToTarget: [(x₀,y₀), (x₁,y₁), ..., (xₙ,yₙ)]  // SVG 좌표 시퀀스
segmentDurations: [d₀, d₁, ..., dₙ₋₁]              // 각 구간 소요시간(초)
```

### 위치 결정 — 뒤에서부터 역산 (원칙 2, `estimateTrainPosition`)
```javascript
// remaining: realRemaining (API 원본 기반 — 재조회 시 늘어날 수 있음)
// segTravel: segmentDurations
// 뒤에서부터 각 세그먼트 시간을 차감하며 매칭되는 세그먼트를 찾는다
function estimateTrainPosition(remaining, segTravel) {
  if (remaining <= 0) return { segmentIndex: segTravel.length - 1, progress: 1 };
  var t = remaining;
  for (var i = segTravel.length - 1; i >= 0; i--) {
    if (t <= segTravel[i]) {
      return { segmentIndex: i, progress: (segTravel[i] - t) / segTravel[i] };
    }
    t -= segTravel[i];
  }
  return { outOfPath: true }; // 경로 시작점보다 더 이전 — 원칙 3에서 현재역에 클램프
}
```
예시: `path=[A,B,C]`, `segTravel=[60,60]` → `remaining=120`이면 A 위치, `remaining=80`이면 A-B 구간의 2/3 지점(B 쪽).

### 좌표 계산 — 선형 보간 (LERP)
`segmentIndex`/`progress`가 정해진 **후**에만 좌표 계산에 사용한다:
```javascript
function lerp(a, b, t) {
  return a + (b - a) * t  // t ∈ [0, 1]
}

currentX = lerp(path[i].x, path[i+1].x, progress)
currentY = lerp(path[i].y, path[i+1].y, progress)
```
⚠ `path[0]`부터 경과시간에 비례해 전방으로 progress를 누적하는 방식(예: "시간 0→d₀초: progress 0→1.0")은 **원칙 2 위반**이다. progress는 항상 `estimateTrainPosition`의 역산 결과로만 정한다.

### 3-way 클램프 (원칙 3)
`estimateTrainPosition`의 결과가 `arvlMsg3`(현재역) 이전 세그먼트를 가리키면 현재역에, 다음역 이후를 가리키면 다음역에 클램프한다. 화면상 열차는 항상 현재역↔다음역 한 구간 안에서만 움직인다.

### 단조 전진 (원칙 1) — 2층 구조

**1층: 위치 역산 입력의 stale 필터** (refresh 당 1회, `startTrainAnimation` 진입부)
```javascript
// 표시용(realRemaining)과 분리된 위치 전용 기준쌍.
// API 원본 값이 **바뀐 refresh 에서만** 보정한다.
if (trainState.posBaseArrival == null
    || trainState.lastRawArrival !== baseArrival) {
  trainState.posBaseArrival = baseArrival;
  trainState.posBaseReceivedAt = receivedAt;
}
trainState.lastRawArrival = baseArrival;
```
⚠ 값이 그대로인데(= `recptnDt` 만 갱신된 stale 반복 보고) 기준쌍을 갱신하면 남은시간이 매 cycle 원복돼 **열차가 정지한다.** 반대로 "더 늦은 도착이면 무조건 무시"로 만들면 실제 지연을 반영하지 못해 아이콘이 실제보다 앞서 달린다. 값이 바뀌면 채택하고, 뒤로 가는 것은 2층 백스톱에 맡긴다.

**2층: 경로상 backstop** — 3-way 클램프 **다음**. 경로 앞부분은 refresh 마다 늘고 줄지만 끝점(목표역)은 고정이므로, 전진량은 **끝에서부터 잰 거리**로만 비교한다:
```javascript
// cumLen: path 누적 길이 테이블(refresh 당 1회 계산), pathTotalLen = cumLen[last]
var distToEnd = pathTotalLen - targetLen;   // targetLen = 3-way 클램프 후 target 의 시작점 기준 거리
if (!isFinite(distToEnd)) {                 // 퇴화 데이터로 기억이 NaN 오염되는 것 방지
  if (trainState.minDistToEnd != null) target = pointAtLength(pathTotalLen - trainState.minDistToEnd);
} else if (trainState.minDistToEnd != null && distToEnd > trainState.minDistToEnd) {
  target = pointAtLength(pathTotalLen - trainState.minDistToEnd); // 뒤로 가는 target 폐기
} else {
  trainState.minDistToEnd = distToEnd;      // 전진했을 때만 기억 갱신
}
```
시간과 무관한 후퇴(현재역 후퇴·경로 재스냅)에서 열차는 뒤로 가는 대신 **그 자리에 멈춰** 기다리다가, target 이 최전진 지점을 다시 넘어서면 전진을 재개한다. `pathEndKey`(끝점 좌표) 변경 시 1·2층 상태를 모두 리셋한다.

⚠ `minDistToEnd = 0`(최전진 확정)은 **실제 도착일 때만** 기록할 것. 단일 점 path('진입'/'도착')에서 `arrivalSeconds` 가 양수인데도 0 을 박으면, 끝점이 같아 `pathEndKey` 리셋도 타지 않으므로 그 열차는 목표역에 **영구 고정**된다.

### 도착 판정
`arrivalCode`/`positionStatus`는 초기 표시값 힌트일 뿐이며, 매 frame 위치는 여전히 `estimateTrainPosition(realRemaining, ...)`로 결정한다. 도착 이펙트는 catch-up 보간(원칙 4) 완료 후에만 발동한다.

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
