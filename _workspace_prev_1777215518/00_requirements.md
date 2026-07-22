# 요구사항: 실시간 열차 위치 정확도 개선 — 남은시간 역산 방식

## 배경

현재 로직은 `arrivalSeconds` 를 전체 경로 `durationMs` 로 보고, 시간 가중 보간으로 위치를 결정한다. 이 방식은 정차 중 구간을 명확히 표현하지 못하고 segmentDurations 가 "주행+dwell 합산" 이라 정차 구간에서도 미세 이동이 발생하는 한계가 있다.

## 새 방식

매 frame 남은시간으로 위치를 뒤에서부터 역산. 주행 중이면 세그먼트 내부 보간, 정차 중이면 역 좌표에 고정.

## 검증 예시 (고정 테스트 필수)

- 경로 A-B-C (C가 조회역), 주행 A-B=60s, B-C=60s, 정차 30s
- 총 예상 소요시간 = 60 + 30 + 60 = 150s
- **t=120s** → A-B 정중앙 (progress 0.5, isDwelling=false)
- **t=80s** → B 정차 중 (isDwelling=true, 잔여 정차 20s)

## 확정된 정책

1. pathToTarget 시작점: `arvlMsg3` 의 currentStation (기존 방식)
2. 남은시간 > 총시간: pathToTarget 앞에 이전 역 prepend. 소진까지 무제한 확장 + 순환선 루프 방어 (방문 역 set + 안전 상한 30칸)
3. 정차 중 시각화: 해당 역 좌표에 고정 (별도 구분 표시 없음)
4. 정차시간: `dwellTimeSeconds` 상수 (전역 고정)
5. `segmentDurations` 의미: "주행시간만"으로 재정의
6. `assets/html/map.html` `startTrainAnimation`: 내용 전면 교체

## 알고리즘 (의사코드)

```
입력: pathToTarget [p[0], ..., p[n]]  (n+1점, n세그먼트)
      segmentTravelTimes [s[0], ..., s[n-1]]  (주행만)
      dwell (상수)
      remaining t

totalTime = sum(s) + (n-1) * dwell

t_rem = remaining
for i from (n-1) down to 0:
  if t_rem <= s[i]:
    progress = (s[i] - t_rem) / s[i]
    return (segIdx=i, progress, isDwelling=false)
  t_rem -= s[i]
  if i > 0:
    if t_rem <= dwell:
      return (segIdx=i, progress=0.0, isDwelling=true)
    t_rem -= dwell

# outOfPath — 경로 확장 필요
return (outOfPath=true, remaining=t_rem)
```

## 투입 에이전트

| 에이전트 | 작업 |
|---|---|
| graph-algorithm-engineer | `estimate_train_position.dart` 신규 + `line_direction.dart` 에 `findPreviousStationId` 추가 |
| map-math-engineer | `assets/html/map.html` `startTrainAnimation` 전면 재작성 (JS 역산 포팅) |
| realtime-data-engineer | `live_train_provider.dart` — segmentDurations 의미 정정, `dwellSeconds`/`receivedAtEpochMs` 전달, 경로 확장 루프 |
| flutter-qa-engineer | 단위 테스트 (검증 예시 고정, 경계값, outOfPath, findPreviousStationId) |
| subway-code-reviewer + subway-requirements-reviewer | 병렬 리뷰 |

## 실행 순서

- Phase 2a (병렬): graph-algorithm-engineer ‖ map-math-engineer
- Phase 2b: realtime-data-engineer (2a 산출물 이후)
- Phase 2c: flutter-qa-engineer
- Phase 3: code-reviewer ‖ requirements-reviewer
- Phase 4: 수정 루프
- Phase 5: flutter analyze + test

## 산출물 경로

`_workspace/10_estimate_position.md`, `11_live_train_rewrite.md`, `12_map_html_rewrite.md`, `13_tests.md`, `14_code_review.md`, `15_requirements_review.md`

## 제약

- 불변 패턴 유지 (모든 데이터 새 객체)
- 한국어 주석/문자열
- core 레이어는 features 의존 금지
- `Connection` 엔티티 구조 변경 금지
- `dwellTimeSeconds` 상수 값은 그대로
- 이전 수정(8호선 arvlCd=1 대응, findPathOnLine isDown, calculateInitialProgress 진입 0.0)과 충돌 없어야 함
