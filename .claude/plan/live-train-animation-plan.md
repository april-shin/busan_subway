# 실시간 열차 위치 맵 표시 기능

## 컨텍스트

출발역과 도착역을 선택하면 경로가 하이라이트되고 출발역으로 포커스가 이동한다. 이 상태에서 실시간 API를 호출하여 **선택된 노선 위를 달리고 있는 열차들을 맵 위에 열차 모양 아이콘으로 표시**한다. 열차는 현재 위치에서 출발역까지 **도착 예상 시간(`barvlDt`)에 맞춰 노선 경로를 따라 부드럽게 이동하는 애니메이션**으로 표현된다. 15초마다 API를 재호출하여 열차의 실제 위치를 확인하고, 애니메이션 위치가 어긋났으면 보정한다.

## 핵심 아이디어

1. **초기 배치**: API 호출 → `arvlMsg3`(현재 위치 역명)으로 열차의 현재 SVG 좌표를 결정
2. **애니메이션**: `barvlDt`(도착 예상 초) 동안 현재 역 → 출발역까지 노선 경로(역 간 연결)를 따라 부드럽게 이동
3. **보정**: 15초 후 API 재호출 → 새로운 `arvlMsg3`와 `barvlDt`로 열차 위치를 보정하고 애니메이션 재시작

## 수정 파일 목록

| 파일 | 변경 내용 |
|------|-----------|
| `lib/domain/entities/arrival_info.dart` | `currentStationName`, `trainNo` 필드 추가 |
| `lib/data/remote/dto/arrival_info_dto.dart` | `btrainNo` 추가, `arvlMsg3` 파싱(`_extractStationName`), `toEntity()` 매핑 |
| `lib/features/subway_map/presentation/providers/live_train_provider.dart` | **(신규)** 실시간 열차 프로바이더 |
| `lib/features/subway_map/presentation/widgets/subway_map_viewer.dart` | `liveTrainsProvider` watch → SvgWebView 전달 |
| `lib/features/subway_map/presentation/widgets/svg_web_view.dart` | `_showTrains()` / `_clearTrains()` JS 호출 추가 |
| `assets/html/map.html` | `<g id="live-trains">` 오버레이 + `showTrains()` / `clearTrains()` JS 함수 |

## 상세 구현 계획

### 1단계: 도메인/데이터 모델 확장

**`lib/domain/entities/arrival_info.dart`**
- `currentStationName` 필드 추가 (`String`, arvlMsg3에서 매핑 — 열차의 현재 위치 역명)
- `trainNo` 필드 추가 (`String`, btrainNo 또는 ordkey에서 추출 — 열차 고유 식별)

**`lib/data/remote/dto/arrival_info_dto.dart`**
- `btrainNo` 필드 추가
- `_extractStationName()` 함수 추가 — arvlMsg3에서 순수 역명만 추출 ("강남 출발" → "강남")
- `toEntity()` 수정:
  - `currentStationName: _extractStationName(arvlMsg3)`
  - `trainNo: btrainNo ?? ordkey ?? ''`

### 2단계: subwayId → lineId 변환 맵

기존 `lib/core/constants/subway_id_mapping.dart`의 `subwayIdToLineId` 맵을 활용.

### 3단계: 실시간 열차 프로바이더

**`lib/features/subway_map/presentation/providers/live_train_provider.dart`** (신규)

`LiveTrain` 클래스:
- `trainNo` — 열차 고유 ID
- `lineId` — 앱 내부 노선 ID
- `direction` — "상행"/"하행"/"내선"/"외선"
- `destination` — 행선지명
- `message` — 도착 메시지 (예: "3분 후")
- `arrivalSeconds` — 출발역까지 도착 예상 초
- `currentStation` — 현재 위치 역명
- `fromSvgX`, `fromSvgY` — 현재 위치 역 SVG 좌표
- `pathToTarget` — 현재역 → 출발역까지 경유 역 좌표 리스트

프로바이더 로직:
1. `selectedStationsProvider` watch → 출발역이 있으면 활성화
2. `arrivalRepositoryProvider`로 출발역명 API 호출
3. `subwayIdToLineId`로 노선 매칭, 열차 필터링
4. 각 열차의 `currentStationName`으로 stations에서 SVG 좌표 조회
5. `findPathOnLine()` — BFS로 현재역 → 출발역까지 경유 역 좌표 경로 계산
6. 동일역 열차 오프셋 적용 (`_applyOverlapOffset`)
7. 15초 `Timer`로 `ref.invalidateSelf()` 자동 새로고침
8. 네트워크 오류 시 `_lastSuccessfulTrainsProvider` 캐시 반환

