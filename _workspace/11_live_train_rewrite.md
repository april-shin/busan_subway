# Phase 2b 산출물 — realtime-data-engineer

## 대상 파일

`/Users/april/Idea/seoul_subway/lib/features/subway_map/presentation/providers/live_train_provider.dart`

부수 재생성: `live_train_provider.g.dart` (build_runner 재실행, 시그니처 변화 없음)

## LiveTrain 클래스 필드 변경

### 추가 필드

| 필드 | 타입 | 의미 |
|---|---|---|
| `dwellSeconds` | `int` | 중간역 정차시간 상수(초). `dwellTimeSeconds` 값을 그대로 복사 전달. |
| `receivedAtEpochMs` | `int` | `arrivalSeconds` 기준 시각의 epoch ms. `arrival.receivedAt.millisecondsSinceEpoch`. |

`toJson()` 에도 두 필드 직렬화 추가.

### 유지 필드 (호환성)

- `initialProgress`: JS 신규 로직은 읽지 않음. 필드는 유지하여 무해하게 전달.

### 시그니처

`dwellSeconds`, `receivedAtEpochMs` 는 `required` 매개변수. 생성자 시그니처 전체를 기존 호출처(`_applyOverlapOffset` 내부, 메인 루프)에서 맞춰 수정.

## `segmentDurations` 의미 변경

- 기존: 각 세그먼트에 `dwellTimeSeconds` 합산("주행+정차").
- 신규: **주행시간만**. 정차는 JS가 `dwellSeconds` 필드로 분리 처리.
- 이에 따라 `_addDwellToDurations` 함수는 **완전 삭제**.

## 경로 확장 루프 (`_expandPathBackward`)

### 역할

`arrivalSecs` 가 `pathToTarget` 총 소요시간(주행합 + 중간역 dwell) 보다 크면,
`findPreviousStationId` 로 이전 역을 앞에 붙여 경로를 늘린다. 남은시간이
총시간 이하가 될 때까지 반복.

### 안전장치

- 방문 역 `Set<String>` — 순환선(2호선 등) 무한 루프 방어
- 안전 상한 `30` 칸 (`estimate_train_position.dart` 설계와 정합)
- `findPreviousStationId` 가 null 반환 → 종결
- `stationsById` 에 매핑 없음 → 종결

### 불변 패턴

- `basePoints` / `baseDurations` 는 읽기만 함 (mutate 금지).
- prepend 할 점들은 `reversedPrependPoints` / `reversedPrependDurations` 에
  **역순 누적**.
- 최종 조립 시 역순 순회하여 새 리스트로 생성:
  ```dart
  final points = <({double x, double y})>[
    for (var i = reversedPrependPoints.length - 1; i >= 0; i--)
      reversedPrependPoints[i],
    ...basePoints,
  ];
  ```
- `insert` / `List.add` 기반 mutate 접근 일체 없음.

### 총시간 누적 전략

확장 루프에서는 `totalWith(...)` 를 매 반복 재계산하지 않고,
`accumulatedTotal` 변수에 증분을 누적하여 O(확장 횟수) 성능 유지.

prepend 한 세그먼트로 인한 증분:
- 주행 `travelSecs` + 이전 첫 역이 중간역으로 전환되며 `dwellTimeSeconds` 추가
- 단, 원본이 0 세그먼트였고(단일 점) 첫 prepend 라면 dwell 없이 주행만 추가

## 기타 정리

- `_addDwellToDurations` 함수 **완전 제거** (호출처·정의 모두 삭제).
- `arrivalSecs` 추정 수식은 변경 없음. `durations` 가 원래 "주행시간만"이라는
  전제를 주석으로 명시.
- `currentStation.id` 기반 경로 확장 시작점 확보.
- 신규 import: `core/utils/line_direction.dart`,
  `domain/entities/connection.dart`.

## 검증

```
flutter analyze lib/features/subway_map/presentation/providers/live_train_provider.dart
→ No issues found! (ran in 1.7s)

flutter analyze lib/
→ 14 warnings (모두 기존 arrival_info_dto.dart JsonKey 경고, 본 작업 무관)

dart run build_runner build --delete-conflicting-outputs
→ Built with build_runner in 17s; wrote 9 outputs.
```

## 후속 단계 호환

- JS(`assets/html/map.html`) 는 `segmentDurations` 를 "주행시간만"으로,
  `dwellSeconds` / `receivedAtEpochMs` 를 필수 입력으로 받는다
  (`_workspace/12_map_html_rewrite.md` 와 정합).
- `estimate_train_position.dart` 의 알고리즘 기대값과 일치
  (`segmentTravelTimes` = 주행만, `dwellSeconds` 상수 주입).
- `liveTrainsProvider` 시그니처 불변 → 외부 consumer 영향 없음.
