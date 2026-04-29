# Phase 06 — HIGH 이슈 3건 재리뷰 (PASS/FAIL 검증)

대상:
- `lib/features/ads/presentation/widgets/home_banner_ad.dart`
- `android/app/build.gradle.kts`

이전 리뷰: `_workspace/03_code_review.md` (HIGH 3건)
수정 내역: `_workspace/05_fix_high_issues.md`

---

## H-1. BannerAd 메모리 누수 방지 — **PASS**

검증 포인트:

1. **`onAdLoaded` unmount 가드 + dispose** (line 97~107)
   ```dart
   onAdLoaded: (loadedAd) {
     if (!mounted) {
       loadedAd.dispose();
       return;
     }
     setState(() { _isLoaded = true; _failed = false; });
   },
   ```
   - 권고안과 정확히 일치. unmount 시 `loadedAd.dispose()` 명시 호출 후 early return. **OK**

2. **`await ad.load()` 후 mounted 재검증 + 정리** (line 120~126)
   ```dart
   _bannerAd = ad;
   await ad.load();
   if (!mounted) {
     ad.dispose();
     _bannerAd = null;
   }
   ```
   - load() 도중 dispose 발생한 race를 정확히 처리. `_bannerAd = null` 까지 함께 처리하여 빈 참조 정리. **OK**

3. **누수 잔여 가능성 분석**
   - 가드 지점 3곳 모두 검증 완료:
     - (a) `getAnchoredAdaptiveBannerAdSize` await 직후 (line 90): `if (!mounted) return;` — 아직 BannerAd 생성 전이므로 누수 없음. **OK**
     - (b) `onAdLoaded` 콜백 (line 97): unmount 시 dispose 명시. **OK**
     - (c) `await ad.load()` 직후 (line 122): unmount 시 dispose. **OK**
   - **`dispose()` 와의 멱등성**: `_bannerAd?.dispose()` (line 131) 가 먼저 실행된 경우, 이후 `ad.dispose()` 가 다시 호출되어도 google_mobile_ads SDK 의 BannerAd.dispose 는 중복 호출 방어가 있음. 또한 dispose 흐름상 `_bannerAd = null` 이 line 132 에서 처리되고, `_loadAd` 의 마지막 mounted 체크는 `mounted == false` 시 별도 객체 참조(`ad`)에 dispose 호출 — 이중 해제도 안전한 패턴. **OK**
   - `onAdFailedToLoad` 도 기존 패턴 (`failedAd.dispose()` → `mounted` 체크 → `setState`) 유지, 변수명만 정리(`ad`→`failedAd`). 회귀 없음. **OK**

판정: **PASS**

---

## H-2. dart:io → defaultTargetPlatform 전환 — **PASS**

검증 포인트:

1. **`dart:io` 제거** (line 1~4)
   ```dart
   import 'package:flutter/foundation.dart'
       show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
   import 'package:flutter/material.dart';
   import 'package:google_mobile_ads/google_mobile_ads.dart';
   ```
   - `dart:io` import 완전 제거. 필요한 4개 심볼(`kDebugMode`, `kIsWeb`, `defaultTargetPlatform`, `TargetPlatform`)을 `flutter/foundation.dart` 에서 명시적 import. **OK**

2. **`kIsWeb` early return** (line 39~40)
   ```dart
   if (kIsWeb) return null;
   ```
   - 함수 진입 직후 첫 줄에 위치 — kDebugMode 분기보다 먼저 평가되어 web debug 빌드에서도 차단. **OK**

3. **`Platform.isAndroid` / `Platform.isIOS` → `defaultTargetPlatform == TargetPlatform.{android,iOS}` 치환 4곳** (line 42, 45, 50, 55)
   - debug Android (line 42), debug iOS (line 45), release Android (line 50), release iOS (line 55) — **4곳 모두 정확히 치환**.
   - `TargetPlatform.iOS` 대소문자(소문자 i, 대문자 O) 정확.
   - 각 분기 후 `return null;` (line 60) 으로 desktop(linux/macOS/windows) 등 미지원 플랫폼도 안전하게 차단. **OK**