### 4단계: SubwayMapViewer → SvgWebView 연동

**`lib/features/subway_map/presentation/widgets/subway_map_viewer.dart`**
- `ref.watch(liveTrainsProvider)`로 열차 데이터 구독
- `liveTrainsAsync.valueOrNull ?? []`로 SvgWebView에 전달

**`lib/features/subway_map/presentation/widgets/svg_web_view.dart`**
- `liveTrains` 파라미터 추가
- `_showTrains(List<LiveTrain>)` — JSON 직렬화 후 `window.showTrains()` JS 호출
- `_clearTrains()` — `window.clearTrains()` JS 호출
- `didUpdateWidget`에서 `liveTrains` 변경 감지
- `_onPageLoaded`에서 초기 열차 데이터 표시

### 5단계: map.html JS 구현 (핵심 — 애니메이션)

**`assets/html/map.html`**

SVG 오버레이 그룹 추가 (selection-markers 뒤):
```html
<g id="live-trains"></g>
```

JS 핵심 함수:

- `createTrainIcon(train, color)` — 열차 아이콘 SVG 생성 (둥근 사각형 + 전조등 + 행선지 라벨)
- `startTrainAnimation(trainState, trainData)` — 경로를 따라 이동하는 requestAnimationFrame 애니메이션
- `cancelTrainAnimation(trainState)` — 애니메이션 취소
- `window.showTrains(trainsJson)` — 열차 표시/갱신 (기존 열차 보정, 신규 생성, 사라진 열차 제거)
- `window.clearTrains()` — 모든 열차 제거

애니메이션 핵심:
- `pathToTarget`: 현재역 → 출발역까지의 경유 역 SVG 좌표 배열
- `arrivalSeconds`: 도착 예상 초 (이 시간 동안 전체 경로를 이동)
- 전체 경로 거리 계산 → progress 비율로 구간 보간 → `transform: translate(x, y)`
- `requestAnimationFrame`으로 60fps 부드러운 이동
- 15초 후 `showTrains()` 재호출 시 → 기존 애니메이션 취소 → 새 위치/시간 기반 보정 재시작

## 데이터 흐름

```
[15초마다 반복]
Timer → ref.invalidateSelf()
  → arrivalRepository.getArrivalInfo(출발역명)
  → API 응답 필터링 (subwayIdToLineId로 노선 매칭)
  → 각 열차:
      arvlMsg3 → _extractStationName() → SVG 좌표 조회
      connections → BFS로 현재역→출발역 경유 좌표 계산
      barvlDt → 도착 예상 초
  → LiveTrain 리스트 생성
  → 동일역 열차 오프셋 적용
  → SvgWebView._showTrains(trains)
  → JS window.showTrains(trainsJson)
  → 기존 열차: 애니메이션 취소 → 보정된 위치에서 재시작
  → 신규 열차: 아이콘 생성 → 애니메이션 시작
  → 사라진 열차: 아이콘 제거
```

## 엣지 케이스 처리

| # | 케이스 | 처리 |
|---|--------|------|
| 1 | arvlMsg3 빈 문자열 / 매칭 실패 | 해당 열차 건너뜀 |
| 2 | 같은 역에 여러 열차 | Y축 12px 오프셋으로 분산 |
| 3 | 네트워크 오류 | 마지막 성공 데이터 반환 (기존 애니메이션 유지) |
| 4 | 경로 해제 | `clearTrains()` 호출 (아이콘 + 애니메이션 모두 제거) |
| 5 | 경로 변경 | 사라진 열차 제거 + 새 열차 생성 |
| 6 | arrivalSeconds ≤ 0 | 0으로 보정 (도착 상태로 정적 배치) |
| 7 | 반대편 열차 (경로 없음) | BFS 실패 시 건너뜀 |

## 검증 방법

1. `flutter analyze` — 정적 분석 통과 확인
2. `flutter test` — 기존 테스트 깨지지 않는지 확인
3. 시뮬레이터에서 `flutter run`:
   - 출발역 + 도착역 선택 → 경로 하이라이트 + 열차 아이콘 애니메이션 확인
   - 열차가 노선 경로를 따라 출발역 방향으로 부드럽게 이동하는지 확인
   - 15초 후 열차 위치 보정 + 애니메이션 재시작 확인
   - 경로 해제 시 열차 아이콘 사라지는지 확인
   - 다른 경로 선택 시 열차 아이콘 갱신 확인
4. API 키가 없는 환경에서 오류 처리 확인
