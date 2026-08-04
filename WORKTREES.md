# WORKTREES.md — 워크트리 작업 선언 & 중복 확인

여러 세션이 `.claude/worktrees/` 아래 각자의 워크트리에서 병렬로 작업한다. 워크트리 이름은
자동 생성(`clever-jackson-51af51` 등)이라 이름만으로는 무슨 작업인지 알 수 없다.

이 문서의 역할은 둘이다.

1. **작업 선언** — 어떤 워크트리가 무슨 작업을 하고 있고, 어느 파일·영역을 점유했는지 남긴다.
2. **중복 방지** — 새 워크트리를 만들기 전에 같은 작업이 이미 돌고 있지 않은지 확인한다.

## 편집 규칙

- **본 체크아웃(`/Users/april/StudioProjects/seoul_subway`)에서만 편집한다.** 워크트리 안에서는
  이 파일을 수정하지 않는다. 워크트리마다 사본을 갖게 되므로 양쪽에서 고치면 병합마다 충돌한다.
- **선언은 작업을 시작할 때 적는다.** 끝나고 적으면 중복 방지에 아무 쓸모가 없다 — 중복은 남이
  시작하려는 순간에만 막을 수 있다.
- **git 이 답할 수 있는 값은 표에 적지 않는다.** HEAD 해시, main 대비 ahead/behind, 변경 파일 수는
  적는 순간 거짓이 된다(이 문서를 처음 쓰는 동안에도 main 이 두 번 움직였다). 아래 명령으로 그때그때
  확인한다.

---

# 1. 현재 진행 중인 작업

브랜치는 따로 적지 않는다 — `claude/<워크트리 이름>` 이거나, `(detached)` 표시된 것은 브랜치가 없다.

| 워크트리 | 작업 | 점유 영역 | 상태 |
|---|---|---|---|
| `nifty-wilson-fb3384` | 급행 이중 모델 정리 (구 모델 제거) | 그래프/경로탐색 코어 + `connections.json` 급행 필드 + `compute_express_skip.py`(삭제) | 커밋 완료, **main 병합 대기** |

## `nifty-wilson-fb3384` — 급행 이중 모델 정리

`GraphEdge.expressWeightSeconds` 필드를 걷어내고, 급행 skip edge 를 따로 계산하던
`tool/compute_express_skip.py`(199줄)를 삭제하는 방향. 변경은 커밋됐고 main 도 받아들인 상태다
(작업 트리 클린). 남은 일은 main 병합.

점유 파일: `lib/graph/{graph_builder,subway_graph}.dart`, `lib/graph/models/graph_edge.dart`,
`lib/domain/entities/{connection,route_result}.dart`, `lib/domain/usecases/search_route.dart`,
`lib/features/route_search/presentation/screens/route_result_screen.dart`,
`lib/features/route_search/utils/departure_time_calculator.dart`,
`assets/json/connections.json`, `tool/compute_travel_times.dart`,
`tool/compute_express_skip.py`(삭제) + 각 테스트.
신규 가드: `test/data/connections_no_express_asset_test.dart`.

**이 워크트리와 겹치기 쉬운 작업**: 경로탐색·환승·급행 소요시간에 손대는 모든 작업. 그래프 코어를
넓게 점유하고 있으므로, 병합 전까지는 `lib/graph/` 와 `search_route.dart` 를 건드리는 새 작업을
시작하지 않는 편이 낫다.

**현재 파일 겹침 없음** (2026-08-03 스캔). 직전까지 있던 `connections.json` / 급행 skip 충돌은
수인선 작업이 먼저 main 에 병합되고 이쪽이 그 main 을 받아들이면서 해소됐다 — "인접한 작업은
병합 순서를 먼저 정한다"(2-3단계)가 실제로 적용된 사례다.

---

# 2. 새 워크트리를 만들기 전 — 중복 확인

## 1단계 · 파일 점유 스캔 (기계적)

각 워크트리의 미커밋 변경 + main 에 없는 커밋을 합쳐, **어떤 파일이 누구에게 점유됐는지** 뽑는다.
여러 워크트리가 같은 파일을 잡고 있으면 `⚠겹침` 으로 표시된다.

