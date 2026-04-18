# map.html `startTrainAnimation` "이어서 진행" 로직 개선

## 변경 파일
- `assets/html/map.html` (단일 파일 수정)

## 수정 라인 범위
- **라인 1862-1865**: 상단 변수 선언부 정리 (segTimes 함수 상단에 선언)
- **라인 1879-1955**: "이어서 진행" 세그먼트 투영 및 분기 로직 재작성
- **라인 1960-1966**: 하단 segTimes 구축 블록을 fallthrough 전용으로 조건 정리

## 변경 요약

### 1. 변수 선언부 (라인 1862-1865)
- `var segTimes = [];` 를 함수 상단에 선언 (JS `var` 호이스팅 명확화)
- `sliceOffset` 주석에 `-1 = segTimes 확정됨` 플래그 의미 명시

### 2. 세그먼트 탐색 루프 (라인 1882-1896)
- `bestT` 변수 추가: 각 세그먼트의 투영 파라미터(0..1)를 `bestSeg`와 함께 저장
- 원래 버그: 투영 t가 루프 지역변수였고 `bestSeg`만 보존 → curPos가 path[bestSeg] 이전인지 이후인지 구분 불가

### 3. `minDist < 30` 분기 재작성 (라인 1898-1955)
세 가지 경우로 분기:

#### (a) `bestT <= 0.001` — curPos가 path[bestSeg] 이전/동일
- **버그 수정의 핵심**: `animPath = [curPos, path[bestSeg], path[bestSeg+1], ..., path[last]]`
- path[bestSeg]를 **포함**하여 중간 경유역 누락 방지
- segTimes: `[segDurations[bestSeg], segDurations[bestSeg], segDurations[bestSeg+1], ...]`
  - 첫 원소는 curPos→path[bestSeg] 구간(거의 0거리이므로 원 세그먼트 시간 근사 사용)
  - 둘째부터는 원본 segDurations 유지

#### (b) `bestT >= 0.999` — curPos가 path[bestSeg+1]과 거의 동일
- `animPath = path.slice(bestSeg + 1)`
- `segTimes = segDurations.slice(bestSeg + 1)`
- `remainingAfter.length` 기준 세 경우(>=2 / ==1 / ==0) 안전하게 처리
  - 길이 1/0은 목적지 고정 후 early return

#### (c) 중간값 (0.001 < bestT < 0.999) — 세그먼트 중간 위치
- 기존 동작 유지: `animPath = [curPos, path[bestSeg+1], ..., path[last]]`
- **개선**: 첫 세그먼트 시간을 `segDurations[bestSeg] * (1 - bestT)` 로 정확히 보정 (남은 비율)
- 이전에는 원 세그먼트 시간 그대로 사용했던 근사치를 수학적으로 정확하게 개선

### 4. sliceOffset 플래그화 (라인 1953-1954)
- 기존 "잘린 세그먼트 수" 의미에서 "segTimes 확정 여부 플래그(-1)"로 의미 확장
- 분기 진입 시 `sliceOffset = -1` 설정

### 5. fallthrough 블록 (라인 1960-1966)
- 기존 `if (sliceOffset > 0 && hasDurations) { ... } else if (hasDurations) { ... }` 이중 분기 제거
- 단일 조건: `sliceOffset !== -1 && segTimes.length === 0 && hasDurations` 일 때만 `segDurations.slice()` 대입
- 이어서 진행 분기에서 이미 segTimes를 채웠다면 그대로 사용

## 불변성 준수
- 모든 `path`, `segDurations` 는 `slice`/`concat`으로 새 배열 생성. 원본 배열 변경 없음.
- `trainData` 필드 직접 변경 없음 (로컬 변수 `animPath`, `segTimes`, `initProgress`로만 작업).

## 함수 시그니처
- `startTrainAnimation(trainState, trainData)` 시그니처 변경 없음.

## 예상 효과
- 2호선 중간 경유역(arvlCd=99, positionStatus="도착") 상황에서 path[bestSeg]를 건너뛰지 않음
- curPos→D 직선 이동 대신 curPos→C→D 경로 통과 → SVG 노선을 따라 자연스럽게 이동
- arrivalSeconds와 실제 이동 경로 시간이 근사적으로 일치하므로 "C 직전 정체" 현상 해소
