# 요구사항 리뷰

## 원래 요청 (재진술)

> "2호선에서 테스트를 해봤는데, API에서는 이미 해당역에 도착했다는데, 화면에서는 열차가 아직 해당역에 도착하지 않는것처럼 보이는 현상이 있었어" — arvlCd=99, positionStatus="도착", 중간 경유역에서 발생.

승인된 플랜(`/Users/april/.claude/plans/memoized-churning-karp.md`)의 4가지 수정 항목을 기반으로 구현 완전성과 의도 부합성을 검증한다.

## 요약

- **충족률**: 4/4 (100%) — 플랜의 모든 항목이 실제 코드에 반영됨
- **누락**: 0건
- **불일치**: 0건 (의도에 부합)
- **과다구현 의심**: 1건 (line_direction.dart 신규 분리 — 근거 존재, 허용 가능)
- **결론**: **Approve**

## 플랜 항목별 검증

### 1. map.html `startTrainAnimation` "이어서 진행" 로직 개선 — 완료 (assets/html/map.html:1870-1974)

- **bestT 보존**: 라인 1891 `var bestT = 0;`, 라인 1903 `bestSeg = si; bestT = t;` — 세그먼트 탐색 루프에서 bestT를 bestSeg와 함께 저장.
- **3분기 처리**:
  - (a) `bestT <= 0.001`: path[bestSeg] 포함 (라인 1910-1919) — path[bestSeg] 누락 방지 → **버그 수정의 핵심**
  - (b) `bestT >= 0.999`: path[bestSeg+1]부터 시작 (라인 1920-1941) — 길이 0/1 방어
  - (c) 중간값: 기존 동작 + 첫 세그먼트 시간 `segDurations[bestSeg] * (1 - bestT)` 보정 (라인 1942-1959)
- **sliceOffset 플래그화**: `-1`을 "segTimes 확정됨" 플래그로 사용 (라인 1872, 1962, 1971) — fallthrough 이중 분기 제거.
- **불변성**: path/segDurations는 slice/concat으로 새 배열만 생성. 원본 변경 없음.

### 2. `calculateInitialProgress` "진입" 매핑 0.85 → 0.0 — 완료 (lib/core/utils/path_on_line.dart:145-165)

- `arrivalCode == 0` (진입): `0.0` (라인 150)
- `arrivalCode == 4` (전역진입): `0.0` (라인 152)
- `positionStatus == '진입'`: `0.0` (라인 162)
- 근거 주석: "currentStation 근사 (이전 세그먼트 끝이나 표현 불가)" — doc 주석(139-144)과 case 옆 주석 모두 존재
- 기존 매핑 유지: 1(0.0), 2(0.15), 3(0.15), 5(0.0), '출발'(0.15), '도착'(0.0), default(0.0)

### 3. `findPathOnLine`에 `isDown` 파라미터 추가 — 완료 (lib/core/utils/path_on_line.dart:23-98)

- 시그니처: `bool? isDown` 선택 파라미터 추가 (라인 29) — null = 기존 양방향 동작 유지
- adjacency 구축 (라인 52-66): isDown이 non-null이면 connection을 `isDownBetween`으로 판정하여 단일 엣지만 등록
- travelTimeMap: 양쪽 키 유지 (BFS 역추적 조회 용이) — 타당
- 기존 BFS(`bfs` 함수) 자체는 건드리지 않음 — 최소 변경

### 4. `live_train_provider` 호출부에서 `routeFilter.isDown` 전달 — 완료 (lib/features/subway_map/presentation/providers/live_train_provider.dart:196-203)

- `findPathOnLine` 호출에 `isDown: routeFilter.isDown` 추가 (라인 202)
- `routeFilter`는 이미 라인 119에서 watch 중 — 일관성 유지
- `estimate_arrival_seconds.dart`는 의도적으로 제외 (방향 정보 없음) — 합리적 결정

## 사용자 증상과의 연결

**시나리오**: 2호선 내선, 열차가 B역(currentStation)에서 C역 방향으로 이동 중인 중간 경유, API 응답 `arvlCd=99`, `positionStatus="도착"` (C역에 도착 중이라 보고). 목적지는 D역.

1. **플랜 항목 1 적용 효과**: `pathToTarget`은 [B, C, D]이고, 이전 틱에서 curPos가 path[0](=B) 근처에 머물렀다면 bestSeg=0, bestT≈0. 기존 코드는 `path.slice(1)` = [C, D]로 animPath를 구성해 curPos→C→D가 아니라 curPos→D의 일직선 경로가 되었음. 수정 후 `bestT <= 0.001` 분기로 진입해 animPath = [curPos, B, C, D]가 되어 SVG 노선을 따라 C를 통과.
2. **항목 2 적용 효과**: arvlCd=99 + positionStatus="도착"은 `calculateInitialProgress` 반환값이 `0.0` (path[0]=currentStation 위치에서 시작). "진입" 매핑은 이번 시나리오에는 직접 해당하지 않지만, 같은 함수의 다른 코드경로 정확도도 함께 향상.
3. **항목 3,4 적용 효과**: 2호선 순환선에서 양방향 BFS가 반대 방향(반시계↔시계) 우회 경로를 뽑아올 수 있는 가능성을 차단. 플랜상 근본 원인은 아니지만, 예상치 않게 path 자체가 기대와 다르게 계산되어 curPos가 path의 어느 점과도 가깝지 않게 되는 2차 증상을 원천적으로 예방.

