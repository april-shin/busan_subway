# Seoul Subway

서울 및 수도권 지하철 노선도 기반 경로 검색 및 실시간 도착 정보 앱

## 주요 기능

- 🗺️ **인터랙티브 노선도**: WebView 기반 SVG 지하철 노선도 (줌/팬 지원)
- 🔍 **최단 경로 검색**: Dijkstra 알고리즘 기반 최적 경로 탐색 (환승 시간 포함)
- 🚇 **실시간 도착 정보**: 서울 열린데이터 API를 통한 열차 도착 예정 시각
- 📍 **역 상세 정보**: 각 역의 위치, 노선, 주변 환승역 정보
- 🎨 **노선별 색상 구분**: 23개 노선의 고유 색상 시각화

### 지원 노선 (23개)

1~9호선, 신분당선, 경의중앙선, 경춘선, 공항철도, 수인분당선, 신림선, 에버라인, 인천1·2호선, 김포골드라인, 서해선, 의정부경전철, 우이신설경전철, GTX-A

## 시작하기

### 필수 요구사항

- Flutter SDK 3.11.0 이상
- Dart 3.11.0 이상
- 서울 열린데이터광장 API 키 ([발급 받기](https://data.seoul.go.kr))

### 설치

1. **저장소 클론**
   ```bash
   git clone <repository-url>
   cd seoul_subway
   ```

2. **환경 변수 설정**

   `.env.example`을 복사하여 `.env` 파일 생성:
   ```bash
   cp .env.example .env
   ```

   `.env` 파일을 열어 API 키 입력:
   ```
   SEOUL_API_KEY=your_api_key_here
   ```

3. **의존성 설치**
   ```bash
   flutter pub get
   ```

4. **코드 생성** (Freezed, Riverpod, JSON Serialization)
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

### 실행

```bash
# 시뮬레이터 (Debug 모드)
flutter run

# 실 디바이스 (Release 모드 필수)
flutter run --release
```

> ⚠️ **중요**: iOS 실 디바이스에서는 반드시 `--release` 모드로 실행해야 합니다. Debug 모드는 Dart VM 연결 문제로 백그라운드 복귀 시 크래시가 발생합니다.

### 개발 명령어

```bash
# 워치 모드 (코드 변경 감지 자동 재생성)
dart run build_runner watch --delete-conflicting-outputs

# 테스트 실행
flutter test                                      # 전체
flutter test test/graph/shortest_path_test.dart   # 특정 파일

# 정적 분석
flutter analyze
```

## 아키텍처

### Clean Architecture + Feature-First

```
lib/
├── core/              # 공통 인프라
│   ├── constants/     # API 엔드포인트, 노선 색상, ID 매핑
│   ├── error/         # 에러 타입 정의
│   ├── network/       # Dio HTTP 클라이언트, 연결 상태 체크
│   └── theme/         # 앱 테마 (다크/라이트 모드)
├── domain/            # 비즈니스 로직 (순수 Dart)
│   ├── entities/      # 불변 데이터 모델 (Freezed)
│   ├── repositories/  # 리포지토리 인터페이스
│   └── usecases/      # 유스케이스 (경로 검색 등)
├── data/              # 데이터 레이어
│   ├── local/         # 로컬 JSON 데이터소스
│   ├── remote/        # 서울 API 데이터소스, DTO
│   └── repositories/  # 리포지토리 구현체
├── features/          # 기능별 UI 모듈
│   ├── home/          # 홈 화면 (노선도 + 검색바)
│   ├── route_search/  # 경로 검색 결과
│   ├── station_detail/# 역 상세 정보
│   ├── arrival_info/  # 실시간 도착 정보
│   └── subway_map/    # WebView 기반 노선도
└── graph/             # 최단경로 알고리즘 (Dijkstra)
    ├── models/        # 그래프 자료구조
    ├── graph_builder.dart
    └── shortest_path.dart
```

### 기술 스택

- **상태 관리**: Riverpod 2.x (코드 생성)
- **라우팅**: go_router
- **불변 모델**: Freezed + json_serializable
- **네트워킹**: Dio
- **로컬 캐시**: SharedPreferences (30초 TTL)
- **지도 렌더링**: webview_flutter (SVG 기반)
- **테스트**: mocktail

### 데이터 흐름

```
UI (ConsumerWidget)
  ↓
Riverpod Provider
  ↓
Repository Interface (domain)
  ↓
Repository Implementation (data)
  ↓
DataSource (Local JSON / Remote API)
```

## 데이터 구조

### 정적 데이터 (로컬 JSON 번들)

프로젝트는 4개의 정적 데이터 파일을 포함합니다:

#### 1. `assets/json/stations.json`
- **내용**: 전체 역 목록 (653개 역)
- **포함 정보**: 역 ID, 이름, 노선 ID, 지리 좌표(위도/경도), SVG 렌더링 좌표
- **생성**: `tool/generate_station_data.dart`

#### 2. `assets/json/connections.json`
- **내용**: 역 간 연결 관계 및 이동 소요시간
- **소요시간 계산**:
  ```
  1. Haversine 공식으로 역 간 거리 계산 (km)
  2. 평균 속도 35km/h 가정: 시간(초) = 거리 / 35 * 3600
  3. 60~300초 범위 제한
  4. 30초 단위 반올림
  ```
  > ⚠️ **주의**: 실제 운행 데이터가 아닌 **지리적 거리 기반 추정값**입니다.

#### 3. `assets/json/lines.json`
- **내용**: 노선별 역 순서 및 메타데이터
- **특수 처리**:
  - 2호선: 순환선 (시청 ↔ 충정로 연결)
  - 경의중앙선 K54(서울역): K24(효창공원앞)에서 분기하는 지선
  - 경춘선 C01~C05 / 경의중앙선 K32~K36: 물리적 동일 선로, 별개 노드 + 환승 엣지 처리

#### 4. `assets/json/transfer_times.json`
- **내용**: 환승 소요시간 (키 형식: `역명_노선1_노선2`)
- **환승시간 규칙**:
  - 기본: **180초 (3분)**
  - 주요 환승역 (수동 지정):
    - 강남(2↔신분당): 300초
    - 왕십리(다중 환승): 240~300초
    - 서울역(다중 환승): 240~360초

#### 데이터 생성 파이프라인

```bash
# 1단계: SVG에서 역 좌표 추출
dart run tool/extract_svg_stations.dart
# → assets/json/svg_station_coords.json

# 2단계: 역/노선/연결 JSON 생성
dart run tool/generate_station_data.dart
# → stations.json, connections.json, lines.json, transfer_times.json

# 3단계: WebView용 HTML 생성
dart run tool/build_map_html.dart
# → assets/html/map.html (SVG 인라인 삽입)
```

**좌표 출처**:
- SVG 좌표: 원본 `seoul_metro_map.svg`에서 자동 추출
- 지리 좌표: `generate_station_data.dart`에 하드코딩 (공공데이터/지도 API에서 수집 추정)

### 실시간 데이터 (서울 열린데이터 API)

#### 엔드포인트
```
GET http://swopenapi.seoul.go.kr/api/subway/{apiKey}/json/realtimeStationArrival/0/20/{stationName}
```

#### 제공 정보
- `subwayId`: 노선 ID (1~9, SB 등)
- `statnNm`: 역 이름
- `updnLine`: 상행/하행 방향
- `bstatnNm`: 종착역
- `arvlMsg2`: 도착 메시지 ("2분 후 도착", "전역 도착")
- `barvlDt`: 도착 예정 시간(초)
- `btrainSttus`: 열차 유형 (일반/급행/특급)
- `recptnDt`: 정보 수신 시각

#### 캐싱 전략
- SharedPreferences에 30초 TTL 캐시
- 오프라인 시 마지막 캐시 데이터 표시

> ⚠️ **제한사항**: 열차 시간표는 제공하지 않으며, 실시간 도착 정보만 지원합니다.

## 핵심 개념

### 그래프 모델링

- **노드 ID 형식**: `{stationId}_{lineId}` (예: `216_2` = 2호선 강남역)
- **환승역**: 동일 역명의 여러 노드를 환승 엣지로 연결
- **환승 시간**: `transfer_times.json`에서 조회 (기본 3분)
- **알고리즘**: Dijkstra 최단경로 (우선순위 큐 기반)

### 지도 렌더링

- **방식**: WebView에서 SVG를 HTML로 렌더링
- **인터랙션**:
  - 줌/팬: CSS `transform: matrix(...)` (0.1x~5.0x)
  - 역 탭: JavaScriptChannel을 통해 Flutter로 전달
  - 경로 하이라이트: SVG `<g>` 오버레이 동적 추가
  - 마커/툴팁: SVG `<circle>` + HTML `div` (position:absolute)
- **초기 뷰**: 2호선 순환선 중심 (1260, 1240), 스케일 0.25

### 라우팅

| 경로 | 화면 | 비고 |
|------|------|------|
| `/` | HomeScreen | 노선도 + 검색바 |
| `/pick-station/:purpose` | StationPickerScreen | purpose = departure/arrival |
| `/route-result` | RouteResultScreen | `RouteResult`를 `extra`로 전달 |
| `/station/:stationId` | StationDetailScreen | 역 정보 |
| `/arrivals/:stationName` | ArrivalInfoScreen | 15초 자동 새로고침 |

## 테스트

```bash
# 전체 테스트
flutter test

# 그래프 알고리즘 테스트
flutter test test/graph/

# 단위 테스트
flutter test test/domain/entities/
flutter test test/domain/usecases/
```

주요 테스트 커버리지:
- Dijkstra 최단경로 알고리즘
- 환승 시간 계산
- 경로 결과 엔티티 변환
- 리포지토리 mock 테스트

## 개발 참고사항

### 코드 생성 필수 파일
- `*.freezed.dart`: Freezed 모델
- `*.g.dart`: JSON 직렬화, Riverpod 프로바이더
- 변경 후 반드시 `build_runner` 실행

### 컨벤션
- UI 문자열/주석/에러 메시지: 한국어
- 모든 데이터 모델: 불변 (`@freezed`)
- 화면 위젯: `*Screen` 접미사
- 프라이빗 헬퍼 위젯: `_` 접두사
- 테스트: `mocktail` 사용

### SVG 수정 시 재생성 필수
원본 `seoul_metro_map.svg` 수정 후 **반드시** 파이프라인 순서대로 실행:
```bash
dart run tool/extract_svg_stations.dart
dart run tool/generate_station_data.dart
dart run tool/build_map_html.dart
```

## 라이선스

MIT License

## 기여

이슈 및 풀 리퀘스트를 환영합니다.
