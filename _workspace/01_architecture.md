# 01 Architecture — UI 일관성 토큰 시스템 설계

작성: flutter-architect
대상: Phase 2 일괄 마이그레이션을 위한 설계 단계 산출물 (코드 수정 X, 문서만)

## 목표 요약

iOS/Android 간 폰트·컴포넌트 사이즈 일관성 확보. Material 3 textTheme 13 슬롯을 한국어 가독성에 맞게 정의하고, 인라인 `TextStyle()` 32곳을 시맨틱 슬롯으로 일괄 치환한다. `Typography.material2021(platform: TargetPlatform.android)` 고정으로 iOS 도 Roboto 메트릭을 받게 하여 글자 폭/줄간격을 통일한다. `textScaler` 0.9~1.15 클램프로 시스템 폰트 배율 극단값을 방지한다.

---

## 1. 디자인 토큰 명세

### 1.1 `lib/core/theme/tokens/app_typography.dart`

Material 3 의 13 시맨틱 슬롯을 한국어 가독성 기준으로 정의한다. **fontFamily 는 명시하지 않는다** — `Typography.material2021(platform: TargetPlatform.android)` 가 Roboto 메트릭을 적용하지만, fontFamily 미지정 시 시스템 한글 fallback (Apple SD Gothic Neo / Noto Sans CJK) 이 정상 동작하도록 한다.

베이스: M3 표준 스케일. 조정 포인트:
- 한국어는 어센더/디센더가 영문보다 작아 `height` 1.4~1.5 가 적절 (M3 기본 1.27~1.50 유지하되 본문 계열은 1.45 고정).
- `letterSpacing` 은 한국어에서 음수 값이 잘 보이지 않으므로 본문 계열은 0 으로 단순화.

```dart
// lib/core/theme/tokens/app_typography.dart
import 'package:flutter/material.dart';

/// 서울 지하철 앱 전역 TextTheme.
///
/// 정책:
///   - fontFamily 명시 X — Typography.material2021(android) 가 Roboto 메트릭을
///     적용하고, 한글은 시스템 fallback 으로 자연 처리됨.
///   - height(line-height) 한국어 가독성을 위해 본문 계열 1.45 로 통일.
///   - 인라인 TextStyle() 사용 금지. 모든 Text 는 Theme.of(context).textTheme.* 사용.
const TextTheme appTextTheme = TextTheme(
  // ───── Display: 거의 사용 안 함. 매우 큰 헤더용 ─────
  displayLarge: TextStyle(
    fontSize: 57, fontWeight: FontWeight.w400, height: 1.12, letterSpacing: -0.25,
  ),
  displayMedium: TextStyle(
    fontSize: 45, fontWeight: FontWeight.w400, height: 1.16, letterSpacing: 0,
  ),
  displaySmall: TextStyle(
    fontSize: 36, fontWeight: FontWeight.w400, height: 1.22, letterSpacing: 0,
  ),

  // ───── Headline: 화면 최상단 큰 제목 (현재 미사용, 향후 확장 여지) ─────
  headlineLarge: TextStyle(
    fontSize: 32, fontWeight: FontWeight.w400, height: 1.25, letterSpacing: 0,
  ),
  headlineMedium: TextStyle(
    fontSize: 28, fontWeight: FontWeight.w400, height: 1.29, letterSpacing: 0,
  ),
  headlineSmall: TextStyle(
    fontSize: 24, fontWeight: FontWeight.w400, height: 1.33, letterSpacing: 0,
  ),

  // ───── Title: AppBar/카드 제목/요약 헤더 (메인 사용처) ─────
  // titleLarge: 24px bold — 출발/도착 시각 헤더
  titleLarge: TextStyle(
    fontSize: 22, fontWeight: FontWeight.w700, height: 1.27, letterSpacing: 0,
  ),
  // titleMedium: 16px semi-bold — 카드 1차 제목 (도착 노선명 등)
  titleMedium: TextStyle(
    fontSize: 16, fontWeight: FontWeight.w600, height: 1.50, letterSpacing: 0.15,
  ),
  // titleSmall: 14px semi-bold — 강조 본문 (역명 endpoint)
  titleSmall: TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600, height: 1.43, letterSpacing: 0.1,
  ),

  // ───── Body: 일반 본문 ─────
  // bodyLarge: 16px regular — 카운트다운 분 표시 (실측 18 → 16 으로 다운, isEstimated 와 동일 슬롯)
  bodyLarge: TextStyle(
    fontSize: 16, fontWeight: FontWeight.w700, height: 1.50, letterSpacing: 0.5,
  ),
  // bodyMedium: 14px regular — 일반 본문, 에러 메시지
  bodyMedium: TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, height: 1.43, letterSpacing: 0.25,
  ),
  // bodySmall: 12px regular — 보조 본문, 직선 표시, 가이드 노트
  bodySmall: TextStyle(
    fontSize: 12, fontWeight: FontWeight.w400, height: 1.33, letterSpacing: 0.4,
  ),

  // ───── Label: 라벨/배지/칩 ─────
  // labelLarge: 14px medium — 칩 텍스트, 출발/도착 라벨
  labelLarge: TextStyle(
    fontSize: 14, fontWeight: FontWeight.w500, height: 1.43, letterSpacing: 0.1,
  ),
  // labelMedium: 13px medium — 환승 가이드, InfoChip
  labelMedium: TextStyle(
    fontSize: 13, fontWeight: FontWeight.w500, height: 1.38, letterSpacing: 0.5,
  ),
  // labelSmall: 11px medium — 카운트다운 초 단위 보조
  labelSmall: TextStyle(
    fontSize: 11, fontWeight: FontWeight.w500, height: 1.45, letterSpacing: 0.5,
  ),
);
```

