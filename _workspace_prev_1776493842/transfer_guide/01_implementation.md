# 환승 가이드 정보 기능 구현 산출물 (A~D, G)

## 변경된/추가된 파일

### 신규 (lib/)
- `lib/domain/entities/transfer_guide.dart`
  - `TransferGuide` freezed 엔티티, nullable 4개 필드 (`doorSide`, `car`, `door`, `note`)
  - `DoorSide` enum (`left`, `right`)
  - `TransferGuide.fromJson` 팩토리
- `lib/domain/entities/transfer_guide.freezed.dart` (build_runner 생성)
- `lib/domain/entities/transfer_guide.g.dart` (build_runner 생성)
- `lib/features/route_search/presentation/widgets/transfer_row.dart`
  - 기존 private `_TransferRow` / `_DashedLinePainter`를 `TransferRow` / `DashedLinePainter`로 승격 분리
  - `guide` 파라미터로 하차 문 방향/객차/문 번호 2행 표시
  - 헬퍼 private 함수: `_buildGuideText`, `_doorSideLabel`, `_buildCarDoorText`, `_resolveGuideIcon`

### 신규 (assets/)
- `assets/json/transfer_guides.json` — 빈 맵 `{}`로 시작

### 신규 (test/)
- `test/domain/entities/transfer_guide_test.dart` (9 케이스)
- `test/data/local/local_data_source_test.dart` (3 케이스 — 캐시/빈 맵/clearCache)
- `test/features/route_search/presentation/transfer_row_test.dart` (8 케이스)

### 수정 (lib/)
- `lib/domain/entities/route_result.dart`
  - `@Default([]) List<TransferGuide?> transferGuides` 필드 추가 (transferDurations 아래)
- `lib/data/local/local_data_source.dart`
  - `_transferGuidesCache` 필드
  - `loadTransferGuides()` 메서드 (loadTransferTimes 패턴 재사용)
  - `clearCache()`에 캐시 무효화 추가
- `lib/domain/repositories/station_repository.dart`
  - `Future<Map<String, TransferGuide>> getTransferGuides()` 인터페이스 추가
- `lib/data/repositories/station_repository_impl.dart`
  - `getTransferGuides()` 위임 구현
- `lib/domain/usecases/search_route.dart`
  - `execute` / `executeAll` / `_buildRouteResult`에서 `getTransferGuides()` 로드
  - `_buildSegments` 반환 레코드에 `transferGuides` 필드 추가
  - `_resolveTransferGuide` private 메서드 추출 (stationName/prevLineId/방향/nextLineId 키 조합)
  - `_buildGuideKey` 순수 헬퍼 함수 추출 (G 단계)
  - `isDownBetween` 재사용 (`lib/core/utils/line_direction.dart:15`)

### 수정 (test/)
- `test/domain/entities/route_result_test.dart`
  - `transferGuides` 기본값 빈 리스트 케이스 추가
  - `transferGuides` 필드 담은 객체 생성 케이스 추가
- `test/domain/usecases/search_route_test.dart`
  - `MockStationRepository.getTransferGuides` stub을 setUp에 빈 맵 기본값으로 추가
  - 신규 그룹 `transferGuides` (7 케이스):
    1. 가이드 데이터 없으면 환승별 null 반환
    2. same-line route의 transferGuides는 빈 리스트
    3. 상행(up) 키가 매칭되면 해당 가이드를 반영한다
    4. 반대 방향(down) 키로만 등록된 경우 null
    5. 역 순서를 뒤집은 경로에서도 방향 판정 일관성 (3호선 감소=up)
    6. 2호선 감소(외선, down) 방향 세그먼트 키 파생
    7. 출발역이 환승역인 경우 첫 transferGuide는 null
    8. transferGuides.length == transferDurations.length 불변
    9. executeAll 결과의 fastest에도 transferGuides 포함

## TDD 진행

### RED → GREEN 순서
1. **TransferGuide 엔티티**: 9개 테스트 → 엔티티 작성 → build_runner → 통과
2. **RouteResult 확장**: `transferGuides` 기본값 테스트 → 필드 추가 → build_runner → 통과
3. **LocalDataSource**: 3개 테스트 (빈 맵 로드, 캐시, clearCache) → 구현 → 통과
4. **Repository 위임**: 별도 테스트 없음 (Mock 기반 usecase 테스트에서 간접 검증)
5. **SearchRoute**: 기존 10 + 신규 9 = 19 테스트 → `_buildSegments` 확장, `_resolveTransferGuide` 추출 → 통과
6. **TransferRow 위젯**: 8 테스트 → public 위젯 분리 + UI 로직 → 통과
7. **IMPROVE**: `_buildGuideKey` 헬퍼 추출, 한국어 주석 보강

