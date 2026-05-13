# 06a Code Review — 2차 리뷰 (수정 결과 검증)

작성: subway-code-reviewer
대상: Phase 5 의 수정 결과 (`05a_arch_fix.md`, `05b_map_fix.md`, `05c_qa_fix.md`)
의존: `03_code_review.md` 1차 리뷰

---

## 종합 판정

**PASS** — CRITICAL/HIGH 이슈 없음. 1차 리뷰의 HIGH 1건 + MEDIUM 4건 모두 적절히 해소됐고, 새 회귀나 보호 영역 침범 없음. 추가 마이그레이션 7곳 매핑도 시맨틱과 정확히 일치한다. 잔존 이슈는 모두 LOW/NIT 수준이며 후속 PR 으로 처리해도 무방.

`flutter analyze` 결과 변경 영역에서 새 warning/error 발생 없음 (잔존 68 건은 모두 사전 존재 — `tool/test_timetable_api.dart`, `tool/generate_schematic_layout.dart` 등 본 작업 범위 외).

---

## 1차 이슈별 해결 상태

| ID | 1차 이슈 | 상태 | 검증 근거 |
|---|---|---|---|
| **H1** | `text_scaler_clamp_test` 가 builder 패턴 검증 X | **해결됨** | `appRootBuilder` top-level 함수로 추출 (`lib/app.dart:108-125`), `@visibleForTesting` 명시. 테스트가 `import 'package:seoul_subway/app.dart' show appRootBuilder;` 후 `MaterialApp(builder: appRootBuilder, home: Builder(...))` 패턴으로 실 함수 검증. 케이스 11→13 으로 확장 (1.1, child==null 추가). 13/13 통과. |
| **M1** | station_detail (4) + station_picker (3) 마이그레이션 누락 | **해결됨** | `station_detail_screen.dart:81-111` 4곳, `station_picker_screen.dart:73-202` 3곳 모두 시맨틱 슬롯 적용. grep 결과 두 파일에 잔존 인라인 `TextStyle(` 0건. |
| **M2** | `AppBorderRadius` 정적 멤버 타입 어노테이션 누락 | **해결됨** | `app_radii.dart:16-25` 5 멤버 모두 `static const BorderRadius xs = …` 형태로 명시. |
| **M3** | `route_result_screen.dart` `Theme.of(context)` 반복 호출 | **해결됨** | `_RouteSummaryHeader.build:290`, `_InfoChip.build:367`, `_ChipDivider.build:389`, `_SegmentHeader.build:555`, `_StationRow.build:633` 모두 `final t = Theme.of(context).textTheme;` 추출 패턴. |
| **M4** | `arrival_card.dart` 급행 배지 10px ↔ `route_result_screen.dart` 12px 불일치 | **해결됨** | `arrival_card.dart:53-60` 이 `bodySmall.copyWith(color: white, fontWeight: w700)` 로 통일. `vertical: 2` padding 도 동일. 두 화면 배지 시각·시맨틱 일치. |
| **M5** | `actionIconTheme` 효과 검증 부재 | **부분 해결** | 본 사이클에서 명시 위젯 테스트 추가는 없지만 1차 리뷰 자체가 "ROI 낮으면 시각 QA 로 대체" 권고했고, 회귀 위험은 낮다 (정적 등록 코드). 시각 QA 후속 권장 유지. |
| **요구사항 04 MED** | spacing 토큰 사용처 0 | **해결됨** | 5 파일 / ~17 곳 시범 적용 (`05a_arch_fix.md` §5). station_detail/station_picker/search_bar_widget/transfer_row/arrival_info_screen 의 `EdgeInsets`/`SizedBox` 가 `AppSpacing.spaceN` 으로 치환. |
| **NIT N1** | `app_typography_test.dart:170` 불필요 중괄호 | 미수정 (LOW) | 본 사이클 작업 범위 외. analyze 잔존 이슈로 남아있을 가능성 — 후속 처리 권장. |

---

## 회귀 검증

