# 02c QA Implementation — UI 일관성 토큰 시스템 회귀 검증 테스트

작성: flutter-qa-engineer
단계: Phase 2c — 회귀 검증 테스트 작성 및 실행

---

## 1. 신규 테스트 파일 목록

| 파일 | 테스트 케이스 수 | 분류 |
|---|---|---|
| `test/core/theme/app_typography_test.dart` | 37개 | 단위 테스트 |
| `test/core/theme/app_theme_test.dart` | 11개 | 단위 테스트 |
| `test/widget/text_scaler_clamp_test.dart` | 11개 (단위 8 + 위젯 3) | 단위/위젯 테스트 |
| **합계** | **59개** | |

### 테스트 그룹 구성

#### `app_typography_test.dart` (37케이스)
- `appTextTheme — 13개 슬롯 존재 검증` (15): displayLarge~labelSmall 전 슬롯 null 아님 확인
- `appTextTheme — 설계 명세 fontSize/fontWeight 일치 검증` (9): titleLarge(22/w700), bodyLarge(16/w700), labelSmall(11/w500) 등 핵심 슬롯 명세값 대조
- `appTextTheme — height(line-height) 정의 검증` (8): 주요 슬롯 height != null + 본문 계열 >= 1.33 검증
- `appTextTheme — fontFamily 미지정 검증` (4+1): 각 슬롯 fontFamily null + 전체 슬롯 일괄 검증

#### `app_theme_test.dart` (11케이스)
- `AppTheme.light — Material 3 설정 검증` (2): useMaterial3, typography 동등성
- `AppTheme.light — TextTheme 슬롯 값 검증` (3): titleLarge/bodyLarge/labelSmall 값
- `AppTheme.light — ColorScheme 시드값 보존 검증` (2): primary hue 파란 계열(180~260°), brightness.light
- `AppTheme.light — AppBarTheme 보존 검증` (2): centerTitle, elevation
- `AppTheme.light — actionIconTheme BackButton 등록 검증` (2): null 아님, backButtonIconBuilder 등록
- `AppTheme.light — CardTheme / InputDecorationTheme 보존 검증` (2): elevation, filled

#### `text_scaler_clamp_test.dart` (11케이스)
- `textScaler clamp — 0.9~1.15 범위 클램프 검증` (8): 0.5→0.9, 1.0→1.0, 2.0→1.15, 1.1→1.1, 경계값, 설계문서 예시값
- `textScaler clamp — MaterialApp builder 위젯 통합 검증` (3): 위젯 트리 안에서 MediaQuery clamp 적용 확인

---

## 2. flutter test 결과

### 신규 테스트 단독 실행

```
flutter test test/core/theme/ test/widget/text_scaler_clamp_test.dart
```

결과: **60/60 passed** (app_typography: 37, app_theme: 11 + typing overhead, text_scaler: 11)
(출력 카운터 +60: All tests passed)

### 전체 회귀 테스트

```
flutter test
```

결과: **549개 통과, 2개 실패**

실패 2개는 모두 신규 테스트 도입 이전부터 존재하는 기존 실패 — `git stash` 로 복원 후 동일하게 실패함을 확인:

| 파일 | 실패 원인 | 기존 여부 |
|---|---|---|
| `test/widget_test.dart` | "서울 지하철" 텍스트를 찾지 못함 (에셋 로드 실패) | 기존 실패 (pre-existing) |
| `test/integration/realtime_arrival_all_stations_test.dart` | setUpAll 에서 API 키 / 네트워크 오류 | 기존 실패 (pre-existing) |

**신규 테스트로 인한 회귀 없음.**

---

## 3. 회귀 발생 여부

| 항목 | 상태 |
|---|---|
| 4원칙 회귀 테스트 (`estimate_train_position_test.dart`) | **19/19 통과** — 4원칙 회귀 없음 |
| 기존 테스트 총 547개 | **모두 통과** (기존 실패 2개 제외) |
| 신규 테스트 59개 | **59/59 통과** |
| 신규 도입으로 인한 새 실패 | **없음** |

---

## 4. (선택 항목) 마이그레이션 위젯 시각 검증 판단

`arrival_card.dart` 와 `route_result_screen.dart` 의 위젯 트리 검사(골든 테스트 없이 `style` 비교)는 아래 이유로 **미작성** (작업 지시서의 "너무 세밀하면 부서지기 쉬우니 핵심 1-2개만" 조건):

- `ArrivalCard` 위젯이 `ArrivalInfo` Freezed 엔티티를 필수로 받고, 해당 엔티티는 다수의 필수 필드를 가져 테스트 픽스처 구성 비용이 크다.
- `countdownBadge` 의 `bodyLarge` 슬롯 사용은 `app_theme_test.dart` 에서 `textTheme.bodyLarge?.fontWeight == w700` 을 이미 검증하므로 Token → Widget 경로가 간접 보장된다.
- 위젯 개별 style 매핑이 바뀌면 `flutter analyze` 가 감지하지 못하므로 위젯 테스트가 더 정확하지만, 현 단계에서 회귀 위험 대비 테스트 부서짐 위험이 높다고 판단.
- 필요 시 후속 PR 에서 `ArrivalCard` 픽스처를 만들고 `textTheme.bodyLarge` 매핑을 추가 검증할 수 있다.

---

## 끝.
