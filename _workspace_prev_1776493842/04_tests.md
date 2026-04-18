# 04 — 테스트 작업 결과

## 작성/수정한 테스트 파일

### 1. 신규 작성
- **`test/core/utils/line_direction_test.dart`** — `isDownBetween` 전용 단위 테스트
  - 일반 노선: ID 증가/감소, 알파벳 접두사(K/D), 숫자 추출 실패 케이스
  - 2호선 순환: 인접 내선/외선, 순환 경계(201↔243, |step|>21 반전), 인접 경계
  - 4호선: 본선/진접선 내부, 진접선↔본선 경계 (449-452 특수 처리)
  - 방어적 케이스: 같은 ID, 빈 문자열

### 2. 기존 업데이트
- **`test/core/utils/path_on_line_test.dart`**
  - `calculateInitialProgress` 테스트 업데이트
    - `arvlCd == 0` (진입) → **0.85 → 0.0** (구현 변경에 맞춰 수정)
    - `arvlCd == 4` (전역진입) → 0.0 신규 케이스 추가
    - `positionStatus == '진입'` → **0.85 → 0.0**
    - arvlCd 3/5, 알 수 없는 코드, arvlCd 99+'진입' 케이스 추가
  - `findPathOnLine - isDown 방향 제한 (순환선)` 신규 그룹 추가 (6개 케이스)
    - 가짜 4역 순환선으로 BFS 방향 제한 동작 검증
    - `isDown=null` (양방향), `isDown=false` (내선 전용), `isDown=true` (외선 전용) 시나리오별 경로 결과 비교
    - 방향 제한이 경로를 아예 차단할 수 있음을 확인 (순환 우회 방지)

### 3. 검증
- **`test/features/route_search/utils/direction_resolver_test.dart`** — 수정 없음
  - `isDownDirection(RouteSegment)` 기존 테스트 23개 모두 통과
  - `isDownBetween`이 core로 이동되고 re-export된 이후에도 동작 동일 확인

## 실행 결과

```
flutter test test/core/utils/line_direction_test.dart \
             test/core/utils/path_on_line_test.dart \
             test/features/route_search/utils/direction_resolver_test.dart
```

**결과:** `00:00 +70: All tests passed!`

- `line_direction_test.dart` — 23개 테스트 전부 통과
- `path_on_line_test.dart` — 24개 테스트 전부 통과 (기존 16 + 신규 8)
- `direction_resolver_test.dart` — 23개 테스트 전부 통과 (기존 유지)

## 주요 변경 근거

### `calculateInitialProgress` 의도 변경
`initialProgress`는 "currentStation → next 세그먼트 내 진행률(0.0~1.0)"로 정의된다.
'진입'(arvlCd 0, 4, positionStatus '진입')은 열차가 currentStation의 *이전* 세그먼트 끝에 있는 상태이지만, 이 함수 구조에서는 이전 세그먼트를 표현할 수 없다.
따라서 이전 구현의 0.85(next 세그먼트를 거의 끝낸 것처럼 표시)는 의미상 부정확하고, currentStation 위치 근사인 0.0으로 변경한 것이 올바른 의도 반영이다.
테스트 설명에 근거를 한국어로 기록했다.

### `findPathOnLine`의 `isDown` 파라미터
2호선 같은 순환선에서 BFS가 반대 방향으로 우회해 엉뚱한 경로를 뽑는 문제 방지용.
테스트는 가짜 4역 순환선으로 방향별 인접 엣지가 어떻게 구성되는지와, 방향 제한이 경로 없음(null)을 유발할 수 있음을 검증한다.

## 제약 준수
- `pubspec.yaml` 수정 없음.
- mocktail 미사용 (순수 함수 단위 테스트라 모킹 불필요).
- 모든 `group`/`test` 라벨 한국어.
- 한국어 주석으로 각 테스트의 근거 기록.