종합: 항목 1이 증상 해결의 **주된 수정**이며, 항목 2-4는 연관된 정확성/일관성 개선. 사용자 증상의 직접 원인인 "C를 건너뛰고 직선 이동" 현상은 항목 1로 해소된다고 판단.

## 누락된 엣지 케이스

### (경미) path[0]이 아닌 중간 세그먼트에서 bestT=0인 경우
- 수정된 (a) 분기는 `bestSeg=N`이고 bestT<=0.001일 때 `path.slice(bestSeg)`를 포함. N>=1이어도 동일하게 동작하여 올바르게 처리됨. 추가 대응 불필요.

### (경미) segDurations 길이 불일치 방어
- 라인 1914, 1925, 1947에서 `hasDurationsForBranch = segDurations.length === path.length - 1` 조건 확인 후 segTimes를 채움. 불일치 시 fallthrough 블록이 거리 기반 폴백으로 처리. 적절히 방어됨.

### (경미) bestT가 정확히 0.001 또는 0.999 경계
- `<=`, `>=`로 경계 포함. bestT==0.001이면 (a) 분기, bestT==0.999면 (b) 분기. 가운데 (c)는 (0.001, 0.999) 열린 구간. 경계 누락 없음.

### (경미) 2호선 순환 경계 실노선 테스트
- `line_direction_test.dart`에서 201→243(|step|=42), 243→201, 243→242 등 핵심 경계 모두 커버.
- `path_on_line_test.dart`의 `isDown 방향 제한` 그룹은 가짜 4역 순환선이어서 실제 2호선 `|step|>21` 반전은 커버하지 않음. 다만 이 동작은 `line_direction_test.dart`에서 검증되므로 레이어별 책임 분리 측면에서 수용 가능.

### (주의) 8호선 등 barvlDt=0 응답 노선에서의 상호작용
- 라인 1866-1869의 방어선(`arrivalSeconds <= 1 && path.length >= 2 && initialProgress < 0.7`)은 기존 유지. 이번 수정의 initialProgress=0 케이스와 조합 시 durationMs 최소 2.5초 확보 로직이 여전히 작동. 이상 없음.

### (주의) 사용자 증상의 구체적 arvlCd 조합 검증
- 사용자 증상은 arvlCd=99 + positionStatus="도착". 해당 조합에서 `calculateInitialProgress` 반환값은 `0.0`. 이 값이 map.html의 (a)/(c) 분기에서 올바르게 사용되는지는 현재 테스트에서 JS 단 테스트가 없어 수동 검증에 의존. **권장**: 향후 flutter_js 또는 WebView 위젯 테스트로 map.html 로직 커버하면 완전. 다만 플랜 범위 밖이므로 본 리뷰에서 강제하지 않음.

## 불일치 사항

없음. 플랜과 구현이 의도/구조/파일 수준에서 모두 일치.

## 오버 엔지니어링 의심

### ➕ `lib/core/utils/line_direction.dart` 신규 분리 (81줄)

- **플랜 원문**: "findPathOnLine에 `isDown` 파라미터 추가" (3번 항목)만 명시, 신규 파일 분리는 미언급.
- **실제 구현**: `isDownBetween`을 `direction_resolver.dart`에서 core로 이동 후, features 측은 re-export로 하위 호환.
- **판단**: **허용 가능**.
  - 이유 1 (Clean Architecture 준수): `path_on_line.dart`는 `core/utils/`에 위치. core 레이어가 features에 의존하면 Clean Architecture 원칙 위반. 분리 필수.
  - 이유 2 (하위 호환): `direction_resolver.dart`에서 `export` 선언으로 기존 호출부(`isDownBetween`을 direction_resolver 경로로 import)가 수정 없이 동작.
  - 이유 3 (최소 추가): 81줄이지만 원본 함수들의 단순 이동 + 주석이 대부분. 신규 복잡도 없음.
  - 이유 4 (테스트 강화): `line_direction_test.dart` 추가로 경계 케이스(순환/진접선) 단위 검증이 오히려 강화됨.

### 기타 검토
- 불필요한 추상화 계층: 없음
- 사용되지 않는 파라미터: 없음 (isDown은 호출부에서 실제 사용)
- 현재 불필요한 미래 대비 코드: 없음
- 디버깅 로그 보강 제외 준수: `kDebugMode`/`debugPrint` 신규 추가 없음 확인 (live_train_provider.dart:138에 기존 로그만 존재)

## 결론

**Approve** — 플랜의 4개 항목이 모두 올바르게 구현되었고, 사용자 증상(2호선 중간 경유역에서 열차가 C를 건너뛰고 정체되는 현상)을 해결하는 방향으로 수정이 이루어졌다. 신규 파일(`line_direction.dart`) 분리는 core-features 의존 역전 방지를 위한 합리적 결정으로 판단. 테스트 70건 전원 통과로 회귀 위험도 낮음.

권장 후속 작업(선택, 본 리뷰 범위 밖):
- map.html의 "이어서 진행" 로직에 대한 브라우저/JS 단 단위 테스트 도입 검토 (현재는 Dart 테스트만 존재)
- 실제 2호선 중간 경유역 동작의 수동 검증 (실 디바이스 `--release` 빌드)
