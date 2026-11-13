---
name: realtime-tracking
description: "부산 지하철 앱의 실시간 열차 추적, 서울 열린데이터 API 통합, 캐싱 전략, 도착시간 추정, 시간표 데이터 관리를 수행. API 연동 수정, 캐싱 로직 변경, 열차 위치 계산, 도착정보 개선, 오프라인 폴백, 시간표/배차간격 관련 요청 시 이 스킬을 사용. live_train_provider.dart, arrival 관련 파일, cache_manager.dart, timetable 관련 작업에 모두 적용."
---

# Realtime Tracking

부산 지하철 앱의 실시간 열차 추적 및 API 통합 가이드.

## ⛔ 실시간 열차 애니메이션 4원칙 중 원칙 1 — 최상위 정책

`live_train_provider.dart`가 넘기는 `receivedAtEpochMs`는 CLAUDE.md "실시간 열차 애니메이션 4원칙"의 **원칙 1(열차는 절대 뒤로 가지 않는다)**을 구성하는 계약이다. `realRemaining = arrivalSeconds − (now − recptnDt)` 값 자체는 API 재조회로 늘어나도 **보정하지 않는다**(옛 단조 감소 clamp 는 제거됨). 대신 이 쌍이 정확해야 JS(`tool/build_map_html.dart`)가 위치를 바르게 역산하고, 단조 전진 가드(`minDistToEnd`)가 올바른 지점에서 작동한다. 이 필드를 수정하기 전 CLAUDE.md 해당 섹션을 먼저 읽고, 원칙 자체를 바꿔야 한다면 사용자 승인을 먼저 구한다.

## API 스펙

### 엔드포인트
```
http://swopenapi.seoul.go.kr/api/subway/{apiKey}/json/realtimeStationArrival/0/20/{stationName}
```

### 인증
- API 키: `.env` 파일의 `BUSAN_SUBWAY_API_KEY`
- `flutter_dotenv`로 런타임 로드
- 플레이스홀더 값이면 예외 발생

### 응답 구조 (ArrivalInfo)
```dart
ArrivalInfo(
  subwayId: String,         // 노선 ID
  stationName: String,      // 역 이름
  direction: String,        // "상행" | "하행" | "내선" | "외선"
  currentStationName: String,  // 현재 열차 위치 역
  trainNo: String,          // 열차 번호
  arrivalCode: int,         // 1=도착, 2=출발, 0=진입
  positionStatus: String,   // 위치 상태 텍스트
  arrivalSeconds: int,      // 도착 예상 초
  receivedAt: DateTime,     // 수신 시각
)
```

## 캐싱 전략

### SharedPreferences 캐시
- 키: `cache_arrival_{stationName}`
- TTL: 30초
- 온라인: TTL 내 캐시 반환, 만료 시 API 호출
- 오프라인: 만료된 캐시도 폴백으로 사용

### 메모리 캐시 (정적 데이터)
- `LocalDataSource`: stations, connections, lines, transfer_times
- 세션 내 1회 로드, `rootBundle`에서 읽기
- `clearCache()`로 명시적 초기화

## 열차 위치 추적 (LiveTrain)

### 데이터 흐름
```
arrivalInfoProvider(departureStationName)  [API 호출]
  ↓
방향 필터링 (activeRouteFilter: lineId + isDown)
  ↓
각 ArrivalInfo에 대해:
  findPathOnLine(currentStation → departure, lineId)  [BFS]
  calculateInitialProgress(arrivalCode)               [위치 보간]
  estimateArrivalSeconds(API값 또는 구간 합산)
  ↓
_applyOverlapOffset(동일 위치 열차 Y오프셋)
  ↓
List<LiveTrain> 생성
```

### LiveTrain 구조
```dart
LiveTrain(
  trainNo, lineId, direction, destination, message,
  arrivalSeconds, currentStation,
  arrivalCode, positionStatus,
  fromSvgX, fromSvgY,          // 시작 위치 (현재역 SVG 좌표)
  pathToTarget: [(x, y), ...],  // 출발역까지 경유 좌표
  segmentDurations: [int, ...], // 각 구간 소요시간(초)
  initialProgress: 0.0~1.0,    // 첫 세그먼트 내 위치
)
```

### 자동 새로고침
- 15초 주기 (Timer + Riverpod invalidateSelf)
- 네트워크 에러 시 마지막 성공 결과 유지 (`_lastSuccessfulTrainsProvider`)

## 도착시간 추정

### 우선순위
1. **실시간 API**: arrivalSeconds 직접 사용
2. **시간표**: 해당 노선/방향의 다음 출발시간 조회
3. **추정**: 현재시간 기반 계산

### 구간별 출발시간 계산
```dart
computeSegmentDepartures(route, allArrivals, schedules)
// 각 세그먼트:
//   1. 실시간 도착정보에서 lineId + 방향 매칭
//   2. 없으면 시간표에서 다음 출발시간
//   3. 없으면 이전 세그먼트 도착시간 + 환승시간
```

## 에러 처리 전략

| 상황 | 처리 |
|------|------|
| API 타임아웃 | 캐시 폴백 |
| API 응답 파싱 실패 | 에러 로깅 + 빈 리스트 |
| 네트워크 미연결 | 마지막 캐시 사용 |
| API 키 누락 | 앱 시작 시 예외 |
| 역 이름 불일치 | 빈 결과 반환 |

## 핵심 파일

| 파일 | 역할 |
|------|------|
| `lib/features/subway_map/presentation/providers/live_train_provider.dart` | 열차 위치 프로바이더 (`receivedAtEpochMs`/`trainNo` 계약 — 원칙 1) |
| `lib/data/remote/busan_api_data_source.dart` | API 클라이언트 |
| `lib/data/repositories/arrival_repository_impl.dart` | API + 캐시 |
| `lib/data/local/cache_manager.dart` | 캐시 관리 |
| `lib/data/local/timetable_data_source.dart` | 시간표 데이터 |
| `lib/core/utils/estimate_arrival_seconds.dart` | 도착시간 추정 |
| `lib/core/utils/parse_arrival_message.dart` | 메시지 파싱 |
| `lib/core/utils/enrich_arrival_info.dart` | 데이터 보강 |
| `lib/features/route_search/utils/departure_time_calculator.dart` | 출발시간 계산 |
