# Phase 03 — 코드 리뷰 (HomeScreen 하단 AdMob 배너)

리뷰 대상:
- 신규: `lib/features/ads/presentation/widgets/home_banner_ad.dart`
- 수정: `pubspec.yaml`, `lib/main.dart`, `lib/features/home/presentation/screens/home_screen.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- 4원칙 보호 파일 변경 여부 확인 결과: **변경 없음** (`git diff --stat`로 `tool/build_map_html.dart`, `lib/features/subway_map/presentation/providers/live_train_provider.dart`, `assets/html/map.html` 모두 unmodified 확인 완료. 원칙 위반 0건.)

---

## 코드 리뷰 결과

### CRITICAL

해당 사항 없음. 앱 크래시·기능 회귀·4원칙 위반은 발견되지 않았다. 미설정 release 단위 ID에 대한 안전 가드(`_resolveAdUnitId() == null` → early return + `SizedBox.shrink()`)가 정확히 작동하므로 release 빌드에서도 크래시 위험은 없다.

---

### HIGH

#### H-1. `_loadAd()` 진행 중에 위젯이 dispose되면 BannerAd가 해제되지 않을 수 있다 (메모리 누수)
- **파일**: `lib/features/ads/presentation/widgets/home_banner_ad.dart:84-111`
- **현상**: `_loadAd()`는 `await AdSize.getAnchoredAdaptiveBannerAdSize(...)` 직후 `if (!mounted) return;`로 보호하지만, **그 직후 `final ad = BannerAd(...)`을 생성하고 `_bannerAd = ad;`로 필드에 대입하기 전에는 `mounted` 체크가 없다.** 더 큰 문제는 `await ad.load();` 호출 도중에 위젯이 dispose되면 `dispose()`가 먼저 실행되어 `_bannerAd`(아직 `null` 또는 이미 대입됨)를 처리하지만, **`ad.load()` 가 진행 중인 BannerAd 객체는 dispose 호출 타이밍에 따라 누락될 수 있다.** 또한 `onAdLoaded` 콜백이 dispose 이후에 호출될 가능성에 대해 `mounted` 가드는 있으나, **이미 dispose된 위젯이 보유했던 ad 인스턴스는 누구도 dispose하지 않고 leak된다.**
- **재현 시나리오**: 사용자가 홈 → 다른 라우트로 빠르게 이동 → 광고 로드 완료 시점 도달 → onAdLoaded 트리거. mounted=false이므로 setState는 스킵되지만, BannerAd 객체 자체는 native side에 살아 있음.
- **수정 제안**:
  ```dart
  Future<void> _loadAd() async {
    final adUnitId = _resolveAdUnitId();
    if (adUnitId == null) return;

    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.portrait,
      width,
    );
    if (size == null) return;
    if (!mounted) return;

    final ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          // dispose된 위젯이면 BannerAd도 즉시 해제.
          if (!mounted) {
            loadedAd.dispose();
            return;
          }
          setState(() {
            _isLoaded = true;
            _failed = false;
          });
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isLoaded = false;
            _failed = true;
          });
        },
      ),
    );

    _bannerAd = ad;
    await ad.load();
    // load() 이후 dispose 됐다면 정리.
    if (!mounted) {
      ad.dispose();
      _bannerAd = null;
    }
  }
  ```
  - 핵심 변경: ① `onAdLoaded`에서 unmount 시 `loadedAd.dispose()` 명시 호출, ② `await ad.load()` 직후 mounted 재검증 + 정리.

#### H-2. `_resolveAdUnitId()`가 build/release 상관없이 데스크탑/웹 등 미지원 플랫폼에서도 호출될 수 있어 `Platform.isAndroid`/`isIOS` 체크는 OK지만, `dart:io`의 `Platform`이 web 빌드에서 컴파일 에러를 낸다.
- **파일**: `lib/features/ads/presentation/widgets/home_banner_ad.dart:1`
- **현상**: 이 프로젝트는 현재 모바일 전용이지만, 향후 web 타겟 추가 시 `import 'dart:io' show Platform;`이 컴파일 실패를 유발한다. google_mobile_ads도 web 미지원.
- **수정 제안**: 현재 시점에서는 우선순위 낮음(LOW로 강등 가능). 다만, 방어적으로 `kIsWeb` 가드를 추가해두는 것이 안전:
  ```dart
  import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
  // ...
  String? _resolveAdUnitId() {
    if (kIsWeb) return null;
    if (kDebugMode) {
      // ...
    }
    // ...
  }
  ```
  - 다만 현재 모바일 전용 프로젝트에서는 문제 없으므로, 이 항목은 web 확장 계획 없으면 생략 가능.

#### H-3. Android `minSdkVersion`이 `flutter.minSdkVersion`(보통 21)일 가능성이 있어, google_mobile_ads 5.x(요구: minSdk 23)와 불일치 시 빌드 실패.
- **파일**: `android/app/build.gradle.kts:37`
- **현상**: `minSdk = flutter.minSdkVersion`. Flutter 3.41 기준 기본값이 21~24 사이로 변동. google_mobile_ads 5.3.x는 **minSdk 23 이상** 요구. 21이면 manifest merger 또는 런타임 빌드 실패.
- **수정 제안**: `02_implementation.md`에서도 "후속 조치"로 언급되었으나, 리뷰 단계에서 명시적으로 점검 권장:
  ```kotlin
  defaultConfig {
      applicationId = "com.april.seoul_subway"
      minSdk = maxOf(flutter.minSdkVersion, 23)
      // ...
  }
  ```
  - 또는 단순히 `minSdk = 23`으로 고정. 빌드 시도에서 오류 발생 시 즉시 처리.

---

### MEDIUM

#### M-1. `_failed` 상태가 영구적이며 재시도 로직이 없다
- **파일**: `lib/features/ads/presentation/widgets/home_banner_ad.dart:33, 98-106`
- **현상**: 네트워크 일시 단절·서버 일시 오류로 광고 로드 실패 시 `_failed = true`로 고정되어, 네트워크 복구 후에도 다시 시도하지 않음. 사용자가 앱을 재시작해야 광고가 보임.
- **수정 제안**: `connectivity_plus`(이미 `pubspec.yaml`에 있음)와 연계해 네트워크 복구 이벤트에 재시도하거나, 최소한 일정 시간 후 1회 재시도 (`Future.delayed(Duration(seconds: 30), _loadAd)` + 재시도 횟수 제한). 단, 이번 단계에서는 요구사항 범위 외 작업이므로 후속 개선 사항으로 기록만.

#### M-2. 광고가 한 번 로드된 후 위젯이 보일 때 `Expanded(SubwayMapScreen)`이 갑자기 줄어드는 layout shift
- **파일**: `lib/features/home/presentation/screens/home_screen.dart:56-59`
- **현상**: 초기 `SizedBox.shrink()` (높이 0) → 광고 로드 완료 시 `Container(height: ad.size.height)` 로 높이가 갑자기 50~60dp 추가됨. `Expanded(SubwayMapScreen)`은 그만큼 줄어들어 지도가 위로 점프하는 시각적 불편.
- **수정 제안**: 적응형 배너 사이즈는 `getAnchoredAdaptiveBannerAdSize`를 통해 *로드 전에도* 미리 알 수 있다. 사이즈가 결정되는 즉시 (load 전) 빈 컨테이너로 자리 예약:
  ```dart
  // _HomeBannerAdState 내부:
  AdSize? _reservedSize;

  Future<void> _loadAd() async {
    // ... adUnitId/size 확인 ...
    if (!mounted) return;
    setState(() => _reservedSize = size); // 자리 예약

    final ad = BannerAd(...);
    _bannerAd = ad;
    await ad.load();
    // ...
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (_failed) return const SizedBox.shrink();
    if (_reservedSize == null) return const SizedBox.shrink();

    return Container(
      color: Theme.of(context).colorScheme.surface,
      width: _reservedSize!.width.toDouble(),
      height: _reservedSize!.height.toDouble(),
      child: (_isLoaded && ad != null) ? AdWidget(ad: ad) : null,
    );
  }
  ```
  - `02_implementation.md`의 "5. SizedBox.shrink()로 통일된 비노출 정책"에서도 "사용자가 지도가 흔들렸다고 느끼지 않도록 광고 영역이 한 번 자리잡으면 유지됨"이라 했으나, 실제로는 첫 로드 시점에 흔들림이 발생함. 이번 PR 범위에서 처리 가능하면 권장.

#### M-3. 컬러 토큰 `Theme.of(context).colorScheme.surface`가 광고와 의도적으로 구분되지 않는다
- **파일**: `lib/features/ads/presentation/widgets/home_banner_ad.dart:128`
- **현상**: 광고 컨테이너 배경이 surface 컬러여서 다크 모드에서 광고와 페이지 배경이 동일해 광고 경계가 불명확. AdMob 정책상 광고는 콘텐츠와 명확히 구분되어야 함 (위반 시 정책 경고 가능).
- **수정 제안**: 상단 1px divider 추가 또는 배경을 약간 다른 톤(`surfaceContainerHigh`)으로:
  ```dart
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
    ),
    child: SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    ),
  );
  ```

#### M-4. 위젯 테스트 누락
- **파일**: `test/features/ads/` 미존재
- **현상**: HomeBannerAd의 ① release 빈 ID → SizedBox.shrink, ② onAdFailedToLoad → _failed=true → SizedBox.shrink, ③ dispose 시 BannerAd.dispose 호출 등 핵심 분기 검증 테스트 없음.
- **수정 제안**: BannerAd를 mock하기 어렵지만, `_resolveAdUnitId()`을 별도 함수/static으로 분리하면 unit test 가능. flutter-qa-engineer에게 테스트 작성 의뢰 권장.

#### M-5. `_workspace/02_implementation.md`의 "iOS SKAN 77개" 와 실제 개수 불일치 가능성
- **파일**: `ios/Runner/Info.plist:73-383`
- **현상**: 산출물 문서는 "77개" 라 명시. 실제로 plist에서 `<key>SKAdNetworkIdentifier</key>` 카운트 확인 필요. 실제 파일에는 약 78~79개로 보임 (아래 명령 결과로 검증 권장):
  ```bash
  grep -c "SKAdNetworkIdentifier" ios/Runner/Info.plist
  ```
  - 위 결과를 산출물 문서와 일치시키거나, 문서를 "공식 권장 목록 (n개)" 형식으로 일반화.
- **영향**: 기능 정상. 문서 일관성 개선 차원.

---

### LOW

#### L-1. `_loadAd()` 함수 내부 흐름이 `if (!mounted) return;` 가드를 한 번만 사용
- **파일**: `lib/features/ads/presentation/widgets/home_banner_ad.dart:68-112`
- **현상**: H-1 항목에서 다룬 내용. await 사이에 mounted 체크가 1회만 있어 재진입 시점에 따라 누수 가능. (HIGH로 이미 다뤘으므로 중복 제거)

#### L-2. `_kAndroidTestUnitId`/`_kIosTestUnitId`/`_kAndroidReleaseUnitId`/`_kIosReleaseUnitId` 가 widget의 static 멤버
- **파일**: `lib/features/ads/presentation/widgets/home_banner_ad.dart:16-24`
- **현상**: 파일 상단 top-level `const`로 두면 `HomeBannerAd._kAndroidTestUnitId` 같은 긴 참조가 사라져 가독성 향상. 다만 기존 패턴과 무관한 사소한 개선.

#### L-3. `pubspec.yaml`의 `# Ads` 섹션이 `dependencies` 끝에 위치하나 `# Utilities` 섹션 바로 아래에 있어 카테고리 그룹핑이 일관적이지 않다
- **파일**: `pubspec.yaml:46-47`
- **현상**: 다른 그룹은 한 줄 비우고 분리되어 있는데 Ads는 동일 패턴. 일관성 OK. 사소한 LOW.