판정: **PASS**

---

## H-3. Android minSdk 23 강제 — **PASS**

검증 포인트:

1. **Kotlin DSL 문법 정확성** (`build.gradle.kts:39`)
   ```kotlin
   minSdk = maxOf(flutter.minSdkVersion, 23)
   ```
   - `maxOf(...)` 는 Kotlin stdlib 의 `kotlin.comparisons.maxOf` — `.kts` 에서 import 없이 사용 가능. **OK**
   - `flutter.minSdkVersion` 은 Flutter Gradle Plugin 이 노출하는 Int 프로퍼티 → `Int, Int` 시그니처와 정확히 매칭. 컴파일 OK. **OK**
   - 권고안과 정확히 일치 (`minSdk = maxOf(flutter.minSdkVersion, 23)`). **OK**

2. **Future-proofing**
   - 단순 `minSdk = 23` 이 아니라 `maxOf(...)` 사용으로 Flutter SDK 가 향후 24+ 로 올라가도 그 값을 존중. 수정 의도와 부합. **OK**

3. **주석** (line 37~38)
   - "google_mobile_ads 5.x는 Android API 23 (Marshmallow) 이상을 요구하므로 / flutter.minSdkVersion 이 23 미만이어도 23 으로 강제한다." — 명확하고 한국어 컨벤션 준수. **OK**

판정: **PASS**

---

## 새 회귀 이슈

**없음.**

상세 검증:

- `home_banner_ad.dart`
  - 함수 길이: `_loadAd` 약 53줄 (74~127) — 50줄 가이드 살짝 초과하나 H-1 가드 추가로 인한 자연 증가, 분기·중첩 단순. 허용 가능.
  - 파일 길이: 149줄 (800줄 한도 내). **OK**
  - 중첩 깊이: 최대 3레벨 (callback 내부 setState). **OK**
  - 4원칙 보호 파일 무수정 — `tool/build_map_html.dart`, `lib/features/subway_map/presentation/providers/live_train_provider.dart`, `assets/html/map.html` 변경 없음. **OK**
  - `print` / `debugPrint` 미사용. **OK**
  - 새 import 4종(`kIsWeb`, `defaultTargetPlatform`, `TargetPlatform`) 모두 사용처 존재 — unused import 없음. **OK**
  - `BannerAdListener` 의 `onAdLoaded` / `onAdFailedToLoad` 시그니처 정확 (1-arg / 2-arg). **OK**

- `build.gradle.kts`
  - 다른 블록(`signingConfigs`, `buildTypes`) 손대지 않음. **OK**
  - `compileSdk`, `targetSdk` 등 인접 라인 변경 없음 — 변경 범위 최소화. **OK**

- 이전 리뷰의 MEDIUM/LOW 이슈는 본 라운드 범위 외 (지시대로 미처리) — 새 회귀 아님.

---

## 종합 판정

| 항목 | 결과 |
|------|------|
| H-1 BannerAd 누수 방지 | **PASS** |
| H-2 web 호환 (dart:io 제거) | **PASS** |
| H-3 Android minSdk 23 | **PASS** |
| 새 회귀 이슈 | **없음** |

### **최종 판정: PASS** (추가 수정 불필요)

HIGH 3건 모두 권고안과 정확히 일치하는 형태로 수정되었으며, 회귀 이슈도 발견되지 않음. 머지 가능 상태.

후속(MEDIUM/LOW)은 별도 이슈로 추적 권장:
- M-1 네트워크 복구 재시도
- M-2 layout shift 완화
- M-3 광고 영역 시각적 구분
- M-4 위젯/단위 테스트 (flutter-qa-engineer 협업)
- M-5 SKAN 개수 문서 정합성
- L-1~L-5 사소한 개선
