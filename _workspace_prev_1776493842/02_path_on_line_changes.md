# 02. path_on_line.dart 및 direction_resolver.dart 변경 요약

## 수정 파일

1. `lib/core/utils/path_on_line.dart`
2. `lib/features/route_search/utils/direction_resolver.dart`

## 작업 1: `calculateInitialProgress` 진입 매핑 정정

- 파일: `lib/core/utils/path_on_line.dart`
- 변경:
  - `arvlCd == 0` (진입): `0.85` → `0.0`
  - `arvlCd == 4` (전역진입): `0.85` → `0.0`
  - `positionStatus == '진입'`: `0.85` → `0.0`
- 근거 주석을 함수 doc과 각 case 옆에 추가:
  > "진입 상태에서는 열차 위치를 currentStation 근사로 표시 (실제로는 이전 세그먼트 끝이지만 initialProgress 구조상 정밀 표현 불가 → currentStation 위치로 근사)"
- 유지된 매핑: 1 (0.0), 2 (0.15), 3 (0.15), 5 (0.0), '출발' (0.15), '도착' (0.0), default (0.0)

## 작업 2: `findPathOnLine` 방향 제한 파라미터 추가

- 파일: `lib/core/utils/path_on_line.dart`
- 변경:
  - 시그니처에 `bool? isDown` 선택 파라미터 추가 (기본 null = 기존 양방향 동작).
  - adjacency 구축 단계에서 `isDown`이 non-null인 경우, 각 connection의 방향을 `isDownBetween(from, to, lineId)`로 판정하여 요청 방향과 일치하면 `from→to` 단일 엣지, 불일치하면 `to→from` 단일 엣지만 추가 (역방향 edge 차단).
  - `travelTimeMap`은 기존과 동일하게 양쪽 키로 저장 (BFS 역추적 시 값 조회 용이).
  - BFS 함수 자체는 건드리지 않음 (adjacency 필터링만으로 방향 제한 달성).
- 호환성: 기존 호출부(isDown 미지정)는 기존 동작 유지.
- import: `../../features/route_search/utils/direction_resolver.dart` 추가.

## 작업 3: direction_resolver.dart 리팩토링 (공유 로직 추출)

- 파일: `lib/features/route_search/utils/direction_resolver.dart`
- 신규 public 함수:
  - `bool isDownBetween(String fromId, String toId, String lineId)` — 두 역 ID와 노선 ID로 방향 판정.
    - 일반 노선: `toNum > fromNum`
    - 2호선: `_isLine2DownBetween(fromNum, toNum)` — step 부호와 |step|>21 반전 유지
    - 4호선: 기존 `_isLine4Down(fromNum, toNum)` 재사용
    - 숫자 ID 추출 실패 시 false 반환
- 기존 `isDownDirection(RouteSegment segment)`는 내부적으로 `isDownBetween`을 호출하도록 리팩토링:
  - 2호선: `isDownBetween(first.id, stations[1].id, '2')`
  - 그 외: `isDownBetween(first.id, last.id, lineId)`
- 기존 private `_isLine2Down(segment, firstNum)` 함수는 제거 후 `_isLine2DownBetween(fromNum, toNum)`으로 대체 (로직 동일).
- `_parseNumericId`, `_isLine4Down`, `findFirstDirectionalSegment`, `isDownDirectionString`은 그대로 유지.

## 동작 동일성 검증

리팩토링 후에도 `isDownDirection(segment)` 결과가 기존과 완전 일치:
- 일반 노선: 기존 `lastNum > firstNum` ≡ `isDownBetween(first, last)` → `toNum > fromNum` (동일)
- 2호선: 기존 `_isLine2Down(segment, firstNum)` (firstNum + segment.stations[1]) ≡ `isDownBetween(first.id, stations[1].id, '2')` (동일 로직)
- 4호선: 기존 `_isLine4Down(firstNum, lastNum)` ≡ `isDownBetween(first.id, last.id, '4')` → `_isLine4Down(fromNum, toNum)` (동일)

## 검증

- `flutter analyze`: 수정 파일에 대해 이슈 없음 (`No issues found`).
- 기타 기존 `tool/test_timetable_api.dart`의 `avoid_print` info는 이번 변경과 무관.

## 제외 사항

- 호출부(live_train_provider.dart, estimate_arrival_seconds.dart) 수정 — 다음 단계 범위.
- 테스트 작성 — flutter-qa-engineer 단계에서 수행.
