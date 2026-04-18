# 요구사항 리뷰 결과 — 환승 가이드 정보 (내리는 문 방향 / 객차 / 문 번호)

## 원래 요청

> "경로 검색결과에 각 환승역 다른 호선으로 환승할때의 정보가 필요해 (내리는 문 방향, 몇번객차 몇번문)"

## 승인된 플랜 핵심 결정사항

1. 외부 API/크롤링 조사 결과 공식 데이터 소스 없음 → 이번 PR은 **스키마·자리만 준비**, 실제 데이터 시딩은 후속
2. 데이터 키: 4-tuple `{환승역, 도착노선, 도착방향(up/down), 목적노선}`
3. UI 위치: 기존 환승 행(`_TransferRow` → `TransferRow`) **내부**에 2행 확장

---

## 1. 기능 완전성

### 사용자 요청 3대 정보

| 요구사항 | 모델링 | UI 표시 | 판정 |
|---------|--------|---------|------|
| 내리는 문 방향 (좌/우) | `DoorSide` enum (left/right) + nullable | "왼쪽 문" / "오른쪽 문" + `arrow_back` / `arrow_forward` 아이콘 | ✅ |
| 몇 번 객차 | `int? car` (1-based) | `"6번 칸"` 또는 `"6-3"` | ✅ |
| 몇 번 문 | `int? door` (1-based, 객차 내) | `"3번 문"` 또는 `"6-3"` | ✅ |

**결과**: 3가지 정보 전부 모델링 + UI 렌더링 경로 완결.

### "각 환승역 다른 호선으로 환승할때" 의미 반영

- 동일 환승역이어도 **오는 방향**과 **가는 노선**이 다르면 다른 가이드가 필요
- 구현된 4-tuple 키(`{역명}_{이전노선}_{방향up|down}_{다음노선}`)가 이 4축을 모두 담음
- 방향 판정: `isDownBetween(prevSeg.stations[-2].id, stations.last.id, prevSeg.lineId)` — 2호선 순환/4호선 진접선 특수 케이스 모두 대응
- 테스트에서 "같은 환승역, 반대 방향(up/down) 키는 매칭 실패" 시나리오 검증 (search_route_test.dart:174)

✅ 의도 정확히 반영

### 플랜 A~G 섹션 구현 여부

| 섹션 | 항목 | 구현 여부 |
|-----|------|----------|
| A | `TransferGuide` Freezed 엔티티 + `DoorSide` enum + nullable 4필드 | ✅ |
| A | `RouteResult.transferGuides: List<TransferGuide?>` (`@Default([])`) | ✅ |
| B | `assets/json/transfer_guides.json` 빈 맵 생성 | ✅ |
| B | `LocalDataSource.loadTransferGuides` + 캐시 + `clearCache()` 무효화 | ✅ |
| B | `StationRepository.getTransferGuides()` 인터페이스 + Impl 위임 | ✅ |
| C | `SearchRoute.execute` / `executeAll` / `_buildRouteResult`에서 guide 로드 | ✅ |
| C | `_buildSegments` 반환 레코드에 `transferGuides` 포함 + 환승 엣지 블록에서 조회 | ✅ |
| C | `isDownBetween` 재사용으로 방향 판정 | ✅ |
| D | UI 확장 (2행, 문방향 아이콘, "왼쪽 문 · 6-3" 텍스트, note) | ✅ |
| D | `guide == null` 또는 필드 모두 null → 2행 비렌더 (하위 호환) | ✅ |
| E | TransferGuide 엔티티 테스트 (9) | ✅ |
| E | SearchRoute 테스트 확장 (9 신규) | ✅ |
| E | TransferRow 위젯 테스트 (8) | ✅ |
| E | RouteResult 테스트 확장 | ✅ |
| F | 외부 데이터 소싱 조사 | ⚠ **문서화 누락** (아래 참조) |
| G | `_buildGuideKey` 순수 헬퍼 추출 | ✅ |

✅ **A~E, G 전부 구현** — F(데이터 소싱 조사 문서)만 부분

---

## 2. 의도 부합성

### 사용자 UX 관점

