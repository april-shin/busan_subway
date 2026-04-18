# 코드 리뷰 결과

## 요약

**판정: 승인 (MEDIUM 이슈 2건, LOW 이슈 3건, 칭찬 다수)**

이번 변경은 버그의 근본 원인을 정확히 짚었고, 아키텍처 의존 방향(core ← features)을 올바른 쪽으로 바로잡는 좋은 리팩토링도 함께 수행되었다. 불변성·네이밍·테스트 커버리지 모두 양호하다. CRITICAL/HIGH 이슈 없음. 수정 없이 머지 가능하나, 아래 MEDIUM 이슈는 후속 리팩토링에서 반영을 권장한다.

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 2
- LOW: 3

---

## CRITICAL 이슈

없음.

---

## HIGH 이슈

없음.

---

## MEDIUM 이슈

### M1. `bestT <= 0.001` 분기의 segTimes 첫 원소 선택 근거가 약함

**파일:** `assets/html/map.html:1913-1918`

```js
if (bestT <= 0.001) {
  animPath = [{ x: curX, y: curY }].concat(path.slice(bestSeg));
  if (hasDurationsForBranch) {
    // 첫 세그먼트(curPos→path[bestSeg])는 거의 0거리이므로
    // 원 세그먼트 시간을 그대로 사용(근사). 이후는 원본 시간 유지.
    segTimes = [segDurations[bestSeg]].concat(segDurations.slice(bestSeg));
  }
  initProgress = 0;
}
```

**문제:** curPos→path[bestSeg] 가 "거의 0거리"인 상황에서 해당 구간에 `segDurations[bestSeg]` (즉, 다음 구간의 운행 시간)을 그대로 할당한다. 총 시간 분모가 실제보다 한 세그먼트분 부풀어오르며, 분기 (c)의 `segDurations[bestSeg] * (1 - bestT)` 보정(정확)과 대조된다. 결과적으로 이 분기에서 열차가 평균보다 약간 느리게 이동한다.

**수정 제안:** 첫 구간 시간을 0 또는 작은 상수(예: 50ms에 해당하는 0.05초)로 두는 편이 의미적으로 더 정확하다. 분기 (c)와 대칭되도록 `segDurations[bestSeg] * (1 - bestT)`로 두면 bestT≈0일 때 `segDurations[bestSeg] * 1` 이 되어 **다음 세그먼트 시간과 중복**되므로 유의. 실제 의도는 "첫 구간은 0거리, 둘째 구간부터 원래 시간"이므로 다음 중 하나를 권장한다.

```js
// 안 1: 첫 구간 시간을 0으로 (useTimes 분기에서 segProgress 계산이 0으로 처리됨)
segTimes = [0].concat(segDurations.slice(bestSeg));

// 안 2: 매우 작은 값 (divide-by-zero 회피가 필요하면)
segTimes = [0.001].concat(segDurations.slice(bestSeg));
```

현 코드도 실용상 큰 시각적 문제는 없으나, 버그 수정 PR의 맥락에서 "근사" 주석보다는 정확한 모델을 권장.

---

### M2. `findPathOnLine`에서 역 이름 중복 시 `isDown` 조합에 따라 O(N²) 탐색

**파일:** `lib/core/utils/path_on_line.dart:75-95`

```dart
for (final fromId in fromIds) {
  for (final toId in toIds) {
    final path = bfs(fromId, toId, adjacency);
    if (path != null) { ... }
  }
}
```

**문제:** `nameToIds`는 환승역처럼 동일 이름이 여러 노선 ID에 매핑될 때 필요하지만, 여기서는 이미 `lineId` 필터링 후이므로 대부분 1개이고, BFS가 최악에 `|fromIds| * |toIds|` 번 호출된다. `isDown`이 지정된 상태에서 경로가 아예 존재하지 않는 경우 BFS가 매번 전체 그래프를 전수 탐색하므로 불필요한 비용.

**영향도:** 실측 노선 데이터에서는 이름 충돌이 드물어 실제 비용은 크지 않다. 다만 2호선처럼 성수지선(성수·신설동·용두 등) 중복이 있는 경우 O(2×2) = 4회 BFS가 일어날 수 있음.

**수정 제안:** 첫 경로를 찾으면 즉시 return하고 있으니 정확도엔 문제가 없으나, BFS 실패 시 조기 종료를 위해 시작 노드에서 외부로 나가는 엣지가 하나도 없는 경우 스킵 등을 고려할 수 있음. 현재 변경과 직접적인 관련은 없으니 LOW/후속으로 분류해도 무방.

---

## LOW 이슈

### L1. `line_direction.dart`의 `_parseNumericId` 정규식이 복합 ID를 잘못 파싱할 여지

**파일:** `lib/core/utils/line_direction.dart:76-80`

```dart
int? _parseNumericId(String id) {
  final match = RegExp(r'(\d+)$').firstMatch(id);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
```

현재 구현은 문자열 끝의 연속 숫자를 취한다. 테스트(`'K10'→10`, `'D10'→10`)는 통과하지만, "101-2" 같은 형식이 미래에 유입되면 "2"가 추출된다. 현재 데이터셋에는 없어 문제 없음. 주석으로 가정을 명시하거나 전체 문자열이 `^\D*(\d+)$` 형식을 갖도록 보수적으로 검증하는 것이 방어적임.

### L2. `path_on_line.dart`의 isDown 분기 내 주석이 독자에게 반직관적일 수 있음

