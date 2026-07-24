# 열차 시간표 (하이브리드: 역별 시간표 + 배차간격 폴백)

`assets/json/line_schedules.json`에 23개 노선의 양방향 운행 스케줄을 컴팩트 JSON으로 보유한다:
- 노선별 상행(내선)/하행(외선) 첫차·막차 시간
- 시간대별 배차간격 (첨두 06:30-09:00/16:30-19:30, 비첨두, 심야)
- 하행 전용 배차간격이 상행과 다를 경우 `pD` 키로 별도 저장
- 역별 정확한 출발시각 목록이 있으면 `t` 키로 저장 (배차간격 대신 사용)

## 컴팩트 JSON 스키마

```json
{
  "id": "1",
  "wd": {
    "f": ["05:20","05:18"],
    "l": ["00:48","00:42"],
    "p": [["05:00","06:00",5],["06:00","09:00",4]],
    "t": {
      "P01": [null, [330, 340, 350, 360]],
      "P05": [[335, 345, 355], [328, 338, 348]]
    }
  },
  "we": { ... }
}
```
- `id` = lineId, `wd` = 평일 (필수), `we` = 주말 (옵셔널, 없으면 `wd`와 동일)
- `f` = firstTrains [상행/내선, 하행/외선], `l` = lastTrains [상행/내선, 하행/외선]
- `p` = 공유 배차간격 [[시작,종료,배차분]], `pD` = 하행 전용 배차간격 (상이할 경우만)
- `t` = 완행 역별 시간표 (옵셔널). `stationId → [상행출발분목록, 하행출발분목록]`
  - 각 목록은 자정 기준 분(minute) 단위 정렬된 정수 배열 (예: 330 = 05:30)
  - 자정 이후 출발은 1440+ (예: 24:49 → 1489)
  - `null`은 해당 방향 출발 없음 (종착역 등)
  - `t`가 없는 역은 `p` 배차간격으로 폴백
- `tE` = 급행 역별 시간표 (옵셔널, 구조는 `t`와 동일). 급행 미정차역은 키가 없다.
  - 급행이 역을 통과하는 노선(9호선)에서 완행(`t`)과 분리 저장한다. 한 배열로 합치면
    급행 미정차역에 급행 출발시각이 섞이는 오류가 생기기 때문.
  - 급행 모드(`{base}E` 가상 노선) 라우팅 시 `findNextDeparture(express: true)`가 `tE`만 조회하며,
    해당 역 급행 데이터가 없으면 완행과 섞지 않고 배차간격으로 폴백한다.
  - 파싱: `DaySchedule.expressStationDepartures` (완행은 `stationDepartures`)
- 상하행 첫차/막차가 동일하고 `pD`/`t`/`tE` 없으면 하행 데이터는 상행으로 자동 폴백

## 역별 시간표 지원 노선

- **김포골드라인 (P01~P09)**: 구간운행(short-turn)이 있어 역별 배차간격이 다름. 9개 역 전체 평일/주말 시간표 포함.
  - 양촌(P01): 비첨두 ~18분 (전구간 운행만), 김포공항 부근: 비첨두 ~6분 (구간운행 포함)
  - 데이터 출처: korailinfo.com 역별 시간표
- **경의중앙선 (K01~K56)**: 급행/완행 혼합 운행으로 역별 정차 패턴이 다름. 56개 역 전체 평일/주말 시간표 포함.
  - 경의중앙선(용문↔문산) + 경의선(서울↔문산) 열차를 역별로 통합
  - K54(서울역)는 K24(효창공원앞)에서 분기하는 지선, 경의선 열차만 정차
  - K55(임진강), K56(운천)은 K01(문산) 이북 연장 구간, 하루 2~4편 운행
  - 데이터 출처: 코레일 시간표 엑셀 (`assets/excel/center_line260228.xlsx`)
