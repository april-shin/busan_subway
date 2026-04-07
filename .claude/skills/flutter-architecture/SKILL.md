---
name: flutter-architecture
description: "서울 지하철 앱의 Flutter 아키텍처 설계, Riverpod 프로바이더 구현, Clean Architecture 계층 구조, go_router 라우팅, Freezed 데이터 모델 작업을 수행. 새 기능 추가, 프로바이더 생성, 라우팅 변경, 아키텍처 리팩토링, 상태관리 최적화 요청 시 이 스킬을 사용. 기존 아키텍처 수정, 계층 구조 변경, 프로바이더 최적화, 리빌드 최소화 작업에도 적용."
---

# Flutter Architecture

서울 지하철 앱의 Clean Architecture + Riverpod 기반 아키텍처 가이드.

## 계층 구조

```
UI (features/) → 프로바이더 (Riverpod) → 유스케이스 (domain/) → 리포지토리 (data/)
                                                                    ↓
                                                            데이터소스 (로컬/원격)
```

### 규칙
- domain/은 순수 Dart. Flutter/패키지 임포트 금지
- data/는 domain/의 인터페이스를 구현
- features/는 Riverpod을 통해서만 data/에 접근
- graph/는 독립 모듈. domain/ 엔티티만 참조

## Riverpod 패턴

### 코드 생성 프로바이더 (@riverpod)
```dart
@riverpod
Future<List<Station>> allStations(Ref ref) async {
  final repo = ref.watch(stationRepositoryProvider);
  return repo.getAllStations();
}
```

### 수동 프로바이더 (StateNotifier)
```dart
// 복잡한 상태 관리가 필요한 경우에만 수동 작성
class SelectedStationsNotifier extends StateNotifier<SelectedStations> {
  SelectedStationsNotifier() : super(const SelectedStations());

  void setDeparture(Station station) {
    state = state.copyWith(departure: station);  // 항상 새 객체
  }
}
```

### 리빌드 최적화
1. `Consumer` 위젯으로 watch 범위 좁히기
2. `ref.listen`으로 사이드 이펙트 분리
3. `initState`에서 Future 1회 생성 (FutureBuilder 리빌드 방지)
4. `const` 위젯 적극 활용

## 데이터 모델

모든 모델은 `@freezed`:
```dart
@freezed
class Station with _$Station {
  const factory Station({
    required String id,
    required String name,
    required String lineId,
    required double svgX,
    required double svgY,
    // ...
  }) = _Station;

  factory Station.fromJson(Map<String, dynamic> json) => _$StationFromJson(json);
}
```

변경 후 반드시: `dart run build_runner build --delete-conflicting-outputs`

## 새 기능 추가 절차

1. domain/entities/에 Freezed 모델 정의
2. domain/repositories/에 인터페이스 정의
3. domain/usecases/에 비즈니스 로직 구현
4. data/에 리포지토리 구현체 + 데이터소스
5. features/{기능명}/에 UI + 프로바이더
6. `build_runner` 실행
7. `flutter analyze` 검증
