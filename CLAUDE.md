# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 작업 워크플로우 (필수)

코드를 작성하거나 수정할 때 반드시 아래 루프를 따릅니다:

1. **구현** — 요청된 작업을 수행
2. **리뷰 (2단계 병렬 실행)**
  - **코드 리뷰** — `code-reviewer` 에이전트로 코드 품질, 버그, 보안, 성능 리뷰
  - **요구사항 리뷰** — 사용자의 원래 요청과 비교하여 다음을 검증:
    - 요청된 기능이 모두 구현되었는가 (누락 없는지)
    - 구현이 요구사항의 의도에 부합하는가
    - 엣지 케이스나 사용자 시나리오가 빠지지 않았는가
    - 불필요하게 추가된 기능은 없는가 (오버 엔지니어링)
3. **수정** — 두 리뷰에서 발견된 이슈를 수정
4. **재리뷰** — 수정된 코드를 다시 2단계로 리뷰
5. **반복** — 리뷰 이슈가 없을 때까지 3~4단계를 반복
6. **완료** — `flutter analyze`로 최종 검증 후 결과 보고

> 단순 오타 수정, 설정 변경 등 1~2줄 변경은 리뷰 루프를 생략할 수 있습니다.

## 빌드 및 개발 명령어

```bash
# 코드 생성 (freezed, json_serializable, riverpod_generator)
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs  # 워치 모드

# 앱 실행
flutter run                    # 시뮬레이터 (debug 모드 OK)
flutter run --release          # 실 디바이스 (반드시 --release)

# 테스트
flutter test                   # 전체 테스트
flutter test test/graph/       # 특정 디렉토리
flutter test test/graph/shortest_path_test.dart  # 단일 파일

# 정적 분석
flutter analyze

# SVG에서 역 좌표 추출 (svg_station_coords.json 생성)
dart run tool/extract_svg_stations.dart

# 역/노선 JSON 에셋 재생성 (svg_station_coords.json 참조)
dart run tool/generate_station_data.dart

# WebView용 HTML 생성 (seoul_metro_map.svg → map.html)
dart run tool/build_map_html.dart
```

**중요:** 실 디바이스(iPhone 등) 빌드는 반드시 `--release` 모드를 사용해야 한다. 디버그 빌드는 Dart VM 연결이 필요하므로 앱을 백그라운드로 보냈다 다시 열면 크래시가 발생한다.

## 환경 설정

프로젝트 루트의 `.env` 파일 (`pubspec.yaml` assets에 등록됨):
```
SEOUL_API_KEY=<data.seoul.go.kr에서 발급받은 키>
```
앱 런타임에 키를 검증하며, placeholder 값이면 예외를 던진다.

## 아키텍처

Clean Architecture + 기능별 폴더 구성:

```
lib/
  core/          # 공통: API 클라이언트(Dio), 네트워크 정보, 테마, 상수, 에러 타입
  domain/        # 순수 Dart: 엔티티(Freezed), 리포지토리 인터페이스, 유스케이스
  data/          # 구현체: 리포지토리 구현, 데이터소스(로컬 JSON + 원격 API), DTO
  features/      # 기능별 UI: 스크린, 위젯, Riverpod 프로바이더
  graph/         # 독립된 최단경로 모듈 (Dijkstra)
```

**데이터 흐름:** UI (ConsumerWidget / Consumer) → Riverpod 프로바이더 → 리포지토리 구현체 → 데이터소스 (번들 JSON 또는 서울 API via Dio)

의존성 주입은 Riverpod 프로바이더 내부에서 수동으로 수행 (서비스 로케이터 미사용).

### 핵심 도메인 개념

- **역(Station)** 은 캔버스 렌더링용 `svgX`/`svgY` 좌표를 가짐 (원본 SVG의 circle 좌표에서 추출, `extract_svg_stations.dart`로 생성)
- **그래프 노드 ID 형식:** `"{stationId}_{lineId}"` (예: `"216_2"` = 2호선 강남역)
- **환승 시간 키 형식:** `"{역이름}_{lineId1}_{lineId2}"` (`transfer_times.json` 내)
### 노선 정보

`lines.json`에 정의된 노선과 `line_colors.dart`의 색상/이름 매핑:

