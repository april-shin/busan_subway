# SVG 데이터 파이프라인

원본 SVG(`seoul_metro_map.svg`)에서 앱 에셋을 생성하는 3단계 파이프라인:

```bash
# 1단계: SVG에서 역 좌표 추출
dart run tool/extract_svg_stations.dart
# → assets/json/svg_station_coords.json (653개 역의 SVG 좌표)

# 2단계: 역/노선/연결 JSON 생성 (SVG 좌표 참조)
dart run tool/generate_station_data.dart
# → assets/json/stations.json, connections.json, lines.json, transfer_times.json

# 3단계: WebView용 HTML 생성 (SVG를 HTML에 인라인 삽입)
# 입력이 SVG 하나가 아니다 — 2단계 산출물 stations.json / lines.json /
# connections.json 을 모두 읽는다(아래 참조)
dart run tool/build_map_html.dart
# → assets/html/map.html
```

**중요:** 원본 SVG를 수정했다면 **무엇을 고쳤는가**로 돌릴 단계를 정한다. 누가·무엇으로 고쳤는가(손/지도 편집기)는 무관하다.

- **노선 `<path>` 와 환승 `<rect>` 만 고쳤다면 3단계(`build_map_html`)만 돈다.** 편집기(`tool/badge_editor.dart` 의
  선분·환승마커 모드)는 저장 때 자동으로 돌리고, 손으로 고쳤다면 직접 돌린다. 커밋 `2c73c10`(경춘선 흰 이중선 추가 — 전부 손 편집)과 `1a4f116`(선분·배지는 편집기, 왕십리 `<circle>`→`<rect>` 만 손)이
  둘 다 손 편집이고 3단계만 돌린 게 옳았던 사례다.
- **1·2단계는 역 `<circle>`·`<text data-station>` 을 추가·이동·삭제했을 때만 고려한다.** 그때도 `generate_station_data`
  단독 재생성은 파괴적이므로(역 소실·좌표 파손 전력. 메모리 `station-data-pipeline-drift`) **`stations.json` 직접 패치를 우선**한다.

⚠️ `extract_svg_stations` 는 `rx` 있는 rect 의 중심을 역 좌표 후보로 쓰므로, **환승 마커를 옮기면 SVG 와 `stations.json`
좌표가 어긋난 채 남는다**(경로 하이라이트·열차 아이콘이 옛 자리). 편집기는 경고만 하고 `stations.json` 을 고치지 않는다 —
마커를 옮겼다면 해당 역 `svgX/svgY` 를 직접 패치할 것. 어긋남은 **편집기 상단 배너(앵커 역이 없는 마커)에 저장 뒤에도 계속 표시**되고
(14px 넘게 옮긴 경우), `test/tool/geometry_svg_test.dart` 가 마커↔역 거리 분포(≤0.5px 54 · 0.5~14px 2(김포공항 12.0px · 왕십리 8.94px) · >14px 0)를
단언해 어느 거리든 커밋 전에 잡는다.
이 SVG 는 이제 편집기의 쓰기 대상이기도 하다(배지 모드는 `data/badge_offsets.json` 만 쓴다).

## SVG 좌표 추출 (`extract_svg_stations.dart`)

- SVG의 `<text data-station="역명">` 라벨과 가장 가까운 `<circle>` 좌표를 매칭
- 역명의 줄바꿈 문자 자동 제거 (SVG `<tspan>` 분할 역명 처리)
- 모든 `data-line` 값을 추출 (GTX-A `1-GA` 포함)

## HTML 빌드 (`build_map_html.dart`)

- **입력 4개 + 선택 1개**: `assets/svg/seoul_metro_map.svg` +
  `assets/json/stations.json` + `assets/json/lines.json` +
  `assets/json/connections.json`, 그리고 있을 때만 읽는
  `data/badge_offsets.json`(배지 수동 보정)
  (하나라도 없으면 빌드 실패. stations.json 에 `isTransfer=true` 인 역이
  하나도 없거나 항목에 문자열 `name` 이 없어도 실패한다 — 스키마가 바뀌었을 때
  라벨 2단 정책이 소리 없이 증발하는 것을 막는 게이트다). stations.json 은 역명 라벨의 2단(tier)
  분류에 쓰인다 — `isTransfer` 인 역의 라벨에만 `tl-major` 클래스를 붙여,
  줌아웃(scale<1) 시 **환승역 라벨만** 최소 크기 하한(`TEXT_COMP_FLOOR`)
  역보정을 받고 일반역은 지도와 함께 축소되게 한다(2026-09-22, 줌아웃 라벨
  겹침 컴플레인 대응). 재생성 시 `환승역(tl-major) N / 전체 M` 을 출력하고,
  stations.json 에 없는 `data-station` 이름은 stderr 로 경고한다.
  ⚠️ MEMORY `station-data-pipeline-drift` 대로 stations.json 은 직접 패치되는
  일이 있는 산출물이다 — `isTransfer` 를 손댔다면 이 도구를 재실행할 것.
