# 환승 가이드(내리는 문/객차/문 번호) 데이터 수집 가이드

## 개요

경로 검색 결과 화면에 표시되는 **환승 가이드**(내리는 문 방향 / 추천 객차 번호 / 문 번호)의 데이터 소스와 입력 워크플로우를 설명한다.

- 런타임 키 포맷: `{환승역명}_{도착노선ID}_{up|down}_{목적노선ID}`
- 생성 함수: [`lib/core/utils/transfer_guide_key.dart`](../lib/core/utils/transfer_guide_key.dart)
- JSON 저장소: [`assets/json/transfer_guides.json`](../assets/json/transfer_guides.json)
- 입력 CSV: [`data/transfer_guides.csv`](../data/transfer_guides.csv)

## 왜 자동 크롤링이 어려운가

조사 결과 이 데이터는 공식 공개 API로 제공되지 않으며, 주요 출처들은 자동 수집에 제약이 있다:

| 출처 | 상태 | 제약 |
|---|---|---|
| 서울 열린데이터광장 (data.seoul.go.kr) | 미제공 | 실시간 도착·노선 정보만 있음 |
| 서울교통공사 "또타지하철" 앱 | 공식·전 노선 | 역엔지니어링 금지 |
| 네이버 지도 경로 검색 API | 문자열 제공 | 비공식 사용 시 서비스 약관 리스크 |
| 카카오맵 | 유사 | 유사 |
| 나무위키 (수도권 전철 환승 정보) | 표 형태로 상세 | 403, Cloudflare 차단 |
| 철도통합정보시스템 (station.kric.go.kr) | "빠른 환승정보" 탭 존재 | JS 렌더링 — 정적 fetch 불가 |
| 한국어 위키백과 | 단편적 | 객차/문 번호 누락 |
| 블로그/커뮤니티 | 단편적 | 일관성 없음 |

따라서 **수동 입력 + CSV→JSON 빌드** 워크플로우가 현재 가장 안전한 방법이다.

## 수집 워크플로우

### 1. 출처 확인

아래 출처 중 하나에서 확인하여 **교차검증**한다:

1. **역내 빠른환승 스티커 (현장 확인)** — 가장 정확. 승강장 바닥/기둥에 부착된 "빠른환승" 스티커에 `M-N` 형식(M호차 N번문) 표기
2. **서울교통공사 "또타지하철" 공식 앱** — 역 정보 → 환승 안내
3. **나무위키 "수도권 전철 환승 정보" 문서 트리** — 403이 나면 VPN/다른 브라우저에서 열람 후 텍스트로 복사
4. **네이버/카카오 지도 경로 검색** — 환승 단계에서 "N-M 호차 빠른환승" 문자열이 등장

**문 방향(left/right)**은 승강장 구조로 결정론적 추론 가능:
- 섬식 승강장 + 좌측통행(1호선): 오른쪽 문
- 섬식 승강장 + 우측통행(대부분): 왼쪽 문
- 상대식 승강장: 진행 방향 반대편 문 (노선별 통행 규정에 따라)

### 2. CSV 편집

`data/transfer_guides.csv` 파일을 엽니다. 컬럼:

| 컬럼 | 값 | 예시 |
|---|---|---|
| `station` | 환승역명 | `사당` |
| `arrival_line` | 도착 노선 ID (이 역에 **도착한** 노선) | `2` |
| `direction` | 도착 방향 (up=상행/내선, down=하행/외선) | `down` |
| `destination_line` | 목적 노선 ID (**갈아탈** 노선) | `4` |
| `door_side` | 내리는 문 방향 (`left`/`right`/빈 값) | `right` |
| `car` | 추천 객차 번호 (양의 정수/빈 값) | `6` |
| `door` | 추천 문 번호 (양의 정수/빈 값) | `3` |
| `note` | 보조 설명 (선택) | `충무로 방면 가까움` |

- **빈 행**: 4개 데이터 필드(door_side, car, door, note)가 모두 비어 있으면 JSON에 기록되지 않음 → 아직 미수집 상태로 해석
- **부분 입력**: 4개 중 하나라도 있으면 기록됨 — 문 방향만 알 때 `door_side`만 채워도 됨

### 3. JSON 빌드

```bash
dart run tool/import_transfer_guides.dart
```

- 채워진 행만 `assets/json/transfer_guides.json`에 기록
- 키 포맷이 런타임 `buildTransferGuideKey`와 일치함이 보장됨
- 잘못된 값(enum 오타, 음수 등)은 경고 후 스킵

### 4. 실행 확인

```bash
flutter run --release
```

경로 검색 시 해당 환승 지점에서 2행 레이아웃(예: `← 왼쪽 문 · 6-3`)이 렌더된다.

## 진행 상황 추적

`_workspace/transfer_guide/stations_checklist.md` 에 **93개 환승역**과 방향쌍 수가 정리되어 있다. 호선 수 많은 역부터 우선 처리를 권장:

1. 서울역 (5개 노선, 방향쌍 40개)
2. 공덕 (4개)
3. 왕십리 (4개)
4. 청량리 (4개)
5. 고속터미널, 김포공항, 대곡, 동대문역사문화공원, 디지털미디어시티, 상봉, 수서, 연신내, 종로3가, 홍대입구, 회기 (3개)
6. 나머지 78개 환승역 (2개)

## 데이터 품질 원칙

- **잘못된 데이터 > 없는 데이터** 규칙이 **성립하지 않음**. 사용자가 잘못된 문으로 내려 불편을 겪을 수 있으므로 **확실치 않으면 빈 값으로 둔다**
- `note` 필드에 출처 간단히 표기 권장 (예: `또타지하철 2026-04`, `현장확인 2026-04-17`)
- 역사 개·보수로 데이터가 바뀔 수 있으므로 `note`의 날짜 정보 유지

## 관련 파일

- [`lib/domain/entities/transfer_guide.dart`](../lib/domain/entities/transfer_guide.dart) — Freezed 모델
- [`lib/core/utils/transfer_guide_key.dart`](../lib/core/utils/transfer_guide_key.dart) — 키 포맷 유틸
- [`lib/data/local/local_data_source.dart`](../lib/data/local/local_data_source.dart) — 번들 JSON 로더 (개별 파싱 실패 폴백 포함)
- [`lib/domain/usecases/search_route.dart`](../lib/domain/usecases/search_route.dart) — 4-tuple 키 조회
- [`lib/features/route_search/presentation/widgets/transfer_row.dart`](../lib/features/route_search/presentation/widgets/transfer_row.dart) — 2행 UI
- [`tool/import_transfer_guides.dart`](../tool/import_transfer_guides.dart) — CSV→JSON 빌드 스크립트
- [`data/transfer_guides.csv`](../data/transfer_guides.csv) — 입력 CSV (556행 템플릿)
