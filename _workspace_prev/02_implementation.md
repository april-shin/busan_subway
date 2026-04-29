# Phase 02 — 구현 산출물 (HomeScreen 하단 AdMob 배너)

## 개요

홈 화면(`/`) 지도 하단에 AdMob 적응형(앵커드) 배너 광고를 추가했다. 디버그 빌드는 Google 공식 테스트 단위 ID, 릴리스 빌드는 추후 발급될 실 단위 ID(현재 빈 문자열) 사용. 단위 ID 미설정 시 광고 로드 자체를 건너뛰며 `SizedBox.shrink()` 로 안전 처리한다.

## 변경된 파일 목록

### 신규 생성
- `/Users/april/StudioProjects/seoul_subway/lib/features/ads/presentation/widgets/home_banner_ad.dart` — 배너 광고 위젯 (Stateful, 라이프사이클 관리)
- `/Users/april/StudioProjects/seoul_subway/_workspace/02_implementation.md` — 본 산출물

### 수정
- `/Users/april/StudioProjects/seoul_subway/pubspec.yaml` — `google_mobile_ads: ^5.3.1` 추가 ("Ads" 섹션 신설)
- `/Users/april/StudioProjects/seoul_subway/lib/main.dart` — `MobileAds.instance.initialize()` await 추가 (`runApp` 이전, `dotenv.load` 이후)
- `/Users/april/StudioProjects/seoul_subway/lib/features/home/presentation/screens/home_screen.dart` — body Column 끝에 `const HomeBannerAd()` 추가, import 1줄 추가
- `/Users/april/StudioProjects/seoul_subway/android/app/src/main/AndroidManifest.xml` — `<application>` 안에 AdMob `APPLICATION_ID` meta-data 추가
- `/Users/april/StudioProjects/seoul_subway/ios/Runner/Info.plist` — `GADApplicationIdentifier`, `NSUserTrackingUsageDescription`, `SKAdNetworkItems` 77개 추가

## 패키지 버전

| 패키지 | 버전 | 비고 |
|---|---|---|
| google_mobile_ads | `^5.3.1` | Flutter 3.41.7 / Dart 3.11.5 (sdk ^3.11.0)와 호환되는 5.x 안정 버전. 캐럿 표기로 5.x 마지막 버전까지 자동 호환 |

## 핵심 의사결정

### 1. 적응형(Anchored Adaptive) 배너 선택
- 요구사항(`_workspace/00_requirements.md`)이 명시적으로 "anchored adaptive banner 권장"
- 디바이스 폭에 맞춰 최적 높이 산정 → 다양한 기기에서 광고 영역이 일관되게 보임
- `AdSize.getAnchoredAdaptiveBannerAdSize(Orientation.portrait, width)` 사용. width는 `MediaQuery.of(context).size.width.truncate()` 로 정수 변환
- 사이즈가 `null` 이면 (구버전 기기 또는 폭 0 등) 로드 자체 포기

### 2. `didChangeDependencies` 에서 광고 로드
- `MediaQuery.of(context)` 는 `initState` 시점에는 안전하지 않을 수 있음
- `_loadAttempted` 플래그로 1회만 호출되도록 가드 (`didChangeDependencies` 가 여러 번 트리거되어도 광고는 한 번만 로드)
- 대안인 `WidgetsBinding.instance.addPostFrameCallback` 보다 흐름이 단순하고 첫 frame 직전에 로드를 시작할 수 있어 채택

### 3. 빈 release ID 안전 처리
- `_kAndroidReleaseUnitId = ''`, `_kIosReleaseUnitId = ''` (TODO 주석)
- `_resolveAdUnitId()` 가 `null` 반환 → `_loadAd()` 가 즉시 return → BannerAd 객체 자체를 생성하지 않음
- `build` 의 `_isLoaded || _failed || ad == null` 가드로 항상 `SizedBox.shrink()` 반환
- 이렇게 하면 release 빌드에서도 절대 크래시하지 않음 (placeholder 단위 ID 로 `load()` 호출하면 SDK 가 throw 할 수 있음)