| 시나리오 | 예상 동작 | 실제 동작 | 부합 |
|---------|----------|----------|------|
| 환승 행에 하차 문 방향 확인 | 한 눈에 "← 왼쪽 문" 표시 | arrow_back 아이콘 + "왼쪽 문" 라벨 | ✅ |
| 객차·문 번호 동시 확인 | "6-3" 같은 간결 표기 | `car + door`일 때 `"6-3"` | ✅ |
| 부분 정보만 있는 경우 | 있는 정보만 graceful 표시 | nullable 필드 + 조합별 분기 (`6번 칸`, `3번 문`, `왼쪽 문` 단독 등) | ✅ |
| 데이터 없는 환승 | 기존 "환승 N분" UI 유지 | `guide == null` → 2행 생략, 픽셀 동일 | ✅ |
| 메모(note) | 부가 설명 가능 | `guide.note` → 회색 텍스트로 덧붙임 | ✅ |

### 기술 설계 의도

- **4-tuple 키 → 환승역 × 도착방향 × 목적노선 정확 식별**: 역명 중복(시청1/2, 서울역 등)은 `{도착노선}`이 들어가 unique
- **`TransferRow` 공개 위젯 분리**: 테스트 편의 + `route_result_screen.dart` 라인 수 611→552 감소
- **`@Default([])`**: 기존 RouteResult 호출자/fixture에 파급 0

✅ 전부 부합

---

## 3. 엣지 케이스

| 엣지 케이스 | 처리 |
|------------|------|
| 출발역이 환승역 (첫 세그먼트 역 1개) | `_resolveTransferGuide`에서 `completedSegment.stations.length < 2` 가드 → null (search_route.dart:280) |
| 데이터 맵이 빈 `{}` | 모든 `transferGuides` 원소 null → UI 그대로 |
| 일부만 매칭 | 매칭된 행만 2행 추가, 나머지 기존 UI |
| 2호선 순환선 방향 판정 | `isDownBetween`의 `_isLine2DownBetween` (`|step| > 21` 경계 반전) 재사용 — 테스트 `2호선 감소(외선, down) 방향 세그먼트` 케이스로 검증 (search_route_test.dart:202) |
| 4호선 진접선 분기 | `_isLine4Down` 재사용 (수정 없음) |
| 역명 중복 (시청 1/2) | 키에 `{도착노선}` 포함 → unique |
| `guide`는 존재하나 모든 필드 null | `TransferRow`가 `hasGuide == false` 분기 → 2행 생략 (transfer_row.dart:23) |
| 잘못된 JSON enum 값 | `DoorSide.fromJson`이 `ArgumentError` throw — 테스트에서 명시 (transfer_guide_test.dart:104). **전역 로드 시점에는 번들 JSON 자체가 무효 데이터를 포함하면 앱 크래시 가능** (아래 참조) |
| `transferGuides.length == transferDurations.length` 불변 | search_route_test.dart:266에서 검증 |
| 역 순서 뒤집은 경로(3호선 감소=up) | search_route_test.dart:186에서 검증 |
| RouteResult fixture 호환성 | `@Default([])` 덕에 기존 fixture 수정 없음, 명시적 테스트도 추가 (route_result_test.dart:24) |
| 번들 JSON 미등록 | `pubspec.yaml`의 `- assets/json/` 디렉터리 등록으로 자동 포함 — 수정 불필요 ✅ |

### ⚠ 발견된 엣지 케이스 미처리

- **잘못된 번들 JSON의 전역 파싱 실패 폴백 없음**
  - `loadTransferGuides()`는 `TransferGuide.fromJson` 실패 시 예외가 그대로 전파됨 → `SearchRoute.execute`가 throw → 사용자는 경로 검색이 먹통이 됨
  - 현재 `assets/json/transfer_guides.json`은 빈 맵 `{}`이라 안전하나, **후속 PR에서 실제 데이터를 주입할 때 잘못된 enum 값(예: `"doorSide":"middle"`) 한 건만 들어가도 전체 경로 검색이 실패**
  - 권장 완화: `loadTransferGuides`에서 `try/catch`로 개별 항목 파싱 실패 시 해당 키만 skip하고 로그 (또는 빈 맵 폴백). 본 PR 범위에서 빠르게 보강 가능.
  - 심각도: **MEDIUM** (후속 데이터 주입까지 드러나지 않지만, 주입 시점에 회귀 위험)