| ID | 이름 | 색상 코드 | 역 ID 범위 | 역 수 |
|---|---|---|---|---|
| `'1'` | 1호선 | `#0052A4` (파랑) | 101–162 | 62 |
| `'2'` | 2호선 | `#00A84D` (초록) | 201–243 | 43 |
| `'3'` | 3호선 | `#EF7C1C` (주황) | 301–343 | 43 |
| `'4'` | 4호선 | `#00A5DE` (하늘) | 401–448 | 48 |
| `'5'` | 5호선 | `#996CAC` (보라) | 501–556 | 56 |
| `'6'` | 6호선 | `#CD7C2F` (황토) | 601–638 | 38 |
| `'7'` | 7호선 | `#747F00` (올리브) | 701–742 | 42 |
| `'8'` | 8호선 | `#E6186C` (분홍) | 801–818 | 18 |
| `'9'` | 9호선 | `#BDB092` (베이지) | 901–938 | 38 |
| `'SB'` / `'신분당'` | 신분당선 | `#D31145` (빨강) | D01–D16 | 16 |
| `'경의중앙'` | 경의중앙선 | `#77C4A3` (민트) | K01–K54 | 54 |
| `'경춘'` | 경춘선 | `#0C8E72` (청록) | C01–C24 | 24 |
| `'공항철도'` | 공항철도 | `#0090D2` (파랑) | A01–A14 | 14 |
| `'수인분당'` | 수인분당선 | `#F5A200` (금색) | B01–B57 | 57 |
| `'신림'` | 신림선 | `#6789CA` (연파랑) | S01–S10 | 10 |
| `'에버라인'` | 에버라인 | `#36A805` (녹색) | E01–E14 | 14 |
| `'인천1'` | 인천1호선 | `#6496DF` (연파랑) | I01–I31 | 31 |
| `'인천2'` | 인천2호선 | `#CF843C` (주황갈) | J01–J24 | 24 |
| `'김포골드'` | 김포골드라인 | `#A18F57` (금갈) | P01–P09 | 9 |
| `'서해'` | 서해선 | `#40A607` (녹색) | H01–H11 | 11 |
| `'의정부'` | 의정부경전철 | `#D9750D` (주황) | U01–U14 | 14 |
| `'우이신설'` | 우이신설경전철 | `#878787` (회색) | W01–W10 | 10 |
| `'GTX-A'` | GTX-A | `#9F6181` (자주) | G01–G09 | 9 |

신분당선은 `'SB'`와 `'신분당'` 두 가지 ID가 모두 색상/이름 맵에 등록되어 있다. `lines.json`에서는 `'SB'`를 사용한다.
경의중앙선 K54(서울역)는 K24(효창공원앞)에서 분기하는 dead-end 지선이다.
경춘선 C01–C05(청량리~망우)와 경의중앙선 K32–K36은 물리적으로 같은 선로이나 별개 노드 + 환승 엣지로 처리한다.
수인분당선 B43–B50(한대앞~오이도)과 4호선 441–448도 별개 노드 + 환승 엣지로 처리한다

### 상태 관리

Riverpod 2.x + 코드 생성 (`@riverpod` 어노테이션). 주요 프로바이더:

- `allStationsProvider` — 번들 JSON에서 전체 역 목록 로드
- `selectedStationsProvider` — 출발/도착역 선택용 `StateNotifier<SelectedStations>` (수동 작성, 비생성)
- `tappedStationProvider` — 지도 탭 상호작용용 `StateProvider<Station?>`
- `arrivalInfoProvider(stationName)` — 실시간 도착 정보 family 프로바이더

**리빌드 최적화 패턴:**
- `HomeScreen`은 `StatelessWidget`이며, `selectedStationsProvider`를 watch하는 부분을 `Consumer` 위젯으로 분리하여 `SubwayMapScreen`의 불필요한 리빌드 방지
- `SubwayMapScreen`은 `ConsumerStatefulWidget`이며, `getAllConnections()` Future를 `initState`에서 한 번만 생성하여 FutureBuilder 리빌드 방지

### 라우팅 (go_router)

| 경로 | 스크린 | 비고 |
|---|---|---|
| `/` | HomeScreen | 지도 + 검색바 |
| `/pick-station/:purpose` | StationPickerScreen | purpose = "departure" 또는 "arrival" |
| `/route-result` | RouteResultScreen | `RouteResult`를 `state.extra`로 전달 |
| `/station/:stationId` | StationDetailScreen | |
| `/arrivals/:stationName` | ArrivalInfoScreen | 15초마다 자동 새로고침 |

