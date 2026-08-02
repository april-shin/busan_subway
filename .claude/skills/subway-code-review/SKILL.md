---
name: subway-code-review
description: "서울 지하철 앱 코드의 품질, 아키텍처 준수, 불변성, 보안, 성능을 리뷰. 코드 작성/수정 직후 자동으로 사용. '코드 리뷰', '리뷰해줘', 코드 수정 완료 후 검증 요청 시 이 스킬을 사용. CLAUDE.md의 리뷰 루프에서 코드 리뷰 단계에 해당."
---

# Subway Code Review

서울 지하철 앱 특화 코드 리뷰 가이드. CLAUDE.md의 작업 워크플로우에서 리뷰 단계에 해당.

## 리뷰 체크리스트

### ⛔ 실시간 열차 애니메이션 4원칙 (최우선, 해당 파일 변경 시)
- [ ] `tool/build_map_html.dart` / `live_train_provider.dart` 변경 시 CLAUDE.md "실시간 열차 애니메이션 4원칙" 위반 여부 확인: 위치 단조 전진(뒤로 가는 target 폐기 — `minDistToEnd`; 숫자 clamp 재도입 금지), 매 frame 역산 위치(전방 보간 금지), 현재역 기준 3-way 클램프, refresh 시 catch-up 보간(순간이동 금지)
- [ ] 위반은 무조건 CRITICAL. 원칙 자체 변경은 사용자 승인 없이는 반려

### 아키텍처 준수
- [ ] domain/에 Flutter 임포트 없음
- [ ] graph/에 Flutter 의존성 없음
- [ ] 리포지토리 인터페이스(domain)와 구현체(data) 분리
- [ ] 프로바이더가 적절한 계층에 위치
- [ ] 새 기능이 features/{기능명}/ 구조를 따름

### 불변성
- [ ] 데이터 모델이 `@freezed` 사용
- [ ] `copyWith`로 상태 업데이트 (직접 필드 변경 없음)
- [ ] List/Map 반환 시 unmodifiable 래퍼 사용
- [ ] StateNotifier에서 항상 새 상태 객체 생성

### Riverpod 패턴
- [ ] `Consumer` 위젯으로 watch 범위 최소화
- [ ] `ref.listen` vs `ref.watch` 적절히 사용
- [ ] 불필요한 프로바이더 의존성 없음
- [ ] Family 프로바이더의 파라미터가 적절함

### 성능
- [ ] FutureBuilder에서 Future 캐싱 (initState에서 생성)
- [ ] const 위젯 활용
- [ ] runJavaScript 호출 최소화 (배치 처리)
- [ ] 불필요한 setState 없음
- [ ] Timer 정리 (dispose에서 cancel)

### 보안
- [ ] API 키 하드코딩 없음
- [ ] 에러 메시지에 민감 정보 없음
- [ ] JS 인젝션 방지 (JSON.stringify 사용)

### 코드 스타일
- [ ] 함수 < 50줄, 파일 < 800줄
- [ ] 의미있는 이름 (한국어 주석 허용)
- [ ] 깊은 중첩 없음 (> 4레벨)
- [ ] print/debugPrint 문 없음

## 출력 형식

```markdown
## 코드 리뷰 결과

### CRITICAL
- [파일:줄] 설명
  ```dart
  // 수정 전
  // 수정 후
  ```

### HIGH
- [파일:줄] 설명 + 수정 제안

### MEDIUM
- [파일:줄] 설명

### LOW
- [파일:줄] 설명

### 칭찬
- [파일:줄] 잘한 점
```

## 프로젝트 특수 규칙

1. **노드 ID 형식**: `"{stationId}_{lineId}"` — 이 형식을 벗어나는 코드는 CRITICAL
2. **환승 시간 키**: `"{역이름}_{lineId1}_{lineId2}"` — 형식 불일치 시 HIGH
3. **build_runner 필요 여부**: `@freezed`/`@riverpod` 변경 시 `build_runner` 실행 필요 알림
4. **SVG 파이프라인**: SVG 관련 변경 시 3단계 파이프라인 실행 필요 알림
5. **--release 빌드**: 실 디바이스 빌드 코드에 `--release` 누락 시 HIGH