---

## 4. 오버 엔지니어링

| 항목 | 평가 |
|-----|------|
| `TransferRow` / `DashedLinePainter`를 public으로 승격 | ✅ 테스트 편의 + 파일 분리 목적 → 플랜 G의 "파일당 800줄" 제약과 정합. 오버엔지니어링 아님 |
| `_buildGuideKey` 헬퍼 함수 추출 | ✅ 플랜 G 명시 요구사항 (라인 294-302) |
| `_buildCarDoorText` / `_doorSideLabel` / `_buildGuideText` / `_resolveGuideIcon` 헬퍼 4종 | ✅ `TransferRow` UI 로직을 데이터 조합 규칙 8가지로 분기하려면 필요. 과하지 않음 |
| `TransferGuide.note` 필드 | 플랜 A에 명시 (표 37행) → 요구사항 |
| `DoorSide` enum (string 대신) | 타입 안전성 확보, 과잉 추상화 아님 |
| `@Default([])` | 기존 fixture 무영향 — 회귀 방지 용도 |

⚠ **오버엔지니어링 없음**. 플랜 범위 내에서 필요한 추상만 도입됨.

### 경미한 관찰 (오버엔지니어링은 아니나 주목할 점)

- **`TransferGuide.note` 필드**는 플랜에 있으나 사용자가 원 요청에서 언급한 3대 정보(문 방향, 객차, 문 번호)에는 포함되지 않음. 다만 플랜의 "보조 설명" 제공은 사용자 UX 확장으로서 합리적이고, null일 때 UI에서 숨겨져 부작용 없음 → 승인된 플랜에 명시되어 있으므로 문제 없음.

---

## 5. 사용자가 "당장" 기능을 체감할 수 있는가

### 현재 상태

- `assets/json/transfer_guides.json`은 빈 맵 `{}`이므로 **당장은 화면에 아무것도 추가되지 않음** — 모든 환승 행이 기존 "환승 N분" 단일 라인 UI로 동일 렌더
- 이는 **플랜의 "자리만 준비" 합의와 일치** (plan.md line 13)

### 후속 작업 필요성 (원래 요청 관점)

사용자가 진짜로 원하는 것은 **화면에서 정보를 확인하는 것**이므로, 현재 구현만으로는 **원 요청을 체감적으로 완결하지 못함**. 이 PR은 "모델·로직·UI 자리 준비" 수준이고, 실제 UX는 후속 데이터 크롤링/수집 PR에 달려 있음.

### 후속 작업 명시성

플랜 F 섹션에 데이터 소싱 테이블이 있으나, 구현 산출물에는 **후속 작업을 기록한 문서가 생성되지 않았음**:

- ❌ `docs/transfer_guide_sourcing.md` 또는 README 추가분 누락
- `_workspace/transfer_guide/01_implementation.md`의 "발견된 이슈/트레이드오프"와 "수동 검증 가이드"에 일부 언급은 있으나, 프로덕트 저장소(`lib/`, `docs/`) 수준의 영속 문서는 없음
- **심각도**: LOW (기능 로직에는 영향 없고, 차기 PR 시작 시 플랜 F 테이블을 직접 참조 가능)
- 권장: README에 "환승 가이드 데이터 후속 작업" 섹션 또는 `lib/domain/entities/transfer_guide.dart` doc 코멘트에 예상 소싱 경로 한 줄 추가

---

## 6. 종합 요약표

### 충족률

| 카테고리 | 항목 수 | 충족 | 부분 | 누락 | 비율 |
|---------|-------|------|------|------|------|
| 사용자 3대 정보 (문방향/객차/문) | 3 | 3 | 0 | 0 | 100% |
| UI 표시 경로 | 1 | 1 | 0 | 0 | 100% |
| 4-tuple 방향별 구분 | 1 | 1 | 0 | 0 | 100% |
| 플랜 A~G 섹션 | 7 | 6 | 1 (F) | 0 | 93% |
| 엣지 케이스 처리 | 11 | 10 | 1 | 0 | 91% |
| 회귀 방지 (기존 테스트) | 1 | 1 | 0 | 0 | 100% |