### 지도 렌더링

지하철 지도는 `webview_flutter`로 원본 SVG를 HTML 내에서 네이티브 렌더링한다:

```
Expanded → WebViewWidget (전체 화면)
  └─ HTML 페이지 (assets/html/map.html)
      ├─ <svg> 원본 (seoul_metro_map.svg 인라인, 한국어 텍스트 포함)
      ├─ 경로 하이라이트 (SVG overlay <g>)
      ├─ 출발/도착 마커 (SVG <circle>)
      ├─ 툴팁 (HTML div, position:absolute)
      ├─ 줌/팬 핸들러 (CSS transform + 터치/포인터 이벤트)
      └─ 탭 핸들러 → JavaScriptChannel → Flutter
```

**SvgWebView** (`svg_web_view.dart`) — WebView 래퍼 위젯:
- `loadFlutterAsset('assets/html/map.html')`로 HTML 로드
- `JavaScriptChannel('StationChannel')`로 탭/액션 이벤트 수신
- `runJavaScript()`로 경로 하이라이트, 마커, 툴팁 제어
- 줌/팬은 JS에서 CSS `transform: matrix(...)` 기반으로 처리 (0.1x~5.0x)
- 초기 뷰: 2호선 순환 중심(1260, 1240), 스케일 0.25

### SVG 데이터 파이프라인

원본 SVG(`seoul_metro_map.svg`)에서 앱 에셋을 생성하는 3단계 파이프라인:

```bash
# 1단계: SVG에서 역 좌표 추출
dart run tool/extract_svg_stations.dart
# → assets/json/svg_station_coords.json (653개 역의 SVG 좌표)

# 2단계: 역/노선/연결 JSON 생성 (SVG 좌표 참조)
dart run tool/generate_station_data.dart
# → assets/json/stations.json, connections.json, lines.json, transfer_times.json

# 3단계: WebView용 HTML 생성 (SVG를 HTML에 인라인 삽입)
dart run tool/build_map_html.dart
# → assets/html/map.html
```

**SVG 좌표 추출** (`extract_svg_stations.dart`):
- SVG의 `<text data-station="역명">` 라벨과 가장 가까운 `<circle>` 좌표를 매칭
- 역명의 줄바꿈 문자 자동 제거 (SVG `<tspan>` 분할 역명 처리)
- 모든 `data-line` 값을 추출 (GTX-A `1-GA` 포함)

**HTML 빌드** (`build_map_html.dart`):
- 원본 SVG를 HTML 템플릿에 인라인 삽입
- SVG 최소 변환: `width="100%" height="100%"` → `width="2416" height="1560"`, `style="background: white;"` 제거
- JS로 줌/팬, 탭 감지, 경로 하이라이트, 마커, 툴팁 기능 구현
- 오버스크롤 여백: 상하좌우 70px (`clampTranslation` 함수)

**JS 성능 패턴** (저사양 기기 대응):
- **rAF 스케줄링**: `pointermove`/`wheel`/`resize` 이벤트에서 `scheduleTransform()` 사용. `rafPending` 플래그로 프레임당 1회만 `applyTransform()` 실행. 초기화(`setInitialView`)나 애니메이션(`panTo`)에서는 직접 `applyTransform()` 호출.
- **CSS 클래스 기반 강조/흐림**: 노선 강조 시 개별 `style.opacity` 대신 `.dimmed` CSS 클래스를 토글. `transition: opacity 0.3s`는 CSS에서 일괄 적용.
- **overlay circle 분리**: overlay 내부에서 생성하는 모든 `<circle>`에 `data-overlay` 속성 부여. 강조 처리 시 `circle:not([data-overlay])` 셀렉터로 원본 SVG circle만 대상. `closest()` DOM 탐색 불필요.

**SVG 스타일 규격** (원본 SVG 교체 시에도 유지해야 할 값):

