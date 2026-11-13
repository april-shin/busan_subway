# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⛔ 실시간 열차 애니메이션 4원칙 — 변경 금지 (최상위 정책)

지도 위 실시간 열차 애니메이션은 아래 4가지 원칙으로 고정되었다. **어떠한 일반 수정이나 버그 수정으로도 이 원칙을 깨뜨릴 수 없다.** 새로운 이슈가 보고되더라도 먼저 "현재 원칙 위반이 아닌지" 확인하고, 원칙을 유지하는 범위 안에서 수정해야 한다. 원칙을 바꿔야 한다고 판단되면 **반드시 사용자 승인을 먼저 구한다.**

### 원칙 1 — 열차는 절대 뒤로 가지 않는다 (위치 단조 전진)
화면상 열차 아이콘은 경로를 따라 **앞으로만 이동한다.** API 재조회로 남은시간이 늘어나든, "현재역" 정보가 뒤로 흔들리든, 아이콘이 뒤로 물러나는 일은 없다.
**보장 범위**: "경로(`pathToTarget`) 위에서의 진행도"가 뒤로 가지 않는다는 뜻이다. 화면 픽셀상 후퇴가 물리적으로 0 이라는 뜻은 아니다 — catch-up(원칙 4)은 경로가 아닌 2D 직선 보간이라 급커브에서는 시각적 후퇴가 남을 수 있다.

**(a) 숫자는 보장 대상이 아니다 — 단, 기준쌍은 (b)와 같은 규칙으로 고른다.** 말풍선의 남은시간은 API 원본을 그대로 쓴다 — `realRemaining = arrivalSeconds − (now − recptnDt)`. 재조회로 **원본 값이 바뀌어** 늘어나면 **늘어난 대로 표시한다.** 과거의 단조 감소 clamp·`trainSlotMemory` 보조키 장치는 제거됐고, **다시 도입하지 말 것** — 값을 깎는 장치와, 아래의 "어느 (값, 시각) 쌍을 새 측정치로 볼 것인가"는 다른 문제다.
- **표시 전용 기준쌍**(`baseArrival`/`baseReceivedAt`)을 `adoptDisplayBase` 로 갱신한다. `lastDisplayRawArrival` 과 비교해 **원본 값이 실제로 바뀐 refresh 에서만** 채택하고, 같은 값이 2회 이상 반복 보고되면 **새 `recptnDt` 도 보지 않는다.**
  - 갱신하면 경과시간이 매 cycle 리셋돼 카운트다운이 "감소 → 원위치" **톱니파**를 그린다. 2026-08-04 사당→방배 실측: 열차가 사당에 정차한 동안 `barvlDt=150` 이 1분 이상 고정된 채 `recptnDt` 만 ~16초씩 전진했다.
  - 이 규칙은 (b)의 위치용 기준쌍과 동일하다. 차이는 표시용에는 `pathEndKey` 리셋이 없다는 점뿐(표시는 경로와 무관).
  - **잔여 증상**: 톱니파가 없어지는 게 아니라 **stall 당 1회의 큰 점프로 뭉쳐진다.** 60초 stall 뒤 원본이 `150→140` 으로 바뀌면 표시는 `90 → 140` 으로 뛴다. 원본이 바뀌면 늘어난 대로 채택한다는 원칙에 부합하는 의도된 동작이다.
- 표시용 기준쌍을 쓰는 곳은 **말풍선 카운트다운·`step()` 도착 판정·z-order 정렬** 셋이다. **silent 제거/jitter grace 판정은 raw**(`lastArrivalSeconds`/`lastUpdateTime`, 매 refresh 무조건 갱신)를 그대로 쓴다 — "API 가 이 열차를 언제 마지막으로 보고했나"를 재는 용도라 raw 가 맞다.
- 예외 1: `remainingFromReceivedAt` 의 경과시간 0 하한(미래 `recptnDt` 방어).
- 예외 2: API 가 `barvlDt` 를 주지 않는 열차(8호선 등)는 `enrichArrivalInfoList` 의 이전 추정값 재사용(`live_train_provider.dart` 의 `_lastEnrichedArrivalsProvider`)이 최초 추정값·추정 시각을 물려주므로, JS 에 오는 `arrivalSeconds` 자체가 현재역·위치상태가 바뀔 때만 갱신된다. (2026-08-13 이전에는 지도 전용 `estimateCache` 가 같은 일을 했으나, 도착정보 화면과의 판정 불일치 때문에 제거됐다 — 아래 '모름 판정' 항목 참조.)
- **위치도 같은 기준쌍을 따른다.** `startTrainAnimation` 은 위치 기준쌍의 입력으로 `trainData` 원본이 아니라 **표시 기준쌍**(`trainState.baseArrival`/`baseReceivedAt`)을 쓴다. 원본을 쓰면 표시는 낡은 `recptnDt` 를, 위치는 새 `recptnDt` 를 물어 아이콘이 카운트다운보다 뒤처진다 — 말풍선이 "곧 도착"인데 열차는 아직 오는 중인 그림이 된다. **두 도메인은 같은 시각에 0 이 되어야 한다.**
- **도착 발동에 API 원본 게이트를 두지 말 것.** 남은시간이 줄어 0 이 되면 열차도 그때 도착해야 한다(사용자 요구). 원본으로 발동을 막는 장치를 넣으면 이 동기화가 깨진다 — 과거 `ARRIVAL_RAW_GATE_SEC` 시도를 그래서 철회했다. 대신 **위치 일관성 조건**(`atFinalLeg = nextIdx === path.length - 1`)은 둔다. 원칙 3 클램프가 아이콘을 중간역에 붙잡은 채 숫자만 0 이 되면 엉뚱한 역에서 사라지기 때문이며, 정상 케이스에서는 항상 참이라 동기화를 깨지 않는다.
- **⛔ 정상 도착 열차는 절대 되살아나지 않는다 (요구사항).** `arrivedTrains[trainNo]` 에 `{final: true}` 를 박고, 이후 API 가 무엇을 보고하든 부활시키지 않는다. **값 비교로 이를 대신하려 하지 말 것** — 목표역에 **진입 중인** 열차가 `barvlDt=10, arvlCd=0`(양수)으로 다시 보고되는 것이 실측된다(2026-08-04 방배). "새 원본이 `<=0` 이면 숨김" 류의 판정은 이 경우를 그대로 통과시켜 아이콘 깜빡임 + 도착 스낵바 중복을 낸다.
- **유령 도착 복구**: 기준쌍이 고정되므로 `realRemaining` 이 실제로 0 까지 내려간다. API 가 원본을 `arrivalSeconds` 초보다 오래 고정하면(장시간 정차·간격조정) 아직 전역에 있는 열차가 도착 처리될 수 있다. 이 경우에 한해 `{raw: N}` 을 기록하고, `showTrains` 가 **원본이 N 에서 바뀌면(= 새 측정치) 되살린다.** 단순히 `true` 만 박으면 API 가 계속 보고하는 한 정리 루프(`!trainNoSet[id]`)가 지우지 못해 **영구히 사라진다.**
  - 두 도착의 구분은 **도착 시점의 API 원본**(`lastArrivalSeconds`)으로 한다 — `> GHOST_ARRIVAL_MIN_SEC`(30초, refresh 주기의 2배)면 유령 후보. 정상 접근 열차는 원본이 벽시계와 함께 줄어 도착 순간엔 통상 refresh 주기 이하이고, stall 열차는 큰 값에 고정돼 있어 두 군이 뚜렷이 갈린다. 이 임계는 **도착 발동이 아니라 부활 가능성**만 가르므로 위 동기화 요구를 깨지 않는다.
  - 페이드아웃(0.6초) 중 부활에 대비해 `arrivalPlaying` 플래그를 둔다. 이 창의 `animationId` 는 주행이 아니라 페이드의 것이라, 조기 `continue` 분기가 살아있는 주행으로 오인하면 열차가 소리 없이 사라진다.