| 항목 | 상태 | 근거 |
|---|---|---|
| 4원칙 코드 (`tool/build_map_html.dart`, `live_train_provider.dart`, `map.html`) | 미수정 | `git diff --stat` 결과 빈 출력 (current branch). |
| AdMob (`lib/features/ads/`) | 미수정 | `git diff --stat` 결과 빈 출력. |
| ColorScheme 시드 `0xFF0052A4` | 보존 | `app_theme.dart` 수정 없음 (1차 변경 후 동일). |
| `SafeArea(top: false)` | 보존 | `appRootBuilder:120-123` 안에서 동일 결합 순서 유지 (MediaQuery 바깥 / SafeArea 안쪽). |
| `child == null` 방어 | 보존 | `appRootBuilder:110` `if (child == null) return const SizedBox.shrink();`. |
| `@visibleForTesting` import | 정상 | `flutter/material.dart` 가 `meta` 재수출 — 추가 import 불필요. analyze 통과. |
| 4원칙 회귀 테스트 (`estimate_train_position_test.dart`) | 19/19 통과 | `05c_qa_fix.md` §3 명시. |
| 신규 테스트 (`text_scaler_clamp_test.dart`) | 13/13 통과 | builder 직접 검증 패턴으로 H1 회귀 방어 가능. |
| `app_typography_test.dart` 37/37, `app_theme_test.dart` 11/11 | 통과 | `05c_qa_fix.md` §3. |

---

## 신규 변경 영역 추가 검토

### 신규 마이그레이션 7곳 시맨틱 일치성

| # | 파일:라인 | 매핑 | 평가 |
|---|---|---|---|
| 1 | `station_detail_screen.dart:83` 노선 배지 | `bodySmall + white + w700` | 정확 — `route_result_screen` 의 #8/#9 노선 배지와 동일 패턴, M4 통일 정책에도 일치 |
| 2 | `station_detail_screen.dart:92` 역명 헤더 (22px bold) | `titleLarge` | 정확 — titleLarge 가 정확히 22/w700 으로 정의됨 |
| 3 | `station_detail_screen.dart:99` 역 번호 | `bodyMedium + grey[600]` | 적절 — size 미지정이었던 텍스트를 14px 본문으로 명시화 |
| 4 | `station_detail_screen.dart:111` 환승 노선 헤더 (16px bold) | `titleMedium` | 정확 — 16/w600 매칭. const 제거도 적절 |
| 5 | `station_picker_screen.dart:75` 빈 상태 안내 | `bodyMedium + grey[500]` | 정확 — `arrival_info_screen` #21 동일 패턴 |
| 6 | `station_picker_screen.dart:160` 역명 타일 (w500 only) | `labelLarge` | 정확 — `search_bar_widget` #22 와 동일 매핑 (14/w500) |
| 7 | `station_picker_screen.dart:199` _LineBadge (11/white/bold) | `labelSmall + white + w700` | 정확 — labelSmall 이 11/w500, override 로 w700 보강 |

→ **7건 모두 시맨틱 의미와 매핑이 일치**. 1차 리뷰의 권장 패턴 그대로 반영.

### Spacing 토큰 시범 적용 적절성

샘플 점검 (`station_detail_screen.dart`):
- `EdgeInsets.all(16)` → `AppSpacing.space16` (의미: 화면 가장자리/카드 내부)
- `SizedBox(height: 24)` → `AppSpacing.space24` (의미: 버튼 분리)
- `Wrap(spacing: 8)` → `AppSpacing.space8` (의미: 칩 간격)

→ **기계적 치환이 아닌 의미상 적절**. `AppPadding.cardPadding` 같은 시맨틱 별칭을 적용하면 더 좋았을 곳도 있으나, 본 사이클의 "가시 시그널 회복" 목적엔 부합. 후속 PR 에서 시맨틱 별칭 도입 고려 여지.

### `appRootBuilder` 추출 적절성

```dart
@visibleForTesting
Widget appRootBuilder(BuildContext context, Widget? child) { … }
```

- top-level 함수 + `@visibleForTesting` 으로 위치 정확
- `MaterialApp.router(builder: appRootBuilder)` 단일 참조로 깔끔
- doc-comment 가 결합 순서·4원칙 영향 없음·textScaler 의도 모두 명시 → 향후 회귀 방지에 유효
- `MediaQuery.of(context)` 호출은 root MediaQuery 가 항상 존재하는 환경이라 안전 (SDK 보장)

---

## 새 이슈

### CRITICAL / HIGH
**없음.**

### MEDIUM
**없음.**

### LOW

#### L1. `arrival_card.dart` — 토큰 미사용 잔재
- `Card(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4))` (L27)
- `Padding(padding: EdgeInsets.all(12))` (L29)
- `BorderRadius.circular(4)` (L51), `BorderRadius.circular(8)` (L131)
- `EdgeInsets.symmetric(horizontal: 12, vertical: 6)` (L128)

