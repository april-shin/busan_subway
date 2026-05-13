# 05a Architecture Fix — 1차 리뷰 이슈 수정

작성: flutter-architect
대상: Phase 5 — 03_code_review.md (HIGH/MEDIUM) + 04_requirements_review.md (HIGH/MEDIUM) 이슈 수정
의존: `_workspace/01_architecture.md`, `_workspace/02a_arch_implementation.md`

---

## 1. 처리 요약 표

| ID | 출처 | 항목 | 결과 |
|---|---|---|---|
| H1 | 03 코드리뷰 HIGH | `lib/app.dart` builder 람다를 테스트 가능 함수로 추출 | 완료 — `appRootBuilder(BuildContext, Widget?)` top-level 함수 + `@visibleForTesting` |
| M1 | 03·04 HIGH/MED | station_detail 4곳 + station_picker 3곳 인라인 TextStyle 마이그레이션 | 완료 — 7곳 모두 시맨틱 슬롯 매핑 |
| M2 | 03 코드리뷰 MED | `AppBorderRadius` 정적 멤버 `BorderRadius` 타입 어노테이션 명시 | 완료 — 5 멤버 모두 `static const BorderRadius` 명시 |
| 04 MED | 04 요구사항 MED | spacing 토큰 시범 적용 (사용처 0 → 가시 시그널) | 완료 — 5 파일 17 곳 (EdgeInsets/SizedBox) → `AppSpacing.spaceN` |

본 책임 범위 외 (다른 에이전트 담당):
- `route_result_screen.dart`, `arrival_card.dart` → map-math-engineer
- `text_scaler_clamp_test.dart` → flutter-qa-engineer (`appRootBuilder` import 가능하도록 노출 완료)

---

## 2. 신규 마이그레이션 7곳 매핑 표

설계 문서 §2 의 매핑 원칙 준수.