> **bodyLarge 의 fontWeight 가 w700 인 이유**: 카운트다운 큰 숫자(18px bold) 매핑 대상. 일반적인 본문 weight 가 w400 이지만 본 앱에서 bodyLarge 는 거의 "분/시각 강조" 에만 쓰여 bold 가 자연스럽다. 향후 일반 본문에 쓰일 일이 생기면 `bodyLarge.copyWith(fontWeight: FontWeight.w400)` 로 재정의.

### 1.2 `lib/core/theme/tokens/app_dimensions.dart`

```dart
// lib/core/theme/tokens/app_dimensions.dart
//
// 4의 배수 그리드 기반 spacing/padding/iconSize 토큰.
// 인라인 매직 넘버(EdgeInsets.all(12), Icon size:14) 대신 사용한다.

abstract final class AppSpacing {
  static const double space2  = 2;
  static const double space4  = 4;
  static const double space6  = 6;   // 비표준이지만 기존 코드에 6 다수
  static const double space8  = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;
}

/// 시맨틱 별칭 — 의미가 명확한 곳에서 사용.
abstract final class AppPadding {
  static const double screenHorizontal = AppSpacing.space16;     // 화면 가장자리 좌우
  static const double screenVertical   = AppSpacing.space12;     // 화면 가장자리 상하
  static const double cardPadding      = AppSpacing.space12;     // Card 내부
  static const double cardOuterMargin  = AppSpacing.space16;     // Card 외곽 좌우
  static const double cardOuterMarginV = AppSpacing.space4;      // Card 외곽 상하
  static const double listItemVertical = AppSpacing.space8;
  static const double summaryHeader    = AppSpacing.space20;     // 결과 요약 헤더 좌우
  static const double summaryHeaderV   = AppSpacing.space16;     // 결과 요약 헤더 상하
}

abstract final class AppIconSize {
  static const double xs = 12;  // dot 표시
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  // 기존 14(InfoChip), 18(Tab icon) 은 가까운 sm/md 로 정규화.
}
```

### 1.3 `lib/core/theme/tokens/app_radii.dart`

