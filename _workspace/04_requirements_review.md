# 04 Requirements Review — UI 일관성 토큰 시스템

작성: subway-requirements-reviewer
대상: Phase 2 (a/b/c) 산출물 검증
연결 문서: `00_requirements.md`, `01_architecture.md`, `02a/02b/02c_implementation.md`

---

## 사용자 원래 요청

> 1. "안드로이드랑 iOS 컴포넌트 모듈이나 폰트사이즈가 너무 차이가 커서 일관적으로 관리할수 있도록 처리해줘"
> 2. "일괄변경하자" — 일괄 마이그레이션 선택

---

## 1. 사용자 확정 디자인 결정 — 반영 검증

| # | 사용자 결정 | 구현 위치 | 결과 |
|---|---|---|---|
| 1 | 한글 전용 폰트 추가 X (시스템 폰트 유지) | `app_typography.dart` 모든 슬롯 fontFamily 미지정 | ✅ |
| 2 | textScaler clamp 0.9~1.15 | `lib/app.dart:97-101` `clamp(min:0.9, max:1.15)` | ✅ |
| 3 | Typography.material2021(Android) | `app_theme.dart:17` 정확히 일치 | ✅ |
| 4 | BackButton.adaptive 도입 | `app_theme.dart:23-25` `actionIconTheme.backButtonIconBuilder = BackButtonIcon()` (옵션 A 전역 적용) | ✅ |
| 5 | 토큰 위치 lib/core/theme/tokens/ | 3 파일(typography/dimensions/radii) 정확한 경로 | ✅ |

**충족: 5/5 (100%)**

---

## 2. 기능 완전성 — 명시 요구사항

### 폰트사이즈 일관 관리
- ✅ Material 3 textTheme 13 슬롯 정의 (`appTextTheme`)
- ✅ 한국어 가독성을 고려한 height(line-height) 조정 (본문 1.45)
- ✅ AppBar/카드/배지/카운트다운 슬롯 시맨틱 분리

### 컴포넌트 모듈 일관성
- ✅ `AppSpacing`(4의 배수 그리드) 정의 (space2~48)
- ✅ `AppPadding`(시맨틱 별칭: screenHorizontal, cardPadding 등)
- ✅ `AppIconSize`(xs/sm/md/lg/xl)
- ✅ `AppRadius` / `AppBorderRadius` (xs/sm/md/lg/pill)
- ⚠ **부분 구현**: 토큰 정의는 있으나 **실제 사용처 0건** — `grep AppSpacing|AppPadding|AppIconSize|AppRadius|AppBorderRadius lib/features/` 결과 0. EdgeInsets 매직넘버 23곳, BorderRadius/Icon size 매직넘버 다수가 그대로 남음. 사용자 원문 "컴포넌트 모듈" 요구를 부분만 충족.

### iOS/Android 차이 해소
- ✅ Typography.material2021(android) 적용 — iOS에서도 Roboto 메트릭

### 일괄 마이그레이션 (인라인 TextStyle)
- ✅ route_result_screen.dart 13곳, arrival_card.dart 5곳, search_bar_widget.dart 2곳, transfer_row.dart 2곳, arrival_info_screen.dart 3곳 = **25곳 마이그레이션 완료**
- ❌ **누락 7곳 발견**: 설계 문서 "station_picker / station_detail 등은 인라인 TextStyle 미발견"이라고 명시했으나 실제 grep 결과 7곳 존재
  - `lib/features/station_detail/presentation/screens/station_detail_screen.dart:81` — 노선 배지 (white/bold)
  - `lib/features/station_detail/presentation/screens/station_detail_screen.dart:90` — 역명(fontSize:22 bold)
  - `lib/features/station_detail/presentation/screens/station_detail_screen.dart:100` — 역 번호(grey[600])
  - `lib/features/station_detail/presentation/screens/station_detail_screen.dart:110` — "환승 노선" 헤더(fontSize:16 bold)
  - `lib/features/route_search/presentation/screens/station_picker_screen.dart:73` — "검색 결과 없음"(grey[500])
  - `lib/features/route_search/presentation/screens/station_picker_screen.dart:156` — 역명 타일(w500)
  - `lib/features/route_search/presentation/screens/station_picker_screen.dart:192` — _LineBadge(white/11/bold)

