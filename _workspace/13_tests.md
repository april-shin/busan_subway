# Phase 2c 산출물 — flutter-qa-engineer

## 추가/수정된 테스트 파일

| 경로 | 상태 | 내용 |
|---|---|---|
| `test/core/utils/expand_path_backward_test.dart` | 신규 | `expandPathBackward` 10개 케이스 |

기존 테스트 파일(`estimate_train_position_test.dart`, `line_direction_test.dart`, `path_on_line_test.dart`, `estimate_arrival_seconds_test.dart`, `enrich_arrival_info_test.dart` 등)은 **수정 없음**.

## `_expandPathBackward` 추출

**접근 A 적용.** 기존 `live_train_provider.dart` 내부 file-private 함수
`_expandPathBackward` 와 typedef `_ExpandedPath` 를 `core/utils/` 로 분리.

### 신규 모듈

- **경로:** `lib/core/utils/expand_path_backward.dart`
- **공개 API:**
  - `typedef ExpandedPath = ({ List<({double x, double y})> points, List<int> durations })`
  - `ExpandedPath expandPathBackward({ required List<({double x, double y})> basePoints, required List<int> baseDurations, required String currentStationId, required String lineId, required bool isDown, required List<Connection> connections, required Map<String, List<Station>> stationsById, required int targetRemainingSeconds })`

### live_train_provider.dart 변경

- `_expandPathBackward`, `_ExpandedPath` 로컬 정의 **삭제**
- `expand_path_backward.dart` **import 추가**
- 호출부 `_expandPathBackward(...)` → `expandPathBackward(...)`
- 불필요해진 import 정리: `line_direction.dart` (isDownDirectionString 은
  `direction_resolver.dart` 에 존재), `connection.dart`
- 로직/공개 시그니처 **변경 없음**

### 검증

- `flutter analyze lib/features/subway_map/presentation/providers/live_train_provider.dart lib/core/utils/expand_path_backward.dart` → **No issues found**
- `flutter analyze lib/` → 14 warnings (모두 기존 `arrival_info_dto.dart` JsonKey 경고, 본 작업 무관)
- `dart run build_runner build --delete-conflicting-outputs` → 성공

## `expandPathBackward` 테스트 케이스 (10개)

| 그룹 | 케이스 |
|---|---|
| 확장 불필요 | 남은시간이 총시간 이하 → 원본 그대로 |
| 확장 불필요 | `targetRemainingSeconds=0` → 원본 그대로 |
| 1칸 확장 | 남은시간이 한 세그먼트만큼 더 필요 → 앞에 1칸 prepend (좌표/duration 정확) |
| 1칸 확장 | 단일 점(세그먼트 0) + 1칸 확장: dwell 없이 주행만 추가 |
| 여러 칸 확장 | 큰 남은시간 → 여러 번 prepend (순서 정확, ID 오름차순) |
| 안전 상한(30칸) | 100역 체인 + 무한대 남은시간 → 정확히 30칸 prepend (path.length=31) |
| 순환 방어 | 2호선 순환선(닫힌 체인) → 방문역 재진입 차단, 중복 좌표 없음 |
| findPreviousStationId==null | 노선 말단역(하행 방향 101) → 확장 불가, 원본 유지 |
| Station 조회 실패 | prevId 가 stationsById 에 없음 → 즉시 종료 |
| dwell 회계 | 확장 후 총시간 = 주행 합 + 중간역 dwell 일치 검증 |

## 회귀 점검 결과

- `flutter test test/core/ test/data/ test/features/` → **255/255 passed** (새 변경 영향 없음)
- `flutter test test/core/utils/expand_path_backward_test.dart` → **10/10 passed**

### 주의해서 점검한 테스트

- `test/core/utils/path_on_line_test.dart`: `findPathOnLine` 의 durations 의미는
  원래 "주행시간만" → 영향 없음. 기존 테스트 그대로 통과.
- `test/core/utils/estimate_arrival_seconds_test.dart`: 수식 유지 → 영향 없음.
- `test/core/utils/enrich_arrival_info_test.dart`: 내부 dwell 처리 로직 영향 없음.

## 최종 `flutter test` 결과

- **393 passed, 1 failed**
- 실패 1건: `test/integration/realtime_arrival_all_stations_test.dart` (setUpAll)
  — 서울 열린데이터 API 를 실제 호출하는 통합 테스트로, 환경(API 키/네트워크)
  이슈. 태스크에서 환경 문제 무시 가능으로 명시.

그 외 모든 단위·위젯·프로바이더·도구 테스트 통과.

## 불변 패턴 준수

- `expand_path_backward.dart` 내부 — `insert`, 인덱스 대입 없음.
  역순 누적 리스트 빌드 후 새 리스트 생성.
- 테스트 헬퍼도 `for-in` 내포 리스트로 새 객체 생성만 사용.
