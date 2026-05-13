# UI 일관성 개선 — 요구사항 (사용자 확정)

## 사용자 원문 요청
1. (1차) "안드로이드랑 iOS 컴포넌트 모듈이나 폰트사이즈가 너무 차이가 커서 일관적으로 관리할수 있도록 처리해줘"
2. (2차 확정) "일괄변경하자" — 점진적 vs 일괄 중 **일괄 마이그레이션** 선택

## 진단 (이미 분석 완료)

| 원인 | 현황 |
|---|---|
| TextTheme 미정의 | `lib/core/theme/app_theme.dart` 에 `useMaterial3: true` 만 있고 Typography/textTheme 명시 X. iOS=SF Pro, Android=Roboto 자동 차이 |
| 하드코딩 산재 | 인라인 `TextStyle()` 32곳, fontSize 6/11/12/13/14/16/24 불규칙 |
| textScaler 무처리 | 시스템 폰트 배율 그대로 통과 |
| 공유 컴포넌트 부재 | 같은 카드/행이 다른 사이즈로 4-5번 재구현 |

## 사용자 확정 디자인 결정

| 항목 | 결정 |
|---|---|
| 한글 전용 폰트 추가 | **X** — 시스템 폰트 유지 |
| `textScaler` clamp | **0.9 ~ 1.15** |
| Typography platform | **`Typography.material2021(platform: TargetPlatform.android)` 고정** — iOS 도 Roboto-like 메트릭 |
| `BackButton.adaptive()` | **도입** — 백 버튼만 플랫폼 네이티브 |
| 디자인 토큰 위치 | `lib/core/theme/tokens/` (`app_typography.dart`, `app_dimensions.dart`, `app_radii.dart`) |

## 예상 변경 파일

**신규**:
- `lib/core/theme/tokens/app_typography.dart`
- `lib/core/theme/tokens/app_dimensions.dart`
- `lib/core/theme/tokens/app_radii.dart`

**수정 (코어)**:
- `lib/core/theme/app_theme.dart` — Typography, TextTheme 명시
- `lib/app.dart` — MaterialApp.builder 에 textScaler clamp

**마이그레이션 (인라인 TextStyle 32곳)**:
- `lib/features/route_search/presentation/screens/route_result_screen.dart` (20+)
- `lib/features/arrival_info/presentation/widgets/arrival_card.dart` (6)
- `lib/features/arrival_info/presentation/screens/arrival_info_screen.dart` (4)
- `lib/features/home/presentation/widgets/search_bar_widget.dart` (2)
- `lib/features/route_search/presentation/widgets/transfer_row.dart` (2)
- 기타 lib/features/home, lib/features/station_picker, lib/features/subway_map

**테스트 (신규)**:
- `test/core/theme/` 또는 `test/widget/` — Typography/TextTheme 적용 검증

## 절대 금지 (보호 영역)

- `tool/build_map_html.dart` — 실시간 열차 애니메이션 4원칙 보호
- `lib/features/subway_map/presentation/providers/live_train_provider.dart` — 4원칙 보호
- `assets/html/map.html` — 직접 수정 금지
- AdMob 관련 코드 (`lib/features/ads/`) — 직전 작업, 손대지 말 것
- `Color`/`ColorScheme` 시드값 — 색상 팔레트 변경 X (사용자가 폰트/사이즈만 요청)

## 결과물 요구

- 변경 파일 목록 + 라인 수 요약
- 32개 인라인 TextStyle 의 시맨틱 매핑 표
- `flutter analyze` 통과
- 회귀 테스트 통과