| # | 파일:라인 | 기존 코드 | 의도 | 매핑 시맨틱 |
|---|---|---|---|---|
| 1 | `station_detail_screen.dart:81-84` | `TextStyle(color: Colors.white, fontWeight: bold)` | 노선 배지 텍스트 | `bodySmall.copyWith(color: white, fontWeight: w700)` ← 03 리뷰 권장 패턴 (#8/#9 일관) |
| 2 | `station_detail_screen.dart:90-93` | `TextStyle(fontSize: 22, fontWeight: bold)` | 역명 큰 헤더 | `titleLarge` ← 22px w700 정확히 매칭 |
| 3 | `station_detail_screen.dart:100` | `TextStyle(color: Colors.grey[600])` (size 미지정) | 역 번호 | `bodyMedium.copyWith(color: Colors.grey[600])` ← size 명시화 |
| 4 | `station_detail_screen.dart:108-110` | `const Text('환승 노선', style: TextStyle(fontSize: 16, fontWeight: bold))` | 환승 노선 헤더 | `titleMedium` (16px w600) — `const Text` → `Text` (`Theme.of(context)` 사용으로 const 불가) |
| 5 | `station_picker_screen.dart:73` | `TextStyle(color: Colors.grey[500])` (size 미지정) | "검색 결과 없음" | `bodyMedium.copyWith(color: Colors.grey[500])` ← 빈 상태 안내 패턴 (#21 일관) |
| 6 | `station_picker_screen.dart:156` | `const TextStyle(fontWeight: w500)` | 역명 타일 | `labelLarge` (14px w500) ← search_bar #22 와 동일 매핑 |
| 7 | `station_picker_screen.dart:192-196` | `TextStyle(color: white, fontSize: 11, fontWeight: bold)` | _LineBadge | `labelSmall.copyWith(color: white, fontWeight: w700)` ← 11 정확 매칭 |

---

## 3. builder 추출 결과

### 시그니처
```dart
@visibleForTesting
Widget appRootBuilder(BuildContext context, Widget? child)
```

### 위치
- 파일: `lib/app.dart`
- 종류: top-level 함수 (SeoulSubwayApp 외부)
- 도큐멘테이션 주석: 두 변환(textScaler clamp + SafeArea) 의 의도와 결합 순서(MediaQuery 바깥, SafeArea 안쪽) 명시

### MaterialApp.router 참조
```dart
return MaterialApp.router(
  ...
  builder: appRootBuilder,
);
```

### 테스트 노출 효과
- `@visibleForTesting` 주석으로 테스트 외부에서 사용 시 lint 경고. 실 앱(MaterialApp.router) 은 같은 라이브러리이므로 경고 없음.
- flutter-qa-engineer 가 `import 'package:seoul_subway/app.dart' show appRootBuilder;` 형태로 import 후 `MaterialApp(builder: appRootBuilder, home: ...)` 패턴으로 위젯 통합 테스트 작성 가능 (H1 해결).
- `@visibleForTesting` 의 source 는 `package:meta/meta.dart` 이지만 실 코드에서는 `package:flutter/material.dart` 가 재수출하므로 추가 import 불필요. (실제 분석 결과 `flutter/foundation.dart` 추가 import 가 unnecessary_import 경고 발생하여 제거.)

---

## 4. AppBorderRadius 타입 어노테이션

`lib/core/theme/tokens/app_radii.dart`:

```dart
abstract final class AppBorderRadius {
  static const BorderRadius xs   = BorderRadius.all(Radius.circular(AppRadius.xs));
  static const BorderRadius sm   = BorderRadius.all(Radius.circular(AppRadius.sm));
  static const BorderRadius md   = BorderRadius.all(Radius.circular(AppRadius.md));
  static const BorderRadius lg   = BorderRadius.all(Radius.circular(AppRadius.lg));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(AppRadius.pill));
}
```

- 5 멤버 모두 `BorderRadius` 타입 명시
- 외부 모듈이 import 시 IDE 자동완성/타입 추론 명확화 (M2 해결)

---

## 5. Spacing 토큰 시범 적용 위치

5 파일 / 17 곳 적용. 본 사이클의 핵심은 "사용처 0 → 가시 시그널" 이라 한 파일당 2~5 곳으로 절제.

### `lib/features/station_detail/presentation/screens/station_detail_screen.dart` (7곳)
| 라인 | Before | After |
|---|---|---|
| body padding | `EdgeInsets.all(16)` | `EdgeInsets.all(AppSpacing.space16)` |
| Card 내부 padding | `EdgeInsets.all(16)` | `EdgeInsets.all(AppSpacing.space16)` |
| 노선 배지 padding | `symmetric(horizontal: 12, vertical: 4)` | `symmetric(horizontal: AppSpacing.space12, vertical: AppSpacing.space4)` |
| 노선 배지 ↔ 역명 간격 | `SizedBox(width: 12)` | `SizedBox(width: AppSpacing.space12)` |
| Card 내부 row 간격 | `SizedBox(height: 12)` | `SizedBox(height: AppSpacing.space12)` |
| 환승 노선 헤더 위 spacing | `SizedBox(height: 16)` `SizedBox(height: 8)` | `space16` `space8` |
| Wrap spacing/runSpacing | `8` `8` | `AppSpacing.space8` x2 |
| 버튼 위 spacing | `SizedBox(height: 24)` | `SizedBox(height: AppSpacing.space24)` |
| 버튼 padding | `symmetric(vertical: 12)` | `symmetric(vertical: AppSpacing.space12)` |

### `lib/features/route_search/presentation/screens/station_picker_screen.dart` (4곳)
| 라인 | Before | After |
|---|---|---|
| 검색바 padding | `EdgeInsets.all(16)` | `EdgeInsets.all(AppSpacing.space16)` |
| ListTile subtitle padding | `EdgeInsets.only(top: 4)` | `EdgeInsets.only(top: AppSpacing.space4)` |
| Wrap spacing/runSpacing | `6` `4` | `space6` `space4` |
| _LineBadge padding | `symmetric(horizontal: 8, vertical: 2)` | `symmetric(horizontal: AppSpacing.space8, vertical: AppSpacing.space2)` |

### `lib/features/home/presentation/widgets/search_bar_widget.dart` (4곳)
| 라인 | Before | After |
|---|---|---|
| 외곽 padding | `symmetric(horizontal: 16, vertical: 8)` | `space16` `space8` |
| 출발↔도착 사이 SizedBox | `height: 4` | `AppSpacing.space4` |
| 검색바 ↔ 우측 액션 SizedBox | `width: 8` | `AppSpacing.space8` |
| _StationField padding | `symmetric(horizontal: 8, vertical: 6)` | `space8` `space6` |
| _StationField 내부 SizedBox | `width: 8`, `width: 4` | `space8`, `space4` |

### `lib/features/route_search/presentation/widgets/transfer_row.dart` (3곳)
| 라인 | Before | After |
|---|---|---|
| Padding 외곽 | `symmetric(vertical: 4)` | `symmetric(vertical: AppSpacing.space4)` |
| 점선 ↔ 아이콘 SizedBox | `width: 8` | `AppSpacing.space8` |
| 아이콘 ↔ 텍스트 SizedBox | `width: 4` | `AppSpacing.space4` |

### `lib/features/arrival_info/presentation/screens/arrival_info_screen.dart` (4곳)
에러 화면(`_buildError`) 안:
| 라인 | Before | After |
|---|---|---|
| Padding | `symmetric(horizontal: 32)` | `symmetric(horizontal: AppSpacing.space32)` |
| Icon ↔ 헤더 SizedBox | `height: 16` | `AppSpacing.space16` |
| 헤더 ↔ 메시지 SizedBox | `height: 8` | `AppSpacing.space8` |
| 메시지 ↔ 버튼 SizedBox | `height: 24` | `AppSpacing.space24` |

### 적용 절제 근거
- 본 사이클은 "토큰 사용처 0건" 가시 시그널 회복이 목표
- 23곳 전체 마이그레이션은 변경량 부담으로 후속 PR 분리 (04 권장사항 #2 일관)
- `_dashedLineHeight = 36`, 점선 너비 `20`, `54px leading offset`, 컴포넌트 size (icon `14`/`6` 동그라미/`10` Chip avatar) 등은 **시각 디자인 매직넘버** 라 토큰화 보류 (의미 색·시각 디자인 보존 정책)

---

## 6. flutter analyze 결과

명령:
```
flutter analyze lib/app.dart lib/core/theme/ \
  lib/features/home/presentation/widgets/search_bar_widget.dart \
  lib/features/route_search/presentation/widgets/transfer_row.dart \
  lib/features/arrival_info/presentation/screens/arrival_info_screen.dart \
  lib/features/station_detail/ \
  lib/features/route_search/presentation/screens/station_picker_screen.dart
```

결과:
```
Analyzing 7 items...
No issues found! (ran in 1.1s)
```

**0 errors / 0 warnings / 0 infos.**

---

## 7. 보호 영역 검증

| 영역 | 상태 |
|---|---|
| 4원칙 코드 (`tool/build_map_html.dart`, `live_train_provider.dart`, `assets/html/map.html`) | 미수정 |
| AdMob (`lib/features/ads/`) | 미수정 |
| `route_result_screen.dart`, `arrival_card.dart` (map-math 동시 작업 영역) | 미수정 |
| 기존 테스트 (`test/widget/text_scaler_clamp_test.dart` 등) | 미수정 (flutter-qa 담당) |
| ColorScheme/AppBarTheme/CardTheme/InputDecoration | 변경 없음 |
| `SafeArea(top: false)` 동작 | 보존 (`appRootBuilder` 안에서 동일) |
| `child == null` 체크 | 보존 |

---

## 8. 다음 단계 인계 사항

### flutter-qa-engineer
- `appRootBuilder(BuildContext, Widget?)` 가 `lib/app.dart` 에서 `@visibleForTesting` 으로 노출됨
- 권장 위젯 통합 테스트 패턴 (03 리뷰 H1):
  ```dart
  import 'package:seoul_subway/app.dart' show appRootBuilder;
  ...
  Widget buildTestApp({required TextScaler inputScaler}) {
    return MediaQuery(
      data: MediaQueryData(textScaler: inputScaler),
      child: MaterialApp(
        builder: appRootBuilder,
        home: Builder(
          builder: (innerCtx) {
            captured = MediaQuery.of(innerCtx).textScaler;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
  ```
- 이렇게 하면 실제 `lib/app.dart` 의 builder 와 정확히 동일 함수가 호출되어, 회귀를 잡을 수 있다.

### map-math-engineer
- `AppBorderRadius.{xs,sm,md,lg,pill}` 가 이제 `BorderRadius` 타입으로 명시되어 IDE 자동완성에서 정확한 타입 표시
- `route_result_screen.dart`, `arrival_card.dart` 에서 `BorderRadius.circular(N)` → `AppBorderRadius.X` 마이그레이션 시 안전

### subway-code-reviewer (재리뷰)
- 본 수정은 03 리뷰의 H1/M1/M2/M3(부분) 와 04 리뷰의 HIGH(7곳)/MEDIUM(spacing 0건) 이슈를 처리
- M3 (Theme.of 반복 호출) 는 `route_result_screen.dart` 영역이라 map-math 가 처리할 예정
- M4 (배지 사이즈 10/12 일관성) 는 `arrival_card.dart` 영역이라 map-math 가 처리할 예정

---

## 끝.