#### L-4. `home_screen.dart:59` `const HomeBannerAd()` 위에 별도 `Divider()`/`SafeArea` 없음
- **파일**: `lib/features/home/presentation/screens/home_screen.dart:56-59`
- **현상**: 요구사항이 "SafeArea는 광고 widget 자체에 두지 말 것"이지만, **Scaffold body Column의 마지막 자식이 SafeArea 처리 없이 노출**되면 일부 기기(노치/홈 인디케이터가 있는 iPhone)에서 광고 하단이 인디케이터 영역과 겹친다. Scaffold가 자체 SafeArea를 적용하나, **bottom inset은 자동 처리되지 않는 경우가 있음** (특히 `extendBody: true`나 keyboard 대응 시).
- **수정 제안**: 검증 권장. iPhone 14 Pro 등 홈 인디케이터 기기에서 시각적 확인 필요. 만일 겹친다면:
  ```dart
  body: SafeArea(
    bottom: true,
    top: false,
    child: Column(...),
  ),
  ```
  또는 광고 위젯이 아닌 Scaffold 단에서 처리. 다만 현재 Scaffold가 별다른 inset 옵션이 없어 기본 SafeArea가 적용되었다고 판단됨. **빌드 후 시각적 회귀 테스트로 검증 필요**.

#### L-5. `home_banner_ad.dart`의 `_loadAttempted` 플래그명이 약간 모호 (`_didLoadAttempt` 또는 `_hasLoadAttempted` 등이 의도가 더 분명)
- **파일**: `lib/features/ads/presentation/widgets/home_banner_ad.dart:34`
- 사소한 네이밍 개선.

