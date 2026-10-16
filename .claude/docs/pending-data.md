# 보류 데이터 — 개통/확인 시 복구할 것

미개통 노선이나 근거 부족 때문에 **일부러 비워 둔** 데이터와 그 복구 절차를 모은다.
"왜 이렇게 돼 있지?" 를 다시 조사하지 않도록, 결정 시점·근거·되돌리는 법을 함께 적는다.

기본 방침은 여전히 **"미개통 데이터는 경로·실시간에 영향 없으면 그대로 둔다"** 이다.
아래는 그 방침의 예외 — 미개통인데 **화면에 잘못 드러나** 사용자가 이상하게 여긴 건들이다.

---

## 1. 평택지제 — GTX-A 환승 표시 해제 (2026-10-16, 사용자 결정)

### 현재 상태
`평택지제`(id `187`, 1호선)는 `isTransfer: false`, `transferLines: ["1"]`.

### 왜 뺐나
원래는 `transferLines: ["1", "GTX-A"]` 였는데 **`평택지제_GTX-A` Station 레코드가 없었다**
(GTX-A 평택 연장 미개통). 그 결과:

- 환승 엣지는 **생기지 않는다** — `GraphBuilder._addTransferEdges` 는 같은 이름의
  `isTransfer` 역을 묶어 만드는데, 짝이 될 GTX-A 레코드가 없으니 묶일 게 없다.
- 그런데 **지도는 환승역으로 강조했다** — 줌아웃 라벨 2단(tier) 정책이
  `stations.json` 의 `isTransfer` 만 보고 `tl-major` 를 붙이기 때문.
- 역 선택기·경로 결과 화면에도 환승 표식이 붙었다.

즉 **"환승이라고 표시만 하고 실제로는 환승이 안 되는"** 유령 배지였다.
사용자가 "평택지제 역은 왜 줌아웃때 강조되지?" 라고 물어 드러났다.

선택지 ⒜ 현상 유지 / ⒝ 강조 해제 / ⒞ GTX-A 레코드 추가 중 **⒝** 를 택했다.

### 개통 시 복구 절차
GTX-A 평택 연장이 개통하면 ⒞ 로 전환한다. 순서:

1. `tool/generate_station_data.dart`
   - GTX-A 역 목록에 평택지제 `StationData` 추가 (ID 는 `G0x` 대역 — **기존 ID 재배정 금지**,
     물리 순서와 어긋나면 `lib/core/utils/line_direction.dart` 의 `_stationRanks` 보정 필요.
     에버라인 `E15`·의정부 `U15` 가 같은 사례다)
   - 1호선 `187` 평택지제에 `isTransfer: true, transferLines: ['1', 'GTX-A']` 복원
   - GTX-A 체인 연결(동탄↔평택지제) 추가
2. `assets/json/{stations,connections,lines}.json` 을 **직접 패치** — 이 generator 단독
   재실행은 파괴적이다(785역만 생성, 실제 산출물은 793역). 자세한 이유는
   `.claude/docs/svg-pipeline.md` 와 MEMORY `station-data-pipeline-drift`.
3. `dart run tool/build_transfer_times.dart`
   — `_nonOfficialCurated` 의 `'평택지제_1_GTX-A': 300` 은 **지우지 않고 남겨 뒀다.**
   필요 키 집합이 `transferLines` 에서 도출되므로, 1번에서 복원만 하면 이 값이 자동으로 다시 쓰인다.
4. `dart run tool/build_map_html.dart` — `tl-major` 가 1 늘어난다(복구 시 121).
5. `flutter test test/graph/graph_connectivity_test.dart` — 고립 컴포넌트 0 유지 확인.
6. 원본 SVG 에 GTX-A 선이 평택지제까지 그려지는지 확인
   (현재 SVG 라벨은 `data-line="2-1"`(1호선) 1개뿐 — 환승역은 라벨 1개가 관례라 추가 불필요).

### 같은 유형인데 **정상**인 역 (건드리지 말 것)
`구성`(수인분당+GTX-A), `성남`(경강+GTX-A), `수서`(3+수인분당+GTX-A) 는 GTX-A 쪽
Station 레코드가 **존재**한다(수서~동탄 개통 구간). 실제 환승 엣지가 생기므로 강조가 맞다.
`tool/audit_transfer_stations.py` 의 "소속 노선 Station 레코드 누락" 감사로
같은 결손을 다시 찾을 수 있다 — 이 건을 처리한 뒤로는 0건이어야 한다.

---

## 2. 기흥 환승소요시간 210초 — 공칭값을 반으로 깎은 값 (2026-10-16)

`transfer_times.json` 의 `기흥_수인분당_에버라인: 210`.
원래 근거는 공식 "서울 도시철도 환승정보" CSV 954·955행의 **07:00 = 420초** 였는데,
**하차/승차 위치가 서로 다른데(1호차3문 → 1호차2문 / 4호차4문) 소요시간이 둘 다 07:00**
이라 실측이 아닌 공칭값으로 판단했다. 역방향(에버라인→수인분당) 행은 CSV 에 아예 없다.
대조로 회룡은 4행이 205·243·320·415초로 전부 달라 실측의 모습을 하고 있다.
**2026-10-16 사용자 지시로 420 → 210(절반)으로 낮췄다.** 이 역시 측정값이 아니다.

- **영향**: 기흥은 에버라인의 유일한 관문이라 **경로 선택은 바뀌지 않는다.**
  표시되는 총 소요시간만 최대 3~4분 부풀 수 있다.
- **복구 조건**: 현장 실측 제보. `tool/build_transfer_times.dart` 의 `_nonOfficialCurated`
  주석에 근거가 남아 있으니 값만 갱신하면 된다.

---

## 3. 에버라인 기흥→강남대 120초 — 추정값 (2026-10-06)

에버라인은 `getTrainSch` 시간표 API 미지원이라 `data/timetables/` 캐시가 없다.
실제 노선 연장과 인접 구간(강남대→지석 150초)에 맞춰 잡은 **추정치**다.
(생성기의 경전철 위경도는 개략값이라 거리 기반 자동 계산을 쓸 수 없다 — 4km 넘게 나온다.)
캐시를 확보하면 `tool/compute_travel_times.dart --line=에버라인` 으로 재실측할 것.
같은 이유로 `line_schedules.json` 의 역별 시간표(`t`)에도 `E15` 가 없어 **배차간격 폴백**을
탄다. 대조로 의정부 `U15`(회룡)는 2026-10-16 에
`dart run tool/build_gettrainsch_timetable.dart --lines=의정부 --stations=U15` 로 실제
시간표를 넣었다 — 에버라인도 API 가 지원되면 같은 방법으로 채울 수 있다.
