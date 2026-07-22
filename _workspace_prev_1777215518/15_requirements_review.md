# 요구사항 리뷰

## 요약

충족률: **10/10 (100%)** — 사용자의 원래 요청(검증 예시 2건)과 AskUserQuestion 으로 확정된 정책 6가지가 모두 구현에 반영되었으며, 검증 예시는 단위 테스트로 고정되었다. 오버 엔지니어링 의심 요소 없음. **판정: Approve.**

## 원래 요청 재인용

> A-B-C 구간, C=출발점, A-B=60초, B-C=60초, 정차 30초 가정.
> 1) 남은시간 120초 → A-B 정중앙 (progress 0.5)
> 2) 남은시간 80초 → B역 정차 중 (잔여 정차 20초)

## 검증 예시 테스트 고정 여부

**두 예시 모두 단위 테스트로 고정되어 통과**
`test/core/utils/estimate_train_position_test.dart`:

| 예시 | 테스트 라인 | 기대값 | 결과 |
|---|---|---|---|
| t=120 | L7–15 | segIdx=0, progress=0.5, isDwelling=false | PASS |
| t=80 | L19 이후 | segIdx=1, progress=0.0, isDwelling=true | PASS |

경계값 추가 고정: t=0(도착), t=60(주행/정차 경계 → 주행), t=90(B 정차 막 시작), t=150(A-B 시작 progress=0.0), t=151(outOfPath) 등. 전체 52/52 통과.

## 정책 6가지 구현 매핑

| # | 정책 | 구현 위치 | 상태 |
|---|---|---|---|
| 1 | pathToTarget 시작점: arvlMsg3 유지 | `live_train_provider.dart:214` (`currentName = arrival.currentStationName`) — enrichArrivalInfo 의 arvlMsg3 파생값 사용, 기존 경로 유지 | 충족 |
| 2 | 남은시간 > 총시간 → currentStationName 으로 경로 확장, 무제한(소진까지) | `expand_path_backward.dart:57–102` — `targetRemainingSeconds <= accumulatedTotal` 될 때까지 루프. 30칸 안전 상한 + 방문 set 으로 순환선 방어 | 충족 |
| 3 | 정차 중 시각화: B 위치에 멈춤 (별도 표시 없음) | Dart: `estimate_train_position.dart:86–94` (isDwelling 시 segmentIndex=i, progress=0.0). JS: `map.html:2129–2131` (`pos = path[res.segmentIndex]`). 별도 아이콘/배지 없음 | 충족 |
| 4 | arvlMsg3 vs 남은시간 충돌: arvlMsg3 우선 | `live_train_provider.dart` — currentName 을 경로 기준점으로 사용. 남은시간이 초과돼도 경로를 앞으로 확장할 뿐 currentName 자체는 건드리지 않음 | 충족 |
| 5 | 정차시간: 전역 고정 `dwellTimeSeconds` 재사용 | `live_train_provider.dart:318` (`dwellSeconds: dwellTimeSeconds`). `expand_path_backward.dart` 내부에서도 동일 상수 사용. JS 는 필드로 전달받음 | 충족 |
| 6 | map.html 애니메이션: 기존 함수 전부 교체 | `map.html:2091–2153` 재작성. 이전 개념(`bestT`/`sliceOffset`/"이어서 진행"/시간 가중 보간/arrivalSeconds≤2 보정) 전면 제거. `showTrains` 의 "도착 임박 유지" 분기도 제거 | 충족 |

## 사용자 증상 대비 개선 논리

- **이전 방식의 문제**: segmentDurations 가 "주행+dwell 합산" 이라 정차 구간에서도 전 구간 보간이 진행돼 정차 역에서 미세 이동이 발생. 총 duration 과 arrivalSeconds 가 어긋나면 전체 경로가 밀림.
- **새 방식의 해결**: 매 frame 실시간 남은시간을 역산해 "정확히 몇 초 전 시점인지"를 결정 → 주행/정차 구분 명확. receivedAtEpochMs 기준 시계 보정으로 refresh 간 점프 최소화. 남은시간이 경로 시간을 넘으면 Dart 에서 이전 역을 prepend 해 "뒤에 있는 상태" 를 좌표로 표현.
- 사용자 시나리오 (A-B-C, t=120 / t=80) 가 시각적으로 정확히 의도대로 동작할 알고리즘이 확립됨.