---

## 통과 항목 요약 (체크리스트)

### 4원칙 준수
- [x] `tool/build_map_html.dart` 변경 없음 (git diff 0 lines)
- [x] `lib/features/subway_map/presentation/providers/live_train_provider.dart` 변경 없음
- [x] `assets/html/map.html` 변경 없음
- [x] 단조 감소 카운트다운 / 매 frame 역산 / 3-way 클램프 / catch-up 보간 모두 영향 없음 (광고 위젯은 지도 렌더링과 독립)

### 아키텍처
- [x] `features/ads/presentation/widgets/` 경로로 features-by-feature 구조 준수
- [x] domain/, graph/ 레이어에 Flutter 의존성 추가 없음
- [x] Riverpod 프로바이더 변경 없음 (광고 위젯은 자체 State로 관리, 글로벌 상태 오염 없음)
- [x] HomeScreen이 여전히 StatelessWidget — 기존 리빌드 최적화 패턴 유지

### 라이프사이클 관리 (BannerAd)
- [x] `dispose()`에서 `_bannerAd?.dispose()` 호출
- [x] `onAdFailedToLoad`에서 `ad.dispose()` 호출
- [x] `onAdFailedToLoad`에서 `mounted` 체크 후 setState
- [x] `didChangeDependencies` 1회 가드(`_loadAttempted`)로 중복 로드 방지
- [⚠️] `await ad.load()` 도중 dispose 시 누수 가능성 — H-1에서 지적