- **미적용 범위(의도)**: 이 stale 필터는 지도 말풍선에만 있다. Flutter 도착정보 화면(`arrival_card.dart`)은 `ArrivalInfo` 가 refresh 마다 새로 생성돼 열차별 기준쌍을 둘 자리가 없어 톱니파가 남아 있다. 적용하려면 열차별 키드 캐시가 필요하다.
- 지도에 오는 열차는 이미 "모름 판정"을 통과한 것이다 — 아래 "모름 판정(지도 진입 게이트)" 절 참조. 이 게이트는 원칙 1 의 일부가 아니라 그 앞단의 데이터 필터다.

**(b) 위치 역산 입력은 stale 응답을 걸러낸다.** **위치 전용 기준쌍**(`posBaseArrival`/`posBaseReceivedAt`)을 두되, 그 입력은 (a)의 표시 기준쌍을 **상속한다**(별도 필드인 이유는 `pathEndKey` 리셋 때문). 직전 값(`lastRawArrival`)과 비교해 **값이 실제로 바뀐 refresh 에서만** 기준쌍을 보정한다.
- 값이 그대로면(= `recptnDt` 만 갱신된 반복 보고. 신분당선 등 `arvlMsg2` 라운딩) 이전 쌍을 유지한다. 여기서 갱신하면 남은시간이 매 cycle 원복돼 **열차가 무기한 정지**한다.
- 값이 바뀌었으면 새 측정치이므로 **그대로 채택한다** — 실제 지연으로 남은시간이 늘어난 경우까지 무시하면 아이콘이 실제보다 앞서 달린다. 채택 결과 목표가 뒤로 가더라도 아이콘은 (c) 백스톱이 붙잡으므로 뒤로 가지 않는다(멈췄다가 재개).
- 대안으로 검토했다가 버린 방식: ① "min 값 기억" — 반복 보고 시 min 이 "직전 값 − refresh 주기"에 고정돼 정지. ② "더 늦은 도착이면 무조건 무시" — 정지는 없지만 실제 지연을 반영 못 해 아이콘이 앞서 달린다.

**(c) 경로상 단조 전진 backstop.** 시간과 무관한 후퇴(현재역 후퇴, 경로 재스냅)까지 막는 2차 방어선.
- 전진 척도는 **"경로 끝까지 남은 거리(px)"**. `pathToTarget` 의 앞부분은 refresh 마다 늘거나(`expandPathBackward`) 줄지만(역 통과) 끝점(목표역)은 고정이므로, 끝에서부터 잰 거리만이 refresh 간 비교 가능하다.
- 원칙 2·3 을 거쳐 나온 target 의 `distToEnd` 가 최소값(`minDistToEnd`)보다 크면 **그 target 을 버리고 최전진 지점에 붙잡아 둔다** (= 뒤로 가는 대신 멈춰 기다린다). NaN 이 들어오면 기억을 오염시키지 않고 최전진 지점만 유지.
- 경로 끝점 좌표(`pathEndKey`)가 바뀌면 다른 경로이므로 기억을 리셋한다. **같은 노선·방향에서 출발역만 바꾸면 `scopeKey` 는 그대로이므로 이 리셋이 유일한 탈출구다.** (리셋 시에는 후퇴가 허용된다 — 의도된 예외)
- rAF 를 타지 않는 분기도 전진 상태를 직접 다뤄야 한다. 단일 점 path 는 **실제 도착(`arrivalSeconds<=0`)일 때만** 최전진으로 고정한다 — 양수에도 고정하면 '진입' 오보고 한 번으로 그 열차가 목표역에 **영구 고정**된다(끝점이 같아 `pathEndKey` 리셋도 안 타 회복 경로가 없다). 데이터 불일치 분기는 아이콘을 **움직이지 않는다** (`path[0]` 은 경로의 맨 뒤라 고정하면 후퇴가 된다).

**한계 1 — 위치·표시가 갈라지는 잔여 경로.** 위치 기준쌍이 표시 기준쌍을 물려받게 되어 "아이콘이 말풍선보다 앞서 달리는" 옛 증상은 해소됐다. 다만 두 쌍은 여전히 별개 필드라 다음 두 경우에 갈라진다: ① 위치 쌍만 `pathEndKey` 변경 시 리셋된다(리셋 직후 표시 쌍을 다시 물어 곧 수렴). ② 도착 임박 열차의 조기 `continue` 분기(`arrivalSeconds<=2`)는 표시 쌍만 갱신하고 위치 쌍은 그대로 둔다(`startTrainAnimation` 미호출과 짝을 맞춘 의도된 동작). 둘 다 짧게 끝나므로 오차는 원칙 3 클램프 상한인 **최대 한 구간**을 넘지 않는다.

**한계 2**: 전진 기억은 `activeTrains[trainNo]` 에 붙어 있어, 열차 식별이 흔들리면 아이콘과 함께 초기화된다. `arrival_info_dto.dart` 의 `btrainNo`→`ordkey` 폴백은 빈 `trainNo` 만 막을 뿐 **지속성을 보장하지 않는다** — `ordkey` 에는 도착 순번이 섞여 있어 앞선 열차가 도착하면 값이 바뀔 수 있다. 그런 노선에서는 보장이 리셋된다.

- 구현 위치: `tool/build_map_html.dart` 의 `startTrainAnimation` (`posBaseArrival`/`posBaseReceivedAt` 기준쌍 선택, `cumLen`/`pathTotalLen`/`pathEndKey`/`pointAtLength` + `step()` 의 단조 전진 가드), `lib/features/subway_map/presentation/providers/live_train_provider.dart` 의 `receivedAtEpochMs` 전달(기준 시각이 틀리면 역산 위치가 틀린다).
- 회귀 테스트: `test/core/utils/train_forward_guard_test.dart` (동작 — Dart 미러 `lib/core/utils/train_forward_guard.dart`), `test/tool/build_map_html_test.dart` (생성 JS 형태).

## 모름 판정 (지도 진입 게이트) — 4원칙 바깥

잔여시간을 알 수 없는 열차의 판정은 `lib/core/utils/live_arrival_seconds.dart` 의 `liveArrivalSeconds` **한 곳**에 있다. 세 경우가 "모름"이다: `arrivalSeconds` 가 null / 양수인데 잔여초가 소진됨 / `0`("역에 있음")인데 `ApiConstants.arrivalStateGrace`(120초)를 넘겨 낡음.

- 도착정보 화면은 **"정보 없음"** 배지를 표시한다.
- 지도(`liveTrainsProvider`)는 그 열차를 **그리지 않는다** (사용자 결정, 2026-08-13).

**규칙을 화면별로 복제하지 말 것.** 복제돼 있던 탓에, 카드가 "정보 없음"으로 판정한 열차를 지도는 계속 카운트다운했다(총신대입구(이수) 7호선 제보). 지도의 JS 는 `max(0, ...)` 로 바닥을 0 에 붙이므로 만료된 데이터로도 "곧 도착"을 **단언**한다.

- 제보 화면의 "1분 후 도착"은 **API 원본 그대로**였다(2026-08-13 15:32 실측: `barvlDt='60' arvlCd='1'(도착) arvlMsg2='총신대입구(이수) 도착'`). 초기에 "지도 전용 추정 폴백이 기준 시각을 `now` 로 리베이스해 만든 숫자"로 진단했으나 실측으로 반증됐다 — 그 폴백은 이 게이트로 도달 불가가 되어 함께 제거됐을 뿐 원인이 아니다.
- 그 행 자체(도착 상태인데 양수 `barvlDt`)는 `arrival_info_dto.dart` 의 도착 우선 판정으로 별도 수정했다. 이 게이트는 그 뒤에도 남는 만료 데이터의 방어선이다.