### 4. `SizedBox.shrink()` 로 통일된 비노출 정책
- 미초기화 / 로드 진행 중 / 실패 / release 미설정 → 모두 `SizedBox.shrink()` (높이 0)
- 광고가 로드된 직후에만 광고 컨테이너가 갑자기 등장 → Column 의 `Expanded(SubwayMapScreen)` 가 광고 높이만큼 줄어듦. 이는 적응형 배너 광고의 표준 패턴이며 사용자가 "지도가 흔들렸다" 고 느끼지 않도록 광고 영역이 한 번 자리잡으면 유지됨 (실패 시에만 다시 사라짐).

### 5. SafeArea 미적용 (위젯 자체)
- 요구사항: "SafeArea는 광고 widget 자체에 두지 말 것"
- `Scaffold` 가 자체 SafeArea 처리 + Column 의 자연스러운 위치 → 별도 SafeArea 불필요
- 광고 컨테이너 배경은 `Theme.of(context).colorScheme.surface` 로 통일하여 다크/라이트 테마에 자연스럽게 어울림

### 6. iOS SKAdNetworkItems 77개 등록
- google_mobile_ads README 권장 SKAN ID 전체 목록 (중복 제거 후 77개)
- 중복이 발생하지 않도록 `plutil -lint` 로 plist 문법 검증 + `grep | sort | uniq -d` 로 중복 검사 통과
- iOS 14+ 의 SKAdNetwork 광고 어트리뷰션을 위해 필수

### 7. Android `INTERNET` 권한
- 이미 기존 `AndroidManifest.xml` 에 `<uses-permission android:name="android.permission.INTERNET"/>` 등록되어 있음 (서울 열린데이터 API 용) → AdMob 도 그대로 사용

## 알려진 제약/주의사항

### iOS 빌드 시 `pod install` 필요
- google_mobile_ads 추가 후 첫 iOS 빌드 전 `cd ios && pod install` 필요
- Flutter 3.41 + iOS 빌드 파이프라인이면 `flutter run` 시 자동 실행되지만, CocoaPods 캐시 충돌이 의심되면 `pod repo update && pod install` 수동 실행 권장
- google_mobile_ads 5.x 는 iOS 12.0+ 필요 → `ios/Podfile` 의 `platform :ios` 가 12.0 이상이어야 함 (현재 프로젝트는 Flutter 기본값 사용)

### Android `minSdkVersion`
- google_mobile_ads 5.x 는 minSdkVersion 23+ 필요. 현재 프로젝트의 `android/app/build.gradle` 미확인. minSdkVersion 22 이하라면 빌드 실패 → 23 이상으로 상향 필요. (이번 변경에는 build.gradle 미수정. Phase 5 의 `flutter pub get` 후 빌드 시도에서 오류가 나면 후속 조치)

### release 단위 ID 발급 후 작업
- AdMob 콘솔 → 앱 추가 → 광고 단위 생성 (배너) → 단위 ID 발급
- `home_banner_ad.dart` 의 `_kAndroidReleaseUnitId`, `_kIosReleaseUnitId` 채우기
- TODO 주석 제거

### 광고 미초기화/로드 실패 시 빈 공간 처리
- 광고가 한 번 로드된 뒤에 `onAdFailedToLoad` 가 트리거되는 경우는 일반적으로 없으나, 만일 발생하면 광고가 사라지면서 Column 이 재배치됨 (지도가 약간 늘어남). 사용자에게 큰 위화감은 없지만, 더 부드러운 UX 가 필요하면 `_failed` 시에도 빈 광고 사이즈만큼의 공간을 유지하는 정책 검토 가능.

### 4원칙 미준수 코드 변경 없음 (확인 완료)
- `tool/build_map_html.dart`, `lib/features/subway_map/presentation/providers/live_train_provider.dart`, `assets/html/map.html` 모두 수정하지 않음
- 기존 Riverpod 프로바이더 / 라우팅 / 위젯 트리 변경 없음 (HomeScreen Column 끝에 위젯 1개 추가만)

## 다음 단계 (오케스트레이터)
1. `flutter pub get` (pubspec.lock 업데이트)
2. `flutter analyze` (정적 분석 통과 확인)
3. iOS: `cd ios && pod install`
4. subway-code-reviewer + subway-requirements-reviewer 병렬 실행
5. 디바이스/시뮬레이터에서 디버그 빌드로 광고 노출 확인 (테스트 ID로 "Test Ad" 라벨 표시되는지)
