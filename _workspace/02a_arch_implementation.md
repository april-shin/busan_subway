# 02a Architecture Implementation — 토큰 시스템 + 코어 인프라 + 단순 위젯 마이그레이션

작성: flutter-architect
대상: Phase 2a 산출물 (실제 코드 작성)
의존: `_workspace/01_architecture.md` 설계 문서

---

## 1. 신규/수정 파일 목록

### 신규 (3)
| 파일 | 라인 수 | 비고 |
|---|---|---|
| `lib/core/theme/tokens/app_typography.dart` | 116 | M3 13 슬롯 TextTheme 정의 |
| `lib/core/theme/tokens/app_dimensions.dart` | 36 | AppSpacing/AppPadding/AppIconSize |
| `lib/core/theme/tokens/app_radii.dart` | 22 | AppRadius/AppBorderRadius |

### 수정 (5)
| 파일 | 변경 라인 수 | 변경 요지 |
|---|---|---|
| `lib/core/theme/app_theme.dart` | +13 / -1 | typography + textTheme + actionIconTheme 추가 |
| `lib/app.dart` | +14 / -3 | textScaler clamp + MediaQuery 결합 |
| `lib/features/home/presentation/widgets/search_bar_widget.dart` | +5 / -10 | 인라인 TextStyle 2곳 시맨틱 슬롯 |
| `lib/features/route_search/presentation/widgets/transfer_row.dart` | +8 / -10 | 인라인 TextStyle 2곳 시맨틱 슬롯 |
| `lib/features/arrival_info/presentation/screens/arrival_info_screen.dart` | +9 / -7 | 인라인 TextStyle 3곳 시맨틱 슬롯 |

---

## 2. 인라인 TextStyle 마이그레이션 항목

### #22: `search_bar_widget.dart` — "선택된 역명"
- **Before**: `style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)`
- **After**: `style: Theme.of(context).textTheme.labelLarge`
- 매핑: `labelLarge` (14px w500) — 설계 문서 §2 결정 그대로

### #23: `search_bar_widget.dart` — "출발/도착역을 선택하세요" 플레이스홀더
- **Before**: `style: TextStyle(fontSize: 13, color: Colors.grey[500])`
- **After**: `style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey[500])`
- 매핑: `labelMedium` (13px w500) — color 보존

### #24: `transfer_row.dart` — 환승 안내 메인
- **Before**: `style: TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: FontWeight.w500)`
- **After**: `style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange[700], fontWeight: FontWeight.w500)`
- 매핑: `bodySmall` (12px) + w500 override + 의미 색 보존

### #25: `transfer_row.dart` — 환승 가이드 노트
- **Before**: `style: TextStyle(fontSize: 11, color: Colors.grey[600])`
- **After**: `style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey[600])`
- 매핑: `labelSmall` (11px w500) — color 보존

### #19: `arrival_info_screen.dart` — 에러 헤더
- **Before**: `style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)` (const Text)
- **After**: `style: Theme.of(context).textTheme.titleMedium`
- 매핑: `titleMedium` (16px w600) — w500→w600 미세 강화 (설계 문서 결정)
- 부수 변경: `const Text(...)` → `Text(...)` — Theme.of(context) 사용으로 const 불가

### #20: `arrival_info_screen.dart` — 에러 상세 메시지
- **Before**: `style: TextStyle(fontSize: 13, color: Colors.grey[600])`
- **After**: `style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey[600])`
- 매핑: `labelMedium` (13px w500) — color 보존

### #21: `arrival_info_screen.dart` — 빈 상태 안내
- **Before**: `style: TextStyle(color: Colors.grey[500])`
- **After**: `style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[500])`
- 매핑: `bodyMedium` (14px) — size 미지정이었으나 명시화

> **arrival_info_screen.dart 4번째 인라인 확인**: 작업 지시서가 언급한 "4곳"을 검증하기 위해 작업 후 `grep -n "TextStyle(" arrival_info_screen.dart` 결과 0건. 실제 인라인 TextStyle 은 3곳이었으며 모두 마이그레이션 완료. (`Icon(... color: Colors.orange)` 등은 TextStyle 이 아님.)

---

## 3. BackButton.adaptive 옵션 A 시도 결과

### 결과: **성공**

`app_theme.dart` 의 `ThemeData(...)` 에 다음을 추가:

```dart
actionIconTheme: ActionIconThemeData(
  backButtonIconBuilder: (context) => const BackButtonIcon(),
),
```