- **`lines.json` + `connections.json`** 은 노선 이름 pill 배지(2026-10-06)에
  쓰인다 — 노선당 양 종점 2개씩 **총 48개 / 24개 노선**. 종점은 `stationIds`
  의 첫/끝이 아니라 **connections 그래프의 hop 지름 양 끝**으로 정한다(지선
  때문: 5호선에서 유클리드 최원점을 쓰면 마천이 하남검단산을 이긴다). 배지
  색은 `lines.json` 의 `colorValue` 가 아니라 **SVG path 의 stroke** 에서
  가져온다 — 둘은 대부분 다르고 경강·경춘은 정반대 값이다. 배지 **문구**도
  `lines.json` 의 `name` 이 기본이지만 `kLineBadgeNames` 에 항목이 있으면 그
  축약명이 우선한다(현재 김포골드라인 → "김포골드" 하나). 글자색은 WCAG
  상대휘도로 판정해 흰 글씨 대비가 3.0 미만인 노선만 짙은 글씨를 쓴다(현재
  수인분당·6호선·인천2). 배지는 줌아웃 보정을 받지 않는다 — 환승역 라벨만
  받는다(사용자 결정, 2026-10-06). 구현은 `tool/line_badges.dart` +
  `tool/line_badges_support.dart`(part).
- ⚠️ **이 도구는 입력이 어긋나면 조용히 틀리는 대신 빌드를 실패시킨다.**
  의도된 하드페일이다. 역/노선을 추가·수정한 뒤 지도 빌드가 깨지면 버그가
  아니라 아래 검증 중 하나에 걸린 것이다:
  - `stations.json` 에 `isTransfer=true` 인 역이 하나도 없거나 항목에 문자열
    `name` 이 없음 (라벨 2단 정책이 소리 없이 증발하는 것을 막는 게이트)
  - `lines.json` 의 노선 id 집합이 `kLineIdToDataLine`(`tool/line_badges.dart`)
    과 불일치, 또는 SVG `data-line` 코드 집합과 불일치
  - 노선 역들이 해당 `data-line` 선 위에 놓이는 비율이 하한 미달
  - 구간이 끊긴 노선(GTX-A 등)에 `kBadgeTerminalOverrides` 항목이 없음
  - `data-line` path 에 M/L 외의 명령(C/Q/A/Z)이 등장
  - **미해결 배지 1개 이상** — 앵커(노선 선 끝점)에서 **24px 이내**에 하드 위반
    없는 자리를 못 찾은 배지가 있음. 하드 위반 6종: 타 노선 선 위 / 역명 라벨
    (f=1.0·1.5) / 역 circle / 환승역 rect / 다른 배지 / 캔버스 이탈(여백 3px).
    ⚠️ **배지↔종점 연결선(줄기)은 없다**(사용자 결정 2026-10-06). 줄기(2.5px)가
    노선 선(3px)과 굵기·색이 같아 화면상 **존재하지 않는 지선**으로 읽혔다.
    따라서 pill 을 멀리 보내 해결하는 길이 막혀 있다. `kLineBadgeNames` 축약은
    **사용자 승인 사안**이므로 빡빡하다고 임의로 늘리지 말 것 — 한때 앵커 상한을
    16px 로 잡고 "2호선"→"2호" 까지 줄였다가, 다른 노선이 전부 "N호선" 인데
    혼자 표기가 깨져 철회하고 상한을 24px 로 올렸다(그쪽이 겹침도 더 좋다).
  - **배지 문구 중복** — 두 노선의 배지 문구가 같음(공백 제거 후 비교)
  - **배지 문구가 실제 역명과 같음** — stations.json 역명 또는 SVG 역명 라벨과
    충돌. 배지가 역명 라벨로 오독되는 것을 막는다(그래서 의정부경전철은
    "의정부" 로 줄일 수 없다 — 의정부역 실존). 상세: `.claude/docs/lines-reference.md`
  실제 사례: 에버라인에 기흥(E15)을 추가하자 배지 종점이 기흥으로 바뀌었다.
  매핑·종점 진단은 `LINE_BADGE_VERBOSE=1 dart run tool/build_map_html.dart`
  로 노선별 마진과 48개 배지의 앵커·방향을 전수 확인할 수 있다.
