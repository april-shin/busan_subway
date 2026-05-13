# 03 Code Review — UI 일관성 토큰 시스템 도입

작성: subway-code-reviewer
대상 단계: Phase 3 (Phase 2 마이그레이션 결과 코드 리뷰)
의존: `01_architecture.md`, `02a_arch_implementation.md`, `02b_map_implementation.md`, `02c_qa_implementation.md`

---

## 종합 판정

**NEEDS_FIX (HIGH 1건 + MEDIUM 다수)**

CRITICAL 이슈 없음. 기능적 회귀 위험은 낮으나, **MaterialApp.builder의 textScaler clamp 가 Material localization 컨텍스트 외부에서 동작하지 않을 가능성** 1건과 **마이그레이션 누락 (station_detail / station_picker)** 1건이 존재한다. 후자는 설계 문서에서 "검색 결과 0" 으로 잘못 결론낸 결과이며, 일관성 목표(원래 사용자 요청)를 부분적으로만 달성한 상태다.

핵심 토큰 설계와 Migration 25곳 자체는 깔끔하게 수행되었다.

---

## CRITICAL

없음.

---

## HIGH

### H1. `lib/app.dart:91-113` — `MaterialApp.builder` 의 `MediaQuery.of(context)` 위치

**문제**: `MaterialApp.router(builder: (context, child) { ... MediaQuery.of(context) ... })` 에서 사용하는 `context` 는 `MaterialApp` 보다 **상위** 의 BuildContext 다. 즉 builder 안의 `MediaQuery.of(context)` 는 `WidgetsApp` 이 주입한 MediaQuery (혹은 시스템 root MediaQuery) 를 가리킨다. 이 자체는 기능상 동작하지만, 다음 두 위험이 있다:

1. **테스트 케이스 불일치**: `test/widget/text_scaler_clamp_test.dart` 의 `buildTestApp` 은 `MaterialApp.home` 안에서 `Builder` 로 `outerCtx` 를 받아 그 위에서 clamp 를 적용한다. 즉 builder 가 `MaterialApp` 내부 컨텍스트를 받는 케이스를 테스트한 셈이라, **실제 `lib/app.dart` 의 builder 케이스(외부 컨텍스트)를 검증하지 못한다**. textScaler clamp 가 실제 앱에서 의도대로 동작하지 않는 회귀가 발생해도 본 테스트는 잡지 못한다.
2. **builder 컨텍스트의 textScaler 출처**: Flutter SDK 에서 `MaterialApp.builder` 의 context 는 `MediaQuery` (`View` 가 만든 root MediaQuery) 의 자식이므로 `textScaler` 는 정상 read 된다. 따라서 동작 자체는 OK 지만, 검증 부재가 회귀 위험.

**권장 수정**:

(A) **테스트 케이스 일치**: `text_scaler_clamp_test.dart` 의 위젯 통합 테스트를 `MaterialApp.builder` 패턴으로 재작성한다.

```dart
Widget buildTestApp({required TextScaler inputScaler}) {
  captured = null;
  return MediaQuery(
    data: MediaQueryData(textScaler: inputScaler),
    child: MaterialApp(
      builder: (ctx, child) {
        // lib/app.dart 와 동일 로직.
        if (child == null) return const SizedBox.shrink();
        final mq = MediaQuery.of(ctx);
        final clamped = mq.textScaler.clamp(
          minScaleFactor: 0.9, maxScaleFactor: 1.15,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          child: SafeArea(top: false, child: child),
        );
      },
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

(B) (선택) `lib/app.dart` 에서 `MediaQuery.maybeOf(context)` 를 사용해 null 안전화. 현 구현은 root MediaQuery 가 항상 존재한다는 가정이 맞으므로 필수는 아님.

---

## MEDIUM

### M1. **마이그레이션 누락 — 사용자 일괄 변경 요청 미충족**

**파일**:
- `lib/features/station_detail/presentation/screens/station_detail_screen.dart` (인라인 4건: L81, L90, L100, L110)
- `lib/features/route_search/presentation/screens/station_picker_screen.dart` (인라인 4건: L73, L156, L192-196)

설계 문서 §2 의 "32 vs 25 차이" 단락에서 "home/station_picker/subway_map 추가 검색 결과 search_bar_widget 만 추가 인라인 사용" 이라 단정했고 02a 보고서도 "0건"으로 결론. 그러나 실제 grep 결과:

```
station_detail_screen.dart:81:  style: const TextStyle(color: Colors.white, fontWeight: bold)  // 노선 배지
station_detail_screen.dart:90:  style: const TextStyle(fontSize: 22, fontWeight: bold)         // 역 이름
station_detail_screen.dart:100: style: TextStyle(color: Colors.grey[600])                      // 역 번호
station_detail_screen.dart:110: style: TextStyle(fontSize: 16, fontWeight: bold)               // "환승 노선" 헤더
station_picker_screen.dart:73:  style: TextStyle(color: Colors.grey[500])                      // "검색 결과 없음"
station_picker_screen.dart:156: style: const TextStyle(fontWeight: w500)                       // 역 이름
station_picker_screen.dart:192: style: const TextStyle(color: white, fontSize: 11, bold)       // _LineBadge
```

요구사항 원문은 **"인라인 TextStyle 32곳 일괄 마이그레이션"** 이며 사용자가 명시적으로 "일괄 변경하자" 라고 확정했다. 본 누락은 사용자 요구를 부분만 만족시킨다.

**권장 수정**: 두 파일에 각각 다음 매핑 적용:

```dart
// station_detail_screen.dart:81 (노선 배지 텍스트)
style: Theme.of(context).textTheme.bodySmall?.copyWith(
  color: Colors.white, fontWeight: FontWeight.w700,
)
// station_detail_screen.dart:90 (역 이름 큰 헤더)
style: Theme.of(context).textTheme.titleLarge  // 22 → titleLarge 22 와 정확히 매칭
// station_detail_screen.dart:100 (역 번호)
style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])
// station_detail_screen.dart:108-111 ("환승 노선" 헤더; const Text 도 풀어야 함)
Text('환승 노선', style: Theme.of(context).textTheme.titleMedium)

