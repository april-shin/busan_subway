# 05b Map Fix — M3 + M4 수정

작성: map-math-engineer
대상: 1차 코드 리뷰(03_code_review.md) M3, M4 항목

---

## M3 — Theme.of(context) 반복 호출 최적화

각 위젯 build 메서드 시작에 `final t = Theme.of(context).textTheme;` 1회 추출 후 `t.X` 형태로 참조.

| 위젯 | 추출 위치 | 감소된 호출 수 |
|---|---|---|
| `_RouteSummaryHeader.build` | build 첫 줄 | 6회 → 1회 |
| `_InfoChip.build` | build 첫 줄 | 1회 → 1회 (1회지만 패턴 통일) |
| `_ChipDivider.build` | build 첫 줄 | 1회 → 1회 (패턴 통일) |
| `_SegmentHeader.build` | build 첫 줄 | 5회 → 1회 |
| `_StationRow.build` | build 첫 줄 | 3회 → 1회 |

기능 로직, 위젯 구조, 색상 copyWith 패턴 변경 없음.

---

## M4 — 급행 배지 사이즈 통일

**결정: (A) 12px 통일**

- `arrival_card.dart` 급행 미니 배지: `labelSmall.copyWith(fontSize: 10, ...)` → `bodySmall.copyWith(color: white, fontWeight: w700)`
- padding: `vertical: 1` → `vertical: 2` (12px 텍스트에 맞게 보완)
- 이제 `route_result_screen.dart`의 급행 배지(`bodySmall`, `vertical: 2`)와 동일

**근거**: 사용자 요청이 "일관성"이므로 10/12 분리보다 통일이 명확히 옳다. 카드 내 배지 영역은 Row 내 인라인이라 2px 높이 증가가 레이아웃 붕괴를 유발하지 않는다.

---

## flutter analyze 결과

```
Analyzing 2 items...
No issues found! (ran in 0.8s)
```

오류 0건, 경고 0건.