- 이 게이트는 **원칙 1~4 의 일부가 아니다** — 어떤 열차를 그릴지 고르는 앞단 필터이고, 원칙은 그려진 열차가 어떻게 움직이는지를 규정한다. 표시 정책을 (B)추정값 표시나 (C)지도에도 "정보 없음" 으로 바꾸는 것은 4원칙 변경 절차 대상이 아니다.
- `barvlDt` 미제공 노선(8호선 등)은 `enrichArrivalInfoList` 가 추정값과 **추정 시각**을 함께 채우므로 이 게이트에 걸리지 않는다. 이 경로가 죽으면 해당 노선 열차가 지도에서 통째로 사라진다.
- 회귀 테스트: `test/core/utils/live_arrival_seconds_test.dart`(판정 규칙), `test/features/subway_map/presentation/providers/live_train_unknown_gate_test.dart`(지도 배선 — 게이트 한 줄을 지우면 깨진다).

### 원칙 2 — 매 frame 남은시간 역산으로 위치 결정
화면상 열차 위치는 **매 frame 뒤에서부터 남은시간을 역산**하여 결정한다. 전방 보간 (path[0]→path[last] 시간 비례) 금지.
- 알고리즘: `estimateTrainPosition(remaining, segTravel)` — 뒤에서부터 각 세그먼트 주행시간만큼 차감하며 매칭되는 세그먼트의 `progress = (s[i] − t) / s[i]` 를 반환. dwell=0 전제.
- 예시: path=[A,B,C], s=[60,60], t=120 → A 위치 / t=80 → A-B 의 2/3 지점 (B 쪽).
- 구현 위치: `tool/build_map_html.dart` 의 `estimateTrainPosition`, `startTrainAnimation.step()`.

### 원칙 3 — 현재역 기준 3-way 클램프
`arvlMsg3`("현재역") 이 A 인 열차는 **화면상 A↔B(다음역) 한 구간 안에서만** 움직인다. 역산이 B-C 세그먼트를 가리켜도 B(다음역)에 클램프, A 이전 세그먼트를 가리키면 A(현재역)에 클램프.
- **단, 원칙 1 가드가 이 상한을 override 할 수 있다.** `arvlMsg3` 가 뒤로 흔들리면 클램프 결과가 후퇴하는데, 가드가 그 target 을 폐기하므로 열차는 새 "다음역"보다 앞에 머문다. 적용 순서(3 → 1)에 따른 의도된 동작이다.
- `currentStationIndex` 는 원본 `pathToTarget` 의 "현재역" index. SVG 곡선 스냅(`expandPathWithSnap`)으로 path 가 세분화되면 `stationIndices` 매핑으로 **확장 path 상 역 위치**로 변환해 3-way 분기.
- 구현 위치: `tool/build_map_html.dart` 의 `expandPathWithSnap.stationIndices` + `startTrainAnimation.step()` 의 3-way 분기.

### 원칙 4 — 열차는 순간이동하지 않는다 (catch-up)
API 갱신으로 열차의 목표 위치(target)가 갑자기 바뀌어도, 아이콘은 즉시 이동하지 않고 **현재 위치에서 목표를 향해 매 프레임 부드럽게 다가간다**.
- 다가가는 속도는 "남은 거리가 절반이 되는 시간(반감기)"으로 조절한다:
  - 목표가 가까우면(≤30px) 반감기 3초 — API 지터·라운딩 노이즈를 잔잔하게 흡수.
  - 목표가 멀면(>30px) 반감기 0.5초 — 빨리 따라잡아 선로 이탈처럼 보이는 시간 최소화.
  - 0.5px 이내로 접근하면 목표에 스냅하고 따라잡기 종료.
- 프레임 간 경과시간(deltaMs)은 100ms 상한 — 백그라운드 복귀 등으로 프레임이 오래 끊겨도 한 번에 확 움직이지 않는다.
- `startTrainAnimation` 재호출 시 `lastFrameMs = null` 리셋 (첫 프레임에 거대한 deltaMs 로 순간 수렴하는 현상 방지).
- 도착 이펙트는 따라잡기(`catchingUp`)가 끝난 뒤에만 발동.
- 구현 위치: `tool/build_map_html.dart` 의 `startTrainAnimation.step()` (`HALF_LIFE_NEAR_MS`/`HALF_LIFE_FAR_MS`/`FAST_DIST_THRESHOLD`/`SNAP_PX`).

### 원칙 적용 순서 (step() 한 프레임)
`realRemaining` 계산 → **원칙 2**(역산으로 target 후보) → **원칙 3**(현재역↔다음역 클램프) → **원칙 1**(단조 전진 가드 — 뒤로 가는 target 이면 최전진 지점으로 대체) → **원칙 4**(currentPos 를 target 으로 부드럽게 catch-up) → transform 적용.
순서를 바꾸면 원칙이 서로를 무력화한다 (예: 원칙 1 가드를 원칙 3 앞에 두면 클램프가 가드를 되돌린다).

### 수정 시 절차
- `tool/build_map_html.dart` 또는 `lib/features/subway_map/presentation/providers/live_train_provider.dart` 편집 시 **해당 파일 상단의 4원칙 보호 주석 반드시 확인**.
- `assets/html/map.html` 직접 수정 금지 — `tool/build_map_html.dart` 가 유일 소스. 생성은 `dart run tool/build_map_html.dart`.
- 4원칙 관련 회귀 테스트가 깨지면 **원칙 위반 가능성을 먼저 의심**한다 — 원칙 1: `test/core/utils/train_forward_guard_test.dart`, 원칙 2: `test/core/utils/estimate_train_position_test.dart`, 생성 JS 형태: `test/tool/build_map_html_test.dart`.
- JS 애니메이션 로직은 WebView 안이라 단위 테스트가 불가능하므로 `lib/core/utils/{estimate_train_position,train_forward_guard}.dart` 에 **Dart 미러**를 두고 테스트한다(앱 런타임 미사용). JS 를 고치면 미러도 함께 고칠 것.

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

> ⚠️ **부산 전환(2026-11-13) — 아래 명령 중 일부는 실행 금지.**
> 정적 데이터와 지도 SVG 의 **유일 소스는 `tool/build_busan_data.py`** 다
> (입력 `tool/data/busan_humetro_{cyberstation,travel_times}.txt` → `assets/json/*.json` 8개 +
> `assets/svg/busan_metro_map.svg`). 데이터를 바꾸려면 입력 txt 나 스크립트를 고친 뒤
> `python3 tool/build_busan_data.py && dart run tool/build_map_html.dart` 를 돌린다.
> - **서울 시절 생성기는 돌리지 말 것** — 부산 에셋을 서울 기반 산출물로 덮는다:
>   `extract_svg_stations`, `generate_station_data`, `build_transfer_times`,
>   `import_official_transfer_guides`, `import_transfer_guides`, `build_*_timetable*`, `extract_express_skip_edges`.
>   (`tool/data/busan_metro_transfer_*.csv`, `data/transfer_guides*.csv`, `data/timetables/` 는 이름과 달리 서울 데이터다.)
> - **SVG 는 생성물이다.** 지도 편집기(`tool/badge_editor.dart`)의 선분·환승마커 모드로 SVG 를 고치면
>   `build_busan_data.py` 재실행 때 사라진다. 배지 모드(`data/badge_offsets.json`)는 안전하다.
> - **실시간 기능은 꺼져 있다**(`lib/core/constants/feature_flags.dart` 의 `FeatureFlags.realtimeEnabled`).
>   4원칙 코드는 그대로 남아 있지만, 플래그가 const 라 배선 회귀 테스트(`live_train_unknown_gate_test`,
>   `live_train_ghost_test` 등 31건)는 `skip` 상태다 — 플래그를 켤 때 부산 픽스처로 복원할 것.
> - 아래 본문과 `.claude/docs/` 의 노선·시간표·환승 설명은 대부분 서울 시절 내용이다.
>   부산 데이터의 근거와 한계는 `.claude/docs/pending-data.md` 의 "부산 전환" 절을 볼 것.