map-math 담당 파일이지만 spacing/radius 토큰 적용은 누락. 1차 리뷰가 명시적으로 요구하지 않았고 사이클 범위가 "M3+M4 핵심"으로 한정됐으니 회귀는 아니다. 후속 PR 에서 `AppSpacing.space*` / `AppBorderRadius.*` 적용 권장.

#### L2. `route_result_screen.dart` — 같은 패턴 반복
- `EdgeInsets.symmetric(horizontal: 16, vertical: 12)` (L428)
- `EdgeInsets.fromLTRB(20, 16, 20, 16)` (L293)
- `Padding(padding: EdgeInsets.symmetric(horizontal: 12))` (L318)
- `BorderRadius.circular(4)` (배지), `BorderRadius.circular(8)` (Container)

L1 과 동일. 후속 spacing 마이그레이션에서 일괄 처리.

### NIT

#### N1. `route_result_screen.dart:299, 313, 327, 376, 395, 596, 603, 649, 689` 등 — `Colors.grey[600]` 등의 직접 참조
ColorScheme 의 `onSurfaceVariant` / `onSurface.withOpacity(...)` 로 점진 마이그레이션이 디자인 시스템 일관성 측면에서 더 좋다. 1차 리뷰 L5 와 동일. 본 작업 범위 외.

#### N2. `app_typography_test.dart:170` — 불필요한 string interpolation 중괄호 (1차 NIT N1)
1차 리뷰가 잡았으나 본 사이클에서 미수정. `flutter analyze` info 1건 잔존. 1줄 수정으로 해결 가능.

#### N3. `arrival_card.dart:14, 17-24` — 시간 계산이 build 안에서 수행
`liveSeconds` 계산이 build 마다 재실행. Riverpod stream/Timer 기반 갱신이 아닌 카드 단위 build 의존이라 큰 문제는 아니지만, 카드 다수 표시 시 매 frame 재계산 가능성. 본 작업 범위 외 (1차 리뷰에서도 미언급).

---

## 칭찬

### 수정 정확성
- **H1 해결**: `appRootBuilder` 추출이 1차 리뷰 권고와 정확히 일치. 단순 함수 추출에 그치지 않고 `@visibleForTesting` + doc-comment 로 유지보수성을 높임. 테스트도 패턴 그대로 검증.
- **M1 해결**: 7곳 모두 1차 리뷰가 제안한 시맨틱과 일치. 매핑 일관성 (예: `_LineBadge` vs 다른 화면 노선 배지) 까지 신중하게 고려.
- **M3 해결**: `final t = Theme.of(context).textTheme;` 추출 패턴이 5 위젯 모두 동일하게 적용 — 코드 가독성 + 미세 최적화.
- **M4 해결**: 사용자 요청 "일관성" 의도와 정확히 부합. 10→12 통일은 토큰 중복 도입 (`badgeMicro`) 보다 우월한 결정.

### 보호 영역
- 4원칙·AdMob·ColorScheme·AppBarTheme·SafeArea·child==null 방어 모두 보존.
- `git diff --stat` 결과 보호 영역 0 byte 변경.

### 테스트 강화
- builder 직접 검증 패턴으로 회귀 방어선 확보. 1.1/child==null 케이스 추가는 가치 있는 보강.
- 4원칙 회귀 테스트 19/19 통과 명시 — 보호 영역 검증을 적극적으로 수행.

### Spacing 토큰 시범
- 5 파일 17 곳으로 절제된 적용. 무분별한 일괄 치환이 아닌 "가시 시그널" 회복에 충실.
- 시각 디자인 매직넘버 (54px leading, 14px icon 등) 는 보존 — "토큰화는 의미상 적절한 곳만" 정책 정확히 따름.

---

## 우선 처리 권고 (후속 사이클)

| 우선순위 | 항목 | 비고 |
|---|---|---|
| LOW | L1, L2 — `arrival_card.dart`, `route_result_screen.dart` 의 spacing/radius 토큰 미적용 | 별도 PR 권장 (변경량 ↑) |
| NIT | N2 — `app_typography_test.dart:170` 중괄호 제거 | 1줄 수정 |
| NIT | N1 — ColorScheme 점진 마이그레이션 | 별도 검토 |
| (선택) | M5 — `actionIconTheme` 시각 검증 | 실디바이스 QA 또는 위젯 테스트 |

---

## 끝.