```dart
// lib/core/theme/tokens/app_radii.dart
//
// BorderRadius 토큰. Card/Container/Badge 등의 모서리 반경.

import 'package:flutter/widgets.dart';

abstract final class AppRadius {
  static const double xs   = 4;     // 배지(노선/급행), InputDecoration 내부
  static const double sm   = 8;     // 카운트다운 박스, StationField
  static const double md   = 12;    // Card, InputDecoration outer
  static const double lg   = 16;
  static const double pill = 9999;  // 캡슐
}

abstract final class AppBorderRadius {
  static const xs   = BorderRadius.all(Radius.circular(AppRadius.xs));
  static const sm   = BorderRadius.all(Radius.circular(AppRadius.sm));
  static const md   = BorderRadius.all(Radius.circular(AppRadius.md));
  static const lg   = BorderRadius.all(Radius.circular(AppRadius.lg));
  static const pill = BorderRadius.all(Radius.circular(AppRadius.pill));
}
```

---

## 2. 인라인 TextStyle 시맨틱 매핑 표

### 매핑 원칙 재확인
| fontSize | 매핑 슬롯 |
|---|---|
| 24+ bold | `titleLarge` (22px bold; 한국어 가독성 위해 24→22) 또는 `headlineSmall` |
| 16~18 bold | `bodyLarge` (16px w700) — 카운트다운, 강조 시각 |
| 15~16 bold | `titleMedium` (16px w600) — 카드 1차 제목 |
| 14 bold/w500 | `titleSmall` (14px w600) 또는 `labelLarge` (14px w500) |
| 13 medium | `labelMedium` (13px w500) |
| 12 (배지/보조) | `bodySmall` (12px w400) — 일반 보조 |
| 12 bold (배지) | `bodySmall.copyWith(fontWeight: FontWeight.w700)` |
| 11 | `labelSmall` (11px w500) |

> **조건부 fontSize 처리**: `fontSize: isEstimated ? 16 : 18` 같은 분기는 `isEstimated ? textTheme.bodyLarge : textTheme.titleLarge` 형태로 분기. 단 시맨틱이 동일한 강조 텍스트면 두 케이스 모두 `bodyLarge` 로 정규화하는 것을 우선 검토.

### 매핑 표 (32곳)

