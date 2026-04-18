# 03 — live_train_provider.dart 변경 내역

## 목적

`findPathOnLine`에 추가된 `bool? isDown` 선택 파라미터를 실시간 열차 추적 경로 계산에 전달한다. 이를 통해 2호선 순환선 등에서 활성 경로의 방향과 일치하는 경로가 올바르게 뽑히도록 보장한다.

## 수정 파일

- `lib/features/subway_map/presentation/providers/live_train_provider.dart`

## 변경 내용

`liveTrains` 프로바이더 내부의 `findPathOnLine` 호출부(약 라인 186~192)에 `isDown: routeFilter.isDown` 인자를 추가.

### Before

```dart
// 현재역 → 출발역 경유 좌표 및 세그먼트 소요시간 계산
final pathResult = findPathOnLine(
  fromStationName: currentName,
  toStationName: departureStationName,
  lineId: lineId,
  stations: stations,
  connections: connections,
);
```

### After

```dart
// 현재역 → 출발역 경유 좌표 및 세그먼트 소요시간 계산
final pathResult = findPathOnLine(
  fromStationName: currentName,
  toStationName: departureStationName,
  lineId: lineId,
  stations: stations,
  connections: connections,
  isDown: routeFilter.isDown,
);
```

## 근거

- `routeFilter`(= `activeRouteFilterProvider`)는 동일 함수 상단(라인 118)에서 이미 watch 중이며, 활성 경로의 `lineId`와 `isDown`(상/하행 방향) 정보를 담고 있다.
- 이 프로바이더는 라인 166~170에서 `trainIsDown != routeFilter.isDown` 으로 방향 필터링도 이미 수행 중이므로, 경로 계산에도 동일한 방향 정보를 넘기는 것이 일관성 있고 의미적으로 정확하다.
- 2호선(순환선) 같은 노선은 같은 두 역 사이에 두 개의 최단 경로(시계/반시계)가 존재할 수 있어, `isDown`이 없으면 잘못된 방향의 경로가 반환될 수 있다.

## 변경하지 않은 파일

- `lib/core/utils/estimate_arrival_seconds.dart`
  - 해당 파일의 `findPathOnLine` 호출은 `arvlMsg3`만 기반으로 동작하므로 방향 정보를 알 수 없다.
  - 따라서 `isDown`을 전달하지 않는 기존 동작(기본값 `null`)을 유지하는 것이 적절하다. (지침에 따라 변경하지 않음)

## 검증

```bash
flutter analyze lib/features/subway_map/presentation/providers/live_train_provider.dart
```

결과: `No issues found!` (1.7s)

## 다음 단계

- 이 호출부에 대한 단위 테스트 작성은 다음 단계에서 수행.
