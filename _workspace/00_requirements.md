# 요구사항: 홈 화면 지도 하단 AdMob 배너 추가

## App ID
- 통합: `ca-app-pub-3206652264632834~4236362749`
- iOS Info.plist `GADApplicationIdentifier`
- Android AndroidManifest.xml `com.google.android.gms.ads.APPLICATION_ID` meta-data

## Ad Unit ID 정책
- 사용자가 아직 광고 단위 미발급
- kDebugMode → Google 공식 테스트 ID
  - Android: `ca-app-pub-3940256099942544/6300978111`
  - iOS:    `ca-app-pub-3940256099942544/2934735716`
- release 모드 실제 ID는 placeholder('') + TODO 주석. 빈 값이면 SizedBox.shrink()로 안전 처리 (크래시 금지)

## 기술 스택
- 패키지: `google_mobile_ads ^5.x`
- main.dart: `WidgetsFlutterBinding.ensureInitialized()` + `MobileAds.instance.initialize()` await 후 runApp
- 사이즈: anchored adaptive banner 권장 (가로폭 = MediaQuery.of(context).size.width)

## UI 통합
- HomeScreen body Column 끝에 광고 배너 추가
- 별도 위젯: `lib/features/ads/presentation/widgets/home_banner_ad.dart`
- StatefulWidget으로 BannerAd 라이프사이클(initState load / dispose) 관리
- 미로드/실패/release-empty-id → SizedBox.shrink()

## 플랫폼 설정
- Android: `<application>` 안에 `<meta-data>` APPLICATION_ID
- iOS: GADApplicationIdentifier, SKAdNetworkItems(google_mobile_ads README 권장), NSUserTrackingUsageDescription("광고 효과 측정을 위해 사용됩니다." 한국어)

## 제약 (절대 준수)
- 4원칙 코드 절대 미수정: `tool/build_map_html.dart`, `lib/features/subway_map/presentation/providers/live_train_provider.dart`
- 기존 Riverpod, 라우팅, 지도 렌더링 변경 없음
- 회귀 금지

## 검증
- subway-code-reviewer + subway-requirements-reviewer 병렬
- `flutter analyze` 에러 0건
- `flutter pub get` 통과 (Flutter 3.41.7 / Dart 3.11.5)
- Flutter PATH: `~/development/flutter/bin/flutter`