```bash
# 코드 생성 (freezed, json_serializable, riverpod_generator)
# build_runner 2.15+ 에서 --delete-conflicting-outputs 는 제거됨(기본 동작화).
# ⚠️ 구 삭제형 플래그는 데드락 시 생성물을 통째로 지워 복구 불가(gitignore)라 위험.
dart run build_runner build
dart run build_runner watch  # 워치 모드

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

# 역/노선 JSON 에셋 재생성 (svg_station_coords.json 참조, transfer_times.json 은 생성하지 않음)
dart run tool/generate_station_data.dart

# 환승소요시간 재생성 (서울교통공사 공식 데이터셋 + stations.json → transfer_times.json, 유일 소스)
dart run tool/build_transfer_times.dart

# 환승 가이드("빠른 환승" 칸-문) CSV 재생성 — 서울교통공사 공식 "서울 도시철도
# 환승정보"(tool/data/busan_metro_transfer_guides_official.csv, 공공데이터포털
# 15098252) + data/transfer_guides_manual.csv(공식 미커버 구간, 수기/나무위키
# 유래) → data/transfer_guides.csv 로 병합한다. data/transfer_guides.csv 는
# 여전히 assets/json/transfer_guides.json 의 유일 소스이지만, 이제 그 자체가
# 이 도구의 산출물이므로 **직접 수정 대신 이 도구를 다시 돌릴 것**(공식 CSV
# 갱신 시 재실행). 공식이 커버하는 조합은 공식 값이 항상 우선한다.
dart run tool/import_official_transfer_guides.dart

# 환승 가이드 CSV → JSON 변환. data/transfer_guides.csv 는
# assets/json/transfer_guides.json 의 유일 소스지만 **직접 편집하지 말 것** —
# 위 공식 임포터의 산출물이라 재실행 시 덮인다. 수기 보정이 필요하면
# data/transfer_guides_manual.csv 를 고친 뒤 위 임포터 → 아래 순서로 실행한다.
dart run tool/import_transfer_guides.dart

# 경의중앙선 시간표 재생성 (코레일 전동열차 시각표 엑셀 → line_schedules.json)
# 역별 시간표 t 와 함께 노선 대표값 f/l(첫차·막차)·p 첫 band 시작을 t 에서 도출한다.
# 코레일 "열차운임/시간표" 게시판에서 평일·휴일 xlsx 를 받아 assets/excel/ 에
# center_line_{wd,we}<시행일 YYMMDD>.xlsx 로 두고 실행한다. 상세는
# .claude/docs/timetable.md 의 "경의중앙선" 항목(시트↔방향 매핑이 코레일 라벨과 다름).
python3 tool/build_center_line_timetable.py --dry-run
python3 tool/build_center_line_timetable.py

# WebView용 HTML 생성
#   입력: busan_metro_map.svg + stations.json + lines.json + connections.json
#         + data/badge_offsets.json (있을 때만 — 배지 수동 보정)
#   출력: assets/html/map.html
# ⚠️ SVG 외에 **assets/json 3개가 모두 입력**이다. 파이프라인 2단계
# (generate_station_data) 뒤에 돌려야 하고, 그 JSON 을 직접 패치했다면 이
# 도구를 반드시 재실행할 것. 각 입력의 쓰임:
#   - stations.json `isTransfer` → 역명 라벨 2단(tier). 환승역 라벨에만
#     `tl-major` 를 붙여 줌아웃 시 최소 크기 하한을 유지한다.
#   - lines.json + connections.json → 노선 이름 pill 배지(노선당 양 종점 2개,
#     총 48개). 종점은 connections 그래프의 hop 지름 양 끝으로 정한다.
# ⚠️ **이 도구는 입력이 어긋나면 조용히 틀리는 대신 빌드를 실패시킨다.**
# 의도된 하드페일이며, 아래가 그 조건이다 — 역/노선을 추가·수정한 뒤 지도
# 빌드가 깨지면 버그가 아니라 이 검증에 걸린 것이다:
#   - stations.json 에 `isTransfer=true` 인 역이 하나도 없음(스키마 드리프트)
#   - lines.json 의 노선 id 집합이 `kLineIdToDataLine`(tool/line_badges.dart)
#     과 불일치하거나, SVG `data-line` 코드 집합과 불일치
#   - 노선 역들이 해당 `data-line` 선 위에 놓이는 비율이 하한 미달
#   - 구간이 끊긴 노선(GTX-A 등)에 `kBadgeTerminalOverrides` 항목이 없음
#   - `data-line` path 에 M/L 외 명령(C/Q/A/Z)이 등장
#   - **미해결 배지 1개 이상** — 앵커(노선 선 끝점)에서 **24px 이내**에 하드
#     위반 없는 자리를 못 찾은 배지가 있음. 하드 위반 6종: 타 노선 선 위 /
#     역명 라벨(f=1.0·1.5) / 역 circle / 환승역 rect / 다른 배지 / 캔버스 이탈.
#     ⚠️ **배지↔종점을 잇는 연결선(줄기)은 없다**(사용자 결정 2026-10-06) —
#     줄기가 노선 선과 굵기·색이 같아 화면상 "존재하지 않는 지선"으로 읽혔다.
#     그래서 pill 을 멀리 보내 해결하는 길이 막혀 있다. 조치 1순위는 배치
#     데이터 점검이고, `kLineBadgeNames` 축약은 **사용자 승인 사안**이다 —
#     빡빡하다고 임의로 늘리지 말 것(과거 "2호선"→"2호" 축약을 그래서 철회).

#   - **배지 문구 중복** — 두 노선의 배지 문구가 같음(공백 제거 후 비교)
#   - `data/badge_offsets.json` 의 JSON 문법/형식/version 오류 (항목 단위
#     오류나 키 불일치는 실패가 아니라 경고 + 자동 배치 폴백)
#   - **배지 문구가 실제 역명과 같음** — stations.json 역명 또는 SVG 역명
#     라벨과 충돌. 배지가 역명 라벨로 오독되는 것을 막는다(예: 의정부경전철
#     을 "의정부" 로 줄이면 의정부역과 충돌해 실패)
# 실제 사례: 에버라인에 기흥(E15)을 추가하자 배지 종점이 기흥으로 바뀌었다.
# 매핑·종점 진단은 `LINE_BADGE_VERBOSE=1 dart run tool/build_map_html.dart`.
dart run tool/build_map_html.dart

# 지도 편집기 — 배지 위치 보정 + 노선 선분 + 환승 마커 (드래그 에디터 + 저장 서버, localhost 전용)
# 패널 상단 탭으로 **세 모드**를 오간다. 모드마다 쓰는 파일이 다르다:
#   - `배지`     → data/badge_offsets.json
#   - `선분`·`환승마커` → assets/svg/busan_metro_map.svg (+ 빌드가 다시 쓰는 assets/html/map.html).
#     SVG 하나를 같이 고치므로 저장도 하나다. 로직은 tool/geometry_svg.dart(순수 함수, test/tool/geometry_svg_test.dart).
# "저장 + 재빌드" 를 누르면 곧바로 build_map_html 이 돌아 실제 결과를 보여 준다.
# 서버는 **한 번에 하나만** 띄운다(저장 락이 프로세스 안에서만 유효).
#
# [배지 모드]
#   - 보정값은 **앵커(노선 선 끝점) 기준 상대 오프셋** `{dx,dy}`. 키는
#     `노선id|종점역명`(예: `김포골드|양촌`) — 한 노선에 배지가 2개라서다.
#   - 보정한 배지는 자동 배치 솔버를 건너뛰고 **장애물로만** 쓰인다.
#   - `data/badge_offsets.json` 은 커밋 대상이고 **직접 편집 대신 이 도구를 쓴다**.
#     파일이 없거나 비면 산출물이 보정 전과 바이트 동일하다.
#   - ⚠️ **수동 보정 배지의 하드 위반은 빌드를 실패시키지 않고 경고만** 남긴다
#     (사람이 고른 자리를 기계가 거부하면 보정 기능이 무의미하므로). 자동 배치
#     배지의 하드 위반은 종전대로 빌드 실패다. 수동 배지가 자동 배지의 자리를
#     막으면 자동 쪽 미해결로 실패하며, 메시지에 수동 보정 키가 표시된다.
#
# [선분·환승마커 모드] 위치 + 크기(길이 16/20/24/28) + 방향(가로/세로/동그라미) 편집.
#   - 선분: 정점을 끌면 그 점만, **정점 사이 선(구간)을 끌면 양 끝 정점이 함께 평행 이동**한다. 같은 노선(`data-line`)의
#     겹친 끝점은 기본으로 같이 움직인다(끄면 2호선 순환 고리 등 이음새가 벌어진다). 흰 이중선(`{code}-1`)은 본체와 같이 간다.
#   - ⚠️ **환승 마커는 두 종류인데 이 도구는 한쪽만 다룬다.** 알약 `<rect rx=4>` **56개**는 편집 가능하지만,
#     동그라미 `<circle r=5 fill:white stroke:#333>` **71개**는 **대상이 아니다**(역 dot `<circle r=4.5>` 와 다른 것이다).
#     그래서 "동그라미를 알약으로" 같은 변환은 **손으로 SVG 를 고쳐야** 한다 — 커밋 `1a4f116` 의 왕십리가 그 사례다
#     (선분 이동으로 수인분당선이 역에서 8px 떨어져 동그라미로 네 노선을 못 묶게 되자 24×8 알약으로 교체했다).
#     마커 드리프트 가드(아래 ②)도 `<rect>` 만 본다 — 동그라미를 손으로 옮기면 **무경고**로 stations.json 과 어긋난다.
#   - **미지원**: 정점 추가·삭제, 베지어, **환승 동그라미 `<circle>`**, 역 dot·라벨 이동. 역은 선과 따로 놀므로
#     **역 이동은 이 도구로 못 한다**.
#   - **길이 0 세그먼트 주의**: 4px 격자 스냅이라 정점을 옮기다 이웃과 좌표가 겹칠 수 있다(커밋 `1a4f116` 의 경춘선에서
#     실제로 4개 생겼다 — G v2-v3·v5-v6 과 흰 이중선 쌍). 렌더에는 무해하지만 **그 구간은 집을 수 없고**(hitSegment 가
#     건너뛴다) 겹친 두 정점 중 뒤쪽은 클릭 선택이 안 된다(정점 카드의 `다음 정점 →` 로만 간다). 경고는 아직 없다.
#   - 편집은 SVG 의 path/rect **등장 순서 index** 로 식별한다. 편집기를 연 뒤 SVG 가 바뀌면(git 전환 등) 저장이 409 로 거부된다.
#   - **저장 실패 시 원복**: 빌드가 하드페일(exit≠0·예외·3분 타임아웃)하면 SVG 와 map.html 을 저장 직전 바이트로 되돌리고
#     바이트까지 재확인한다(`reverted:true`). 사본은 `.dart_tool/geometry_editor/*.bak`(assets/ 밖 — `assets/svg/` 는 통째로
#     번들된다). 서버가 저장 도중 죽으면 표식 파일이 남아 다음 접속 때 UI 배너로 알리고, 복구 1순위는 `.bak` 이다.
#     **표식이 남아 있는 동안 새 저장은 409 로 거부된다**(복구를 확인하고 표식 파일을 지울 때까지 — 저장이 `.bak` 을 덮어
#     복구 소스를 잃는 것을 막는다).
#   - **선로 이탈 경고 2단계**: 역(stations.json)이 자기 노선 선로에서 **12px 초과 = 하드**(빨강 — 드래그 중 실시간·저장 직전
#     confirm·저장 응답), **4px 초과 12px 이하 = 소프트**(노랑 — "눈에 보이게 벌어짐": 선 두께 4px·dot r4.5~5px 이라 dot 이
#     선에서 분리돼 보인다. 목록·저장 후 배너·로그에만, confirm 은 없다). **둘 다 저장을 막지는 않는다.** 겹친 두 선을 떼려고
#     한쪽을 8px 올리면 역↔선이 정확히 12.0px 이 되어 하드(`> 12`)는 침묵하므로 소프트가 있다. 하드 수치(12)는 불변이고
#     `test/tool/geometry_svg_test.dart` 의 가드가 CI 에서 잡는다(소프트는 편집 전에도 20건 안팎 있어 회색 `pre` 로만 보인다).
#   - **연속 구간(런) 선택**: 구간을 Shift-클릭(정점·구간 모두)하면 같은 선의 인접 구간까지 확장되고, 런을 끌면 모든 정점이
#     **같은 양을 한 번만** 움직인다(공유 정점 이중 이동 없음). 정점을 하나씩 밀 필요가 없다.
#   - **마커 드리프트 경고**: 환승 마커를 **끌면** stations.json 좌표와 벌어진다(아래 SVG 파이프라인 주의). 두 겹으로 잡는다:
#       ① 편집 중·저장 직후 — 앵커된 역과의 거리가 늘었는지(`findMarkerDrift`, 이동량 기준. 12px 가드는 못 잡고 공유 캡슐 3건은
#       면제). 길이·방향 변경은 중심을 보존하므로 해당 없음.
#       ② **상시·영속** — 저장된 SVG 에서 **앵커 역이 없는 마커**(`orphanMarkers`)를 `/api/geometry/model` 이 싣고 UI 가 상단
#       배너·마커 목록에 계속 띄운다(새로고침·새 세션 불문). 현재 56/56 마커가 앵커를 가져 오탐 0 이다. 앵커 반경(14px) 안으로
#       옮긴 마커(환승역은 14px 이내면 앵커)는 ② 에 안 걸리지만, `test/tool/geometry_svg_test.dart` 가 마커↔역 거리 분포
#       (≤0.5px 54 · 0.5~14px 2(김포공항 12.0px · 왕십리 8.94px) · >14px 0)를 단언하므로 **어느 거리로 옮겨 커밋해도 CI 가 깨진다.**
#     ⚠️ 두 신호가 가리키는 해결은 같다: stations.json 의 해당 역 svgX/svgY 를 직접 패치(생성기 단독 재실행 금지)하거나 마커를 원위치.
#   - **선을 옮기면 수동 보정 배지 42개가 같이 움직인다**(오프셋이 앵커=선 끝점 기준 상대값). 저장 뒤 배너로 올리는 것 둘:
#     ① "이번 저장으로 새로 생기거나 값이 바뀐 수동 배지 **하드 위반** 경고"(저장 전부터 있던 10건 안팎은 제외),
#     ② **위반 여부와 무관한 이동량** — "수동 배지 N개(전체 M개 중)가 최대 Mpx 움직였다"(앵커를 저장 전후로 풀어 비교;
#     path 를 안 건드린 저장은 건너뛴다). 위반 없이 조용히 틀어진 배지가 우려의 본체라서다.
dart run tool/badge_editor.dart          # http://localhost:8765
```

**중요:** 실 디바이스(iPhone 등) 빌드는 반드시 `--release` 모드를 사용해야 한다. 디버그 빌드는 Dart VM 연결이 필요하므로 앱을 백그라운드로 보냈다 다시 열면 크래시가 발생한다.

## 환경 설정

프로젝트 루트의 `.env` 파일 (`pubspec.yaml` assets에 등록됨):
```
BUSAN_SUBWAY_API_KEY=<data.seoul.go.kr에서 발급받은 실시간 지하철 API 키>
```
실시간 도착정보 데이터소스(`busan_api_data_source.dart`)가 `BUSAN_SUBWAY_API_KEY` 를 읽는다. 앱 런타임에 키를 검증하며, 미설정/placeholder 값이면 예외를 던진다.

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
- **그래프 노드 ID 형식:** `"{stationId}_{lineId}"` (예: `"222_2"` = 2호선 강남역, `"216_2"` 는 잠실)
- **환승 시간 키 형식:** `"{역이름}_{lineId1}_{lineId2}"` (`transfer_times.json` 내)
### 노선 정보

6개 노선 — 1~4호선, 동해선(`동해`), 부산김해경전철(`부산김해`). 전부 단순 선형(지선·순환·급행 없음). (`.claude/docs/lines-reference.md` 는 서울 시절 문서)

**미개통·근거부족으로 일부러 비워 둔 데이터**는 `.claude/docs/pending-data.md` 에 모아 둔다
(결정 시점·근거·복구 절차 포함). "왜 이 역은 환승역이 아니지?" 류의 의문이 들면 먼저 볼 것 —
현재 등재: 평택지제 GTX-A 환승 표시 해제, 기흥 환승시간 근거 약함, 에버라인 기흥→강남대 추정치.

### 상태 관리

Riverpod 3.x + 코드 생성 (`@riverpod` 어노테이션). `StateProvider`/`StateNotifier` 는
riverpod 3 에서 레거시로 이동해 `package:flutter_riverpod/legacy.dart` 임포트가 필요하다.
주요 프로바이더:

- `allStationsProvider` — 번들 JSON에서 전체 역 목록 로드
- `selectedStationsProvider` — 출발/경유/도착역 선택용 `StateNotifier<SelectedStations>` (수동 작성, 비생성). 경유역은 `waypoints` 리스트로 최대 `maxWaypoints`(3)개
- `favoriteRoutesProvider` / `resolvedFavoriteRoutesProvider` — 즐겨찾기 경로(출발·경유·도착 id + 별칭, 최대 5개, 배열 순서=표시 순서). SharedPreferences `pref_favorite_routes`. 최근 검색(`recentSearchProvider`)과는 별개. 홈 태그·경로 결과 별 버튼·설정 목록이 쓴다(`lib/features/favorites/`)
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
| `/pick-station/:purpose` | StationPickerScreen | purpose = `departure` / `arrival` / `waypoint` / `home`(지도 시작점) / `favorite-departure`·`favorite-arrival`(설정의 즐겨찾기 편집 — `context.push<Station>` 으로 열면 고른 역을 pop 결과로 돌려주고 `selectedStationsProvider` 는 건드리지 않음). `waypoint` 는 쿼리 `?index=N`(대상 슬롯) + `?insert=true`(그 자리에 삽입, 없으면 교체) |
| `/route-result` | RouteResultScreen | `RouteResult`를 `state.extra`로 전달. extra 의 `searchedStations` 는 그 결과를 **계산한** 출발·경유·도착(즐겨찾기 별 판정 키 — 지도 툴바 '결과'는 재계산 중이면 현재 선택과 다를 수 있어 뷰어의 `_routeSelection` 을 넘긴다) |
| `/station/:stationId` | StationDetailScreen | |
| `/arrivals/:stationName` | ArrivalInfoScreen | 15초마다 자동 새로고침 |

### 지도 렌더링

지하철 지도는 `webview_flutter`로 원본 SVG를 HTML 내에서 네이티브 렌더링한다:

```
Expanded → WebViewWidget (전체 화면)
  └─ HTML 페이지 (assets/html/map.html)
      ├─ <svg> 원본 (busan_metro_map.svg 인라인, 한국어 텍스트 포함)
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

