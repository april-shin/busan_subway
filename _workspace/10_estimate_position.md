# Phase 2a 산출물 — graph-algorithm-engineer

## 변경/추가 파일

| 경로 | 상태 |
|---|---|
| `lib/core/utils/estimate_train_position.dart` | 신규 |
| `lib/core/utils/line_direction.dart` | 추가(`findPreviousStationId`), 기존 함수 불변 |
| `test/core/utils/estimate_train_position_test.dart` | 신규 |
| `test/core/utils/line_direction_test.dart` | 추가(`findPreviousStationId` 케이스) |

## 공개 API

### `estimate_train_position.dart`

```dart
typedef TrainPositionResult = ({
  bool outOfPath,
  int segmentIndex,
  double progress,
  bool isDwelling,
  int remainingAfterPath,
});

TrainPositionResult estimateTrainPosition({
  required int remainingSeconds,
  required List<int> segmentTravelTimes,
  required int dwellSeconds,
});
```

의미:
- `segmentIndex`: 주행 중이면 해당 세그먼트 인덱스(`path[i] → path[i+1]`).
  정차 중이면 "직전 세그먼트 인덱스 i" = 정차 중인 역은 `path[i]`.
- `progress`: 주행시 `(s[i]-t_rem)/s[i]`, 정차시 0.0.
- `isDwelling`: 정차 플래그.
- `outOfPath`: true면 경로 앞쪽 확장 필요. `remainingAfterPath` 는 경로 시작점보다 더 뒤에 남은 초.

경계 규칙(고정):
- `remainingSeconds <= 0` → 도착(`segIdx=n-1, progress=1.0`).
- `t_rem == s[i]` → 주행 쪽 귀속(`progress=0.0`).
- `t_rem == dwell` → 정차 쪽 귀속.
- 단일 세그먼트(`n==1`) → dwell 없음.
- `segmentTravelTimes.isEmpty` → `ArgumentError`.

### `line_direction.dart` (추가)

```dart
String? findPreviousStationId({
  required String currentId,
  required String lineId,
  required bool isDown,
  required List<Connection> connections,
});
```

동일 노선(`lineId`)의 비환승 인접 연결만 순회하여, `other → currentId` 방향이 `isDown` 과 일치하는 첫 인접역을 반환. 없으면 null.

## 알고리즘 복잡도

- `estimateTrainPosition`: O(n) (n = 세그먼트 수, 최대 30 — 안전 상한)
- `findPreviousStationId`: O(|connections|) 선형 스캔

## 검증

- `flutter analyze lib/core/utils/estimate_train_position.dart lib/core/utils/line_direction.dart` → **No issues found**
- `flutter test test/core/utils/estimate_train_position_test.dart test/core/utils/line_direction_test.dart` → **52/52 passed**

커버된 케이스:
- 검증 예시 t=120, t=80 고정 통과
- 경계값 t=0, t=60, t=90, t=150, t=151
- 단일 세그먼트 t=30/60/61
- 빈 배열 ArgumentError
- 3 세그먼트 중간 정차
- `findPreviousStationId`: 1호선(하행/상행/경로끝/환승무시/타노선무시), 2호선 순환 4종(내·외선 및 201↔243 경계), 4호선 본선/진접선 경계 7종

## 후속 단계 호환

- `_workspace/00_requirements.md` 4항 `dwellTimeSeconds` 전역 상수 인자로 주입받도록 설계 → realtime-data-engineer 가 값만 전달하면 됨.
- outOfPath 시 `remainingAfterPath` 반환 → 호출측에서 `findPreviousStationId` 로 경로 prepend 후 재호출하는 루프가 자연스럽게 동작.
- `Connection` 엔티티 구조 변경 없음(제약 준수).
