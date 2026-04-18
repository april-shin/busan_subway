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

22개 노선 (1~9호선, 신분당, 경의중앙, 경춘, 공항철도 등). 상세: `.claude/docs/lines-reference.md`

### 상태 관리

Riverpod 2.x + 코드 생성 (`@riverpod` 어노테이션). 주요 프로바이더:

- `allStationsProvider` — 번들 JSON에서 전체 역 목록 로드
- `selectedStationsProvider` — 출발/도착역 선택용 `StateNotifier<SelectedStations>` (수동 작성, 비생성)
- `tappedStationProvider` — 지도 탭 상호작용용 `StateProvider<Station?>`
- `arrivalInfoProvider(stationName)` — 실시간 도착 정보 family 프로바이더
- `activeRouteFilterProvider` — 활성 경로의 첫 세그먼트 노선+방향 필터 (`StateProvider<ActiveRouteFilter?>`)
- `liveTrainsProvider` — 실시간 열차 위치 데이터 (15초 자동 새로고침, `activeRouteFilter`로 방향 필터링)

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
- 줌/팬은 JS에서 CSS `transform: matrix(...)` 기반으로 처리 (0.5x~5.0x)
- 초기 뷰: 중심(1040, 618), 스케일 1.0

### SVG 데이터 파이프라인

원본 SVG → JSON → HTML 3단계 (빌드 명령어 섹션 참조). 상세: `.claude/docs/svg-pipeline.md`

**중요:** SVG 수정 후 반드시 3단계 파이프라인을 순서대로 재실행.

### 네트워크 및 캐싱

- 서울 열린데이터 API: `http://swopenapi.seoul.go.kr/api/subway/{apiKey}/json/realtimeStationArrival/0/20/{stationName}`
- 도착 정보는 SharedPreferences에 30초 TTL로 캐시 (`cache_arrival_{stationName}`)
- 오프라인 시 마지막 캐시 데이터로 폴백

### 정적 데이터

`assets/json/`의 번들 JSON (stations, connections, lines, transfer_times, line_schedules)은 `LocalDataSource` / `TimetableDataSource`가 `rootBundle`로 로드하며 세션 내 메모리에 캐시된다.

### 열차 시간표

역별 시간표 + 배차간격 폴백 하이브리드. 상세: `.claude/docs/timetable.md`

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

## 하네스: 서울 지하철 앱 개발

**목표:** 7인 전문가 에이전트 팀으로 앱 개발 작업(기능 구현, 버그 수정, UI/지도 개선, 알고리즘 최적화)을 체계적으로 수행

**에이전트 팀:**
| 에이전트 | 역할 |
|---------|------|
| flutter-architect | Flutter 아키텍처/상태관리/라우팅 전문가 |
| map-math-engineer | 지도 UI/수학/좌표변환/애니메이션 전문가 |
| graph-algorithm-engineer | 그래프 알고리즘/최단경로/방향결정 전문가 |
| realtime-data-engineer | 실시간 API/캐싱/열차추적 전문가 |
| flutter-qa-engineer | 테스트/경계면검증/커버리지 전문가 |
| subway-code-reviewer | 코드 품질/아키텍처준수/보안/성능 리뷰 전문가 |
| subway-requirements-reviewer | 요구사항 충족도/누락/오버엔지니어링 검증 전문가 |

**스킬:**
| 스킬 | 용도 | 사용 에이전트 |
|------|------|-------------|
| flutter-architecture | Clean Architecture + Riverpod 패턴 가이드 | flutter-architect |
| subway-map-math | SVG 좌표/줌팬/보간/애니메이션 수학 가이드 | map-math-engineer |
| graph-pathfinding | Dijkstra/BFS/방향결정 알고리즘 가이드 | graph-algorithm-engineer |
| realtime-tracking | API 통합/캐싱/열차추적 가이드 | realtime-data-engineer |
| subway-testing | 테스트 전략/경계면 검증 가이드 | flutter-qa-engineer |
| subway-code-review | 프로젝트 특화 코드 리뷰 체크리스트 | subway-code-reviewer |
| subway-requirements-review | 요구사항 충족도 검증 프레임워크 | subway-requirements-reviewer |
| subway-app-orchestrator | 전체 팀 조율 오케스트레이터 | 메인 세션 |

**실행 규칙:**
- 앱 개발 작업(기능 구현, 버그 수정, UI 개선, 알고리즘 최적화 등) 요청 시 `subway-app-orchestrator` 스킬을 통해 에이전트 팀으로 처리하라
- 단순 질문, 설정 변경, 1~2줄 수정은 에이전트 팀 없이 직접 처리해도 무방
- **모든 에이전트는 Opus 4.7 (1M context) 사용** — `.claude/agents/*.md`의 YAML frontmatter에 `model: opus` 명시
- 코드 변경 후 반드시 subway-code-reviewer + subway-requirements-reviewer를 병렬 실행
- 중간 산출물: `_workspace/` 디렉토리

**1M 컨텍스트 활용 원칙 (Opus 4.7):**
- **모듈 단위 일괄 처리** — 에이전트 1명이 한 feature 폴더 전체(파일·테스트·참조 문서)를 한 번에 읽고 수정. 작게 쪼개 라운드트립을 늘리지 말 것.
- **참조 문서 동시 로딩** — SKILL.md + references/ + 관련 코드를 한 컨텍스트에 투입해 사전 탐색 부담 감소.
- **리뷰 단계 풀 컨텍스트** — 코드/요구사항 리뷰는 변경 파일 + 인근 파일 + 테스트 + 원래 요청 전문을 한 번에 받아 맥락 손실 없이 판단.
- **1M을 꼭 채우지 말 것** — 작업 범위에 비례한 컨텍스트만 투입 (비용·캐시 효율).
- 상세 전략: `.claude/skills/subway-app-orchestrator/SKILL.md`의 "모델 및 컨텍스트 전략" 섹션.

**디렉토리 구조:**
```
.claude/
├── agents/
│   ├── flutter-architect.md
│   ├── map-math-engineer.md
│   ├── graph-algorithm-engineer.md
│   ├── realtime-data-engineer.md
│   ├── flutter-qa-engineer.md
│   ├── subway-code-reviewer.md
│   └── subway-requirements-reviewer.md
├── skills/
│   ├── flutter-architecture/
│   │   └── SKILL.md
│   ├── subway-map-math/
│   │   └── SKILL.md
│   ├── graph-pathfinding/
│   │   └── SKILL.md
│   ├── realtime-tracking/
│   │   └── SKILL.md
│   ├── subway-testing/
│   │   └── SKILL.md
│   ├── subway-code-review/
│   │   └── SKILL.md
│   ├── subway-requirements-review/
│   │   └── SKILL.md
│   └── subway-app-orchestrator/
│       └── SKILL.md
└── docs/
    ├── lines-reference.md
    ├── svg-pipeline.md
    └── timetable.md
```

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-04-07 | 초기 구성: 7인 전문가 팀 하네스 | 전체 | 앱 개발 전문가 팀 구성 요청 |
| 2026-04-17 | Opus 4.7 (1M context) 대응: 전 에이전트 YAML frontmatter 추가(`model: opus`, name, description), 오케스트레이터에 "모델 및 컨텍스트 전략" 섹션 추가, CLAUDE.md에 1M 컨텍스트 활용 원칙 명시 | agents/*, skills/subway-app-orchestrator/SKILL.md, CLAUDE.md | Opus 4.7에 적합하게 하네스 설정 수정 요청 |