**중요:** SVG 를 고쳤다면 **무엇을 고쳤는가**로 돌릴 단계를 정한다(누가·무엇으로 고쳤는가는 무관하다 — 손이든 `tool/badge_editor.dart` 든 같다).
- **노선 `<path>` 와 환승 `<rect>` 만 고쳤다면 3단계(`build_map_html`)만 돈다.** 편집기는 저장 때 자동으로 돌리고, 손으로 고쳤다면 직접 돌린다(예: `2c73c10` 경춘선 흰 이중선 추가는 전부 손 편집, `1a4f116` 은 선분·배지를 편집기로 고치고 왕십리 `<circle>`→`<rect>` 만 손으로 바꾼 혼합 — 둘 다 3단계만 돌린 게 옳았다).
  ⚠️ `<circle>` 을 지우거나 더하는 변경은 이 칸의 "`<rect>` 만" 에 **들어가지 않는다**(역 좌표 후보가 바뀐다). `1a4f116` 은 알약 중심을 보기 좋은 자리로 두느라 stations.json 과 8.94px 어긋남을 **의도적으로 수용**한 사례이고, 그래서 1·2단계를 돌리면 왕십리 좌표가 끌려간다.
- **1·2단계(`extract_svg_stations`·`generate_station_data`)는 역 `<circle>`·`<text data-station>` 을 추가·이동·삭제했을 때만 고려한다.** 그때도 단독 재생성은 파괴적(역 소실·좌표 파손 전력 — 메모리 `station-data-pipeline-drift`)이므로 **`stations.json` 직접 패치를 우선**한다.