| 요소 | 속성 | 값 | 비고 |
|---|---|---|---|
| 역이름 텍스트 (`<text>`) | `font-size` | `12px` | 인라인 스타일 |
| 역이름 텍스트 (`<text>`) | CSS `stroke` | `white`, `2px`, `paint-order: stroke` | `build_map_html.dart`의 `<style>` 블록에서 적용, 흰색 테두리 |
| 역이름 줄바꿈 | `<tspan>` | `dy="14"` | 띄어쓰기 포함 역이름은 `<tspan>`으로 분리 |
| 일반역 원 (`<circle>`) | `r` | `4.5` | |
| 환승역 원 (`<circle>`) | `r` | `5` | |
| 노선 경로 (`<path>`) | `stroke-width` | `3` | 2호선 제외 |
| 2호선 경로 (`data-line="3-2"`) | `stroke-width` | `4` | 순환+지선 |

**SVG data-line 매핑** (원본 SVG의 노선 코드 → 앱 lineId):

| data-line | 앱 lineId | 비고 |
|---|---|---|
| `2-1` | `1` | 1호선 |
| `3-2` ~ `10-9` | `2` ~ `9` | 2~9호선 (N-M 형식, M이 호선 번호) |
| `S` | `SB` | 신분당선 |
| `K` | `경의중앙` | 경의중앙선 |
| `KK` | `경춘` | SVG 내 경강선 역, 앱에서는 경춘 lineId로 매핑 |
| `A` | `공항철도` | 공항철도 |
| `B` | `수인분당` | 수인분당선 |
| `SL` | `신림` | 신림선 |
| `E` | `에버라인` | 에버라인 (용인경전철) |
| `G` | `경춘` | 경춘선 고유구간 (SVG 경로용, 별도 노선 아님) |
| `I` | `인천1` | 인천1호선 |
| `I2` | `인천2` | 인천2호선 |
| `KP` | `김포골드` | 김포골드라인 |
| `SH` | `서해` | 서해선 |
| `U` | `의정부` | 의정부경전철 |
| `W` | `우이신설` | 우이신설경전철 |
| `1-GA` | `GTX-A` | GTX-A 광역급행철도 |

**중요:** 원본 SVG를 수정한 후 반드시 3단계 파이프라인을 순서대로 재실행해야 한다.

### 네트워크 및 캐싱

- 서울 열린데이터 API: `http://swopenapi.seoul.go.kr/api/subway/{apiKey}/json/realtimeStationArrival/0/20/{stationName}`
- 도착 정보는 SharedPreferences에 30초 TTL로 캐시 (`cache_arrival_{stationName}`)
- 오프라인 시 마지막 캐시 데이터로 폴백

### 정적 데이터

`assets/json/`의 번들 JSON (stations, connections, lines, transfer_times, line_schedules)은 `LocalDataSource` / `TimetableDataSource`가 `rootBundle`로 로드하며 세션 내 메모리에 캐시된다.

### 열차 시간표 (하이브리드: 역별 시간표 + 배차간격 폴백)

`assets/json/line_schedules.json`에 22개 노선의 양방향 운행 스케줄을 컴팩트 JSON으로 보유한다:
- 노선별 상행(내선)/하행(외선) 첫차·막차 시간
- 시간대별 배차간격 (첨두 06:30-09:00/16:30-19:30, 비첨두, 심야)
- 하행 전용 배차간격이 상행과 다를 경우 `pD` 키로 별도 저장
- 역별 정확한 출발시각 목록이 있으면 `t` 키로 저장 (배차간격 대신 사용)

**컴팩트 JSON 스키마:**
```json
{
  "id": "1",
  "wd": {
    "f": ["05:20","05:18"],
    "l": ["00:48","00:42"],
    "p": [["05:00","06:00",5],["06:00","09:00",4]],
    "t": {
      "P01": [null, [330, 340, 350, 360]],
      "P05": [[335, 345, 355], [328, 338, 348]]
    }
  },
  "we": { ... }
}
```
- `id` = lineId, `wd` = 평일 (필수), `we` = 주말 (옵셔널, 없으면 `wd`와 동일)
- `f` = firstTrains [상행/내선, 하행/외선], `l` = lastTrains [상행/내선, 하행/외선]
- `p` = 공유 배차간격 [[시작,종료,배차분]], `pD` = 하행 전용 배차간격 (상이할 경우만)
- `t` = 역별 시간표 (옵셔널). `stationId → [상행출발분목록, 하행출발분목록]`
  - 각 목록은 자정 기준 분(minute) 단위 정렬된 정수 배열 (예: 330 = 05:30)
  - `null`은 해당 방향 출발 없음 (종착역 등)
  - `t`가 없는 역은 `p` 배차간격으로 폴백