```bash
cd /Users/april/StudioProjects/seoul_subway && git worktree list | tail -n +2 | awk '{print $1}' | while read p; do n=$(basename "$p"); { git -C "$p" -c core.quotepath=false status --porcelain | cut -c4- | sed 's/^.* -> //'; git -C "$p" diff --name-only main...HEAD; } | sort -u | sed "s|^|$n\t|"; done | awk -F'\t' '{o[$2]=o[$2]" "$1; c[$2]++} END{for(f in c) printf "%s\t%s\t←%s\n", (c[f]>1?"⚠겹침":"·"), f, o[f]}' | sort -k1,1r -k2,2 | column -t -s$'\t'
```

내가 건드릴 파일이 목록에 있으면 그 워크트리와 겹친다.

**이 스캔의 한계 — 이것만 믿으면 안 된다.** 아직 파일을 저장하지 않은 워크트리는 아무것도 잡히지
않는다. 방금 시작해서 조사만 하고 있는 세션, 곧 같은 파일을 열 세션은 스캔에 안 나온다. 그래서
2단계가 필요하다.

## 2단계 · 선언 대조 (사람의 판단)

위 **"1. 현재 진행 중인 작업"** 의 `작업` / `점유 영역` / 각 절의 "겹치기 쉬운 작업" 을 읽고, 하려는
일이 이미 선언된 작업과 같은 영역인지 본다. 파일 이름이 안 겹쳐도 같은 도메인이면 겹침이다 —
예: 역 순서를 고치는 두 작업은 서로 다른 노선을 만져도 결국 같은 에셋을 재생성한다.

특히 다음 영역은 **파일이 달라도 충돌로 취급**한다.

- `assets/json/*` 재생성 — 다단계 산출물이라 서로의 결과를 덮어쓴다(아래 규칙).
- `lib/graph/` + `search_route.dart` — 경로탐색 코어. 한 작업이 넓게 점유한다.
- `tool/build_map_html.dart` / 실시간 열차 애니메이션 — CLAUDE.md 4원칙 영역. 두 세션이 동시에
  만지면 원칙 위반을 서로 못 알아본다.

## 3단계 · 겹치면 판단

| 상황 | 조치 |
|---|---|
| **같은 작업** | 새로 만들지 말고 기존 워크트리에서 계속한다. 그 워크트리가 detached HEAD 면 먼저 `git switch -c <브랜치>`. |
| **인접한 작업** (같은 파일, 다른 목적) | 병합 **순서를 먼저 정한다.** 선행이 main 에 들어간 뒤 후행이 main 을 받아 다시 얹는다. 동시에 진행할 거면 표의 상태 칸에 "`<상대>` 뒤에 병합" 이라고 적어둔다. |
| **무관** | 진행. 4단계로. |

## 4단계 · 등록하고 시작

워크트리를 만들었으면 **바로** 위 표에 한 줄 추가한다(작업 한 줄 + 점유 예정 영역). 이게
다음 사람의 2단계 입력이다.

커밋되지 않는 산출물이 둘 있어서, 새 워크트리는 "깨끗한데 빌드는 안 되는" 상태로 시작한다.
`flutter test` 전에 먼저 처리한다. 여기서 나는 컴파일 에러를 코드 회귀로 오진하지 말 것.

```bash
cp /Users/april/StudioProjects/seoul_subway/.env . && dart run build_runner build
```

- `.env` 미복사 → `No file or variants found for asset: .env`
- `build_runner` 미실행 → `*.freezed.dart` / `*.g.dart` 부재로 `The getter '...' isn't defined` 류 에러

## 에셋은 한 번에 한 워크트리만

`assets/json/{stations,connections,express_skip_edges,line_schedules}.json` 은 SVG·시간표·공식
데이터셋을 거친 **다단계 산출물**이다. 두 워크트리가 각자 파이프라인을 재실행하면 서로의 결과를
덮어쓰고, 텍스트 병합으로는 복구되지 않는다. 또 `generate_station_data.dart` 단독 재실행은
파괴적이다(CLAUDE.md 의 SVG 데이터 파이프라인 절 참조).

→ 에셋 재생성 작업은 **직렬로** 진행한다. 이미 선언된 에셋 작업이 있으면 그게 병합될 때까지
기다리거나, 같은 워크트리에 합쳐서 한다.