## 검증 결과

- `dart run build_runner build --delete-conflicting-outputs`: 성공 (17s, 11 outputs)
- `flutter analyze`: 에러 0건 (기존 `tool/*.dart` warning/info만 존재, 작업 무관)
- `flutter test --exclude-tags integration`: 343개 테스트 전부 통과
- 통합 테스트 `realtime_arrival_all_stations_test.dart`만 실패 — `SEOUL_API_KEY` 환경변수 미설정 때문이며 본 작업과 무관한 기존 이슈

## 파일 라인 수 (800줄 이하 제약 준수)

- `route_result_screen.dart`: 611 → 552 (기존 `_TransferRow` / `_DashedLinePainter` 분리)
- `search_route.dart`: 247 → 320
- `transfer_row.dart`: 189 (신규)

## 주요 설계 결정

1. **`TransferRow` public 위젯 분리**: 위젯 테스트 편의성 + `route_result_screen.dart` 라인 수 감소. `_DashedLinePainter`도 같이 `DashedLinePainter`로 공개.
2. **`UI 텍스트 조합 규칙 확장`**: 플랜의 "doorSide만 있으면 '왼쪽 문'" 케이스를 지원하기 위해 `_buildGuideText`를 조합 로직으로 구성. 플랜 명세에 없던 "doorSide + car만" 등 중간 조합도 합리적으로 처리(` · ` 구분자).
3. **방향 판정 재사용**: `isDownBetween(prevSeg.stations[-2].id, prevSeg.stations[-1].id, prevSeg.lineId)`. `prevSegment.stations.length < 2`이면 null로 간주.
4. **`guide == null`과 "가이드는 있으나 모든 필드 null"을 동등 취급**: 위젯에서 텍스트/아이콘이 모두 null이면 2행 생략 → 기존 UI와 픽셀 동일.
5. **Mocktail 회귀 방지**: `setUp`에 `getTransferGuides()` 기본 stub(빈 맵)을 명시 추가하여 기존 10개 테스트가 그대로 통과.

## 발견된 이슈/트레이드오프

- **JSON 파싱 방식**: `rootBundle.loadString` 직접 호출하므로 테스트에서 mock하기가 까다로움. 모의 JSON 주입 테스트를 초기에 시도했으나 rootBundle mock이 제대로 반영되지 않아 제거하고 번들 기본 파일(`{}`) 기반 기본 동작/캐시/clearCache만 검증. 추후 개선 여지는 있으나 LocalDataSource 다른 메서드도 같은 한계.
- **`_buildGuideKey` 외부 추출 여부**: 플랜 G 단계에서 "search_route.dart 또는 별도 헬퍼"라 권장. 지금은 SearchRoute 내부 메서드로 유지(다른 곳에서 사용처 없음). 향후 JSON generator 스크립트(`tool/build_transfer_guides.dart`)가 추가될 때 공용 유틸로 이동을 고려.
- **"출발역이 환승역" 시나리오**: 테스트 Dijkstra 경로에 따라 환승 엣지 발생 시점이 다를 수 있어, 테스트에서는 `transferGuides.isNotEmpty`인 경우만 null을 검증하는 방어적 형태로 작성. 실제 프로덕션에서는 `prevSegment.stations.length < 2` 가드가 null을 반환.

## 수동 검증 가이드 (플랜 Verification)

1. `assets/json/transfer_guides.json`에 임시 샘플 주입:
   ```json
   {
     "사당_2_up_4": {"doorSide": "right", "car": 6, "door": 3, "note": null}
   }
   ```
2. `flutter run` → 강남(2호선) → 동작(4호선) 경로 검색
3. 사당 환승 지점에 "→ 오른쪽 문 · 6-3" 2행 표시 확인
4. 다른 환승 경로는 기존 한 줄 UI 유지 확인
5. JSON 원복 후 모든 환승 행이 기존 UI로 복귀하는지 확인
