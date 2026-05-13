# 최종 보고서 — UI 일관성 토큰 시스템 도입

## 사용자 요청
1. "안드로이드랑 iOS 컴포넌트 모듈이나 폰트사이즈가 너무 차이가 커서 일관적으로 관리할수 있도록 처리해줘"
2. "일괄변경하자"

## 결과: 완료 (PASS)

- 코드 리뷰: PASS (CRITICAL/HIGH/MEDIUM 0건, LOW 2건/NIT 3건은 후속 PR 권장)
- 요구사항 리뷰: PASS (충족률 14/15, 93%)
- `flutter analyze lib/ test/`: 본 작업 추가 lint 0건
- `flutter test test/core/theme/ test/widget/text_scaler_clamp_test.dart test/core/utils/estimate_train_position_test.dart`: 81/81 통과
- 4원칙 회귀 테스트 (`estimate_train_position_test.dart`) 19/19 보존

## 변경 파일 목록

### 신규 (6 파일)
| 파일 | 라인 수 | 역할 |
|---|---|---|
| `lib/core/theme/tokens/app_typography.dart` | 116 | M3 13 시맨틱 슬롯 정의 |
| `lib/core/theme/tokens/app_dimensions.dart` | 36 | AppSpacing/AppPadding/AppIconSize |
| `lib/core/theme/tokens/app_radii.dart` | 22 | AppRadius/AppBorderRadius |
| `test/core/theme/app_typography_test.dart` | 37 케이스 | 토큰 슬롯 명세 검증 |
| `test/core/theme/app_theme_test.dart` | 11 케이스 | ThemeData 통합 검증 |
| `test/widget/text_scaler_clamp_test.dart` | 13 케이스 | clamp 동작 + builder 검증 |

### 수정 (10 파일)
| 파일 | 변경 |
|---|---|
| `lib/app.dart` | `appRootBuilder` 추출 (`@visibleForTesting`), MaterialApp.router builder 결합 |
| `lib/core/theme/app_theme.dart` | `typography: Typography.material2021(android)` + `textTheme: appTextTheme` + `actionIconTheme.backButtonIconBuilder` |
| `lib/features/home/presentation/widgets/search_bar_widget.dart` | 인라인 TextStyle 2곳 → labelLarge/labelMedium |
| `lib/features/route_search/presentation/widgets/transfer_row.dart` | TextSpan 인라인 2곳 → bodySmall/labelSmall |
| `lib/features/arrival_info/presentation/screens/arrival_info_screen.dart` | 인라인 3곳 → titleMedium/labelMedium/bodyMedium |
| `lib/features/arrival_info/presentation/widgets/arrival_card.dart` | 인라인 6곳 → titleMedium/labelMedium/bodyLarge/labelSmall + 급행 배지 12px 통일 |
| `lib/features/route_search/presentation/screens/route_result_screen.dart` | 인라인 13곳 → titleLarge/bodyMedium/labelMedium/bodySmall + Theme.of 재사용 |
| `lib/features/station_detail/presentation/screens/station_detail_screen.dart` | 인라인 4곳 (재리뷰에서 발견) |
| `lib/features/route_search/presentation/screens/station_picker_screen.dart` | 인라인 3곳 (재리뷰에서 발견) |

총 **인라인 TextStyle 마이그레이션: 32곳 (100%)** — features/ 디렉토리 잔존 0건.

## 디자인 토큰 적용 결과

### Typography (M3 13 슬롯)
- titleLarge: 22px w700 (기존 24 → 22 다운, iOS/Android 폭 안정화)
- titleMedium: 16px w600
- titleSmall: 14px w600
- bodyLarge: 16px w700 (카운트다운 강조)
- bodyMedium: 14px w400
- bodySmall: 12px w400
- labelLarge: 14px w500
- labelMedium: 13px w500
- labelSmall: 11px w500
- (display/headline 슬롯은 향후 확장용으로 정의)
- 한국어 가독성: 본문 계열 height 1.43~1.50 통일
- fontFamily 미명시 → 한글 fallback 보호 (Apple SD Gothic Neo / Noto Sans CJK)

### Dimensions / Radii
- 토큰 정의 완료, 17곳 시범 적용 (5 파일). 나머지 EdgeInsets 매직넘버 마이그레이션은 후속 PR 분리 권장.

## 플랫폼 일관성 메커니즘

| 메커니즘 | 적용 위치 | 효과 |
|---|---|---|
| `Typography.material2021(platform: TargetPlatform.android)` | `app_theme.dart` | iOS 도 Android Roboto 메트릭 사용 → 글자 폭/줄간격 통일 |
| `textScaler.clamp(0.9~1.15)` | `app.dart` `appRootBuilder` | 시스템 폰트 배율 극단값 방어 |
| `actionIconTheme.backButtonIconBuilder = BackButtonIcon()` | `app_theme.dart` | 백 버튼만 플랫폼 네이티브 (iOS chevron / Android arrow) |
| `appTextTheme` 13 슬롯 | 전역 ThemeData | 인라인 TextStyle 제거 → 모든 텍스트가 한 곳에서 관리됨 |

## 보호 영역 (검증 완료, 미수정)
- 4원칙 코드 (`tool/build_map_html.dart`, `live_train_provider.dart`, `assets/html/map.html`)
- AdMob 코드 (`lib/features/ads/`)
- ColorScheme 시드 (`0xFF0052A4`)
- AppBarTheme(centerTitle: true)
- SafeArea(top: false) — Android 15 edge-to-edge 보존

## 후속 권장 (별도 PR 분리)
1. `arrival_card.dart` / `route_result_screen.dart` 등의 잔여 EdgeInsets 매직넘버 토큰화 (~17곳)
2. iOS/Android 실 디바이스 시각 QA — 22px titleLarge / 16px 카운트다운 / BackButton.adaptive 모양
3. `JsonKey.new` warning (lib/data/remote/dto/arrival_info_dto.dart) 정리 — 본 작업과 무관, 기존 이슈

## 산출물 위치
- 단계별 산출물: `_workspace/00_requirements.md` ~ `_workspace/06b_requirements_review.md`
- 1차 작업 백업: `_workspace_prev/` (이전 세션)