⚠️ **환승 마커를 이동하면 stations.json 과 어긋난다.** `extract_svg_stations` 는 `rx` 있는 **모든 rect 의 중심을 역 dot 후보**로 쓰므로 캡슐 중심이 일부 역 `svgX/svgY` 의 원천이다(56개 마커 중 54개는 역 좌표 = 마커 중심, 김포공항 12px · 왕십리 8.94px 만 옆). 편집기가 1·2단계를 돌리지 않으니 마커를 끌면 SVG 와 stations.json 이 벌어진 채 남고(경로 하이라이트·열차 아이콘이 옛 자리), 12px 선로 가드는 못 잡는다. 편집기는 경고만 하며 **stations.json 을 고치지 않는다** — 마커를 옮겼다면 해당 역 좌표를 직접 맞출 것.

### 네트워크 및 캐싱

- 서울 열린데이터 API: `http://swopenapi.seoul.go.kr/api/subway/{apiKey}/json/realtimeStationArrival/0/20/{stationName}`
- 도착 정보는 SharedPreferences에 30초 TTL로 캐시 (`cache_arrival_{stationName}`)
- 오프라인 시 마지막 캐시 데이터로 폴백

### 정적 데이터

`assets/json/`의 번들 JSON (stations, connections, lines, transfer_times, line_schedules)은 `LocalDataSource` / `TimetableDataSource`가 `rootBundle`로 로드하며 세션 내 메모리에 캐시된다.

### 열차 시간표

역별 시간표 + 배차간격 폴백 하이브리드. 상세: `.claude/docs/timetable.md`

## 코드 생성

모든 `@freezed` 모델과 `@riverpod` 프로바이더는 변경 후 `build_runner` 실행이 필요하다. 생성 파일: `*.freezed.dart`, `*.g.dart`. `dart run build_runner build` 로 실행한다(build_runner 2.15+ 부터 충돌 산출물은 기본 덮어쓰기되며, 구 `--delete-conflicting-outputs` 플래그는 제거됨).

## 컨벤션

- UI 문자열, 주석, 에러 메시지는 한국어
- 모든 데이터 모델은 불변 (`@freezed`)
- 스크린은 `*Screen`, 재사용 위젯은 설명적 이름
- 프라이빗 위젯 헬퍼는 `_` 접두사 (예: `_RouteSummary`)
- 테스트 모킹은 `mocktail` 사용

## 미사용 의존성

`hive_flutter`는 pubspec.yaml에 등록되어 있으나 현재 코드에서 사용되지 않음.

## 하네스: 부산 지하철 앱 개발

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
- **모델 차등 배치** — 판단 계층(아키텍처·리뷰) 3개는 **opus 4.7**, 구현 계층 4개는 **sonnet 4.5**. 각 에이전트 `.md` frontmatter의 `model:` 값이 소스 오브 트루스. Agent 호출 시 별도 `model` 파라미터를 넘기지 않으면 frontmatter가 적용됨.
- 코드 변경 후 반드시 subway-code-reviewer + subway-requirements-reviewer를 병렬 실행
- 중간 산출물: `_workspace/` 디렉토리

**모델 배치표 (토큰 비용 최적화):**

| 계층 | 모델 | 에이전트 |
|------|------|---------|
| 판단 (설계·리뷰) | **opus** | flutter-architect, subway-code-reviewer, subway-requirements-reviewer |
| 구현 (전문 코드/테스트) | **sonnet** | map-math-engineer, graph-algorithm-engineer, realtime-data-engineer, flutter-qa-engineer |