**"일괄 변경" 의도 위반**: 사용자가 점진적이 아닌 일괄 선택했음에도 7곳이 누락된 채 완료 처리됨. station_detail_screen은 라우터에 등록되어 실제 사용되는 화면(`/station/:stationId`).

---

## 3. 기능 완전성 종합 표

| 항목 | 상태 |
|---|---|
| Material 3 textTheme 13슬롯 정의 | ✅ |
| Typography.material2021(android) | ✅ |
| textScaler clamp 0.9~1.15 | ✅ |
| BackButton.adaptive 전역 적용 | ✅ |
| 토큰 파일 3개 신규 (typography/dimensions/radii) | ✅ |
| 인라인 TextStyle 마이그레이션 — route_result_screen | ✅ |
| 인라인 TextStyle 마이그레이션 — arrival_card | ✅ |
| 인라인 TextStyle 마이그레이션 — arrival_info_screen | ✅ |
| 인라인 TextStyle 마이그레이션 — search_bar_widget | ✅ |
| 인라인 TextStyle 마이그레이션 — transfer_row | ✅ |
| 인라인 TextStyle 마이그레이션 — **station_detail_screen** | ❌ 누락 4곳 |
| 인라인 TextStyle 마이그레이션 — **station_picker_screen** | ❌ 누락 3곳 |
| EdgeInsets/Icon size 매직넘버 → AppSpacing/AppIconSize 적용 | ❌ 미적용 (토큰만 정의, 사용처 0) |
| BorderRadius 매직넘버 → AppBorderRadius 적용 | ❌ 미적용 |
| 회귀 테스트 (4원칙) 통과 | ✅ 19/19 |
| 신규 토큰/테마 단위 테스트 | ✅ 59/59 |

**충족률**: 11/15 (73%) — 명시 핵심 요구사항만 카운트할 경우.

---

## 4. 의도 부합성

| 사용자 의도 | 구현 | 부합 |
|---|---|---|
| "iOS/Android 폰트사이즈 차이 일관 관리" | Typography.material2021(android) + textTheme 13슬롯 | ✅ |
| "컴포넌트 모듈 차이 일관 관리" | spacing/padding/iconSize/radii 토큰 정의됨 | ⚠ 정의만 있고 사용처가 없어 사실상 미적용 |
| "일괄 변경하자" (점진 X) | TextStyle 25곳 일괄 + 7곳 누락 | ⚠ 부분 일괄 — station 영역 제외됨 |

---

## 5. 엣지 케이스 검증

| 시나리오 | 처리 |
|---|---|
| iOS 사용자가 시스템 폰트 200% 설정 | ✅ clamp 1.15로 제한 (`text_scaler_clamp_test.dart` 검증) |
| iOS 사용자가 시스템 폰트 50% 설정 | ✅ clamp 0.9로 제한 |
| Android 15 edge-to-edge | ✅ SafeArea(top:false) 보존 |
| BackButton iOS Cupertino 표시 | ✅ BackButtonIcon이 platform 자동 감지 (시각 확인은 QA 단계 필요) |
| station_detail_screen에서 fontSize:22 역명 — clamp 1.15 적용 시 25.3px, 레이아웃 영향 | ⚠ 인라인 TextStyle이 남아 textTheme 일관성에서 빠지므로, clamp는 적용되지만 시맨틱 매핑 누락 |
| station_picker_screen 검색 결과 0건 텍스트 | ⚠ 인라인 TextStyle 잔존, 시맨틱 슬롯 미적용 |

---

## 6. 오버 엔지니어링 검증

