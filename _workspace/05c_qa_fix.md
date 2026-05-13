# 05c QA Fix — H1 text_scaler_clamp_test builder 기반 재작성

작성: flutter-qa-engineer
대상: Phase 5c — 03_code_review.md H1 이슈 수정

---

## 1. 재작성 결과 요약

| 항목 | 1차 (02c) | 재작성 후 |
|---|---|---|
| 단위 테스트 케이스 수 | 8 | 8 (변경 없음, 유지) |
| 위젯 통합 테스트 케이스 수 | 3 | 5 |
| 총 케이스 수 | 11 | 13 |
| builder 기반 검증 여부 | X (인라인 재현) | O (appRootBuilder 직접 import) |

---

## 2. 변경 내용

### 위젯 통합 테스트 그룹 재작성

**1차 방식 (잘못됨):**
- `MaterialApp.home` 안에서 `Builder` 로 `outerCtx` 를 받아 직접 clamp 로직을 인라인으로 재현
- 실제 `lib/app.dart` 의 `appRootBuilder` 함수를 검증하지 않음
- `MaterialApp.builder` 패턴이 아닌 `MaterialApp.home + Builder` 패턴이라 컨텍스트 위치도 다름

**재작성 방식 (올바름):**
```dart
import 'package:seoul_subway/app.dart' show appRootBuilder;

MaterialApp(
  builder: appRootBuilder,  // ← 실제 lib/app.dart 와 동일 함수
  home: Builder(builder: (innerCtx) {
    captured = MediaQuery.of(innerCtx).textScaler;
    return const SizedBox.shrink();
  }),
)
```
- `@visibleForTesting` 으로 노출된 `appRootBuilder` 를 `show` import 로 직접 사용
- `MaterialApp.builder` 자리에 실제 함수가 들어가므로 앱 런타임 경로와 동일

### 추가된 케이스 (+2)

| 케이스 | 사유 |
|---|---|
| `appRootBuilder: 1.1 → 1.1 범위 안 변화 없음` | 작업 지시서 요청 케이스 추가 |
| `appRootBuilder: child == null 이면 SizedBox.shrink 반환` | 방어 코드 검증, 직접 함수 호출 패턴으로 검증 |

---

## 3. flutter test 결과

### 해당 테스트 단독 실행

```
flutter test test/widget/text_scaler_clamp_test.dart
```

```
00:00 +13: All tests passed!
```

**13/13 통과.**

### 테마 + 4원칙 회귀 테스트

```
flutter test test/core/theme/ test/core/utils/estimate_train_position_test.dart
```

```
00:00 +68: All tests passed!
```

- `app_typography_test.dart` 37케이스 — 통과
- `app_theme_test.dart` 11케이스 — 통과
- `estimate_train_position_test.dart` 19케이스 — 통과 (4원칙 회귀 없음)

---

## 4. 4원칙 회귀 테스트 보존 확인

| 파일 | 케이스 수 | 결과 |
|---|---|---|
| `test/core/utils/estimate_train_position_test.dart` | 19 | **19/19 통과** |

`tool/build_map_html.dart`, `live_train_provider.dart`, `assets/html/map.html` 미수정 확인.

---

## 5. 보호 영역 검증

| 항목 | 상태 |
|---|---|
| `test/core/theme/app_typography_test.dart` | 미수정, 37/37 통과 |
| `test/core/theme/app_theme_test.dart` | 미수정, 11/11 통과 |
| `lib/app.dart` | 미수정 (import 만 사용) |
| 4원칙 파일 | 미수정 |
| AdMob 파일 | 미수정 |

---

## 끝.
