# Phase 04 — 요구사항 리뷰 (HomeScreen 하단 AdMob 배너)

## 원래 요청

> 앱 메인 페이지 지하철 맵 하단에 광고배너 추가하자 ca-app-pub-3206652264632834~4236362749

후속 명확화:
- App ID `ca-app-pub-3206652264632834~4236362749`는 통합 ID (iOS GADApplicationIdentifier + Android APPLICATION_ID)
- Ad Unit ID는 미발급 → kDebugMode 테스트 ID 사용, release placeholder 빈 값
- 자세한 요구사항: `_workspace/00_requirements.md`

---

## 1. 기능 완전성 (충족도 체크리스트)

| # | 요구사항 | 결과 | 근거 |
|---|---------|------|------|
| 1 | App ID 양 플랫폼 정확 반영 (`ca-app-pub-3206652264632834~4236362749`) | ✅ | `AndroidManifest.xml:38`, `Info.plist:70` 모두 정확. grep 으로 양쪽 1건씩 확인 (오타·중복 없음) |
| 2 | kDebugMode 테스트 단위 ID 정확 | ✅ | `home_banner_ad.dart:17` Android `ca-app-pub-3940256099942544/6300978111`, `:19` iOS `ca-app-pub-3940256099942544/2934735716` — Google 공식 테스트 ID와 일치 |
| 3 | release placeholder 빈 문자열 + SizedBox.shrink() 안전 처리 | ✅ | `_kAndroidReleaseUnitId = ''`, `_kIosReleaseUnitId = ''` (`:22-24`). `_resolveAdUnitId()` 가 빈 값일 때 `null` 반환 → `_loadAd()` 즉시 return → `_bannerAd` 가 항상 null → `build()` 에서 `SizedBox.shrink()` |
| 4 | google_mobile_ads 패키지 추가 | ✅ | `pubspec.yaml:47` `google_mobile_ads: ^5.3.1` (Ads 섹션 신설) |
| 5 | main.dart MobileAds.initialize() await 후 runApp | ✅ | `main.dart:11` `await MobileAds.instance.initialize();` — `runApp(:12)` 이전, `dotenv.load(:10)` 이후 |
| 6 | HomeScreen 지도 하단(Column 끝)에 배너 배치 | ✅ | `home_screen.dart:59` `const HomeBannerAd()` 가 Column 마지막 자식. 위 순서: SearchBar → Expanded(SubwayMapScreen) → HomeBannerAd |
| 7 | 별도 파일로 분리 (`lib/features/ads/presentation/widgets/home_banner_ad.dart`) | ✅ | 신규 파일 생성, feature-scoped 경로 정확 |
| 8 | iOS NSUserTrackingUsageDescription 한국어 | ✅ | `Info.plist:71-72` "광고 효과 측정을 위해 사용됩니다." |
| 9 | iOS SKAdNetworkItems (google_mobile_ads README 권장) | ✅ | `Info.plist:73-383` 77개 항목 등록. plist 문법 검증 통과 보고됨 |
| 10 | Android `<meta-data>` APPLICATION_ID | ✅ | `AndroidManifest.xml:36-38` `<application>` 안 (flutterEmbedding 다음에 위치, scope 정확) |

**충족 항목: 10/10 (100%)**

---

## 2. 의도 부합성

| 요구사항 | 구현 | 부합 | 비고 |
|---------|------|------|------|
| App ID는 통합 ID | iOS·Android 모두 동일 ID 박음 | ✅ | 정확 |
| 단위 ID 미발급 시 크래시 금지 | `_resolveAdUnitId()` null → 로드 자체 미시도 → `SizedBox.shrink()` | ✅ | placeholder 로 `BannerAd.load()` 호출 시 SDK 가 throw 할 가능성을 사전 차단 |
| Anchored adaptive banner 권장 | `AdSize.getAnchoredAdaptiveBannerAdSize(Orientation.portrait, width)` 사용 | ✅ | 요구사항 명시 패턴 그대로 |
| StatefulWidget 라이프사이클 관리 | initState→didChangeDependencies(1회 가드)→dispose() 흐름 정확 | ✅ | `_loadAttempted` 플래그로 중복 로드 방지, `dispose()` 에서 `_bannerAd?.dispose()` 호출 |
| 미로드/실패/release-empty → SizedBox.shrink() | `if (!_isLoaded \|\| _failed \|\| ad == null) return SizedBox.shrink()` | ✅ | 3가지 케이스 일괄 처리 |

---

## 3. 엣지 케이스 검증