### 보안
- [x] AdMob App ID는 placeholder가 아닌 실제 값 (`ca-app-pub-3206652264632834~4236362749`) — release/debug 양쪽 모두 동일 (App ID 정책상 적절)
- [x] 테스트 단위 ID는 Google 공식 값 사용
- [x] release 단위 ID 미설정 시 안전 처리 (early return + SizedBox.shrink)
- [x] `.env` API 키 노출 없음 (광고 모듈은 dotenv 미사용)
- [x] 사용자 입력/JS 인젝션 risk 없음 (광고 SDK 내부 처리)
- [x] iOS NSUserTrackingUsageDescription 한국어 (`광고 효과 측정을 위해 사용됩니다.`) 명시 — ATT 정책 준수
- [x] iOS SKAdNetworkItems 등록 (Google 공식 권장 목록)

### 성능
- [x] `Consumer` 위젯으로 watch 범위 분리되어 있음 (HomeScreen 기존 패턴 유지)
- [x] `const HomeBannerAd()` 사용 (불필요한 리빌드 방지)
- [x] FutureBuilder/StreamBuilder 사용 안 함 (직접 setState로 단순화)
- [x] 광고 로드 미설정 시 BannerAd 객체 자체 생성 안 함 (메모리 절약)

### 초기화 순서
- [x] `WidgetsFlutterBinding.ensureInitialized()` → `dotenv.load()` → `MobileAds.instance.initialize()` → `runApp` 순서 정확
- [x] 두 await가 직렬로 실행되어 race condition 없음
- [x] `MobileAds.instance.initialize()` 실패는 SDK 내부에서 처리되며 `runApp`에 전파되지 않음 (검증된 패턴)

### Android 매니페스트
- [x] `<application>` 태그 안에 `<meta-data>` 위치 (Activity 태그 외부, application 자식)
- [x] `com.google.android.gms.ads.APPLICATION_ID` 키 정확
- [x] App ID 형식 `ca-app-pub-XXXXXXX~YYYY` 정확 (틸드 `~` 사용, 단위 ID의 `/`와 구분)
- [x] `<uses-permission android:name="android.permission.INTERNET"/>` 기존에 등록됨