---

# 3. 상태 확인과 정리

## 상태 새로고침

```bash
cd /Users/april/StudioProjects/seoul_subway && echo "main = $(git rev-parse --short main)" && git worktree list | tail -n +2 | awk '{print $1}' | while read p; do n=$(basename "$p"); printf "%-34s HEAD=%-9s ahead=%-3s behind=%-3s dirty=%-3s %s\n" "$n" "$(git -C "$p" rev-parse --short HEAD)" "$(git -C "$p" rev-list --count main..HEAD)" "$(git -C "$p" rev-list --count HEAD..main)" "$(git -C "$p" status --porcelain | wc -l | tr -d ' ')" "$(git -C "$p" log -1 --format='%s' | cut -c1-40)"; done
```

읽는 법:
- `ahead=0 behind=0 dirty=0` → main 과 동일하고 변경 없음. **정리 대상**(또는 새 작업에 재사용).
- `ahead=0` + `dirty>0` → 커밋 안 된 진행 중 작업. 지우면 유실된다.
- `ahead>0` → main 에 아직 안 들어간 커밋 보유. 병합 전에는 지우면 안 된다.
- `(detached HEAD)` → 브랜치 없이 특정 커밋에 붙어 있음. 여기서 커밋하면 어느 브랜치에도 안
  달리므로, 작업을 재개하려면 먼저 `git switch -c <새 브랜치>`.

**표에 없는데 스캔에 뜨는 워크트리 = 선언 안 된 작업.** 발견하면 소유 세션을 찾거나, 위 새로고침으로
`dirty`/`ahead` 를 확인해 표에 등록하거나 정리한다.

## 정리 대상 (2026-08-03 확인)

작업이 끝나 main 에 들어갔고 변경도 없다. 새 작업에 재사용하거나 지운다.

- `youthful-poincare-cfe04c` — 수인선 소래포구~연수 역 순서 교정. main 에 병합됨
  (`940f69a`), `ahead=0 behind=0 dirty=0`. 이 워크트리를 쓰던 세션이 끝났으면 제거 가능.

병합 완료된 4개(`clever-jackson-51af51`, `kind-goldstine-9e1b50`, `nice-solomon-0f1dd7`,
`optimistic-brahmagupta-cf6c52`)는 2026-08-03 제거했다. **브랜치 `claude/<이름>` 4개는 남아 있다**
— 전부 main 에 포함된 상태이므로 아래 절차로 지울 수 있다.

## 제거 절차

**지우기 전에 위 새로고침으로 `ahead=0 dirty=0` 을 반드시 확인한다** — `ahead>0` 이면 main 에 없는
커밋이, `dirty>0` 이면 커밋 안 된 작업이 함께 사라진다.

```bash
cd /Users/april/StudioProjects/seoul_subway && git worktree remove .claude/worktrees/<이름> && git worktree prune
```

- 디렉토리를 손으로 `rm -rf` 하면 등록 정보가 남는다. 그 경우 `git worktree prune`.
- 워크트리를 지워도 브랜치는 남는다. 정리하려면 `git branch -d claude/<이름>`
  (병합 안 된 브랜치는 `-d` 가 거부한다 — 그게 안전장치다).
- 정리했으면 이 문서에서 해당 항목을 지운다.

---

## 갱신 이력

| 날짜 | 변경 |
|---|---|
| 2026-08-03 | 최초 작성. 진행 중 작업 2건 선언, 새 워크트리 생성 전 중복 확인 4단계(점유 스캔 → 선언 대조 → 판단 → 등록), 에셋 직렬화 규칙, `connections.json`·급행 skip 실재 충돌 기록 |
| 2026-08-03 | 병합 완료 워크트리 4개 제거(`clever-jackson-51af51`, `kind-goldstine-9e1b50`, `nice-solomon-0f1dd7`, `optimistic-brahmagupta-cf6c52`) — 제거 전 전부 `ahead=0 dirty=0` 확인. 브랜치는 미삭제. 수인선 작업이 main 병합되어 `connections.json` 겹침 해소, `youthful-poincare-cfe04c` 는 정리 후보로 이동 |