- 도메인 규칙(4원칙, 노선별 방향 로직, API 포맷)은 스킬 문서에 명시되어 sonnet이 가이드를 따라 구현 가능
- 판단 계층에서 리뷰 누락·아키텍처 오류 발생 시 sonnet으로 내리지 말 것 (품질 방어선)
- 구현 계층 sonnet이 규칙을 반복 위반하면 해당 에이전트만 opus로 승격

**1M 컨텍스트 활용 원칙:**
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
    ├── pending-data.md
    ├── svg-pipeline.md
    └── timetable.md
```

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-04-07 | 초기 구성: 7인 전문가 팀 하네스 | 전체 | 앱 개발 전문가 팀 구성 요청 |
| 2026-04-17 | Opus 4.7 (1M context) 대응: 전 에이전트 YAML frontmatter 추가(`model: opus`, name, description), 오케스트레이터에 "모델 및 컨텍스트 전략" 섹션 추가, CLAUDE.md에 1M 컨텍스트 활용 원칙 명시 | agents/*, skills/subway-app-orchestrator/SKILL.md, CLAUDE.md | Opus 4.7에 적합하게 하네스 설정 수정 요청 |
| 2026-04-19 | 요구사항 리뷰에 "버그 수정 회귀 검증 (6단계)" 추가: 판별 기준·회귀 위험 영역·대조군 시나리오 매트릭스, 출력 형식에 회귀 검증 섹션과 회귀 위험 등급 추가 | agents/subway-requirements-reviewer.md, skills/subway-requirements-review/SKILL.md | 버그 수정 시 기존 기능을 변경하지 않은 채로 버그만 수정했는지 확인 필요 피드백 |
| 2026-04-20 | 에이전트별 모델 차등 배치: 판단 계층(flutter-architect, subway-code-reviewer, subway-requirements-reviewer) opus 유지, 구현 계층(map-math-engineer, graph-algorithm-engineer, realtime-data-engineer, flutter-qa-engineer)을 sonnet으로 전환. 오케스트레이터 호출 예시에서 하드코딩된 model 파라미터 제거 (frontmatter 기반). CLAUDE.md에 모델 배치표 추가 | agents/*, skills/subway-app-orchestrator/SKILL.md, CLAUDE.md | 에이전트·스킬별 적절한 모델로 토큰 사용량 최적화 요청 (약 45% 비용 절감 기대) |
| 2026-07-05 | 하네스 재점검(운영 감사): (1) map-math-engineer.md·subway-map-math SKILL.md에 4원칙 누락 발견 및 추가 — 특히 subway-map-math의 기존 "경로 보간" 예시가 원칙 2(전방 보간 금지)를 정면 위반하는 내용이라 estimateTrainPosition 역산 방식으로 전면 수정. (2) realtime-data-engineer.md·realtime-tracking SKILL.md에 원칙 1(receivedAtEpochMs 계약) 추가. (3) subway-code-reviewer.md·subway-code-review SKILL.md 체크리스트에 4원칙 위반 최우선 확인 항목 추가. (4) flutter-qa-engineer.md·subway-testing SKILL.md에 estimate_train_position_test.dart를 4원칙 회귀 가드로 명시. (5) map-math-engineer.md/realtime-data-engineer.md/realtime-tracking SKILL.md의 `lib/features/subway_map/{widgets,providers}/...` 경로를 실제 경로 `lib/features/subway_map/presentation/{widgets,providers}/...`로 수정. (6) subway-app-orchestrator SKILL.md의 프로젝트 루트 예시 경로가 구 경로(`/Users/april/Idea/seoul_subway`)로 남아있던 것을 현재 경로로 수정, 모델 승격 기준에 "4원칙 자체 변경은 사용자 승인 사안(모델 승격 아님)" 명시 | agents/map-math-engineer.md, agents/realtime-data-engineer.md, agents/subway-code-reviewer.md, agents/flutter-qa-engineer.md, skills/subway-map-math/SKILL.md, skills/realtime-tracking/SKILL.md, skills/subway-code-review/SKILL.md, skills/subway-testing/SKILL.md, skills/subway-app-orchestrator/SKILL.md | "하네스를 재점검해줘" 요청에 따른 Phase 7-5 운영 감사 — CLAUDE.md 최상위 정책(4원칙)이 정작 이를 구현하는 map/realtime 에이전트·스킬 문서에는 반영되지 않았고, 스킬 예시가 금지된 알고리즘을 가르치고 있었으며, 경로 리팩토링(presentation/ 계층 도입)과 프로젝트 이전(Idea→StudioProjects) 이후 문서가 갱신되지 않은 드리프트 발견 |
| 2026-07-31 | 2차 리뷰 반영: (1) 단일 점 path 분기가 `arrivalSeconds` 양수에도 `minDistToEnd=0` 을 박아 '진입' 오보고 한 번으로 열차가 목표역에 **영구 고정**되던 신규 회귀 수정 — 실제 도착(`<=0`)일 때만 고정. (2) 같은 분기의 `lastRawArrival` 을 `posBaseArrival` 과 같은 0 으로 정렬(어긋나면 다음 refresh 가 stale 오판으로 `posRemaining=0` 을 물려받음). (3) 조기 continue 분기가 `lastRawArrival` 을 갱신하지 않는 이유를 주석화. (4) Dart 미러의 미사용 `nowMs` 파라미터 제거·JS 와의 미세 divergence 3건 주석화. (5) CLAUDE.md 에 "위치가 표시 숫자보다 앞설 수 있다" 한계 추가 | CLAUDE.md, tool/build_map_html.dart, assets/html/map.html(재생성), lib/core/utils/train_forward_guard.dart, test/core/utils/train_forward_guard_test.dart, test/tool/build_map_html_test.dart | subway-code-reviewer + subway-requirements-reviewer 2차 병렬 리뷰에서 MEDIUM 2건(동일 결함) 검출 |
| 2026-07-31 | 원칙 1 재정의 후속 리뷰 반영: (1) 위치 역산 입력을 표시용과 분리된 **기준쌍**(`posBaseArrival`/`posBaseReceivedAt`)으로 분리하고, `lastRawArrival` 비교로 **API 원본 값이 바뀐 refresh 에서만** 보정하도록 함(사용자 제안) — 초기 구현(가드 단독)은 API 가 같은 `arrivalSeconds` 를 `recptnDt` 만 갱신해 반복 보고하는 노선에서 열차가 무기한 정지하는 결함이 있었고, 중간안(더 늦은 도착이면 무조건 무시)은 실제 지연을 반영하지 못해 아이콘이 앞서 달리는 문제가 있었음. (2) `segDurations` 불일치 분기의 `path[0]`(경로 맨 뒤) 고정 제거 — 후퇴 순간이동이었음. (3) 단일 점 path 분기에서 `currentPos`/`minDistToEnd`/`pathEndKey`/`posBase*` 동기화 — stale `currentPos` 로 인한 후퇴 차단. (4) `distToEnd` NaN 방어. (5) 원칙 3 본문에 "원칙 1 가드가 상한을 override 할 수 있다" 명시, 원칙 1에 보장 범위(경로상 진행도)·`estimateCache` 예외·`ordkey` 폴백 한계 명시. (6) Dart 미러 `lib/core/utils/train_forward_guard.dart` + 동작 회귀 테스트 신설 | CLAUDE.md, tool/build_map_html.dart, assets/html/map.html(재생성), lib/core/utils/train_forward_guard.dart(신규), test/core/utils/train_forward_guard_test.dart(신규), test/tool/build_map_html_test.dart, agents/map-math-engineer.md, skills/subway-map-math/SKILL.md, skills/subway-testing/SKILL.md | subway-code-reviewer + subway-requirements-reviewer 병렬 리뷰에서 HIGH 3건 검출 |
| 2026-08-04 | **원칙 1-a 신설(사용자 지시)**: 표시용 남은시간도 위치와 같은 stale 필터를 쓰도록 전환. `adoptDisplayBase` 신설 — `lastDisplayRawArrival` 과 비교해 **API 원본이 바뀐 refresh 에서만** 표시 기준쌍(`baseArrival`/`baseReceivedAt`)을 채택하고, 같은 값이 2회 이상 반복 보고되면 새 `recptnDt` 를 무시한다. 나아가 `startTrainAnimation` 의 **위치 기준쌍 입력을 표시 기준쌍으로 상속**시켜 말풍선 0 과 아이콘 도착을 같은 시각으로 동기화. 부작용 방어로 (i) 도착 발동에 위치 일관성 조건(`atFinalLeg`) 추가, (ii) `arrivedTrains` 를 객체로 바꿔 **정상 도착은 `{final:true}` 로 영구 확정(요구사항 — 절대 부활 금지)**, 유령 도착만 `{raw:N}` 으로 기록해 원본이 바뀌면 복구, (iii) 페이드 중 부활 대비 `arrivalPlaying` 플래그. 1차 시도였던 `ARRIVAL_RAW_GATE_SEC`(원본으로 도착을 막는 게이트)는 사용자 의도와 충돌해 철회 | CLAUDE.md, tool/build_map_html.dart, assets/html/map.html(재생성), lib/core/utils/train_forward_guard.dart(`TrainDisplayBase`·`onRefreshFrom` 신설), test/core/utils/train_forward_guard_test.dart, test/tool/build_map_html_test.dart | 사용자 제보: 사당→방배 모니터링 중 도착 예정 초가 계속 늘어남. 실측 결과 열차가 사당 정차 중 `barvlDt=150` 이 1분 이상 고정된 채 `recptnDt` 만 ~16초씩 전진 → 표시 숫자가 톱니파. 사용자 지시: "barvlDt 가 같은값으로 2회차이면 recptnDt을 새값으로 채택하지 않아서 남은시간은 줄어들거고 열차도 그 남은시간에 맞춰서 도착하길 원한거야" |
| 2026-07-31 | **원칙 1 재정의(사용자 지시)**: "단조 감소 카운트다운" → "열차는 절대 뒤로 가지 않는다(위치 단조 전진)". 남은시간 숫자는 API 원본을 그대로 표시(재조회 시 증가 허용)하고, 대신 아이콘의 경로상 위치를 "경로 끝까지 남은 거리(`minDistToEnd`)" 기준으로 단조 전진 강제. JS 에서 단조 감소 clamp·`trainSlotMemory` 보조키·slotOccupancy·TTL sweep(약 100줄) 전면 제거, `startTrainAnimation` 에 `cumLen`/`pathEndKey`/`pointAtLength` + step() 단조 전진 가드 추가. CLAUDE.md 에 "원칙 적용 순서(2→3→1→4)" 섹션 신설 | CLAUDE.md, tool/build_map_html.dart, assets/html/map.html(재생성), lib/features/subway_map/presentation/providers/live_train_provider.dart(주석), lib/data/remote/dto/arrival_info_dto.dart(주석), test/data/remote/arrival_info_dto_test.dart(주석), agents/map-math-engineer.md, agents/realtime-data-engineer.md, agents/subway-code-reviewer.md, skills/subway-map-math/SKILL.md, skills/realtime-tracking/SKILL.md, skills/subway-code-review/SKILL.md, skills/subway-testing/SKILL.md | 사용자 요청: "남은 숫자는 API 재조회시 뒤로갈수있지만, 열차는 절대로 뒤로가지 않길 바라" — 숫자를 붙잡아 위치를 간접 보장하던 구조에서, 위치를 직접 보장하는 구조로 전환 |
| 2026-10-28 | **지도 편집기 3모드화**: `tool/badge_editor.dart` 에 `선분`·`환승마커` 모드 추가(정점·구간 드래그, 마커 위치·길이·방향). SVG 가 편집기의 쓰기 대상이 됨 — 저장 실패 시 원복·`svgRev` 낡은 탭 방어·12px(하드)/4px(소프트) 선로 이탈 경고·마커↔stations.json 드리프트(이동량 + 앵커 없는 마커 영속 배너 + CI 거리 분포 가드)·수동 배지 경고 승격 및 이동량 보고·연속 구간(런) 선택·중단 표식 시 저장 409 거부. **"SVG 수정 후 3단계 전부 재실행" 규칙을 "무엇을 고쳤나" 축으로 재정의**(path/rect 만이면 손이든 편집기든 3단계만, 1·2단계는 역 circle/라벨을 건드렸을 때만이고 그때도 stations.json 직접 패치 우선) | CLAUDE.md, .claude/docs/svg-pipeline.md, tool/badge_editor.dart, tool/badge_editor/{editor.js,editor.css,geometry.js}(신규), tool/geometry_svg.dart(신규), test/tool/geometry_svg_test.dart(신규) | 사용자 요청: 노선 선분과 환승 동그라미/알약을 옮길 수 있는 에디터. 리뷰에서 "마커 이동이 stations.json 과 조용히 어긋난다"·"문서가 파이프라인 전체 재실행을 지시한다" 검출 |
| 2026-07-22 | 원칙 4 문서 현행화(사용자 승인): 코드에 존재하지 않는 `JUMP_THRESHOLD_PX=20` 파라미터와 "stationChanged/headMoved>8px 시 currentPos=null 리셋" 예외 조항을 삭제하고, 실제 구현인 거리 기반 이중 반감기(≤30px→3초, >30px→0.5초, 0.5px 스냅, deltaMs 상한 100ms)로 기술을 교체. 섹션 제목을 "열차는 순간이동하지 않는다"로 평문화 | CLAUDE.md, tool/build_map_html.dart(헤더 주석), agents/map-math-engineer.md, skills/subway-map-math/SKILL.md | build_map_html.dart 전체 리뷰 중 원칙 4 문서-코드 드리프트 발견(HIGH). 코드는 원칙 의도를 충족하므로 문서를 코드에 맞춰 갱신 — 사용자 승인 완료 |
| 2026-10-28 | **2호선 성수지선 API 라벨 반전(사용자 결정 — 세 안 중 ⓑ)**: 도착 API `updnLine` 이 성수지선에서만 앱 `isDownBetween` 과 정반대인 것을 실측 확인(2026-10-28 15:54, 183질의. 양방향 모두 반대, 본선 35행 중 32·신정지선은 일치). 증상은 지도에서 탈 방향 열차가 전부 탈락하고 반대 방향이 통과 + 출발 시각에 반대 방향 열차의 실시간 값이 찍힘. **ⓐ 삼중 보정(규칙+시간표+환승가이드)을 쓰지 않은 이유**: 우이신설(41471aa)과 달리 성수지선은 시간표(`INOUT_TAG`)가 앱 규칙과 **이미 정합**이라(커밋 75b9e03 이 역방향 조회 버그를 고치며 맞춘 것) 규칙을 뒤집으면 그 버그가 되살아난다. 그래서 `isDownBetween` 은 0줄 두고 `isApiLabelReversedBetween`/`apiLabelReversedForTrain` 으로 **라벨 해석만** 뒤집었다. 판정 단위는 경로가 아니라 **열차의 접근 쌍** — 분기역 성수(211)는 본선 순환에도 쓰여 지선 집합에 넣을 수 없어, 경로 단위로 걸면 본선 열차까지 통과해 hop 상한 없는 `findPathOnLine` 이 순환 42정거장 경로를 잡아 엉뚱한 자리에 그린다. 위치 API(`realtimePosition`)는 극성이 앱과 **이미 일치**해 폴백에는 반전을 걸지 않는다(실측 확인) | lib/core/utils/line_direction.dart, lib/features/subway_map/presentation/providers/live_train_provider.dart, lib/features/route_search/utils/departure_time_calculator.dart, test/core/utils/line_direction_api_label_test.dart, test/features/route_search/utils/departure_seongsu_label_test.dart(신규), test/features/subway_map/presentation/providers/live_train_seongsu_label_test.dart(신규), tool/check_api_direction_labels.dart(신규 — 드리프트 탐지기), .claude/docs/timetable.md, .claude/docs/lines-reference.md | 신설 탐지기 전 노선 실행에서 유일한 불일치로 검출. 우이신설처럼 **조용히 노후화**되던 건을 사용자 제보 전에 잡은 첫 사례다 |