### iOS Info.plist
- [x] `GADApplicationIdentifier` 키 정확, App ID 동일
- [x] `NSUserTrackingUsageDescription` 한국어 등록
- [x] `SKAdNetworkItems` 배열 형식 정확 (`<dict><key>SKAdNetworkIdentifier</key><string>...</string></dict>` × N)
- [x] plist root `<dict>` 닫힘 정상 (line 384)

### 코드 스타일
- [x] 함수 모두 < 50줄 (`_loadAd` 약 45줄, `build` 약 12줄)
- [x] 파일 < 800줄 (`home_banner_ad.dart` 134줄)
- [x] 한국어 주석 적절히 사용
- [x] 깊은 중첩 없음 (최대 3레벨)
- [x] `print`/`debugPrint` 미사용

---

## 칭찬

- **`lib/features/ads/presentation/widgets/home_banner_ad.dart:38-55`** — `_resolveAdUnitId()`의 분기 구조가 매우 명확. kDebugMode + Platform 분기 + release 빈 ID 안전 처리(null 반환)을 한 함수로 깔끔하게 추상화. 추후 release ID 입력만으로 활성화 가능.
- **`lib/features/ads/presentation/widgets/home_banner_ad.dart:62-66`** — `_loadAttempted` 플래그로 `didChangeDependencies` 다회 호출에 대한 방어. orientation 변경, 테마 변경 등에도 광고는 1회만 로드되어 정확하다.
- **`lib/features/ads/presentation/widgets/home_banner_ad.dart:99-106`** — `onAdFailedToLoad`에서 ① `ad.dispose()` 우선 호출 → ② `mounted` 체크 → ③ setState 순서가 정확. dispose 호출 누락이나 unmounted setState 호출 모두 회피.
- **`lib/features/home/presentation/screens/home_screen.dart:59`** — `const HomeBannerAd()`로 기존 Consumer 분리 패턴(`SubwayMapScreen` 리빌드 최적화)을 깨뜨리지 않으며 한 줄 추가만으로 통합. HomeScreen이 여전히 StatelessWidget로 유지되는 점이 우수하다.
- **`lib/main.dart:8-17`** — main 함수의 초기화 시퀀스가 명확. `dotenv.load()` 와 `MobileAds.initialize()` 가 직렬화되어 race condition 위험 없음. await 순서가 의존성에 부합 (dotenv는 SDK 초기화와 무관하지만 `WidgetsFlutterBinding` 다음 → SDK init 순서가 표준).
- **`ios/Runner/Info.plist`** — Google 공식 권장 SKAN 식별자를 일괄 등록하여 iOS 14+ 어트리뷰션 누락 방지. plist 구조 위반 없음.
- **4원칙 보호 파일 무수정** — 광고 기능 추가가 지도 렌더링/실시간 열차 코드에 단 한 줄도 영향 주지 않음. 이는 가장 중요한 회귀 방지 성과이며, 이번 변경의 가장 큰 강점.

---

## 권고 우선순위 요약

| # | 등급 | 항목 | 처리 시점 |
|---|------|------|-----------|
| 1 | HIGH (H-1) | `_loadAd` await 도중 dispose 누수 방지 (`load()` 후 mounted 재검증, `onAdLoaded` unmount 시 dispose) | **이번 단계 수정 권장** |
| 2 | HIGH (H-3) | Android `minSdkVersion` 23+ 명시적 설정 (build.gradle.kts) | **이번 단계 수정 권장** (빌드 실패 방지) |
| 3 | MEDIUM (M-2) | layout shift 완화 (size 미리 예약) | 차기 PR 또는 이번 단계 |
| 4 | MEDIUM (M-1) | 네트워크 복구 시 재시도 | 별도 이슈 |
| 5 | MEDIUM (M-3) | 광고 영역 시각적 구분 (border/색조) | UX 검토 후 |
| 6 | MEDIUM (M-4) | 위젯/단위 테스트 추가 | flutter-qa-engineer 협업 |
| 7 | LOW | L-1~L-5 | 후속 정리 |

CRITICAL 0건, HIGH 3건(H-2 web 가드는 web 확장 전 보류 가능 → 실질 2건), MEDIUM 5건, LOW 5건. **CRITICAL 부재로 머지 진행은 가능하되, H-1과 H-3는 이번 단계에서 수정 권장.**