| 항목 | 평가 |
|---|---|
| Material 3 표준 13슬롯 모두 정의 (display/headline 미사용 슬롯 포함) | OK — 표준 준수, 향후 확장 여지 |
| AppPadding의 cardOuterMarginV/summaryHeader 등 시맨틱 별칭 | ⚠ 사용처 0건이라 현 시점 over-design 의심. 단 후속 PR에서 사용 가능 |
| AppIconSize/AppRadius/AppBorderRadius 정의 | ⚠ 사용처 0건이라 토큰 정의가 사실상 죽은 코드 (dead code) |
| ColorScheme 시드 보존 | ✅ 변경 없음 (사용자 보호 영역 준수) |
| AdMob 위젯 미수정 | ✅ ColorScheme.surface 참조 보존, 영향 없음 |
| 4원칙 코드 미수정 | ✅ tool/build_map_html.dart, live_train_provider.dart, map.html 모두 미수정 |
| 색상 팔레트 변경 X | ✅ 사용자가 폰트/사이즈만 요청한 의도 준수 |
| 애니메이션 변경 X | ✅ 변경 없음 |

**오버 엔지니어링 의심**: AppPadding/AppIconSize/AppRadius/AppBorderRadius 토큰이 정의만 되고 실제 사용처가 0이다. 사용자가 "컴포넌트 모듈 일관 관리"를 명시 요청했음을 고려하면 over-design이라기보다는 **마이그레이션 누락**으로 해석하는 것이 맞다.

---

## 7. 회귀 검증 (보존 영역)

| 항목 | 상태 | 검증 방법 |
|---|---|---|
| 4원칙 회귀 테스트 | ✅ 19/19 통과 | `flutter test test/core/utils/estimate_train_position_test.dart` 직접 실행 |
| AdMob 위젯 ColorScheme.surface 참조 | ✅ 영향 없음 | grep `colorScheme` lib/features/ads/ → 1건, ColorScheme 시드 미변경 확인 |
| SafeArea(top:false) Android 15 edge-to-edge | ✅ 보존 | `app.dart:108-111` MediaQuery 안쪽으로 이동, 동작 동일 |
| AppBarTheme(centerTitle:true, elevation:0) | ✅ 보존 |
| cardTheme/inputDecorationTheme 12px radius | ✅ 보존 |
| ColorScheme 시드 0xFF0052A4 | ✅ 보존 |
| 신규 토큰/테마 테스트 | ✅ 59/59 통과 |
| 기존 테스트 547개 (pre-existing 실패 2건 제외) | ✅ 모두 통과, 본 변경에 의한 회귀 0건 |
| `flutter analyze lib/` | ✅ 본 변경 부분 0 issues (기존 14 warnings는 무관한 JsonKey 어노테이션) |

영향 범위(grep 결과):
- `Theme.of(context).textTheme.*` 사용처: 5개 파일에서 18곳 추가 적용
- `appTextTheme` import: app_theme.dart 단독
- 토큰(AppSpacing 등) import: features/ 내 0건

**회귀 위험 등급: LOW** — 변경 자체는 안전하나, 누락된 7곳이 시맨틱 일관성에서 빠져 `clamp`만 적용되고 textTheme 매핑이 안 되는 부분 일관성 결손이 있음.

---

## 8. 누락/불일치 항목 (심각도 분류)

### HIGH (사용자 명시 요구사항 위배)
1. **station_detail_screen.dart 인라인 TextStyle 4곳 미마이그레이션** — 사용자 "일괄 변경" 결정에 반함. 노선 배지(line 81), 역명 fontSize:22(line 90), "환승 노선" 헤더 fontSize:16(line 110) 등이 textTheme을 거치지 않아 iOS/Android 폰트 메트릭 통일에서 빠짐. station_detail은 라우터(`/station/:stationId`)로 노출된 실사용 화면.
2. **station_picker_screen.dart 인라인 TextStyle 3곳 미마이그레이션** — 검색 결과 없음 텍스트(line 73), 역명 타일(line 156), _LineBadge(line 192). 라우터(`/pick-station/:purpose`)로 노출된 실사용 화면.

