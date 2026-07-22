# 리뷰 이슈 수정 결과

## 적용된 수정 (CRITICAL/HIGH/MEDIUM)

### HIGH-1: shortest_path.dart dead code 제거
- `path.reversed; edges.reversed;` 두 줄 (게터만 호출하고 결과 무시) 삭제

### HIGH-2: route_result_screen.dart `_tabConfig` 중복 통합
- `_resolveTabConfig(RouteResultScreen w)` 정적 함수로 단일화
- `_tabConfig` getter / `didUpdateWidget` 모두 동일 함수 호출

### MEDIUM-A: app.dart dead 분기 제거
- 2종/1종 record 하위 호환 분기 삭제 (모든 호출자가 4종으로 마이그레이션 완료 — `home_screen.dart`, `subway_map_viewer.dart`)
- 4종 record + 폴백 메시지만 유지

### MEDIUM-B: `endsWith('E')` 패턴 산재 → `isExpressLineId` / `baseLineId` 유틸 통합
- `departure_time_calculator.dart`의 `_isExpressLineId` / `_baseLineId`를 public으로 승격 (각각 `isExpressLineId`, `baseLineId`)
- `route_result_screen.dart`의 `_useExpress`, `firstScheduleLineId`, `showExpressBadge` 모두 신규 유틸 사용
- `departure_time_calculator.dart` 내부 호출도 public 유틸로 교체

## 보류된 사항 (별도 후속 작업)

### MEDIUM-C: subway_map_viewer.dart `_activeRouteMode` 4모드 미지원
- 현재는 `'fastest'` / `'leastTransfer'` 두 모드만 처리 — Case B(모드 트레이드오프) 케이스에서 지도 toolbar UX 일관성 결여
- 결과 화면은 정상 동작하므로 사용자 명시 요구사항은 충족
- → spawn_task로 별도 등록

### LOW: `executeAll` 반환 타입을 Freezed로 승격
- record 4필드 → Freezed 모델 (copyWith + 명시 타입)
- 향후 필드 추가 시 안전성 확보용. 현재 동작에는 영향 없음

## 재검증

- `flutter analyze`: 변경 파일 관련 이슈 없음
- `flutter test --exclude-tags integration`: **452/452 통과**