- **서울교통공사 운영 노선 1·3~9호선**: 서울 열린데이터광장 API에서 역별 시간표 수집.
  - **1호선**: 100역 완행(`t`) + 급행 94역(`tE`). 1호선 급행은 급행분류(EXPRESS_YN=D) 열차 기준이며
    경원선/도심 구간에선 각 역 정차하므로 tE가 광범위. 완행모드는 `t`(G), 급행모드는 `tE`(D)로 분리.
    (`express_skip_edges.json`에 `1` 존재 → `1E` 라우팅 활성)
  - **3(44)·4(51)·5(56)·6(39)·7(53)·8(24)호선**: 전 역 완행(`t`)만. 급행 없음(`tE` 없음).
  - **9호선 (901~938)**: 38역 완행(`t`) + 급행 정차 16역(`tE`).
    급행 정차역: 902(김포공항) 905(마곡나루) 907(가양) 910(염창) 913(당산) 915(여의도)
    917(노량진) 920(동작) 923(고속터미널) 925(신논현) 927(선정릉) 929(봉은사)
    930(종합운동장) 933(석촌) 936(올림픽공원) 938(중앙보훈병원)
  - **⚠ 2호선(순환)은 이 API가 시간표를 제공하지 않아 미수집** → 배차간격 폴백 유지.
  - 방향 매핑: API `INOUT_TAG` 1=상행→`t` index0, 2=하행→index1. 전 노선에서 API 하행의 물리방향이
    앱 `isDownBetween`(하행)과 일치(1호선 남행=ID증가, 4호선 오이도=`_isLine4Down`, 9호선 개화=규칙반전 등).
  - **키잉 주의**: `t`/`tE` 키는 **앱 역ID**(stations.json id). 1~8호선은 API `FR_CODE`와 앱 역ID가
    다르므로(예: 종로3가 FR 130 vs 앱 131) 역명+노선으로 매칭 후 앱 역ID로 키잉한다.
    역명 표기차(예: 총신대입구(이수)→4호선 "총신대입구"/7호선 "이수")는 괄호제거/괄호내용 폴백으로 흡수.
  - 데이터 출처: 서울 열린데이터광장 `SearchSTNTimeTableByIDService` (OA-101),
    역코드는 `SearchInfoBySubwayNameService`. `.env`의 `SEOUL_GENERAL_API_KEY` 사용.
  - `we`는 WEEK_TAG=3(일요일/공휴일) 데이터. **토요일(WEEK_TAG=2)은 미반영** — 컴팩트 스키마가
    주말 1종(`we`)만 지원하는 한계.
  - 재생성: `dart run tool/build_metro_timetable.dart` (기본 1,3~8) / `--lines=9` 등으로 노선 지정.
- **비(非)서울교통공사 노선 11개**: 공공데이터포털 `getTrainSch`로 수집.
  - 대상: 신분당(SB, 16역)·경춘(33, tE24)·공항철도(14)·수인분당(63, tE51)·신림(11)·
    에버라인(14)·인천2(24)·서해(12)·의정부(14)·우이신설(13)·GTX-A(9). 전부 누락 0.
  - **경춘**은 앱이 경강선 구간(삼동~여주, C25~C33)을 함께 묶어두어, `경춘선`+`경강선` 두 노선명을 조회.
  - **급행 tE**: 경춘(ITX)·수인분당(급행)은 `etrnYn=Y`를 tE로 분리 (`express_skip_edges.json`에 경춘·수인분당 존재).
    단 **주말 tE는 없음(`we.tE` 빔)** — getTrainSch가 주말 열차를 전부 `etrnYn=N`으로 제공(급행 플래그 미부여).
    주말 급행 라우팅은 배차간격으로 graceful 폴백(오답·크래시 없음). 데이터 소스 특성이며 tool 버그 아님.
  - **방향 반전 3노선(공항철도·의정부·우이신설)**: getTrainSch 하행 라벨이 앱 `isDownBetween`(상행)에
    해당하므로 뒤집어 저장(하행→idx0, 상행→idx1). 공항철도는 앱이 하행=서울역 방면(ID감소)으로 반전,
    의정부·우이신설은 앱 일반규칙(ID증가=하행)이 getTrainSch 하행과 반대 방향. 나머지 8개는 정합(하행→idx1).
    검증: 공항철도 서울역(A01) 상행154/하행0, 인천공항2터미널(A14) 상행0/하행102.
  - 역명 표기차(예: 앱 `전대·에버랜드` → API `전대.에버랜드`)는 가운뎃점(·)/마침표(.) 정규화 폴백으로 흡수.
  - 요일: `wkndSe` 평일→`wd`, 주말→`we`. 데이터에 `crtrYmd`(기준일자)·`vldBgngDt`(유효시작일) 포함.
  - 데이터 출처: 공공데이터포털 `getTrainSch` (`apis.data.go.kr/B553766/schedule/getTrainSch`), `.env`의 `KOREA_API_KEY`.
  - 재생성: `dart run tool/build_gettrainsch_timetable.dart` (기본 11개 전체) / `--lines=SB,서해` 등 지정.
- **⚠ 역별 시간표 없는 노선(2개): 2호선·인천1호선** — 두 API(서울 열린데이터광장·getTrainSch) 모두
  데이터 미제공. 배차간격 폴백으로만 동작.

## 데이터 기준일 (재수집 필요 여부 판단용)

**최종 수집일: 2026-07-24.** 다음 갱신 시 아래 기준일과 비교해 변경 여부를 판단한다.