// station_picker_screen.dart:73 (검색 결과 없음)
style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[500])
// station_picker_screen.dart:156 (역 이름)
style: Theme.of(context).textTheme.labelLarge   // search_bar_widget #22 와 동일 매핑
// station_picker_screen.dart:192 (_LineBadge: 11/white/bold)
style: Theme.of(context).textTheme.labelSmall?.copyWith(
  color: Colors.white, fontWeight: FontWeight.w700,
)
```

> 분담 계획상 두 파일은 어느 에이전트에게도 명시 할당되지 않았다. 일괄 마이그레이션 후속 작업으로 처리해야 한다.

### M2. `lib/core/theme/tokens/app_radii.dart:16-20` — `BorderRadius` 타입 어노테이션 누락

```dart
abstract final class AppBorderRadius {
  static const xs   = BorderRadius.all(Radius.circular(AppRadius.xs));
  ...
}
```

타입 추론으로 `BorderRadius` 가 정해지지만, 토큰 파일은 다른 모듈이 import 하는 공개 API 다. **명시적 타입 어노테이션이 가독성·IDE 자동 완성·실수 방지 측면에서 권장**.

**권장 수정**:
```dart
static const BorderRadius xs = BorderRadius.all(Radius.circular(AppRadius.xs));
static const BorderRadius sm = BorderRadius.all(Radius.circular(AppRadius.sm));
// ... 동일 패턴
```

### M3. `lib/features/route_search/presentation/screens/route_result_screen.dart` — `Theme.of(context)` 반복 호출

`build` 한 번에 `Theme.of(context)` 가 12+ 회 호출됨. 각 호출은 InheritedWidget lookup 으로 `O(depth)` 이지만 캐시되므로 실측 비용은 미미. 다만 가독성과 일관성을 위해 build 시작에서 한번 추출하는 것이 패턴상 깔끔하다.

**권장 (선택)**: `_RouteSummaryHeader.build` / `_SegmentHeader.build` / `_StationRow.build` 시작에 `final t = Theme.of(context).textTheme;` 도입 후 `t.bodyMedium` 형태로 사용.

```dart
@override
Widget build(BuildContext context) {
  final t = Theme.of(context).textTheme;
  return Padding(
    ...
    Text(text, style: t.labelMedium?.copyWith(color: Colors.grey[600])),
  );
}
```

이 패턴은 설계 문서 §부록 "After (ternary 분기)" 예시와도 일치한다.

### M4. `arrival_card.dart:55-59` — 배지 fontSize override 의 토큰 일탈

```dart
Theme.of(context).textTheme.labelSmall?.copyWith(
  fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700,
)
```

토큰 슬롯에 없는 10px 를 override 로 주입. 설계 §2 의 "10px 는 토큰에 없음 → labelSmall 베이스 + fontSize override 허용 (배지는 예외)" 결정 그대로지만, **토큰 시스템의 핵심 가치(일관성)를 약화**. 동일 의도(`route_result_screen.dart:564, 581` 의 급행 배지)에는 12px = `bodySmall` 그대로 사용 중이라 **배지 사이즈가 두 화면에서 각각 10/12 로 다른 것 자체가 일관성 위반**.

**권장 수정 (택1)**:
- (a) `arrival_card` 의 급행 미니 배지도 `bodySmall` (12px) 로 통일하고 fontSize override 제거. 시각상 12 vs 10 차이는 미세하며 카드 레이아웃에 큰 영향 없음.
- (b) 토큰에 `badgeMicro` 별칭 (10px w700) 을 추가해 명시적으로 분리.

**우선 권장: (a)** — 추가 토큰 도입보다 일관성 회복이 가치가 높다.

### M5. `app_theme.dart:23-25` — `actionIconTheme` 의 효과 검증 부재

```dart
actionIconTheme: ActionIconThemeData(
  backButtonIconBuilder: (context) => const BackButtonIcon(),
),
```

`BackButtonIcon` 위젯은 내부적으로 `Theme.of(context).platform` 을 검사한다. 그러나 다음 환경에서 동작이 다를 수 있다:
- 시뮬레이터/디바이스에서 `Platform.isIOS == true` 면 `Icons.arrow_back_ios_new`, 아니면 `Icons.arrow_back`.
- `app_theme_test.dart` 의 검증은 단지 "`backButtonIconBuilder != null`" 만 확인. 실제 iOS 에서 Cupertino 화살표가 렌더되는지 위젯 시각 검증 없음.

**권장**: 위젯 테스트 1건 추가 (회귀 방지):

```dart
testWidgets('iOS 플랫폼에서 BackButton 이 arrow_back_ios_new 로 렌더된다', (tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Theme(
      data: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
      child: Scaffold(
        appBar: AppBar(title: const Text('Test')),
        body: const SizedBox.shrink(),
      ),
    ),
  ));
  // BackButton 아이콘 검증은 routes 가 push 되어야 leading 이 자동 생성되므로
  // 별도 라우터 setup 필요. 현 단계 위험 대비 ROI 가 낮으면 시각 QA 로 대체.
});
```

ROI 가 낮다고 판단되면 **시각 QA 체크리스트** 로 대체 — 02a §3 도 "후속 단계에서 화면별 검증 권장" 명시.

---

## LOW

### L1. `lib/app.dart:97` — `MediaQuery.of(context)` 가 `MediaQuery.textScalerOf(context)` 보다 무거움

`MediaQuery.of` 는 모든 MediaQuery 변경 시 리빌드를 트리거. textScaler 만 필요하면 `MediaQuery.textScalerOf(context)` (Flutter 3.16+) 가 더 좁은 의존성. 다만 builder 자체가 frame 단위 빈번 호출이 아니라 영향 미미.

```dart
final clamped = MediaQuery.textScalerOf(context).clamp(
  minScaleFactor: 0.9, maxScaleFactor: 1.15,
);
return MediaQuery(
  data: MediaQuery.of(context).copyWith(textScaler: clamped),
  child: SafeArea(top: false, child: child),
);
```

### L2. `app_typography.dart` — 슬롯 주석의 일부 사이즈 표기 불일치

L75 주석: "bodyLarge: 16px bold — 카운트다운 분 표시 (실측 18 → 16 으로 다운)" — 정확. L52 주석: "titleLarge: 22px bold — 출발/도착 시각 헤더" — 정확. 다만 설계 문서 §1.1 원본의 `letterSpacing: 0.15` (titleMedium) 와 같은 값이 코드와 일치하는지 일괄 점검 권장. **현재 점검 결과 모두 일치.** (점검 완료 — 이슈 없음)

### L3. `app_dimensions.dart:9` 주석 — "비표준이지만 기존 코드에 6 다수"

토큰의 의도가 "**4의 배수 그리드**" 인데 6 만 예외. 기존 코드 스무딩이 끝난 시점에 토큰에서 제거 가능한지 후속 평가 필요. 현 시점 회귀 방지 목적이라면 보존이 맞다.

### L4. `arrival_info_screen.dart:259` — 한국어 가독성 height 활용 미흡

`titleMedium` 은 height 1.50 으로 설정. 단일 라인 `Text('도착 정보를 불러올 수 없습니다')` 라면 시각적 영향 미미하지만, 설계 의도(한국어 가독성 line-height 통일) 는 이미 토큰에 들어가 있어 추가 작업 없음. **현 구현 OK.**

### L5. `route_result_screen.dart:644` — `Colors.grey[700]` 사용 의미 미약

기존 hardcoded color 보존 결정에 따른 자연스러운 코드. ColorScheme 의 `onSurfaceVariant` 로 점진 마이그레이션 가능하지만 본 작업 범위 외.

---

## NIT

### N1. `app_typography_test.dart:170` — 불필요한 string interpolation 중괄호

`flutter analyze` 가 다음 info 를 보고:
```
info • Unnecessary braces in a string interpolation • test/core/theme/app_typography_test.dart:170:22
```

**수정**:
```dart
reason: '$style 슬롯에 fontFamily 가 명시되어 있어 한글 fallback 이 차단될 수 있다',
```

### N2. `app_theme_test.dart` — `theme()` 헬퍼의 매번 `AppTheme.light` 호출

`AppTheme.light` 는 getter 라 매번 새 ThemeData 인스턴스를 만든다. 11 케이스 × ThemeData 생성 비용은 미미하지만 `setUp` 에서 한 번 캐시 가능. 가독성 vs 비용 trade-off 로 유지 OK.

### N3. `app_typography.dart` 의 `appTextTheme` 변수명

`const TextTheme appTextTheme = ...` — Dart 컨벤션상 top-level const 는 `kAppTextTheme` 또는 `appTextTheme` 둘 다 허용. `appTextTheme` (lowerCamelCase) 가 더 일반적이라 OK.

---

## 통과 항목 (칭찬)

### 토큰 설계
- **`abstract final class` 사용 (Dart 3+) 적절.** `AppSpacing`/`AppPadding`/`AppIconSize`/`AppRadius`/`AppBorderRadius` 모두 인스턴스화 차단. 정적 토큰 컨테이너에 정확한 패턴.
- **fontFamily 미명시 의도가 코드 코멘트(L5-L7) 에 명확히 기록.** "한글은 시스템 fallback 으로 자연 처리됨" — 재호출 에이전트가 의도를 이해하고 위반하지 않게 한다.
- **height (line-height) 한국어 가독성 정책이 코드 코멘트로 보호됨.** 본문 계열 1.45 통일 의도가 명시.

### 4원칙 보호
- **`tool/build_map_html.dart`, `live_train_provider.dart`, `assets/html/map.html` 미수정 확인** (`git diff -- ...` 결과 빈 출력). 4원칙 회귀 영역 완전 보호.
- **AdMob (`lib/features/ads/`) 미수정 확인.** 직전 작업 보호.
- **ColorScheme 시드 `0xFF0052A4` 보존 확인** (app_theme.dart L12-14).
- **`SafeArea(top: false)` 보존** — `MediaQuery` 안쪽으로 위치 이동했지만 동작 동일. `SafeArea` 가 `MediaQuery.of(context).padding` 을 정상 read 하기 위한 결합 순서 (MediaQuery 바깥, SafeArea 안쪽) 가 정확히 적용됨.

### 마이그레이션 정확성
- **color 보존이 의도대로 되어 있음.** `Colors.grey[600]` 등 모든 의미 색상이 `copyWith(color: ...)` 로 보존 (route_result_screen.dart:298, 313, 326, 374, 392; arrival_info_screen.dart:265, 304; transfer_row.dart:52, 60).
- **ternary 분기 처리 (#13 `_StationRow`, #17 `_CountdownBadge`) 시맨틱 의미 보존.**
  - #13: `isEndpoint ? titleSmall : bodySmall` — 종착역 vs 중간역의 시맨틱 분리 정확.
  - #17: 18→16 통일은 설계 결정 (iOS/Android 일관성 우선) 그대로 적용. `bodyLarge` 단일 슬롯으로 정규화.
- **`copyWith` 의 `?.` null safety 처리 적절.** Theme의 textTheme 슬롯이 null 일 가능성에 대비한 chain (`?.copyWith(...)`).
- **`const Text(...)` → `Text(...)` 교체 (arrival_info_screen.dart:257-260)** — Theme.of(context) 사용으로 const 불가능. 정확한 처리.

### 보호 영역 손상 여부
- ColorScheme/AppBarTheme/CardTheme/InputDecorationTheme 모두 보존 (app_theme.dart:12-46).
- `SystemChrome.setSystemUIOverlayStyle(...)` 보존 (app.dart:79-84).
- `child == null` 체크 보존 (app.dart:92).

### textScaler clamp 기본 동작
- `app.dart:98-101` — `clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15)` 정확.
- 단위 테스트 (`text_scaler_clamp_test.dart`) 의 8 단위 케이스 (0.5/1.0/2.0/1.1/0.9/1.15/0.85/1.3) 가 경계와 내부 모두 커버. 회귀를 잡을 수 있는 핵심 케이스 포함.

### 회귀 위험 영역
- **18→16 카운트다운 다운사이즈**: iOS Roboto 메트릭 적용 + 16px bodyLarge bold 로 가독성 충분. 시각 회귀 위험 **낮음**. 단, "분 단위 카운트다운" 의 강조 임팩트가 약간 줄어드는 부작용은 있을 수 있어 시각 QA 권장.
- **24→22 titleLarge**: 한국어 가독성과 iOS/Android 폭 일관성 측면에서 **22px 가 더 안정적**. 의미상 적절한 다운사이즈. M3 표준 22px와도 매칭.
- **BackButton.adaptive 옵션 A**: `actionIconTheme.backButtonIconBuilder` 등록만으로 동작하는지는 SDK 버전 의존. **실 디바이스에서 시각 검증 필수.**

### 테스트 커버리지
- `app_typography_test.dart` 37 케이스 — 13 슬롯 존재 + fontSize/Weight 명세 + height ≥ 1.33 + fontFamily null. **회귀를 잡을 수 있는 핵심을 빠짐없이 커버.**
- `app_theme_test.dart` 11 케이스 — Material 3, ColorScheme 시드 hue, AppBarTheme, actionIconTheme, CardTheme 모두 검증.
- `text_scaler_clamp_test.dart` 11 케이스 — 단위 8 + 위젯 3.
- **오버엔지니어링 없음.** 02c 보고서가 "ArrivalCard 픽스처 비용이 크다" 며 위젯 시각 검증을 의도적으로 스킵한 결정도 합리적.
- **4원칙 회귀 테스트 (`estimate_train_position_test.dart` 19/19) 보존 확인.** 02c 보고서 §3 명시.

---

## 리뷰 체크리스트 결과

### 아키텍처
- [x] domain/ 레이어에 Flutter 임포트 없음 (변경 없음)
- [x] graph/ 모듈에 Flutter 의존성 없음 (변경 없음)
- [x] 리포지토리 인터페이스/구현체 분리 (변경 없음)
- [x] 프로바이더 계층 적절 (변경 없음)

### 불변성
- [x] `@freezed` 사용 (변경 영향 없음)
- [x] `copyWith` 사용 — 모든 마이그레이션이 `textTheme.X?.copyWith(...)` 패턴
- [x] List/Map unmodifiable (변경 없음)

### 상태 관리
- [x] Consumer watch 범위 (변경 없음)
- [x] ref.listen vs ref.watch 적절 (변경 없음)
- [x] StateNotifier 새 객체 생성 (변경 없음)

### 성능
- [x] FutureBuilder 캐싱 (변경 없음)
- [x] `const` 위젯 활용 — `arrival_info_screen.dart:257` 등은 const 제거가 불가피
- [x] runJavaScript 호출 (변경 없음, 4원칙 보호)
- [x] 불필요 setState 없음

### 보안
- [x] API 키 하드코딩 없음
- [x] 사용자 입력 검증 (변경 없음)
- [x] 에러 메시지 민감정보 없음
- [x] JS 인젝션 방지 (변경 없음)

### 코드 스타일
- [x] 함수 < 50줄 (모든 변경 함수가 50줄 이내)
- [x] 파일 < 800줄 (route_result_screen.dart 698줄로 800줄 미만)
- [x] 의미 있는 이름
- [x] 깊은 중첩 없음
- [x] print/debugPrint 없음

### 프로젝트 특수
- [x] 노드 ID 형식 (변경 없음)
- [x] 환승 시간 키 (변경 없음)
- [x] build_runner 트리거 — `@freezed`/`@riverpod` 변경 없으므로 불요
- [x] SVG 파이프라인 — SVG 미수정
- [x] --release 빌드 — 코드 변경 없음

---

## 정리 및 우선 처리 권고

| 우선순위 | 항목 | 조치 |
|---|---|---|
| **HIGH** | H1 — text_scaler_clamp_test 의 위젯 통합 테스트가 실제 builder 패턴과 다름 | 테스트 재작성 (MaterialApp.builder 패턴) |
| **MEDIUM** | M1 — station_detail / station_picker 마이그레이션 누락 | 추가 마이그레이션 8건 |
| MEDIUM | M2 — AppBorderRadius 타입 어노테이션 명시 | 6줄 추가 |
| MEDIUM | M3 — Theme.of(context) 반복 호출 정리 | 가독성 개선 (선택) |
| MEDIUM | M4 — 급행 배지 사이즈 일관화 (10 → 12) | arrival_card.dart 1곳 |
| MEDIUM | M5 — actionIconTheme 시각 회귀 방지 | 시각 QA 또는 위젯 테스트 |
| NIT | N1 — string interpolation 중괄호 | 1줄 |

---

## 끝.
