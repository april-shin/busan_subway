# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

# 역/노선 JSON 에셋 재생성
dart run tool/generate_station_data.dart
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

**데이터 흐름:** UI (ConsumerWidget) → Riverpod 프로바이더 → 리포지토리 구현체 → 데이터소스 (번들 JSON 또는 서울 API via Dio)

의존성 주입은 Riverpod 프로바이더 내부에서 수동으로 수행 (서비스 로케이터 미사용).

### 핵심 도메인 개념

- **역(Station)** 은 캔버스 렌더링용 `svgX`/`svgY` 좌표를 가짐 (위경도 → 2400x1500 캔버스로 사전 변환)
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

### 라우팅 (go_router)

| 경로 | 스크린 | 비고 |
|---|---|---|
| `/` | HomeScreen | 지도 + 검색바 |
| `/pick-station/:purpose` | StationPickerScreen | purpose = "departure" 또는 "arrival" |
| `/route-result` | RouteResultScreen | `RouteResult`를 `state.extra`로 전달 |
| `/station/:stationId` | StationDetailScreen | |
| `/arrivals/:stationName` | ArrivalInfoScreen | 15초마다 자동 새로고침 |

### 지도 렌더링

지하철 지도는 SVG가 아닌 `CustomPainter`로 렌더링된다. `SubwayMapPainter`가 연결선을, `StationMarker`가 역 원형을 그리며, 전체가 `InteractiveViewer`(줌 0.2x~5x)로 감싸져 있다.

### 네트워크 및 캐싱

- 서울 열린데이터 API: `http://swopenapi.seoul.go.kr/api/subway/{apiKey}/json/realtimeStationArrival/0/20/{stationName}`
- 도착 정보는 SharedPreferences에 30초 TTL로 캐시 (`cache_arrival_{stationName}`)
- 오프라인 시 마지막 캐시 데이터로 폴백

### 정적 데이터

`assets/json/`의 번들 JSON (stations, connections, lines, transfer_times)은 `LocalDataSource`가 `rootBundle`로 로드하며 세션 내 메모리에 캐시된다.

## 코드 생성

모든 `@freezed` 모델과 `@riverpod` 프로바이더는 변경 후 `build_runner` 실행이 필요하다. 생성 파일: `*.freezed.dart`, `*.g.dart`. 항상 `--delete-conflicting-outputs` 옵션과 함께 실행할 것.

## 컨벤션

- UI 문자열, 주석, 에러 메시지는 한국어
- 모든 데이터 모델은 불변 (`@freezed`)
- 스크린은 `*Screen`, 재사용 위젯은 설명적 이름
- 프라이빗 위젯 헬퍼는 `_` 접두사 (예: `_RouteSummary`)
- 테스트 모킹은 `mocktail` 사용

## 미사용 의존성

`hive_flutter`와 `flutter_svg`는 pubspec.yaml에 등록되어 있으나 현재 코드에서 사용되지 않음.