**종합 충족률**: 22/24 ≒ **92%**

### 누락 / 부분 구현

1. **⚠ [MEDIUM]** 번들 JSON의 부분 파싱 실패 폴백 — 후속 PR에서 실제 데이터를 주입할 때 회귀 위험 (권장: `loadTransferGuides`에서 항목별 try/catch)
2. **⚠ [LOW]** 후속 작업(데이터 크롤링/소싱) 영속 문서 미생성 — `_workspace/` 임시 문서는 있으나 `docs/` 또는 README에 반영되지 않음
3. **ℹ [정보]** 빈 맵으로 시작 → 사용자가 화면에서 기능을 체감하려면 후속 데이터 PR 필요 (플랜 합의사항이라 누락 아님)

### 불일치

- 없음. 플랜과 구현 1:1 매칭.

### 오버엔지니어링

- 없음.

---

## 7. 후속 작업 제안 (우선순위 순)

1. **데이터 소싱 PR** (원 기능 체감의 핵심)
   - 플랜 F의 테이블을 참조하여 네이버/카카오 지도 경로 파싱 또는 수동 수집
   - `tool/build_transfer_guides.dart` generator 스크립트 추가
   - 주요 환승역 10-20개부터 시드 (사당, 을지로3가, 신도림, 종로3가 등)

2. **[MEDIUM] `loadTransferGuides` 항목별 파싱 폴백** (본 PR에 선택적으로 포함 가능)
   ```dart
   // 의사코드
   for (final entry in jsonMap.entries) {
     try {
       result[entry.key] = TransferGuide.fromJson(entry.value);
     } catch (e) {
       // log & skip — 전역 실패 방지
     }
   }
   ```

3. **[LOW] 후속 작업 영속 문서화**
   - `docs/transfer_guide_sourcing.md` 생성 (플랜 F 테이블 + TODO)
   - 또는 `TransferGuide` doc 코멘트에 "데이터 소싱: …" 한 줄

4. **(장기) WebView 탭 이벤트와 통합** — 환승역을 탭했을 때 가이드를 별도 모달로 띄우기 (현재 PR 범위 밖)

---

## 8. 종합 판정

**판정**: ✅ **APPROVED** (경미한 개선 권장)

### 근거

- 사용자 원 요청의 3대 정보(문 방향/객차/문)가 모두 모델링되고 UI 경로까지 연결됨
- "각 환승역 다른 호선으로 환승할때"의 방향·노선별 구분이 4-tuple 키로 정확히 반영
- 승인된 플랜의 합의사항(자리만 준비, 데이터는 후속)과 일치
- 하위 호환성 완벽 (`@Default([])` + null 가드 + 픽셀 동일 UI)
- 19+8+3+9+기타 → 총 40여 테스트 신규/확장, 기존 343개 테스트 회귀 0건
- `flutter analyze` 신규 오류 0건

### 권장 후속 조치

- **본 PR 내 선택적 수정**: `loadTransferGuides` 항목별 try/catch 추가 (후속 데이터 주입 시 안전성↑)
- **후속 PR 필수**: 실제 환승 가이드 데이터 시딩 — 이것이 있어야 사용자가 기능을 체감
- **문서**: 후속 작업 소스 테이블을 `docs/`에 영속 기록

---

## 부록: 검증 체크리스트

- [x] 요청된 3가지 정보(문 방향/객차/문) 모두 모델링
- [x] 방향별/노선별 구분 (4-tuple)
- [x] UI 표시 경로 (`TransferRow` 확장)
- [x] 승인된 플랜 A~G 모든 섹션 구현 (F는 문서화 부분만 미흡)
- [x] 엣지 케이스 처리 (출발역=환승역, 2호선 순환, 역명 중복, 빈 맵)
- [x] 하위 호환성 (기존 UI 픽셀 동일)
- [x] 오버엔지니어링 없음
- [x] 데이터 부재 상태는 의도된 것(플랜 합의)임을 확인
- [ ] 후속 작업(데이터 소싱) 영속 문서화 — **LOW 우선순위 누락**
- [ ] 번들 JSON 부분 파싱 실패 폴백 — **MEDIUM 우선순위 누락**
