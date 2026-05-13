# 02b Map Implementation — 복잡 화면 인라인 TextStyle 마이그레이션

작성: map-math-engineer
단계: Phase 2b — 복잡 화면 TextStyle 시맨틱 슬롯 교체

---

## 변경 파일 및 라인 수

| 파일 | 변경 라인 수 (추가+삭제) | 인라인 TextStyle 처리 건수 |
|---|---|---|
| `lib/features/route_search/presentation/screens/route_result_screen.dart` | +26 / -23 | 13건 |
| `lib/features/arrival_info/presentation/widgets/arrival_card.dart` | +14 / -13 | 5건 |

합계: 총 18건 TextStyle 마이그레이션

---

## 인라인 TextStyle 마이그레이션 Before/After 표

### route_result_screen.dart

| # | 설계 # | 위치(클래스) | Before | After | 비고 |
|---|---|---|---|---|---|
| 1 | #1 | `_RouteSummaryHeader` 로딩 텍스트 | `TextStyle(fontSize: 14, color: Colors.grey)` | `textTheme.bodyMedium?.copyWith(color: Colors.grey)` | const 제거 필요 |
| 2 | #2 | `_RouteSummaryHeader` 출발 시각 | `TextStyle(fontSize: 24, fontWeight: bold)` | `textTheme.titleLarge` | 24→22px, color 기본 |
| 3 | #3 | `_RouteSummaryHeader` " 출발" 라벨 | `TextStyle(fontSize: 14, color: Colors.grey[600])` | `textTheme.bodyMedium?.copyWith(color: Colors.grey[600])` | color 보존 |
| 4 | #4 | `_RouteSummaryHeader` 도착 시각 | `TextStyle(fontSize: 24, fontWeight: bold)` | `textTheme.titleLarge` | #2 와 동일 |
| 5 | #5 | `_RouteSummaryHeader` " 도착" 라벨 | `TextStyle(fontSize: 14, color: Colors.grey[600])` | `textTheme.bodyMedium?.copyWith(color: Colors.grey[600])` | color 보존 |
| 6 | #6 | `_InfoChip` 텍스트 | `TextStyle(fontSize: 13, color: Colors.grey[600])` | `textTheme.labelMedium?.copyWith(color: Colors.grey[600])` | color 보존 |
| 7 | #7 | `_ChipDivider` | `TextStyle(color: Colors.grey[400])` | `textTheme.bodyMedium?.copyWith(color: Colors.grey[400])` | size 미지정 → bodyMedium 명시화 |
| 8 | #8 | `_SegmentHeader` 노선 배지 | `TextStyle(color: white, fontSize: 12, fontWeight: bold)` | `textTheme.bodySmall?.copyWith(color: white, fontWeight: w700)` | |
| 9 | #9 | `_SegmentHeader` 급행 배지 | `TextStyle(color: white, fontSize: 12, fontWeight: bold)` | `textTheme.bodySmall?.copyWith(color: white, fontWeight: w700)` | #8 과 동일 패턴 |
| 10 | #10 | `_SegmentHeader` 방향 텍스트 | `TextStyle(fontSize: 12, color: Colors.grey[600])` | `textTheme.bodySmall?.copyWith(color: Colors.grey[600])` | color 보존 |
| 11 | #11 | `_SegmentHeader` N분 N개역 | `TextStyle(fontSize: 12, color: Colors.grey[500])` | `textTheme.bodySmall?.copyWith(color: Colors.grey[500])` | color 보존 |
| 12 | #12 | `_StationRow` 시각 표시 | `TextStyle(fontSize: 12, fontWeight: w500, color: Colors.grey[700])` | `textTheme.bodySmall?.copyWith(fontWeight: w500, color: Colors.grey[700])` | |
| 13 | #13 | `_StationRow` 역명 ternary | `TextStyle(fontSize: isEndpoint ? 14 : 12, fontWeight: isEndpoint ? bold : normal, color: isEndpoint ? black : grey[600])` | `(isEndpoint ? textTheme.titleSmall : textTheme.bodySmall)?.copyWith(color: ...)` | ternary 두 슬롯으로 분리 |

### arrival_card.dart