## 누락된 엣지 케이스

모두 **커버됨**:

| 케이스 | 처리 |
|---|---|
| arrivalSeconds = 0 | `estimateTrainPosition`: remainingSeconds<=0 → 마지막 세그먼트 끝 고정 (L53–61) |
| pathToTarget 단일 점(n=0) | JS `map.html:2102` path.length===1 → 좌표 고정 + 즉시 도착 이펙트. Dart 는 `segmentTravelTimes.isEmpty → ArgumentError` 로 명시적 차단 |
| elapsed > arrivalSeconds | JS `map.html:2122` `Math.max(0, ...)` 로 음수 방지 → outOfPath 아닌 "도착"으로 수렴 |
| segmentDurations 길이 불일치 | JS `map.html:2110` path[0] 고정 + 이펙트 없이 return |
| 순환선(2호선) 확장 무한루프 | `expand_path_backward.dart:51,67` 방문 set |
| 안전 상한 초과 | 30칸 for-guard |
| Station 조회 실패 | prevCandidates null/empty → break |
| 단일 세그먼트 (dwell 적용 안 함) | `estimate_train_position.dart:85` `if (i > 0)` 조건으로 차단. 테스트 고정 |
| 경계값 t == segTime / t == dwell | `<=` 로 주행/정차 쪽에 귀속하도록 명시. 테스트 고정 |
| 네트워크 오류 시 | `live_train_provider.dart:163` `_lastSuccessfulTrainsProvider` 로 마지막 데이터 유지 |

## 오버 엔지니어링 의심

**없음.** 추가 점검:

- `estimate_train_position.dart` — 알고리즘과 1:1 대응. 불필요한 추상화 없음.
- `expand_path_backward.dart` — 30칸 상한과 방문 set 은 요구사항 명시. `hadAnySegment` 분기(단일 점에서 첫 prepend 시 dwell 생략)도 실제 회계 정확성에 필요.
- `LiveTrain.initialProgress` 필드는 **유지**했지만(0.0 기본), JS 로직에서 더 이상 읽지 않음. 기존 호출처 호환용으로 보수적 유지 — 과한 보수도 아님.
- `map.html` 의 `projectOnPolyline` / `expandPathWithSnap` / `getSnappedSlice` 는 *보존*되어 있지만 `startTrainAnimation` 은 호출하지 않는다. 12_map_html_rewrite.md 에 "향후 필요시를 위해 파일에 보존" 이라고 의도 명시. 기존 자산이며 이번에 추가된 코드가 아니므로 오버 엔지니어링이 아님.
- 디버그 패널 `prog: initialProgress` 라벨은 유지 — 범위 관리(최소 변경) 차원에서 합리적.

## map.html 교체 완전성 검증

- `startTrainAnimation` (L2091–2153): 신규 `estimateTrainPosition` 루프만 사용. 이전 흔적 없음.
- 파일 전체 grep 결과:
  - `bestT` / `bestDist`: `projectOnPolyline` 유틸에만 존재 (별도 함수, startTrainAnimation 밖). 의도적 보존.
  - `sliceOffset`: 0건.
  - `이어서 진행`: 0건.
  - `showTrains` 내부 "도착 임박 유지" 분기: 제거됨 (L2210–2224 일관 처리, 주석 L2211–2212 로 제거 사유 명시).

## 결론

**Approve.** 모든 요구사항 · 정책 · 엣지 케이스가 구현과 테스트에 반영되어 있다. 오버 엔지니어링 없음, 불변 패턴 준수, flutter analyze 통과, 관련 단위 테스트 100% 통과. 회귀 없음(기존 393 tests pass, 1 실패는 외부 API 통합 테스트로 본 작업과 무관).

### 선택적 후속 (비차단)

우선순위 낮음 — 별도 작업으로 분리해도 무방:

1. `LiveTrain.initialProgress` 필드 및 `calculateInitialProgress` 호출 제거 (현재 JS 가 읽지 않음). 동반: `live_train_provider.dart:242–245, 272–274, 320, 374`.
2. 디버그 패널 라벨을 `arvSec` / `isDwelling` 실시간 표시로 갱신 (12_map_html_rewrite.md 에도 별도 작업 명시).
3. `updateTrainDebugInfo` 존재 여부와 연동 점검 (본 리뷰 범위 밖).