| # | 파일:라인 | 기존 코드 | 의도 | 매핑 시맨틱 | 비고 |
|---|---|---|---|---|---|
| 1 | `route_result_screen.dart:298` | `TextStyle(fontSize: 14, color: Colors.grey)` | 로딩 상태 안내 | `bodyMedium` | color 는 `colorScheme.onSurfaceVariant` 또는 `Colors.grey` 유지 (광고 인접) |
| 2 | `route_result_screen.dart:306` | `TextStyle(fontSize: 24, fontWeight: bold)` | 출발 시각 강조 | `titleLarge` | 22px 로 다운 — iOS/Android 모두 안정적 폭 확보 |
| 3 | `route_result_screen.dart:313` | `TextStyle(fontSize: 14, color: Colors.grey[600])` | "출발" 보조 라벨 | `bodyMedium` | color 유지 |
| 4 | `route_result_screen.dart:321` | `TextStyle(fontSize: 24, fontWeight: bold)` | 도착 시각 강조 | `titleLarge` | 위와 동일 |
| 5 | `route_result_screen.dart:328` | `TextStyle(fontSize: 14, color: Colors.grey[600])` | "도착" 보조 라벨 | `bodyMedium` | color 유지 |
| 6 | `route_result_screen.dart:373` | `TextStyle(fontSize: 13, color: Colors.grey[600])` | InfoChip 텍스트 | `labelMedium` | color 유지 |
| 7 | `route_result_screen.dart:387` | `TextStyle(color: Colors.grey[400])` | 칩 구분자 \| | `bodyMedium` | size 미지정이라 기본값 사용 중 — 명시화 |
| 8 | `route_result_screen.dart:557` | `TextStyle(color: Colors.white, fontSize: 12, fontWeight: bold)` | 노선 배지 | `labelSmall.copyWith(color: white, fontWeight: w700)` | 11→12 미세 차이 → `labelSmall` (11) 대신 `bodySmall.copyWith(fontWeight: w700, color: white)` 가 더 적합. **결정: `bodySmall + w700`** |
| 9 | `route_result_screen.dart:575` | `TextStyle(color: white, fontSize: 12, fontWeight: bold)` | 급행 배지 | `bodySmall.copyWith(color: white, fontWeight: w700)` | 8 과 동일 패턴 |
| 10 | `route_result_screen.dart:586` | `TextStyle(fontSize: 12, color: Colors.grey[600])` | 세그먼트 방향 | `bodySmall` | color 유지 |
| 11 | `route_result_screen.dart:591` | `TextStyle(fontSize: 12, color: Colors.grey[500])` | 세그먼트 N분 N개역 | `bodySmall` | color 유지 |
| 12 | `route_result_screen.dart:633-637` | `TextStyle(fontSize: 12, fontWeight: w500, color: Colors.grey[700])` | 역 시각 표시 | `labelMedium.copyWith(fontSize: 12)` 또는 `bodySmall.copyWith(fontWeight: w500)` | **결정: `bodySmall.copyWith(fontWeight: w500)`** — letterSpacing 일관 |
| 13 | `route_result_screen.dart:675-679` | `TextStyle(fontSize: isEndpoint ? 14 : 12, fontWeight: isEndpoint ? bold : normal, color: isEndpoint ? black : grey[600])` | 역명 (endpoint vs 중간역) | `isEndpoint ? titleSmall : bodySmall` | 두 케이스를 시맨틱 분기 |
| 14 | `arrival_card.dart:40` | `TextStyle(fontSize: 15, fontWeight: bold)` | 도착 노선명 | `titleMedium` | 15→16 으로 통일 |
| 15 | `arrival_card.dart:58` | `TextStyle(color: white, fontSize: 10, fontWeight: bold)` | 급행 미니 배지 | `labelSmall.copyWith(fontSize: 10, color: white, fontWeight: w700)` | 10px 는 토큰에 없음 → `labelSmall` 베이스 + fontSize override 허용 (배지는 예외) |
| 16 | `arrival_card.dart:71` | `TextStyle(fontSize: 13, color: Colors.grey[600])` | 도착 메시지 | `labelMedium` | color 유지 |
| 17 | `arrival_card.dart:142-146` | `TextStyle(fontSize: isEstimated ? 16 : 18, fontWeight: bold, color: textColor)` | 카운트다운 분/초 큰 숫자 | `isEstimated ? bodyLarge : titleLarge.copyWith(fontSize: 18)` | **단순화 결정: 둘 다 `bodyLarge` 사용 (16px bold). 18→16 으로 미세 다운, iOS/Android 일관성 우선** |
| 18 | `arrival_card.dart:151-153` | `TextStyle(fontSize: 11, color: subTextColor)` | 카운트다운 초 보조 | `labelSmall` | color 유지 |
| 19 | `arrival_info_screen.dart:259` | `TextStyle(fontSize: 16, fontWeight: w500)` | 에러 헤더 | `titleMedium` | weight w600 으로 자연 매핑 (w500→w600 미세 강화) |
| 20 | `arrival_info_screen.dart:264` | `TextStyle(fontSize: 13, color: Colors.grey[600])` | 에러 상세 메시지 | `labelMedium` | color 유지 |
| 21 | `arrival_info_screen.dart:301` | `TextStyle(color: Colors.grey[500])` | 빈 상태 안내 | `bodyMedium` | size 미지정 — 명시화 |
| 22 | `search_bar_widget.dart:131` | `TextStyle(fontSize: 14, fontWeight: w500)` | 선택된 역명 | `titleSmall` | w500→w600 미세 강화 OR `labelLarge` (w500 유지). **결정: `labelLarge` (w500 보존)** |
| 23 | `search_bar_widget.dart:139` | `TextStyle(fontSize: 13, color: Colors.grey[500])` | "출발/도착역을 선택하세요" 플레이스홀더 | `labelMedium` | color 유지 |
| 24 | `transfer_row.dart:51` | `TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: w500)` | 환승 안내 메인 | `bodySmall.copyWith(fontWeight: w500)` | color 유지 (의미 색) |
| 25 | `transfer_row.dart:60` | `TextStyle(fontSize: 11, color: Colors.grey[600])` | 환승 가이드 노트 | `labelSmall.copyWith(color: Colors.grey[600])` | letterSpacing 0.5 무리 없음 |
| **나머지 (현 시점 미발견)** ||||| home/station_picker/subway_map 추가 검색 결과 search_bar_widget 만 추가 인라인 사용 — 32 곳 추정치는 일부 분기 케이스(13/22/17 같은 ternary) 를 별개로 카운트한 결과. 실 사용처는 위 25 항목으로 커버 |