| 시나리오 | 처리 여부 | 비고 |
|---------|---------|------|
| 적응형 사이즈 계산 실패 (구버전 기기/폭 0) | ✅ `size == null` 가드로 광고 미노출 | `home_banner_ad.dart:80-83` |
| 비동기 await 중 위젯 unmount | ✅ `if (!mounted) return` 2회 (`:84`, `:92`, `:100`) | 메모리 누수·setState-after-dispose 방지 |
| 미지원 플랫폼 (web/desktop) | ✅ `Platform.isAndroid/isIOS` 외 → null → 미노출 | google_mobile_ads 자체가 모바일 전용이므로 합리적 |
| 광고 로드 실패 (`onAdFailedToLoad`) | ✅ `ad.dispose()` 호출 후 상태 reset (`_failed = true`) | 메모리 정리 정확. 다만 자동 재시도 없음 — 정책상 보수적 선택으로 적절 |
| 광고 로드 후 실패 → 갑자기 사라짐 | ⚠ 발생 시 Column 재배치 (지도 늘어남) | 산출물 자체에 명시(`02_implementation.md` 알려진 제약 7번). 일반적이지 않은 케이스이므로 후속 개선 후보 |
| 회전(Orientation 변경) | ⚠ 회전 시 광고 사이즈 재계산 미수행 | 요구사항이 portrait 한정이므로(`AdSize.getAnchoredAdaptiveBannerAdSize(Orientation.portrait, width)` 명시) 현재 범위에서 OK. iPad/landscape 지원 확장 시 후속 작업 필요 |
| `MediaQuery` 비안전 시점 | ✅ `didChangeDependencies` 이동, 1회 가드 | `initState`에서 호출 안 함 — 정확 |
| dotenv 미로드 / .env 부재 | ✅ `MobileAds.initialize()` 가 dotenv.load 이후 → dotenv 실패 시 main 자체가 throw, 광고 초기화 영향 없음 (현 동작 보존) |

---

## 4. 오버 엔지니어링 감지

| 항목 | 결과 | 비고 |
|------|------|------|
| Riverpod 프로바이더 신설 | ✅ 없음 | 단순 위젯, 상태는 위젯 내부 State 로 충분 — 적절한 판단 |
| 라우팅 변경 | ✅ 없음 | go_router config 미수정 |
| 별도 도메인/리포지토리 레이어 | ✅ 없음 | 광고는 외부 SDK 호출이라 도메인 추상화 불필요 |
| Riverpod family/AsyncValue 래핑 | ✅ 없음 | 광고 로딩 단발성 + 위젯 종속 → 위젯 State 가 적절 |
| 미사용 옵션/파라미터 | ✅ 없음 | `BannerAd` 생성자 인자가 모두 사용됨 |
| 과도한 추상화 (인터페이스/팩토리) | ✅ 없음 | 단일 위젯, 직접 SDK 호출 — 단순 |

**오버엔지니어링: 발견되지 않음.** 단순 위젯이라는 요구사항 의도에 부합하는 최소 구조.

---

## 5. 회귀 위험 분석

요청 유형이 **신규 기능 추가**이므로 "버그 수정 회귀 검증" 항목은 해당 없음. 다만 사용자가 명시적으로 변경 영향 분석을 요청했으므로 별도 점검:

### 5.1 4원칙 코드 변경 여부 (절대 금지 영역)

| 영역 | 변경 | 근거 |
|------|------|------|
| `tool/build_map_html.dart` | ❌ 변경 없음 | `git status tool/` clean |
| `lib/features/subway_map/presentation/providers/live_train_provider.dart` | ❌ 변경 없음 | `git status` 미포함 |
| `assets/html/map.html` | ❌ 변경 없음 (작업 시작 전부터 별도 변경. 본 작업과 무관) | `git status` 의 기존 항목 확인 |

→ **4원칙 절대 무손상.** ✅

### 5.2 기존 Riverpod / 라우팅 / 지도 렌더링 회귀

- **Riverpod**: HomeBannerAd 가 `ConsumerWidget` 이 아닌 일반 `StatefulWidget` 으로 추가되어 ProviderScope 와 무관. 기존 `selectedStationsProvider`, `liveTrainsProvider` 등에 영향 없음.
- **라우팅**: `app.dart`/go_router 설정 미변경 (git diff 미발견).
- **지도 렌더링**: `SubwayMapScreen`/`SvgWebView` 코드 미변경. 다만 다음 한 가지만 확인 필요 ↓

### 5.3 HomeScreen Column 영역 축소가 SubwayMapScreen 에 미치는 영향

```dart
Column(
  children: [
    SearchBar,             // 고정 높이
    Expanded(SubwayMapScreen),  // 남은 공간을 채움
    HomeBannerAd,          // 광고 로드 후 ~50-60dp
  ],
)
```