### MEDIUM (요구사항 의도와 부분 부합)
3. **AppSpacing/AppPadding/AppIconSize/AppRadius/AppBorderRadius 토큰 사용처 0건** — 사용자가 명시한 "컴포넌트 모듈 일관 관리"는 폰트뿐 아니라 spacing/padding/iconSize/radii 일관성도 포함된다. 토큰만 정의되고 실제 EdgeInsets 매직넘버 23곳, fontSize/Icon size 매직넘버가 그대로 남았다. 사용자 결정 §"디자인 토큰 위치 lib/core/theme/tokens/"에는 3 토큰 파일이 모두 명시되어 있으므로 정의만으로는 의도 미충족.

### LOW (시각/체감 이슈)
4. **카운트다운 18→16 다운사이즈 시각 회귀 위험** — 설계에서 "18→16 미세 다운, iOS/Android 일관성 우선"으로 결정했으나 실 디바이스 시각 확인 미수행. 시각 회귀 시 사용자 체감 가능.
5. **route_result_screen.dart 24→22 출발/도착 시각 다운사이즈** — 동일 사유. 사용자가 보던 헤더 사이즈가 약간 작아짐.

---

## 9. 권장 수정 (우선순위)

1. **[HIGH] station_detail_screen.dart 4곳 + station_picker_screen.dart 3곳 마이그레이션**
   - station_detail line 81 (노선 배지): `bodySmall.copyWith(color: white, fontWeight: w700)` (#8/#9 패턴과 동일)
   - station_detail line 90 (역명 22px): `titleLarge` (22px w700과 동등)
   - station_detail line 100 (역 번호): `bodyMedium.copyWith(color: Colors.grey[600])`
   - station_detail line 110 ("환승 노선" 헤더): `titleMedium`
   - station_picker line 73 (빈 상태): `bodyMedium.copyWith(color: Colors.grey[500])`
   - station_picker line 156 (역명 타일): `labelLarge` (14px w500)
   - station_picker line 192 (_LineBadge): `labelSmall.copyWith(fontSize: 11, color: white, fontWeight: w700)` 또는 `bodySmall.copyWith(...)` (#8 패턴)

2. **[MEDIUM] EdgeInsets/Icon size/BorderRadius 매직넘버 토큰화 후속 PR**
   - 본 단계에서 일괄 적용 시 회귀 위험이 있어 별도 PR 권장
   - 우선순위: AppPadding(가장 빈도 높음) > AppBorderRadius > AppIconSize > AppSpacing
   - 또는 사용자에게 "spacing 토큰은 정의만 해두고 후속 PR에서 적용" 명시적 동의 받기

3. **[LOW] 시각 검증** — iOS/Android 실디바이스에서 22px 헤더, 16px 카운트다운, BackButton 아이콘 시각 확인 (QA 단계)

---

## 10. 종합 판정

| 지표 | 값 |
|---|---|
| 사용자 확정 결정 충족률 | 5/5 (100%) |
| 명시 핵심 요구사항 충족률 | 11/15 (73%) |
| 보호 영역 보존 | 100% (4원칙/AdMob/ColorScheme/SafeArea 모두 보존) |
| 회귀 위험 등급 | **LOW** |
| 오버 엔지니어링 의심 | LOW (over-design보다는 "토큰 정의 후 사용처 미마이그레이션" 누락) |
| 새로 도입된 회귀 | 없음 (4원칙 19/19, 기존 테스트 547/547) |

**최종 판정: NEEDS_FIX**

이유:
- 사용자 "일괄 변경" 결정에 반해 7곳이 누락됨 (HIGH)
- 사용자 "컴포넌트 모듈 일관 관리" 의도 부분 부합 (MEDIUM) — 토큰 정의만 있고 사용처 0
- 보호 영역과 핵심 인프라(typography/textScaler/BackButton)는 정확히 구현됨

권장 액션:
1. 즉시: station_detail/station_picker 7곳 마이그레이션 → 일괄 변경 결정 충족
2. 근시: spacing/iconSize/radii 토큰 일괄 적용 또는 사용자 동의 후 후속 PR로 분리
3. QA: iOS/Android 실디바이스 시각 검증 (22px 헤더, 16px 카운트다운, BackButton)

---

## 끝.