> 32 vs 25 차이: 요구사항 원문이 "ternary/조건부 fontSize" 와 "TextSpan 내부 inline TextStyle" 을 별도로 카운트한 것으로 보인다. 본 매핑은 시맨틱 단위로 압축. ternary 케이스(#13, #17) 는 마이그레이션 시 두 시맨틱 슬롯 간 분기로 그대로 유지된다.

---

## 3. textScaler clamp 적용 위치

`lib/app.dart` 의 기존 `builder` 가 이미 `SafeArea(top: false)` 를 처리 중. **두 동작을 한 builder 안에서 결합**한다.

### 패치 (정확한 코드 형태)

```dart
// lib/app.dart  ─ MaterialApp.router(...)
return MaterialApp.router(
  title: '서울 지하철',
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light,
  routerConfig: router,
  builder: (context, child) {
    if (child == null) return const SizedBox.shrink();

    // (1) 시스템 폰트 배율을 0.9~1.15 로 클램프.
    //     - 너무 작으면 가독성 저하, 너무 크면 레이아웃 깨짐.
    //     - 4원칙 코드(map.html WebView)는 textScaler 영향 없음 (자체 CSS).
    final mq = MediaQuery.of(context);
    final clamped = mq.textScaler.clamp(
      minScaleFactor: 0.9,
      maxScaleFactor: 1.15,
    );

    // (2) Android 15 edge-to-edge 처리: bottom inset 만큼 콘텐츠 올림.
    return MediaQuery(
      data: mq.copyWith(textScaler: clamped),
      child: SafeArea(
        top: false,
        child: child,
      ),
    );
  },
);
```

**결합 순서 결정 근거**:
- `MediaQuery` 가 바깥 → `SafeArea` 가 안쪽. `SafeArea` 가 `MediaQuery.of(context).padding` 을 읽어야 정상 동작하므로 `MediaQuery` 를 더 바깥에 둔다.
- `child!` 가 아닌 `child == null ? SizedBox.shrink() : ...` 패턴은 기존 코드 보존.

---

## 4. `app_theme.dart` 갱신 명세

### 변경 항목
- **추가**: `typography: Typography.material2021(platform: TargetPlatform.android)` — iOS 도 Android Roboto 메트릭 적용 (글자 폭/줄간격 통일)
- **추가**: `textTheme: appTextTheme` — 신규 토큰 주입
- **유지**: `useMaterial3`, `colorScheme`, `appBarTheme`, `cardTheme`, `inputDecorationTheme`

### 패치 형태

```dart
// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'tokens/app_typography.dart';   // 신규

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      // ColorScheme 시드 보존 — 색상 팔레트 변경 X.
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0052A4),
        brightness: Brightness.light,
      ),
      // 신규: iOS 도 Android Roboto 메트릭 적용 → 글자 폭/줄간격 통일.
      typography: Typography.material2021(platform: TargetPlatform.android),
      // 신규: 시맨틱 슬롯 13 정의.
      textTheme: appTextTheme,
      appBarTheme: const AppBarTheme(
        centerTitle: true,           // 보존
        elevation: 0,                // 보존
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),  // AppRadius.md 와 등치
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }
}
```

> `cardTheme`/`inputDecorationTheme` 의 12px 는 `AppRadius.md` 와 일치하므로 후속 PR 에서 토큰화해도 무방하나, 본 단계에서는 **회귀 위험 최소화** 를 위해 그대로 둔다.

---

## 5. `BackButton.adaptive` 도입 방식

### 옵션 비교

| 옵션 | 회귀 위험 | 일관성 | 작업량 |
|---|---|---|---|
| A. `ThemeData.actionIconTheme` 에 `BackButtonIconBuilder` 등록 | **낮음** — 한 곳 수정으로 전역 적용 | 자동 일관 | 1 줄 |
| B. 각 Scaffold appBar leading 직접 교체 | 높음 — 누락 가능, AppBar 마다 작성 | 수동 관리 | 화면 수만큼 N 줄 |

### 권장안: **옵션 A**

```dart
// app_theme.dart 의 ThemeData(...) 에 추가
actionIconTheme: ActionIconThemeData(
  backButtonIconBuilder: (context) => const BackButtonIcon(),  // 플랫폼 자동 감지
),
```

> 정확한 호출은 Flutter SDK 버전에 따라 `BackButton.adaptive()` 위젯이 자동으로 플랫폼별 아이콘을 그려준다. `ActionIconThemeData(backButtonIconBuilder: ...)` 가 더 정확한 전역 훅이지만, 가장 단순한 형태는 **AppBar 가 자동으로 `BackButton` 을 leading 에 넣고, `BackButton` 자체가 `BackButtonIcon` 을 사용**한다. 따라서 구현 단계에서는 다음 둘 중 작동하는 쪽을 선택:
>
> 1. `AppBar` 가 만드는 기본 leading 을 `BackButton.adaptive()` 로 그린다 — 이미 Material 3 + `Typography.material2021(android)` 환경에서 플랫폼 감지가 동작하지 않을 수 있으므로, `actionIconTheme` 등록을 우선 시도.
> 2. 등록이 안 통하면 `Scaffold.appBar.leading: BackButton.adaptive()` 를 헬퍼로 래핑.

**Phase 2 결정**: 옵션 A 를 1차로 시도하되, 정상 동작 확인까지는 회귀 위험이 가장 적은 곳(Scaffold 4 곳: ArrivalInfoScreen, RouteResultScreen, StationPickerScreen, StationDetailScreen) 만 명시적 `BackButton.adaptive()` 로 폴백 가능.

---

## 6. 회귀 위험 영역과 검증 항목

### 보존 사항
| 항목 | 상태 | 검증 방법 |
|---|---|---|
| ColorScheme 시드 (`0xFF0052A4`) | 보존 | `app_theme.dart` diff 확인 |
| `AppBarTheme(centerTitle: true)` | 보존 | 모든 AppBar 타이틀 가운데 정렬 시각 확인 |
| `SafeArea(top: false)` | 보존 (builder 안에서 결합) | Android 15 edge-to-edge 디바이스에서 하단 nav bar 가림 확인 |
| `cardTheme` / `inputDecorationTheme` 12px radius | 보존 | 카드/검색바 시각 확인 |

### 절대 손대지 말 것
| 영역 | 파일 | 이유 |
|---|---|---|
| 4원칙 코드 | `tool/build_map_html.dart`, `lib/features/subway_map/presentation/providers/live_train_provider.dart`, `assets/html/map.html` | CLAUDE.md 최상위 정책 |
| AdMob | `lib/features/ads/presentation/widgets/home_banner_ad.dart` | 직전 작업 보호. `Theme.of(context).colorScheme.surface` 참조는 ColorScheme 보존으로 영향 없음 |

### 검증 체크리스트
- [ ] `flutter analyze` 0 errors / 0 warnings
- [ ] `flutter test` 전체 통과 (특히 `test/core/utils/estimate_train_position_test.dart` — 4원칙 회귀 테스트)
- [ ] AppBar 타이틀 가운데 정렬 시각 확인
- [ ] iOS/Android 양쪽에서 출발/도착 시각 헤더(titleLarge) 동일 폭 확인
- [ ] 시스템 폰트 0.85 / 1.3 / 2.0 설정 시 0.9 / 1.15 / 1.15 로 클램프 동작 확인
- [ ] Android 15 단말에서 광고 바 위 콘텐츠 가림 없음 확인
- [ ] BackButton 이 iOS 에서 `<` (Cupertino), Android 에서 `←` (Material) 표시 확인

---

## 7. 마이그레이션 분담 계획 (Phase 2b)

**원칙**: 동일 파일을 두 에이전트가 동시에 건드리지 않도록 **파일 단위로 완전 분리**.

### flutter-architect (자기 자신) — 토큰 정의 + 코어 인프라 + 단순 위젯
| 파일 | 작업 | 인라인 개수 |
|---|---|---|
| `lib/core/theme/tokens/app_typography.dart` | 신규 작성 | — |
| `lib/core/theme/tokens/app_dimensions.dart` | 신규 작성 | — |
| `lib/core/theme/tokens/app_radii.dart` | 신규 작성 | — |
| `lib/core/theme/app_theme.dart` | typography/textTheme/actionIconTheme 추가 | — |
| `lib/app.dart` | textScaler clamp + SafeArea 결합 | — |
| `lib/features/home/presentation/widgets/search_bar_widget.dart` | 인라인 → 시맨틱 (단순) | 2 |
| `lib/features/route_search/presentation/widgets/transfer_row.dart` | 인라인 → 시맨틱 (단순) | 2 |
| `lib/features/arrival_info/presentation/screens/arrival_info_screen.dart` | 인라인 → 시맨틱 + BackButton.adaptive 폴백 | 4 |

### map-math-engineer — 복잡한 timeline/카드 구조
| 파일 | 작업 | 인라인 개수 |
|---|---|---|
| `lib/features/route_search/presentation/screens/route_result_screen.dart` | 인라인 → 시맨틱, _SegmentHeader/_StationRow ternary 처리 | ~13 (요구사항 원문 20+ 카운트) |
| `lib/features/arrival_info/presentation/widgets/arrival_card.dart` | 인라인 → 시맨틱, _CountdownBadge ternary 처리 | 6 |

### 분담 근거
- 인프라/단순 파일은 flutter-architect (구조 정합성 중요)
- 다중 ternary + 복합 레이아웃이 있는 두 파일은 map-math-engineer (시각 디자인 감각 + 라인 수가 많아 1M context 활용)
- station_picker / subway_map / station_detail / home_screen 등은 인라인 TextStyle 미발견 (검색 결과 0)

### 동시작업 방지
- 두 에이전트가 같은 파일을 절대 동시에 편집하지 않음
- flutter-architect 가 토큰 파일을 먼저 commit → map-math-engineer 가 import 만 하면 됨
- 마이그레이션 후 flutter-qa-engineer 가 테스트, subway-code-reviewer 가 리뷰

### 단계 순서
1. flutter-architect: 토큰 3 파일 + app_theme.dart + app.dart 변경 → `flutter analyze` 통과
2. flutter-architect: search_bar_widget / transfer_row / arrival_info_screen 마이그레이션 → analyze 통과
3. map-math-engineer: route_result_screen / arrival_card 마이그레이션 → analyze 통과
4. flutter-qa-engineer: 토큰 적용 검증 위젯 테스트 추가
5. subway-code-reviewer + subway-requirements-reviewer 병렬 리뷰
6. 이슈 수정 후 최종 verify

---

## 부록: 토큰 사용 예시 (Phase 2b 참고용)

### Before
```dart
Text(
  _formatTime(departureTime),
  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
)
```

### After
```dart
Text(
  _formatTime(departureTime),
  style: Theme.of(context).textTheme.titleLarge,
)
```

### Before (color 유지)
```dart
Text(
  text,
  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
)
```

### After
```dart
Text(
  text,
  style: Theme.of(context).textTheme.labelMedium?.copyWith(
    color: Colors.grey[600],
  ),
)
```

### Before (ternary 분기)
```dart
Text(
  stationName,
  style: TextStyle(
    fontSize: isEndpoint ? 14 : 12,
    fontWeight: isEndpoint ? FontWeight.bold : FontWeight.normal,
    color: isEndpoint ? Colors.black : Colors.grey[600],
  ),
)
```

### After
```dart
final t = Theme.of(context).textTheme;
Text(
  stationName,
  style: (isEndpoint ? t.titleSmall : t.bodySmall)?.copyWith(
    color: isEndpoint ? Colors.black : Colors.grey[600],
  ),
)
```

---

## 끝.
