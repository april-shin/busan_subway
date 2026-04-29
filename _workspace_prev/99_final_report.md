# 최종 보고: HomeScreen 하단 AdMob 배너 추가

## 결과: 통과

- 코드 리뷰: HIGH 3건 수정 후 PASS
- 요구사항 리뷰: 10/10 (100%)
- `flutter pub get`: 통과
- `flutter analyze`: 에러 0건 (info/warning 67건은 모두 기존 tool/ 스크립트, 본 변경 무관)
- 4원칙 보호 파일 무수정 (git diff 0)

## 변경 파일

### 신규
- `lib/features/ads/presentation/widgets/home_banner_ad.dart` — Stateful 배너 위젯

### 수정 (Dart)
- `lib/main.dart` — `MobileAds.instance.initialize()` await 후 runApp
- `lib/features/home/presentation/screens/home_screen.dart` — Column 끝에 `const HomeBannerAd()` + import 1줄

### 의존성
- `pubspec.yaml` — `google_mobile_ads: ^5.3.1` 추가 (Ads 섹션 신설)
- `pubspec.lock` — 락파일 갱신
- `ios/Podfile.lock` — pub get으로 자동 갱신

### 플랫폼
- `android/app/src/main/AndroidManifest.xml` — `<meta-data>` APPLICATION_ID
- `android/app/build.gradle.kts` — `minSdk = maxOf(flutter.minSdkVersion, 23)`
- `ios/Runner/Info.plist` — GADApplicationIdentifier + NSUserTrackingUsageDescription(한국어) + SKAdNetworkItems 77개

## 핵심 동작

- **debug 빌드** → Google 공식 테스트 광고 단위 ID 사용 (Android `…/6300978111`, iOS `…/2934735716`)
- **release 빌드** → placeholder 빈 문자열 → `_resolveAdUnitId() == null` → 로드 시도 안 함 → `SizedBox.shrink()` (크래시 0)
- **web 빌드** → `kIsWeb` early return → 광고 영역 0 (회귀 0)
- **위젯 dispose 중 로드 완료** → mounted 가드 3지점에서 `dispose()` 호출 (메모리 누수 0)
- **anchored adaptive banner** → `MediaQuery` 가로폭 기반, 디바이스 별로 최적 높이

## release 시 해야 할 일

1. AdMob 콘솔 → 앱 → 광고 단위 → 배너 단위 발급
2. `lib/features/ads/presentation/widgets/home_banner_ad.dart` 의 `_kAndroidReleaseUnitId`, `_kIosReleaseUnitId` 빈 문자열 → 발급받은 ID로 교체
3. TODO 주석 제거
4. iOS 첫 빌드 시 `cd ios && pod install`

## 처리하지 않은 항목 (의도적, 오버엔지니어링 회피)

- MEDIUM (failed 영구화 재시도, layout shift 보강, 광고 영역 시각 구분, 위젯 테스트, SKAN 개수 문서)
- LOW (스타일/네이밍/SafeArea 시각 검증)

필요 시 별도 이슈로 추적.