**파일:** `lib/core/utils/path_on_line.dart:57-66`

"connection의 from→to 방향이 요청 방향과 같으면 from→to만, 반대면 to→from만 추가(역방향 edge 차단)" — 맞는 설명이지만 "역방향 edge 차단"이라는 문구가 "항상 한 방향만 남긴다"로도 읽혀 혼란 여지가 있다. `connection`의 from/to는 데이터 편집 편의상 임의로 기록되어 있으며, 실제 "하행/상행"은 `isDownBetween`이 결정한다는 점을 한 줄 더 부기하면 좋다.

### L3. `live_train_provider.dart` 주석에 `isDown` 근거 누락

**파일:** `lib/features/subway_map/presentation/providers/live_train_provider.dart:195-203`

호출 직전 주석이 "현재역 → 출발역 경유 좌표 및 세그먼트 소요시간 계산" 뿐이다. 2호선 순환선 반대방향 우회를 방지하기 위해 `isDown`을 넘긴다는 의도는 `_workspace/03_live_train_provider_changes.md`에만 기술돼 있다. 인라인에 "// 순환선 반대 방향 우회 방지" 정도의 한 줄 주석을 추가하면 향후 독자가 바로 이해 가능.

---

## 긍정 평가

### 아키텍처 정리 (highlight)
- **`lib/core/utils/line_direction.dart`** 신설로 core가 features에 의존하던 잘못된 방향을 올바르게 반전시킨 점이 훌륭하다. `direction_resolver.dart`는 `export 'line_direction.dart' show isDownBetween;` 로 호환성을 유지해 호출부 대대적 수정 없이 안전하게 리팩토링됐다.
- CLAUDE.md의 레이어 의존 방향(core → domain ← data ← features)과 정확히 부합.

### 불변성 및 코드 스타일
- `path_on_line.dart`의 adjacency/travelTimeMap 모두 로컬 `Map`을 새로 구성하며 입력 컬렉션을 변경하지 않음.
- `map.html` 변경도 `path.slice`/`concat`으로 새 배열 생성, 원본 `path`/`segDurations` 불변.
- 파일 크기 모두 기준(800줄) 이내. `line_direction.dart` 80줄, `path_on_line.dart` 165줄로 적절한 크기.

### 버그 수정의 정확성 (map.html)
- `bestT`를 보존해 "curPos가 path[bestSeg]의 앞/중간/뒤" 세 경우로 분기한 설계가 수학적으로 정확. 특히 (c) 분기의 `segDurations[bestSeg] * (1 - bestT)` 는 기존 근사보다 개선된 정확한 시간 보정이다.
- `remainingAfter.length` 분기별 early return으로 `animPath.length < 2` 상황에서도 안전하게 목적지 고정.
- `sliceOffset = -1` 플래그로 "이어서 진행 분기에서 이미 segTimes가 확정됨"을 하단 fallthrough에 알리는 구조도 깔끔.

### `calculateInitialProgress` 의미 정정
- 기존 0.85 매핑이 "진입" 상태의 위치를 실제 좌표와 반대로 배치하던 문제(currentStation 이전 세그먼트 끝을 다음 세그먼트 거의 끝 지점으로 표시)를 올바르게 0.0으로 정정. doc 주석에 구조적 한계("initialProgress 구조상 이전 세그먼트 표현 불가")까지 명시해 독자가 설계 의도를 이해할 수 있음.

### 테스트 커버리지
- `line_direction_test.dart` 23건은 일반/2호선/4호선/방어적 케이스를 포괄적으로 커버. 각 케이스에 `step` 계산과 `|step|>21` 경계 설명을 한국어로 부기해 가독성이 매우 좋다.
- `path_on_line_test.dart`의 "isDown 방향 제한 (순환선)" 그룹은 가짜 4역 순환선으로 **경로 없음 케이스까지** 명시적으로 검증한다(외선 전용에서 A→C null, D→A 성공 등). 방향 제한이 의도와 다르게 과도하게 작동하지 않는지 확인하기에 훌륭한 설계.
- `calculateInitialProgress` 테스트 주석에서 정정 이유("0.85 → 0.0")를 명시적으로 기록.

### Riverpod 패턴 유지
- `live_train_provider.dart`는 기존 `ref.watch(activeRouteFilterProvider)` 결과의 `isDown`을 재사용해 신규 의존성 추가 없이 방향 정보를 전달. Riverpod 의존성 그래프가 건드려지지 않은 점이 안전.

---

## 보안/성능 스캔 결과

- 하드코딩 시크릿 없음.
- JS 인젝션 위험 없음 (map.html 변경은 모두 SVG transform 문자열 생성이며, 외부 입력이 숫자 좌표로 한정).
- 성능 회귀 없음 (BFS 자체는 변경 없음, adjacency 구축에 O(E) 추가 작업).
- 타이머/리소스 누수 없음.
- console.log/print 신규 유입 없음.

## 프로젝트 특수 규칙 검토

- 노드 ID 형식 `"{stationId}_{lineId}"`: 본 변경 범위에서 신규 노드 생성 없음. `findPathOnLine` 내부는 단일 노선에서만 동작하므로 순수 `stationId` 사용이 적절.
- `@freezed`/`@riverpod` 스키마 변경 없음 → `build_runner` 재실행 불필요.
- SVG 파이프라인 비대상 (map.html의 startTrainAnimation은 HTML 내부 JS, SVG 데이터 재생성과 무관).
- `--release` 빌드 코드 없음.