- 상하행 첫차/막차가 동일하고 `pD`/`t` 없으면 하행 데이터는 상행으로 자동 폴백

**역별 시간표 지원 노선:**
- 김포골드라인 (P01~P09): 구간운행(short-turn)이 있어 역별 배차간격이 다름. 9개 역 전체 평일/주말 시간표 포함.
  - 양촌(P01): 비첨두 ~18분 (전구간 운행만), 김포공항 부근: 비첨두 ~6분 (구간운행 포함)
  - 데이터 출처: korailinfo.com 역별 시간표
- 경의중앙선 (K01~K56): 급행/완행 혼합 운행으로 역별 정차 패턴이 다름. 56개 역 전체 평일/주말 시간표 포함.
  - 경의중앙선(용문↔문산) + 경의선(서울↔문산) 열차를 역별로 통합
  - K54(서울역)는 K24(효창공원앞)에서 분기하는 지선, 경의선 열차만 정차
  - K55(임진강), K56(운천)은 K01(문산) 이북 연장 구간, 하루 2~4편 운행
  - 데이터 출처: 코레일 시간표 엑셀 (`assets/excel/center_line260228.xlsx`)

**방향 결정 로직** (`direction_resolver.dart`):
- `RouteSegment`의 역 ID 순서로 방향 판별
- 일반 노선: ID 증가 = 하행(index 1), ID 감소 = 상행(index 0)
- 2호선 순환: 첫 두 역 ID 비교 + 순환 경계(201↔243) 처리

**출발시각 계산 우선순위:**
1. 실시간 도착정보 API (가장 정확, 방향 필터 적용)
2. 역별 시간표 (이진탐색으로 다음 출발시각 반환, `t` 키 데이터)
3. 배차간격 기반 시간표 추정 (방향별, 역별 시간표 없는 노선)
4. 현재 시각 폴백 (운행 시간 외이거나 데이터 없음)

**핵심 함수:**
- `findNextDeparture()` — `lib/domain/usecases/find_next_departure.dart`: 역별 시간표(이진탐색) 또는 배차간격으로 다음 출발 시각 계산 (`isDown`, `stationId` 파라미터)
- `computeDepartureTime()` — `lib/features/route_search/utils/departure_time_calculator.dart`: 실시간 + 시간표 통합 계산 (방향 자동 결정, `stationId` 전달)
- `computeSegmentDepartures()` — 환승역에서도 방향별 시간표 기반 출발시각 계산 (`stationId` 전달)
- `isDownDirection()` — `lib/features/route_search/utils/direction_resolver.dart`: RouteSegment에서 하행/외선 여부 결정

**데이터소스:**
- `TimetableDataSource` (`lib/data/local/timetable_data_source.dart`): 컴팩트 JSON 파싱 (레거시 포맷 호환, `t` 키 역별 시간표 파싱)
- `timetableProviders` (`lib/features/route_search/presentation/providers/timetable_providers.dart`): Riverpod 프로바이더

**시간표 재생성:**
```bash
dart run tool/extract_schedules.dart
# → assets/json/line_schedules.json (양방향 컴팩트 포맷)

# 김포골드라인 역별 시간표 변환 (수동 데이터 갱신 시)
dart run tool/build_gimpo_json.dart
# → line_schedules.json의 김포골드 항목에 't' 키 갱신

# 경의중앙선 역별 시간표는 Python으로 엑셀에서 추출
# assets/excel/center_line260228.xlsx → line_schedules.json의 경의중앙 항목에 't' 키 갱신
```

## 코드 생성

모든 `@freezed` 모델과 `@riverpod` 프로바이더는 변경 후 `build_runner` 실행이 필요하다. 생성 파일: `*.freezed.dart`, `*.g.dart`. 항상 `--delete-conflicting-outputs` 옵션과 함께 실행할 것.

## 컨벤션

- UI 문자열, 주석, 에러 메시지는 한국어
- 모든 데이터 모델은 불변 (`@freezed`)
- 스크린은 `*Screen`, 재사용 위젯은 설명적 이름
- 프라이빗 위젯 헬퍼는 `_` 접두사 (예: `_RouteSummary`)
- 테스트 모킹은 `mocktail` 사용

## 미사용 의존성

`hive_flutter`는 pubspec.yaml에 등록되어 있으나 현재 코드에서 사용되지 않음.