- `Expanded` 가 광고 높이만큼 줄어듦 → WebView 의 `viewport` 가 변경됨.
- WebView 의 줌/팬은 CSS `transform: matrix(...)` 기반 (CLAUDE.md 지도 렌더링 섹션 참조). 컨테이너 크기가 변해도 transform 기준점만 재계산되며, 광고 로드 시점에 1회 layout 변경이 발생할 뿐 줌/팬 동작 자체에 회귀 위험은 없음.
- 광고 로드 직후 한 번 지도 영역이 줄어드는 시각적 변화가 발생함 → 산출물에서 "사용자가 흔들렸다고 느끼지 않도록 광고 영역이 한 번 자리잡으면 유지됨" 으로 정책 명시. 적응형 배너 광고의 표준 패턴.
- **위험 등급: Low.** 회귀 가능성 낮음. 만약 광고 로드 후 실패 시 사라지면 Column 재배치 발생(산출물 알려진 제약 7번에 명시) — 일반적 시나리오는 아님.

### 5.4 main.dart 초기화 순서 회귀

순서: `WidgetsFlutterBinding.ensureInitialized` → `dotenv.load` → `MobileAds.initialize` → `runApp(ProviderScope)`

- `dotenv.load` 가 가장 먼저 → SEOUL_API_KEY 검증 로직이 영향받지 않음.
- `MobileAds.initialize` 는 await 됨 → 첫 frame 전 SDK 준비 완료. AdMob 공식 권장 패턴.
- `ProviderScope` 는 가장 마지막 → Riverpod 초기화 기존과 동일.
- `MobileAds.initialize()` 가 throw 할 경우 앱 자체가 실행 안 됨. 일반적으로는 throw 하지 않음(SDK 가 초기화 실패해도 결과 객체로 반환). 단, 매우 보수적으로 본다면 try/catch 로 감싸 광고 실패가 앱 실행을 막지 않게 할 수 있음. 현재 미구현 — 우선순위 낮음.
- **위험 등급: Low.**

### 5.5 영향 범위 grep 결과

신규 파일 `home_banner_ad.dart` 의 import 처:
- `home_screen.dart:6` (1곳)

`MobileAds.instance` 호출처:
- `main.dart:11` (1곳)

→ 영향 범위가 명확히 제한적. 호출처 폭증·전이적 변경 없음.

### 5.6 회귀 위험 등급

**Low.** 신규 파일 1개 + import 1줄 + Column 자식 1개 + main 초기화 1줄 + 플랫폼 설정. 기존 코드 의미 변경은 0건.

---

## 6. 사용자 경험 관점

- ✅ 디버그 빌드 → "Test Ad" 라벨 노출 (Google 공식 테스트 단위 ID 동작)
- ✅ release 빌드 + 단위 ID 미발급 → 광고 영역 0px, 지도 전체 노출 (보호 동작)
- ✅ 다크/라이트 테마 → `Theme.of(context).colorScheme.surface` 배경으로 자연스러움
- ⚠ 광고 로드 직후 1회 layout 변경 발생 (지도 영역 축소) — 적응형 배너의 표준 동작이며 산출물에 정책 명시
- ⚠ 광고 로드 후 실패 시 광고 사라짐 → 지도 영역 재팽창 (드문 케이스, 산출물 알려진 제약에 기록)

---

## 7. 검증 메모

- `flutter test` 직접 실행은 본 리뷰 범위 외 (오케스트레이터 단계 5에서 수행). 본 변경은 광고 위젯 단독으로 테스트가 추가되지 않았음 — 테스트 추가는 google_mobile_ads SDK 모킹이 어려워 정책상 통합 테스트 단계에서 처리 권장.
- `flutter analyze` 직접 실행은 본 리뷰 범위 외 (오케스트레이터 단계 5).

---

## 종합 판정

- **충족률: 10/10 (100%)**
- **회귀 위험: Low** (4원칙 무손상, Riverpod/라우팅/렌더링 무변경, 영향 범위 제한적)
- **판정: 통과 (조건 없음)**

### 권장 보완 (선택, 우선순위 순)

1. **[Low]** `MobileAds.instance.initialize()` 를 try/catch 로 감싸 광고 SDK 초기화 실패가 앱 시작을 막지 않게 (보수적 안전망).
2. **[Low]** `onAdFailedToLoad` 후 자동 재시도 정책 검토 (현재는 한 번 실패 시 영구 미노출). 사용자 트래픽 손실이 우려되면 일정 시간 뒤 1회 재시도 추가.
3. **[Low]** release 단위 ID 발급 후 `_kAndroidReleaseUnitId`/`_kIosReleaseUnitId` 채우고 TODO 주석 제거 (산출물에 이미 안내됨).
4. **[Low]** 광고 위젯 단위 테스트 추가 — google_mobile_ads SDK fake 가 어려우므로 `_resolveAdUnitId()` 만 분리 가능한 형태로 리팩토링 후 테스트 (선택적, 현재 범위에서는 불필요).

### 권장 즉시 수정

**없음.** 모든 명시적·암묵적 요구사항이 충족되었고 오버엔지니어링도 없음.