| # | 설계 # | 위치(클래스) | Before | After | 비고 |
|---|---|---|---|---|---|
| 14 | #14 | `ArrivalCard` 노선명 | `TextStyle(fontSize: 15, fontWeight: bold)` | `textTheme.titleMedium` | 15→16px 통일 |
| 15 | #15 | `ArrivalCard` 급행 미니 배지 | `TextStyle(color: white, fontSize: 10, fontWeight: bold)` | `textTheme.labelSmall?.copyWith(fontSize: 10, color: white, fontWeight: w700)` | 10px override 허용(배지 예외) |
| 16 | #16 | `ArrivalCard` 도착 메시지 | `TextStyle(fontSize: 13, color: Colors.grey[600])` | `textTheme.labelMedium?.copyWith(color: Colors.grey[600])` | color 보존 |
| 17 | #17 | `_CountdownBadge` 카운트다운 | `TextStyle(fontSize: isEstimated ? 16 : 18, fontWeight: bold, color: textColor)` | `textTheme.bodyLarge?.copyWith(color: textColor)` | ternary 제거, 16px bold 통일 |
| 18 | #18 | `_CountdownBadge` 초 보조 | `TextStyle(fontSize: 11, color: subTextColor)` | `textTheme.labelSmall?.copyWith(color: subTextColor)` | color 보존 |

---

## ternary 처리 결정

### #13 역명 ternary (`_StationRow`)
- **결정**: 설계 §2 권장대로 두 시맨틱 슬롯으로 분리.
  - `isEndpoint = true` → `titleSmall` (14px w600)
  - `isEndpoint = false` → `bodySmall` (12px w400)
- **근거**: isEndpoint는 실제로 다른 의도의 텍스트이므로 ternary 분기가 의미상 옳다. 단순히 크기만 다른 게 아니라 역할(종착역 이름 vs 중간역 이름)이 다르다.

### #17 카운트다운 ternary (`_CountdownBadge`)
- **결정**: 설계 단순화 결정 채택 — ternary 완전 제거, `bodyLarge` (16px w700) 단일 슬롯.
- **근거**: `isEstimated ? 16 : 18` 두 케이스 모두 "강조 시각 숫자" 라는 동일한 시맨틱. 18→16px 미세 다운이지만 iOS/Android 일관성과 코드 단순성이 우선이다. `bodyLarge`는 설계 문서에서 "카운트다운 분 표시"로 정의되어 있으므로 의도에 완전히 부합.

---

## 색상 처리 원칙 준수 확인

| 색상 | 처리 방식 | 결과 |
|---|---|---|
| `Colors.grey[600]` | copyWith 로 그대로 보존 | 보존 |
| `Colors.grey[500]` | copyWith 로 그대로 보존 | 보존 |
| `Colors.grey[700]` | copyWith 로 그대로 보존 | 보존 |
| `Colors.grey[400]` | copyWith 로 그대로 보존 | 보존 |
| `Colors.white` | copyWith 로 그대로 보존 | 보존 |
| `textColor` (런타임 색) | copyWith(color: textColor) | 보존 |
| `subTextColor` (런타임 색) | copyWith(color: subTextColor) | 보존 |

---

## import 추가

없음. `Theme.of(context).textTheme` 사용이므로 별도 token import 불필요. `ThemeData`가 `appTextTheme`을 주입하면 자동으로 적용된다.

---

## flutter analyze 결과

```
Analyzing 2 items...
No issues found! (ran in 1.5s)
```

오류 0건, 경고 0건.

> 참고: `app_typography.dart`, `app_dimensions.dart` 등 토큰 파일은 flutter-architect가 동시에 작성 중이므로, 해당 파일이 없는 상태에서도 본 마이그레이션 파일 자체는 analyze를 통과한다. `Theme.of(context).textTheme.X` 접근은 ThemeData에서 제공하는 표준 API이므로 토큰 파일 존재 여부와 무관하게 컴파일된다.

---

## 기능 로직 보존 확인

- Riverpod watch/ref: 변경 없음
- 위젯 구조(Column/Row/Stack): 변경 없음
- 상태 관리(_CountdownBadge, isEstimated, isImminent): 변경 없음
- 색상 계산 로직(backgroundColor/textColor/subTextColor): 변경 없음
- 타이밍 계산(liveSeconds, arrivalSeconds): 변경 없음
