---
name: subway-testing
description: "서울 지하철 앱의 테스트 작성, 커버리지 관리, 경계면 검증을 수행. 단위 테스트, 통합 테스트, 위젯 테스트 작성, 테스트 실패 분석, 모킹 설정, 커버리지 확인 요청 시 이 스킬을 사용. 새 기능 테스트, 버그 수정 검증, 리팩토링 안전성 확인, 알고리즘 정확성 검증에도 적용."
---

# Subway Testing

서울 지하철 앱의 테스트 전략 및 작성 가이드.

## 테스트 구조

```
test/
  graph/          # Dijkstra, BFS, 그래프 구조
  domain/         # 유스케이스, 엔티티
  data/           # 리포지토리, 데이터소스, DTO
  core/           # 유틸리티 함수
  features/       # 위젯, 프로바이더
  providers/      # 상태 관리
  integration/    # 통합 테스트
  fixtures/       # 테스트 데이터
  tool/           # 도구 스크립트
```

## 모킹 (mocktail)

```dart
import 'package:mocktail/mocktail.dart';

class MockStationRepository extends Mock implements StationRepository {}

// 사용
final mockRepo = MockStationRepository();
when(() => mockRepo.getAllStations()).thenAnswer((_) async => testStations);
```

### rootBundle 모킹
```dart
TestWidgetsFlutterBinding.ensureInitialized();
// 테스트용 JSON 에셋은 test/fixtures/에 배치
```

## 경계면 교차 검증

핵심: "존재 확인"이 아니라 **양쪽의 shape을 동시에 읽고 비교**.

| 경계면 | 검증 방법 |
|--------|----------|
| API JSON → DTO | 실제 API 응답 샘플로 파싱 테스트 |
| DTO → 도메인 엔티티 | 필드 매핑 1:1 검증 |
| 프로바이더 → 위젯 | ProviderScope 테스트로 상태 변경 → UI 반영 확인 |
| Flutter → JS | runJavaScript 호출 파라미터 JSON 직렬화 검증 |
| 그래프 노드 ID | `"{stationId}_{lineId}"` 형식 정규식 검증 |
| 환승 시간 키 | `"{역이름}_{lineId1}_{lineId2}"` 형식 + 역방향 |

## 알고리즘 테스트

### Dijkstra
```dart
test('2호선 강남→역삼 직통 경로', () {
  final result = finder.findShortestPath('216_2', '217_2');
  expect(result.nodeIds, ['216_2', '217_2']);
  expect(result.totalTimeSeconds, greaterThan(0));
});

test('1호선→2호선 환승 경로', () {
  final result = finder.findShortestPathBetweenStations('150', '216');
  expect(result.first.edges.any((e) => e.isTransfer), isTrue);
});
```

### 방향 결정
```dart
test('2호선 순환선 래핑', () {
  // 201→243: |step|=42 > 21 → 방향 반전
  expect(isDownDirection(segment201to243), isFalse);
});
```

## 테스트 커맨드

```bash
flutter test                                    # 전체
flutter test test/graph/                        # 그래프만
flutter test test/graph/shortest_path_test.dart # 단일 파일
flutter test --coverage                         # 커버리지
```

## 테스트 작성 원칙

1. **Arrange-Act-Assert** 패턴 사용
2. 테스트 이름은 한국어로, 시나리오를 명확히 기술
3. 하나의 테스트는 하나의 동작만 검증
4. `group()`으로 관련 테스트 묶기
5. 매직 넘버 대신 명명된 상수 사용
6. 비동기 테스트는 `async`/`await` 사용, `pumpAndSettle()` 주의

## 커버리지 목표

- 전체: 80%+
- graph/: 90%+ (핵심 알고리즘)
- domain/usecases/: 85%+
- core/utils/: 85%+
- data/: 80%+
- features/: 70%+ (위젯 테스트 한계 고려)