`flutter analyze` 0 issues 통과. `ActionIconThemeData` 와 `BackButtonIcon` 은 현재 SDK(Flutter 3.x stable, Material 3) 에서 정식 API 로 제공된다. `BackButtonIcon` 위젯이 내부적으로 `Theme.of(context).platform` 을 검사해 iOS 에서는 `Icons.arrow_back_ios_new`, Android 에서는 `Icons.arrow_back` 을 그린다. 따라서 별도 화면별 BackButton.adaptive() 폴백 작업 불필요.

후속 단계에서 화면별 검증 (실제 디바이스 또는 시뮬레이터 시각 확인) 은 flutter-qa-engineer 에서 수행 권장.

---

## 4. `flutter analyze` 결과

명령:
```
flutter analyze lib/core/theme/ lib/app.dart \
  lib/features/home/presentation/widgets/search_bar_widget.dart \
  lib/features/route_search/presentation/widgets/transfer_row.dart \
  lib/features/arrival_info/presentation/screens/arrival_info_screen.dart
```

결과:
```
Analyzing 5 items...
No issues found! (ran in 1.5s)
```

**0 errors / 0 warnings / 0 infos**.

---

## 5. 보존 사항 검증

| 항목 | 상태 |
|---|---|
| ColorScheme 시드 `0xFF0052A4` | 보존 |
| `AppBarTheme(centerTitle: true, elevation: 0)` | 보존 |
| `cardTheme(elevation: 1, radius: 12)` | 보존 |
| `inputDecorationTheme` (filled, OutlineInputBorder, padding 16/12) | 보존 |
| `SafeArea(top: false)` 동작 | 보존 (MediaQuery 안쪽으로 이동) |
| `child == null` 체크 | 보존 |
| `SystemChrome.setSystemUIOverlayStyle(...)` | 보존 |
| 4원칙 보호 영역 (`tool/build_map_html.dart`, `live_train_provider.dart`, `assets/html/map.html`) | 미수정 |
| AdMob (`lib/features/ads/`) | 미수정 |
| `route_result_screen.dart`, `arrival_card.dart` (map-math 담당) | 미수정 |

---

## 6. 다음 단계 (map-math-engineer 인계 사항)

### 토큰 import 경로
```dart
import 'package:seoul_subway/core/theme/tokens/app_typography.dart';   // 직접 사용 X (theme 으로 자동 주입)
import 'package:seoul_subway/core/theme/tokens/app_dimensions.dart';   // AppSpacing, AppPadding, AppIconSize
import 'package:seoul_subway/core/theme/tokens/app_radii.dart';        // AppRadius, AppBorderRadius
```

또는 상대 경로 (각 파일 위치에 따라 조정):
```dart
import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../core/theme/tokens/app_radii.dart';
```

### 사용 예시
```dart
// TextStyle: Theme.of(context).textTheme.{slot}?.copyWith(color: ...)
Text(value, style: Theme.of(context).textTheme.titleLarge);

// Spacing
const SizedBox(height: AppSpacing.space12);
const EdgeInsets.symmetric(horizontal: AppPadding.cardOuterMargin);

// Radius
const Container(
  decoration: BoxDecoration(borderRadius: AppBorderRadius.md),
);
```

### map-math-engineer 가 처리할 파일
- `lib/features/route_search/presentation/screens/route_result_screen.dart` (~13곳)
- `lib/features/arrival_info/presentation/widgets/arrival_card.dart` (6곳)

---

## 7. 회귀 위험 평가

| 영역 | 위험 등급 | 근거 |
|---|---|---|
| 토큰 신규 파일 | **낮음** | 신규 파일이라 기존 동작 영향 없음 |
| `app_theme.dart` typography 추가 | **중간** | iOS 폰트 메트릭 변경. 시각 검증 필요 |
| `app_theme.dart` textTheme 추가 | **중간** | 아직 명시 사용처가 없는 슬롯도 정의됨. Material 컴포넌트(AppBar 타이틀 등) 의 기본 폰트 크기에 영향 가능 |
| `actionIconTheme` 추가 | **낮음** | iOS 에서 Cupertino 스타일 화살표로 변경 — 의도된 변화 |
| `app.dart` MediaQuery+SafeArea 결합 | **중간** | 시스템 폰트 배율 클램프. 0.85/1.3/2.0 설정에서 0.9/1.15/1.15 로 매핑 |
| 단순 위젯 3곳 시맨틱 매핑 | **낮음** | TextStyle 만 교체, 위젯 트리/로직 무변경 |

권장 검증:
- iOS/Android 실디바이스에서 AppBar 타이틀, 검색바, 환승 안내, 도착 화면 헤더 시각 확인
- 시스템 폰트 크기 설정 변경 후 레이아웃 깨짐 여부 확인
- 4원칙 회귀 테스트 (`test/core/utils/estimate_train_position_test.dart`) 통과 확인

---

## 끝.