### getTrainSch 노선 — API가 기준일 필드 제공
응답 필드 `crtrYmd`(기준일자)·`vldBgngDt`(유효시작일)로 데이터 버전을 확인할 수 있다.
재확인: 해당 노선을 재조회해 `crtrYmd`가 아래보다 최신이면 재수집한다.

| 노선 | crtrYmd(기준일) | vldBgngDt(유효시작) |
|---|---|---|
| SB·경춘·공항철도·수인분당·신림·에버라인·의정부·우이신설 | 20250619 | 2025-05-01 |
| 인천2 | 20250811 | 2025-05-01 |
| GTX-A | 20250812 | 2025-05-01 |
| 서해 | 20250619 + **20251208** | 2025-05-01 + **2025-12-01** |

- ⚠ **서해선**은 현행(2025-05-01)과 예정(2025-12-01) 두 유효기간이 함께 수집됨. 2025-12-01 이후엔
  구(舊)기간 열차가 섞여 있을 수 있으니 재수집 권장(현재는 양쪽 병합, 다음 출발 계산엔 큰 영향 없음).

### 서울교통공사 노선 (1·3~9호선) — API에 기준일 필드 없음
`SearchSTNTimeTableByIDService` 응답엔 시행일/기준일 필드가 없다. 대신 데이터셋 포털의 갱신일로 판단:
- OA-101 데이터 갱신일: **2026-07-23** 확인 (갱신주기: 비정기/자료변경시)
- 재확인: https://data.seoul.go.kr/dataList/OA-101/A/1/datasetView.do 의 "데이터 갱신일"이
  위보다 최신이면 재수집(`dart run tool/build_metro_timetable.dart`).

### 정적 배차간격(경의중앙·김포골드 등)
경의중앙은 코레일 엑셀(`assets/excel/center_line260228.xlsx`, 파일명 260228=시행일), 김포골드는
korailinfo.com 기준. 원본 갱신 시 각 생성 도구 재실행.

## 방향 결정 로직 (`direction_resolver.dart`)

- `RouteSegment`의 역 ID 순서로 방향 판별
- 일반 노선: ID 증가 = 하행(index 1), ID 감소 = 상행(index 0)
- 2호선 순환: 첫 두 역 ID 비교 + 순환 경계(201↔243) 처리

## 출발시각 계산 우선순위

1. 실시간 도착정보 API (가장 정확, 방향 필터 적용)
2. 역별 시간표 (이진탐색으로 다음 출발시각 반환, `t` 키 데이터)
3. 배차간격 기반 시간표 추정 (방향별, 역별 시간표 없는 노선)
4. 현재 시각 폴백 (운행 시간 외이거나 데이터 없음)

## 핵심 함수

- `findNextDeparture()` — `lib/domain/usecases/find_next_departure.dart`: 역별 시간표(이진탐색) 또는 배차간격으로 다음 출발 시각 계산 (`isDown`, `stationId`, `express` 파라미터). `express=true`면 급행 시간표(`tE`/`expressStationDepartures`)만 조회.
- `computeDepartureTime()` — `lib/features/route_search/utils/departure_time_calculator.dart`: 실시간 + 시간표 통합 계산 (방향 자동 결정, `stationId` 전달)
- `computeSegmentDepartures()` — 환승역에서도 방향별 시간표 기반 출발시각 계산 (`stationId` 전달)
- `isDownDirection()` — `lib/features/route_search/utils/direction_resolver.dart`: RouteSegment에서 하행/외선 여부 결정

## 데이터소스

- `TimetableDataSource` (`lib/data/local/timetable_data_source.dart`): 컴팩트 JSON 파싱 (레거시 포맷 호환, `t` 키 역별 시간표 파싱)
- `timetableProviders` (`lib/features/route_search/presentation/providers/timetable_providers.dart`): Riverpod 프로바이더

## 시간표 재생성

```bash
dart run tool/extract_schedules.dart
# → assets/json/line_schedules.json (양방향 컴팩트 포맷)

# 김포골드라인 역별 시간표 변환 (수동 데이터 갱신 시)
dart run tool/build_gimpo_json.dart
# → line_schedules.json의 김포골드 항목에 't' 키 갱신

# 경의중앙선 역별 시간표는 Python으로 엑셀에서 추출
# assets/excel/center_line260228.xlsx → line_schedules.json의 경의중앙 항목에 't' 키 갱신

# 서울교통공사 운영 노선(1·3~9호선) 역별 시간표 — 서울 열린데이터광장 API에서 수집
dart run tool/build_metro_timetable.dart            # 기본: 1,3,4,5,6,7,8
dart run tool/build_metro_timetable.dart --lines=9  # 특정 노선만 (예: 9호선)
# → line_schedules.json의 해당 노선 wd/we에 't'(완행)/'tE'(급행) 역 단위 병합
#   (2호선은 API 미제공으로 제외)
```
