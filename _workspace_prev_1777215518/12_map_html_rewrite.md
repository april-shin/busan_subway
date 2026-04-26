# map.html startTrainAnimation 재작성

## 대상 파일

`/Users/april/Idea/seoul_subway/assets/html/map.html`

## 변경 라인 범위 (재작성 후)

| 영역 | 라인 | 내용 |
|---|---|---|
| `createTrainIcon` 초기 위치 | 1806~1811 | `initialProgress` 기반 보간 → `path[0]` 단순 배치 |
| `estimateTrainPosition` (신규) | 2048~2076 | Dart 알고리즘 JS 포팅 |
| `startTrainAnimation` (전면 교체) | 2084~2145 | 매 frame 역산 루프 |
| `window.showTrains` 내 기존 열차 분기 | 2205~2218 | "도착 임박 유지" 분기 제거, 일관 처리 |

## 제거된 코드 요약

아래 모든 개념/로직이 startTrainAnimation 에서 완전히 사라짐:

1. **`expandPathWithSnap` 호출** — Dart 측에서 경로 좌표가 이미 확정된다는 전제. (단 `expandPathWithSnap` / `getSnappedSlice` 함수 자체는 향후 필요 시를 위해 파일에 보존. startTrainAnimation 에서는 호출하지 않음.)
2. **`bestT` / `bestSeg` / `minDist` 분기** — 기존 애니메이션의 현재 위치를 역산하기 위한 투영 로직. 매 frame 역산 방식에서는 불필요.
3. **"이어서 진행" 3분기** (`bestT <= 0.001` / `>= 0.999` / 중간) — sliceOffset/segTimes 조작. 전부 제거.
4. **시간 가중 보간 (`useTimes`)** — `initProgress * segTimes[0]` 오프셋, `targetTime` 누적 루프. 제거.
5. **SVG 거리 기반 폴백 (`totalDist`, `segDists`)** — 제거. 거리 기반 보간 완전 배제.
6. **`durationMs` 보정들** — `arrivalSeconds <= 2 && initialProgress >= 0.7 → 3000ms` / `<= 1 → 2500ms` 방어선 모두 제거.
7. **`initialProgress` 사용** — `startTrainAnimation` / `createTrainIcon` 양쪽에서 더 이상 읽지 않음. (Dart 측이 필드를 전달해도 무해.)
8. **`showTrains` 의 "도착 임박 유지" 분기** — `arrivalSeconds <= 2 && initialProgress >= 0.7` 조건으로 기존 애니메이션 보존하던 continue 분기 제거.

## 신규 로직 구조

### `estimateTrainPosition(remaining, segTravel, dwell)`

Dart `estimate_train_position.dart` 와 동일 알고리즘의 JS 포팅:

- `segTravel` 빈 배열 → `{ segmentIndex: 0, progress: 0, isDwelling: false }`
- `remaining <= 0` → 마지막 세그먼트의 끝 (`progress: 1.0`)
- 뒤에서부터 루프:
  - `t <= s[i]` 면 해당 세그먼트 내 `progress = (s[i] - t) / s[i]`
  - 아니면 `t -= s[i]` 후, `i > 0` 일 때 `t <= dwell` 이면 중간역 정차 (`isDwelling: true`, `progress: 0`), 아니면 `t -= dwell`
- 루프 소진 → `outOfPath: true, remainingAfterPath: t` (경로 확장이 안 된 상태의 시그널)

### `startTrainAnimation(trainState, trainData)` 구조

```
1. 입력 추출: path, segDurations, dwell
2. 엣지 처리:
   - path 비었거나 null → 조기 return (표시 없음)
   - path.length === 1 → 해당 좌표 고정 + playArrivalEffect, return
   - segDurations.length !== path.length - 1 → path[0] 고정, 이펙트 없이 return
3. receivedAt / baseArrival 확보
4. step() frame 루프:
   - realRemaining = max(0, baseArrival - (now - receivedAt)/1000)
   - res = estimateTrainPosition(realRemaining, segDurations, dwell)
   - 위치 결정:
       outOfPath → path[0]
       isDwelling → path[segmentIndex]
       else → lerp(path[i], path[i+1], progress)
   - transform 갱신
   - realRemaining <= 0 → playArrivalEffect 후 종료
   - 아니면 다음 frame 예약
```

## 함수 시그니처

`startTrainAnimation(trainState, trainData)` — **변경 없음** (제약 준수).

## 불변 패턴 준수

- `path` / `segDurations` 에 `slice()` / `push` / 인덱스 대입 등 일체 없음. 참조만 읽음.
- `pos` 객체는 매 frame 새로 생성 (기존 값 수정 없음).

## 보류 / Dart 측 연계

| 필드 | 현재 처리 | 비고 |
|---|---|---|
| `trainData.initialProgress` | **읽지 않음** (무해) | Dart 측 `LiveTrain` 정리는 realtime-data-engineer 담당 |
| `trainData.receivedAtEpochMs` | `Date.now()` 폴백 | Dart 측에서 필수 전달 필요 |
| `trainData.dwellSeconds` | `0` 폴백 | Dart 측에서 상수 전달 필요 |
| `trainData.segmentDurations` | "주행시간만" 전제 | Dart 측 의미 재정의와 정합 |

## 디버그 패널

`buildDebugGroup` 은 변경 없음. `prog: initialProgress` 라벨은 유지 (최소 변경 원칙, 범위 관리). 향후 `arvSec` / `isDwelling` 실시간 표시는 별도 작업.

## 검증 예시 동작 (수동 검토)

경로 A-B-C (s=[60,60], dwell=30, total=150):

| remaining | 루프 결과 | 위치 |
|---|---|---|
| 120 | i=1: t=120 > 60, t-=60 → 60; dwell=30 < 60, t-=30 → 30; i=0: t=30 <= 60, progress=(60-30)/60=0.5 | A-B 세그먼트 0.5 지점 |
| 80 | i=1: 80>60, t-=60 → 20; t=20 <= 30 → isDwelling, segmentIndex=1 | B 역 좌표 고정 |

요구사항의 검증 예시와 일치.
