# Phase 05 — HIGH 이슈 3건 수정 결과

`_workspace/03_code_review.md` 의 HIGH 등급 이슈(H-1, H-2, H-3) 3건을 수정. MEDIUM/LOW 는 본 라운드 범위 외이므로 손대지 않음. 4원칙 보호 파일(`tool/build_map_html.dart`, `lib/features/subway_map/presentation/providers/live_train_provider.dart`, `assets/html/map.html`) 변경 없음.

---

## 변경 파일 요약

| # | 파일 | 변경 라인 | 대응 이슈 |
|---|------|----------|----------|
| 1 | `lib/features/ads/presentation/widgets/home_banner_ad.dart` | 다수 (전체 재작성) | H-1, H-2 |
| 2 | `android/app/build.gradle.kts` | `defaultConfig.minSdk` 1줄 | H-3 |

---

## H-1. BannerAd 메모리 누수 방지

**파일:** `lib/features/ads/presentation/widgets/home_banner_ad.dart`

### 변경 내용

1. **`onAdLoaded` 콜백에 unmount 가드 추가**
   ```dart
   onAdLoaded: (loadedAd) {
     // dispose된 위젯이면 BannerAd도 즉시 해제하여 누수를 방지한다.
     if (!mounted) {
       loadedAd.dispose();
       return;
     }
     setState(() {
       _isLoaded = true;
       _failed = false;
     });
   },
   ```
   - 기존: `if (!mounted) return;` 만 있어 BannerAd 객체가 native side에 leak 되었음.
   - 수정: unmount 시 `loadedAd.dispose()` 명시 호출 후 return.

2. **`await ad.load()` 직후 mounted 재검증 + 정리**
   ```dart
   _bannerAd = ad;
   await ad.load();
   // load() 도중 dispose 되었다면 ad를 직접 해제하여 누수 방지.
   if (!mounted) {
     ad.dispose();
     _bannerAd = null;
   }
   ```
   - `ad.load()` 진행 중에 위젯이 dispose 되는 race condition 보호.
   - `dispose()` 가 먼저 실행되어 `_bannerAd?.dispose()` 가 동작했더라도 멱등하므로 안전.

3. **`onAdFailedToLoad`** 는 기존 패턴 유지 (`failedAd.dispose()` → `mounted` 체크 → `setState`). 파라미터명만 `ad` → `failedAd` 로 변경하여 `loadedAd` 와 일관성 확보.

### 의도

- 광고 로드 진행 중인 상태에서 사용자가 빠르게 라우트 이동 → 위젯 dispose 시나리오에서 BannerAd 객체가 native heap에 살아남는 누수 차단.
- 3개의 가드 지점 (`getAnchoredAdaptiveBannerAdSize` 직후, `onAdLoaded` 콜백, `await ad.load()` 직후) 모두에서 mounted 검증.

---

## H-2. dart:io Platform → 플랫폼 중립 API 전환

**파일:** `lib/features/ads/presentation/widgets/home_banner_ad.dart`

### 변경 내용

1. **import 변경**
   ```dart
   // 제거
   import 'dart:io' show Platform;
   import 'package:flutter/foundation.dart' show kDebugMode;

   // 추가
   import 'package:flutter/foundation.dart'
       show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
   ```

2. **`_resolveAdUnitId()` 시작 부분에 web 가드 추가**
   ```dart
   String? _resolveAdUnitId() {
     // google_mobile_ads는 web을 지원하지 않으므로 즉시 차단.
     if (kIsWeb) return null;
     // ...
   }
   ```

3. **`Platform.isAndroid` / `Platform.isIOS` 치환**
   ```dart
   // before
   if (Platform.isAndroid) return HomeBannerAd._kAndroidTestUnitId;
   if (Platform.isIOS) return HomeBannerAd._kIosTestUnitId;

   // after
   if (defaultTargetPlatform == TargetPlatform.android) {
     return HomeBannerAd._kAndroidTestUnitId;
   }
   if (defaultTargetPlatform == TargetPlatform.iOS) {
     return HomeBannerAd._kIosTestUnitId;
   }
   ```
   - 4개 분기 모두 동일하게 `defaultTargetPlatform == TargetPlatform.{android,iOS}` 형태로 치환.

### 의도

- 향후 web 타겟 추가 시 `dart:io` import 가 컴파일 에러를 유발하던 문제 사전 차단.
- `defaultTargetPlatform` 은 web/desktop/mobile 모두에서 안전하게 사용 가능.
- `kIsWeb` 가드로 google_mobile_ads 미지원 플랫폼에서 광고 로드 시도 자체를 차단.

---

## H-3. Android minSdkVersion 23 강제

**파일:** `android/app/build.gradle.kts`

### 형식 확인

- 파일 형식: **Kotlin DSL (`.gradle.kts`)** — Groovy `.gradle` 아님.
- 기존 값: `minSdk = flutter.minSdkVersion` (Flutter SDK 버전에 따라 21~24 변동)

### 변경 내용

```kotlin
// before
minSdk = flutter.minSdkVersion

// after
// google_mobile_ads 5.x는 Android API 23 (Marshmallow) 이상을 요구하므로
// flutter.minSdkVersion 이 23 미만이어도 23 으로 강제한다.
minSdk = maxOf(flutter.minSdkVersion, 23)
```

### 의도

- `maxOf(flutter.minSdkVersion, 23)` 으로 flutter SDK 가 향후 minSdk 를 24+ 로 올리더라도 자동으로 따라가면서, 21~22 였을 경우엔 23 으로 강제.
- 단순히 `minSdk = 23` 로 고정하지 않은 이유는 future-proofing — Flutter 가 30+ 로 올라가도 그 값을 존중.
- google_mobile_ads 5.3.x 의 manifest merger 실패/런타임 빌드 실패를 사전 차단.

---

## 검증

### flutter analyze

```
$ flutter analyze lib/features/ads/presentation/widgets/home_banner_ad.dart
Analyzing home_banner_ad.dart...
No issues found! (ran in 0.9s)
```

### 4원칙 보호 파일 무수정 확인

- `tool/build_map_html.dart` — 변경 없음
- `lib/features/subway_map/presentation/providers/live_train_provider.dart` — 변경 없음
- `assets/html/map.html` — 변경 없음

### 변경 범위 (git diff 대상 파일)

- `lib/features/ads/presentation/widgets/home_banner_ad.dart` (수정)
- `android/app/build.gradle.kts` (수정)
- 그 외 0건

---

## 본 라운드 처리하지 않은 이슈

| 등급 | 항목 | 사유 |
|------|------|------|
| MEDIUM | M-1 네트워크 복구 재시도 | 별도 이슈 권장 (지시: MEDIUM 이번 라운드 제외) |
| MEDIUM | M-2 layout shift 완화 | 별도 이슈 권장 (지시: MEDIUM 이번 라운드 제외) |
| MEDIUM | M-3 광고 영역 시각적 구분 | 별도 이슈 권장 (지시: MEDIUM 이번 라운드 제외) |
| MEDIUM | M-4 위젯/단위 테스트 | flutter-qa-engineer 협업 권장 (지시: MEDIUM 이번 라운드 제외) |
| MEDIUM | M-5 SKAN 개수 문서 일치 | 문서 정합성 차원 (지시: MEDIUM 이번 라운드 제외) |
| LOW | L-1~L-5 | 본 라운드 범위 외 (지시: LOW 이번 라운드 제외) |

오버 엔지니어링 회피 원칙에 따라 HIGH 3건만 정확히 수정 완료.
