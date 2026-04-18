# 요구사항: 실시간 열차 애니메이션 중간 경유역 도착 지연 버그 수정

## 사용자 리포트
- 노선: 2호선
- 증상: API는 중간 경유역에 도착(arvlCd=99, positionStatus="도착")이라 보고하는데 화면 열차 아이콘은 해당 역 직전에 머무름
- 최종 출발역이 아닌 **중간 경유역**에서 발생

## 근본 원인
`assets/html/map.html:1895-1909`의 "이어서 진행" 로직:
```js
var remaining = path.slice(bestSeg + 1);
animPath = [{ x: curX, y: curY }].concat(remaining);
```
→ `bestSeg=0`이고 curPos가 path[0] 이전(세그먼트 투영 t≈0)에 있어도 path[0]이 animPath에서 항상 제외됨.
→ curPos→D 직선 이동 발생, SVG 노선의 C 역을 건너뜀.
→ arrivalSeconds > totalTime이면 추가로 느려져 "C 직전에서 멈춘 듯" 보임.

## 수정 작업
1. **map.html startTrainAnimation**: bestT를 저장해 분기 처리 (curPos 위치에 따라 path[bestSeg] 포함 여부 결정)
2. **calculateInitialProgress**: arvlCd=0/4, positionStatus="진입"을 0.85 → 0.0으로 정정
3. **findPathOnLine**: `isDown` 선택 파라미터로 순환선 방향 제한
4. **live_train_provider**: routeFilter.isDown을 findPathOnLine에 전달

## 투입 에이전트
- **map-math-engineer**: map.html startTrainAnimation 수정 (작업 1)
- **graph-algorithm-engineer**: path_on_line.dart의 calculateInitialProgress + findPathOnLine 수정 (작업 2, 3)
- **realtime-data-engineer**: live_train_provider.dart 호출부 갱신 (작업 4)
- **flutter-qa-engineer**: 단위 테스트 추가/갱신
- **subway-code-reviewer** + **subway-requirements-reviewer**: 병렬 리뷰

## 실행 순서
- Phase 2a (병렬): map-math-engineer ‖ graph-algorithm-engineer
- Phase 2b (순차): realtime-data-engineer (path_on_line 수정 후)
- Phase 2c: flutter-qa-engineer (테스트)
- Phase 3 (병렬): subway-code-reviewer ‖ subway-requirements-reviewer
- Phase 4: 필요 시 수정 루프
- Phase 5: flutter analyze + flutter test

## 제외
- 디버깅 로그 보강 (플랜 섹션 4) — 이번 범위에서 제외

## 주요 참조
- 기존 `isDownDirection` 함수: `lib/features/route_search/utils/direction_resolver.dart:19`
- `ActiveRouteFilter.isDown`: `lib/features/subway_map/presentation/providers/subway_map_providers.dart:83`
- `Connection` 엔티티에 `isDown` 필드 없음 → 역 ID로 방향 판정 로직 재사용 필요