- **배지 수동 보정 `data/badge_offsets.json`**(선택, 커밋 대상). 드래그 에디터
  `dart run tool/badge_editor.dart`(localhost:8765, `.claude/launch.json` 의
  `badge-editor`)로 만든다 — **직접 편집하지 말 것.** 키는 `노선id|종점역명`,
  값은 앵커 기준 오프셋 `{dx,dy}`. 보정된 배지는 자동 배치를 건너뛰고 장애물로만
  쓰이며, 하드 위반이어도 **경고만** 내고 빌드는 계속한다(자동 배치 배지는 종전대로
  실패). 파일이 없거나 비면 산출물이 바이트 동일하다. 파일 문법/version 오류는
  빌드 실패, 항목 단위 오류·키 불일치는 경고 + 자동 배치 폴백.
- 배지 모듈 구성: `tool/line_badges.dart`(본체) + `tool/line_badges_support.dart`
  (part) + `tool/line_badges_offsets.dart`(part, 보정 포맷·`check()`).
  **하드 위반 판정은 `_BadgePlacer._hard` 한 곳**이며 빌드·에디터가 공유한다 —
  두 벌로 갈라지면 화면과 빌드 결과가 달라진다.
- 테스트 규칙: 앵커 24px 같은 **자동 배치 품질 가드는 수동 배지를 제외**하고
  (`autoBadges()`) 검사한다.
- ⚠️ **SVG `data-line` 코드와 `lines.json` id 는 서로 다른 체계다.** 머리글자로
  추측하면 틀린다 — `G`=경춘, `KK`=경강, `U`=의정부, `W`=우이신설,
  `2-1`=1호선(접두 숫자가 1 크다), 신분당선 id 는 `SB`. 정본은
  `kLineIdToDataLine` 이고, JS 런타임의 `lineIdToDataLine` 도 이 상수에서
  생성된다(단일 소스).
- 원본 SVG를 HTML 템플릿에 인라인 삽입
- SVG 최소 변환: `width="100%" height="100%"` → `width="2416" height="1560"`, `style="background: white;"` 제거
- JS로 줌/팬, 탭 감지, 경로 하이라이트, 마커, 툴팁 기능 구현
- 오버스크롤 여백: 상하좌우 70px (`clampTranslation` 함수)

## JS 성능 패턴 (저사양 기기 대응)

- **rAF 스케줄링**: `pointermove`/`wheel`/`resize` 이벤트에서 `scheduleTransform()` 사용. `rafPending` 플래그로 프레임당 1회만 `applyTransform()` 실행. 초기화(`setInitialView`)나 애니메이션(`panTo`)에서는 직접 `applyTransform()` 호출.
- **CSS 클래스 기반 강조/흐림**: 노선 강조 시 개별 `style.opacity` 대신 `.dimmed` CSS 클래스를 토글. `transition: opacity 0.3s`는 CSS에서 일괄 적용.
- **overlay circle 분리**: overlay 내부에서 생성하는 모든 `<circle>`에 `data-overlay` 속성 부여. 강조 처리 시 `circle:not([data-overlay])` 셀렉터로 원본 SVG circle만 대상. `closest()` DOM 탐색 불필요.

## SVG 스타일 규격 (원본 SVG 교체 시에도 유지해야 할 값)

| 요소 | 속성 | 값 | 비고 |
|---|---|---|---|
| 역이름 텍스트 (`<text>`) | `font-size` | `12px` | 인라인 스타일 |
| 역이름 텍스트 (`<text>`) | CSS `stroke` | `white`, `2px`, `paint-order: stroke` | `build_map_html.dart`의 `<style>` 블록에서 적용, 흰색 테두리 |
| 역이름 줄바꿈 | `<tspan>` | `dy="14"` | 띄어쓰기 포함 역이름은 `<tspan>`으로 분리 |
| 일반역 원 (`<circle>`) | `r` | `4.5` | |
| 환승역 원 (`<circle>`) | `r` | `5` | |
| 노선 경로 (`<path>`) | `stroke-width` | `3` | 2호선 제외 |
| 2호선 경로 (`data-line="3-2"`) | `stroke-width` | `4` | 순환+지선 |

## SVG data-line 매핑

노선 코드 매핑 테이블은 `.claude/docs/lines-reference.md`의 "SVG data-line 매핑" 섹션 참조.
