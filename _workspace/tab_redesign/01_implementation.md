# 구현 결과 — 경로 결과 탭 동적 결정 + 토글 제거

## 변경 파일

### 수정
- `lib/graph/shortest_path.dart` — `nodeFilter` 옵션 추가 (시작/도착/모든 방문 노드에 적용)
- `lib/domain/usecases/search_route.dart` — `executeAll`을 4종 반환(`fastest`, `leastTransfer`, `fastestExpress`, `fastestLocal`)으로 확장
- `lib/app.dart` — `/route-result`의 `state.extra`에 4종 record 케이스 추가, 하위 호환 유지(2종/1종)
- `lib/features/home/presentation/screens/home_screen.dart` — `executeAll` 4종 결과를 router로 전달
- `lib/features/subway_map/presentation/widgets/subway_map_viewer.dart` — `_fastestExpressRoute`/`_fastestLocalRoute` 필드 추가, 라우터로 전달
- `lib/features/route_search/presentation/screens/route_result_screen.dart` — **전면 재설계**:
  - `_TabConfig` enum 추가 (transferTradeoff/modeTradeoff/single)
  - 탭 라벨 동적 결정 (우선순위: 환승 트레이드오프 → 모드 트레이드오프 → 단일)
  - `enum TrainMode`, `_TrainModeToggle`, `_TrainModeTab`, `_trainMode` state 모두 제거
  - `_RouteView`를 `ConsumerStatefulWidget` → `ConsumerWidget`로 단순화
  - `useExpress` 자동 판정: 첫 세그먼트 lineId가 `E`로 끝나면 true
  - 시간표 조회 시 `9E` → `9` 변환 (base 노선 ID 기준)

### 테스트
- `test/graph/shortest_path_test.dart` — `nodeFilter` 옵션 검증 (시작/도착/중간 노드 모두 필터)
- `test/domain/usecases/search_route_test.dart` — `executeAll` 4종 반환 검증 (모드 트레이드오프 그룹)
- `test/features/route_search/presentation/route_result_screen_test.dart` — Case A/B/C 탭 동작 검증 (기존 토글 테스트 제거)

## 검증 결과

- `flutter analyze`: 변경 파일 관련 이슈 없음 (기존부터 있던 tool/DTO warning만 존재)
- `flutter test --exclude-tags integration`: **452/452 통과**

## 요구사항 충족 매트릭스

| 요구사항 | 구현 |
|---------|------|
| 환승 트레이드오프 시 "최단시간/최소환승" 탭 | ✅ Case A |
| 모드 트레이드오프 시 "급행/완행" 탭 | ✅ Case B |
| 단일 경로 시 탭 없음 | ✅ Case C |
| 모드별 다른 출발 시각 | ✅ `_useExpress` 기반 자동 판정 + 기존 `expressOnly` 필터 |
| `_TrainModeToggle` 제거 | ✅ 코드/테스트 모두 제거 |
