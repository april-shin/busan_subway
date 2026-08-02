#!/usr/bin/env python3
"""급행 정차역 간 skip edge를 추출하여 assets/json/express_skip_edges.json 생성.

알고리즘:
    1. 각 급행 운영 노선(`1`, `9`, `경춘`, `수인분당`)의 시간표 캐시를 읽음
    2. `etrnYn=='Y'`(급행) 열차의 (역, 출발시각, trainno, direction) 수집
    3. 같은 trainno로 묶어 정차 순서 구성 (시간 오름차순)
    4. 각 trainno의 인접 정차역 쌍 (A, B)의 시간 차 = skip 구간 소요시간
    5. 여러 trainno의 동일 쌍은 중앙값 채택
    6. 해당 쌍 사이의 완행 경로(연속된 역 ID)를 BFS로 찾아 skippedStationIds 기록
    7. 결과: {lineId: [{lineId, fromStationId, toStationId, seconds, skippedStationIds}, ...]}

실행:
    python3 tool/extract_express_skip_edges.py
"""
import json
import re
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / 'data' / 'timetables'
CONN_JSON = ROOT / 'assets' / 'json' / 'connections.json'
STATIONS_JSON = ROOT / 'assets' / 'json' / 'stations.json'
OUTPUT_JSON = ROOT / 'assets' / 'json' / 'express_skip_edges.json'
MANUAL_JSON = ROOT / 'tool' / 'manual_express_stops.json'

# 급행 운영 노선 — 자동 수집(시간표 API 기반) 대상.
#
# 1호선은 data.go.kr timetable API 가 `etrnYn='Y'` 열차에 대해 **모든 완행역에
# trainDptreTm 을 기록**하기 때문에 대방·신길·구일·개봉 등 통과역까지 자동
# 수집되어 사실상 완행과 같은 그래프가 된다(사용자 관찰: "급행 13역 / 완행
# 17역"). 따라서 1호선은 자동 수집에서 제외하고 `manual_express_stops.json`
# 기반 수동 매핑으로만 처리한다.
LINES = ['9', '경춘', '수인분당']

# 수동 매핑으로 skip edge 를 **강제 생성**할 노선.
#
# 여기에 있는 노선만 `_apply_manual` 이 동작한다. `manual_express_stops.json` 에
# 항목이 있어도 이 목록에 없으면 강제 생성하지 않는다 — 경춘·수인분당은 정차역
# 목록을 갖지만 그것을 **필터**로만 쓰기 때문이다(`_STOP_FILTER_LINES` 참조).
MANUAL_LINES = ['1']

# `manual_express_stops.json` 의 정차역 목록을 "강제 생성" 대신 **Y 편성 시퀀스
# 필터**로 쓰는 노선.
#
# 배경 — 경춘·수인분당은 1호선과 같은 함정에 빠져 있다. data.go.kr 시간표 API 가
# `etrnYn='Y'` 열차에 대해 **통과역까지 trainDptreTm 을 채워** 주기 때문에, 자동
# 수집이 전 역을 정차역으로 잡아 `skippedStationIds` 가 전부 빈 인접쌍이 된다.
# 그 결과 가상 노선 `경춘E`·`수인분당E` 가 완행의 복제본이 되어, 급행/완행 비교
# 탭이 실질적으로 같은 여정을 둘로 보여주고 있었다(경춘 22/22, 수인분당 55/55 가
# 통과역 0개였다).
#
# 다만 1호선과 달리 **시각 자체는 진짜 급행 시각이다.** 실측 교차검증:
#   · 편성 수 — 경춘 Y 5편성 = 공표 "평일 상행 2회·하행 3회". 수인분당 Y 는
#     분당 계열 14 + 수인 계열 8 = 공표 14 + 8.
#   · 소요시간 — 죽전→수원 Y 중앙값 23분 00초(n=14) = 공표 급행 23분.
#     같은 구간 N 중앙값 31분 30초(n=205) = 공표 완행 31분.
#   · 구간 전체 — 청량리→남춘천 Y 4620s vs N 5520s(15분 단축),
#     왕십리→수원 Y 4650s vs N 5190s(9분 단축).
# 즉 API 는 급행의 정차 **패턴**만 뭉갰고 시각은 보존했다. 따라서 Y 편성 시퀀스에서
# 통과역 레코드를 걸러내면, 남은 인접 정차쌍의 시간차가 그대로 **실측** 급행
# 소요시간이 된다 — 1호선처럼 `0.7 × 완행 합` 으로 근사할 필요가 없다.
#
# 정차역 목록의 근거는 `manual_express_stops.json` 의 각 항목 `_comment` 참조.
_STOP_FILTER_LINES = {'경춘', '수인분당'}

# 노선별 `MIN_FREQUENCY` 예외 — 기본값 3.
#
# 기본 3 은 "각 평일 시간표에 같은 trainno 가 1개씩 등장하므로 3편성 이상이면
# 임시열차가 아닌 정기 운행" 이라는 가정이다. 그런데 경춘선 급행은 **공표
# 운행횟수 자체가 평일 상행 2회·하행 3회**라서, 상행 전체가 이 문턱에 걸려
# 통째로 버려진다. 그러면 상행에만 나타나는 남춘천→춘천 이 빠져 `경춘E` 가
# 종점에 닿지 못한다(춘천행 경로가 남춘천에서 완행으로 갈아타야 한다).
#
# 캐시의 Y 편성 수가 공표 횟수와 정확히 일치하므로(상행 2 = K8402·K8404,
# 하행 3 = K8401·K8403·K8405) 2편성도 정기 운행이 확실하다. 이 노선만 2 로
# 내린다. 표본이 2개면 중앙값이 큰 값 쪽으로 치우치지만, 위의 완행 상한
# 클램프가 상한을 잡아 준다.
_MIN_FREQUENCY = {'경춘': 2}

# 수동 매핑에서 skip edge 의 seconds 를 완행 시간 합에 곱할 비율.
# 1호선 경인선/경부선 급행은 통상 완행 대비 65~75% 시간으로 운행.
#
# ⚠ 이 비율은 어디까지나 실측이 없을 때의 근사다. 실제 Y/N 비율은 구간마다
# 0.5~1.0 으로 흩어지며, 특히 skip 역이 0 개인 인접 구간은 급행도 완행과 같은
# 시간이 걸려 0.7 배가 명백히 틀린다. 실측이 가능한 구간은 아래
# `_CURATED_MANUAL_SECONDS` 로 고정한다.
MANUAL_EXPRESS_RATIO = 0.7

# 수동 매핑 skip edge 의 `seconds` 실측 고정값 — 재생성 안전장치.
#
# 배경: 과거 `assets/json/express_skip_edges.json` 이 생성기 출력과 어긋난
# 상태로 커밋돼 있었다(1호선 오산→평택 `861`, 재생성하면 `798`). `861` 은
# connections.json 의 해당 구간 완행 시간이 수기 갱신되기 전 값(합 1230)에
# 0.7 을 곱한 산출물이었다. JSON 만 고치면 다음 재생성에 원복되므로, 정답을
# **생성기 쪽에** 둔다. `tool/build_transfer_times.dart` 의
# `_nonOfficialCurated` 와 같은 취지.
#
# 키 형식: `{lineId}_{fromStationId}_{toStationId}` — 방향 무관(역순도 매칭).
# 값 출처: `data/timetables/1_*.json` (getTrainSch 캐시) 의 실제 급행 편성
#   K1902·K1904(상행) / K1945(하행) 3편성 구간 소요시간 중앙값.
#   척도는 `trainDptreTm` → `trainDptreTm`(출발시각 차) 로, connections.json 의
#   `travelTimeSeconds`(tool/compute_travel_times.dart 정의)와 같다. 종착역은
#   출발시각이 없으므로 `trainArvlTm` 으로 폴백한다 — 이 폴백을 빠뜨리면
#   서울역·천안 인접 구간에서 표본이 1~2개로 줄어 중앙값이 틀어진다.
#   원본 시각이 30초 격자라 값도 30초 배수다.
#
# ⚠ 한계 1 — 표본이 상행 2 + 하행 1 이라 상하행이 갈리는 구간에서는 중앙값이
#   사실상 상행 값이 된다. 24개 중 14개 구간이 상하행 60초 이상 벌어진다
#   (최대 90초: 노량진→영등포 하행 150 / 상행 240). skip edge 는 양방향 단일
#   가중치(`graph_builder.dart` 의 `addBidirectionalEdge`)라 구조적 한계다.
# ⚠ 한계 2 — 이 3편성이 경부선 급행 전체를 대표한다는 보장은 없다. "통과역엔
#   레코드가 없다"는 판별 신호는 캐시 커버리지에 의존하며, 실제로 경인선에는
#   같은 신호가 전혀 나타나지 않아(전 편성이 전 역 레코드 보유) 경인선 매핑은
#   미검증 상태다. 그래도 0.7 근사보다는 확실히 실측에 가깝다.
_CURATED_MANUAL_SECONDS = {
    # --- 1호선 경부선 급행 (통과역: 남영·대방·신길·신도림·구로·독산·관악·석수·명학·당정) ---
    '1_134_136': 270,   # 서울역→용산 (남영 통과). [210, 270, 270] — 하행 210 은
                        # dep→dep, 상행 270 은 dep→arv(서울역 종착)라 실제 상행
                        # dep→dep 는 270 이상. 방향차 60초 이상인 구간.
    '1_136_137': 150,   # 용산→노량진 (인접). 경인선 급행과 공유하는 구간.
    '1_137_140': 240,   # 노량진→영등포 (대방·신길 통과). 경인선 급행과 공유.
    '1_140_166': 540,   # 영등포→금천구청 (신도림·구로 통과)
    '1_166_170': 360,   # 금천구청→안양 (독산·관악·석수 통과)
    '1_170_172': 360,   # 안양→군포 (명학 통과)
    '1_172_174': 240,   # 군포→의왕 (당정 통과)
    # 의왕 이남은 급행도 전 역 정차 — 완행보다 정차시간(dwell)만큼만 빠르다.
    '1_174_175': 210,   # 의왕→성균관대
    '1_175_176': 180,   # 성균관대→화서
    '1_176_177': 120,   # 화서→수원
    '1_177_178': 240,   # 수원→세류. 완행 상한(210)에 걸려 실제 출력은 210 —
                        # 급행 편성이 수원에서 오래 정차해 중앙값이 완행을 넘음.
    '1_178_179': 210,   # 세류→병점
    '1_179_181': 180,   # 병점→세마
    '1_181_182': 150,   # 세마→오산대
    '1_182_183': 150,   # 오산대→오산
    '1_183_184': 210,   # 오산→진위
    '1_184_185': 150,   # 진위→송탄
    '1_185_186': 120,   # 송탄→서정리
    '1_186_187': 210,   # 서정리→평택지제
    '1_187_188': 210,   # 평택지제→평택
    '1_188_189': 450,   # 평택→성환. 완행 상한(420)에 걸려 실제 출력은 420 —
                        # 사유는 수원→세류와 같다.
    '1_189_190': 240,   # 성환→직산
    '1_190_191': 210,   # 직산→두정
    '1_191_192': 240,   # 두정→천안. [240, 240, 270] — 하행 240 은 천안이 종착이라
                        # trainArvlTm 폴백으로 잡힌 표본.
}


def _curated_seconds(line, a, b):
    """해당 skip edge 의 실측 고정값(없으면 None). 방향 무관."""
    return _CURATED_MANUAL_SECONDS.get(
        f'{line}_{a}_{b}',
        _CURATED_MANUAL_SECONDS.get(f'{line}_{b}_{a}'),
    )


def parse_sec(s):
    """HH:MM 또는 HH:MM:SS 문자열을 자정 기준 초 단위로 변환."""
    if not s or ':' not in s:
        return None
    p = s.split(':')
    try:
        h = int(p[0])
        m = int(p[1])
        sec = int(p[2]) if len(p) >= 3 else 0
        return h * 3600 + m * 60 + sec
    except ValueError:
        return None


def _manual_stop_names(line):
    """`manual_express_stops.json` 의 해당 노선 전체 정차역 이름 집합(패턴 합집합).

    없으면 None. 한 노선에 여러 급행 패턴이 있을 수 있어(분당선 급행 + 수인선 급행)
    합집합을 쓴다. 두 패턴은 지리적으로 겹치지 않고 한 편성이 양쪽 레코드를 함께
    갖는 경우도 없으므로, 합집합으로 걸러도 패턴이 섞이지 않는다.
    """
    if not MANUAL_JSON.exists():
        return None
    try:
        data = json.loads(MANUAL_JSON.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        return None
    routes = data.get(line) or []
    names = set()
    for r in routes:
        names.update(r.get('stops') or [])
    return names or None


def gather_express_stops(line):
    """같은 노선의 모든 시간표 캐시를 읽어 trainno별 정차 순서를 반환.

    Returns:
        { (trainno, direction): [(stnNm, time_sec), ...] (시간 오름차순) }
    """
    ts = defaultdict(list)
    for d in ['상행', '하행']:
        for f in CACHE_DIR.glob(f'{line}_*_{d}.json'):
            m = re.match(rf'{re.escape(line)}_(.+)_{d}\.json$', f.name)
            if not m:
                continue
            stn_nm = m.group(1)
            try:
                with f.open(encoding='utf-8') as fp:
                    items = json.load(fp)
            except (OSError, json.JSONDecodeError):
                continue
            for item in items:
                if item.get('etrnYn') != 'Y':
                    continue
                # [데이터 오염 방어] fetch_timetables.dart 의 substring 검색이 한
                # 파일에 이웃 역 레코드를 함께 담는 경우가 있다(예: `수원` 파일에
                # `수원시청`). 시각을 그대로 쓰는 이상 이 오염은 구간 소요시간을
                # 직접 틀리게 하므로, stnNm 이 대상 역명과 정확히 일치하는
                # 레코드만 채택한다. (`compute_travel_times.dart` 와 같은 방어)
                if item.get('stnNm') != stn_nm:
                    continue
                tno = item.get('trainno')
                t = parse_sec(item.get('trainDptreTm', ''))
                if not tno or t is None:
                    continue
                ts[(tno, d)].append((stn_nm, t))
    # 같은 trainno+dir 내에서 `(역명, 시각)` 중복 제거.
    # data.go.kr API 응답에서 1호선 같은 노선은 동일 레코드가 5~6번
    # 반복 나타나 시퀀스 길이가 부풀려지는 이슈가 확인됨 (예: K1906 312역 = 실제
    # 52역의 6배). 정렬 후 consecutive dedupe 로 실제 정차 순서만 남긴다.
    for key in ts:
        ts[key].sort(key=lambda x: x[1])
        deduped = []
        prev = None
        for item in ts[key]:
            if item != prev:
                deduped.append(item)
            prev = item
        ts[key] = deduped

    # 통과역 레코드 걸러내기 (`_STOP_FILTER_LINES` 참조).
    #
    # API 가 통과역에도 시각을 채워 주는 노선은 이 필터 없이는 전 역이 정차역으로
    # 잡혀 skip edge 가 전부 인접쌍이 된다. 남는 시퀀스의 인접쌍 시간차는 실제
    # 급행 시각의 차이이므로 그대로 실측값이다.
    if line in _STOP_FILTER_LINES:
        allowed = _manual_stop_names(line)
        if allowed:
            dropped = 0
            for key in ts:
                before = len(ts[key])
                ts[key] = [x for x in ts[key] if x[0] in allowed]
                dropped += before - len(ts[key])
            print(f'  [{line}] 통과역 레코드 {dropped}건 제외 '
                  f'(정차역 {len(allowed)}개 기준)')
        else:
            print(f'  ⚠ [{line}] _STOP_FILTER_LINES 에 있으나 '
                  f'manual_express_stops.json 에 정차역이 없다 — 필터 미적용')
    return ts


def build_line_graph(line, conns, stations):
    """노선 내 인접 관계 및 name↔ID 매핑."""
    name_to_id = {}
    for s in stations:
        if s['lineId'] == line:
            name_to_id[s['name']] = s['id']
    adj = defaultdict(list)
    for c in conns:
        if c['lineId'] != line or c.get('isTransfer'):
            continue
        adj[c['fromStationId']].append(c['toStationId'])
        adj[c['toStationId']].append(c['fromStationId'])
    return adj, name_to_id


def _travel_time_lookup(line, conns):
    """(from, to) 또는 (to, from) 쌍의 완행 travelTimeSeconds 를 반환하는 dict."""
    m = {}
    for c in conns:
        if c['lineId'] != line or c.get('isTransfer'):
            continue
        t = c.get('travelTimeSeconds', 0)
        m[(c['fromStationId'], c['toStationId'])] = t
        m[(c['toStationId'], c['fromStationId'])] = t
    return m


def _bfs_full_path(start, end, adj):
    """start→end 최단 경로의 역 ID 리스트(양 끝 포함)."""
    if start == end:
        return [start]
    q = deque([(start, [start])])
    visited = {start}
    while q:
        cur, path = q.popleft()
        for nb in adj.get(cur, []):
            if nb in visited:
                continue
            visited.add(nb)
            np_ = path + [nb]
            if nb == end:
                return np_
            q.append((nb, np_))
    return None


def _apply_manual(
    *, line, adj, conns, name_to_id, existing_keys, line_edges, curated_hits,
    clamped,
):
    """`manual_express_stops.json` 의 해당 노선 항목을 skip edge 로 변환해 병합.

    `curated_hits` 는 실제로 적용된 `_CURATED_MANUAL_SECONDS` 키를 모으는 set
    (미사용 curated 키 경고용). `clamped` 는 완행 상한에 걸린 edge 를 모으는
    list (보고용).

    Returns: (추가된 edge 수, curated 로 결정된 edge 수).
    """
    # 정차역 목록을 **필터**로만 쓰는 노선은 강제 생성하지 않는다. 그렇지 않으면
    # MIN_FREQUENCY 등에 걸려 자동 수집에서 빠진 쌍이 `0.7 × 완행 합` 근사값으로
    # 되살아나, 실측만 담기로 한 원칙이 조용히 깨진다.
    # (예: 경춘 남춘천→춘천 은 상행 2편성뿐이라 빈도 미달로 빠지는데, 강제 생성이
    #  돌면 147s 라는 근거 없는 값이 들어간다.)
    if line not in MANUAL_LINES:
        return 0, 0
    if not MANUAL_JSON.exists():
        return 0, 0
    try:
        data = json.loads(MANUAL_JSON.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        return 0, 0
    manual_for_line = data.get(line, [])
    if not manual_for_line:
        return 0, 0

    tt_lookup = _travel_time_lookup(line, conns)
    added = 0
    curated_used = 0
    for route in manual_for_line:
        stops = route.get('stops') or []
        for i in range(len(stops) - 1):
            a = name_to_id.get(stops[i])
            b = name_to_id.get(stops[i + 1])
            if not a or not b:
                continue
            if (a, b) in existing_keys or (b, a) in existing_keys:
                continue
            full_path = _bfs_full_path(a, b, adj)
            if not full_path or len(full_path) < 2:
                continue
            local_sum = 0
            for k in range(len(full_path) - 1):
                local_sum += tt_lookup.get(
                    (full_path[k], full_path[k + 1]), 0,
                )
            # 실측 고정값이 있으면 우선. 없으면 완행 travelTime 합 × 비율.
            curated = _curated_seconds(line, a, b)
            if curated is not None:
                seconds = curated
                curated_hits.add((line, a, b))
                curated_used += 1
            elif local_sum > 0:
                seconds = max(60, int(round(local_sum * MANUAL_EXPRESS_RATIO)))
            else:
                continue
            # 불변식: 같은 구간에서 급행이 완행보다 느릴 수는 없다.
            # 실측 표본이 적은 인접 구간(수원→세류, 평택→성환)은 급행 편성이
            # 주요역에서 오래 정차해 중앙값이 완행을 넘기도 한다. 30초 격자
            # 해상도 안의 오차이므로 완행 값으로 눌러 라우팅 역전을 막는다.
            if local_sum > 0 and seconds > local_sum:
                clamped.append((line, a, b, seconds, local_sum))
                seconds = local_sum
            skipped = full_path[1:-1]
            line_edges.append({
                'lineId': line,
                'fromStationId': a,
                'toStationId': b,
                'seconds': seconds,
                'skippedStationIds': skipped,
            })
            existing_keys.add((a, b))
            added += 1
    return added, curated_used


def bfs_station_ids(start, end, adj):
    """start→end 최단 경로상의 **중간 역 ID** 리스트(양 끝 제외)."""
    if start == end:
        return []
    q = deque([(start, [])])
    visited = {start}
    while q:
        cur, path = q.popleft()
        for nb in adj.get(cur, []):
            if nb in visited:
                continue
            visited.add(nb)
            new_path = path + [nb]
            if nb == end:
                # new_path는 end 포함, 중간 역만 반환
                return new_path[:-1]
            q.append((nb, new_path))
    return None


def main():
    conns = json.loads(CONN_JSON.read_text(encoding='utf-8'))
    stations = json.loads(STATIONS_JSON.read_text(encoding='utf-8'))

    result = {}
    total_edges = 0
    curated_hits = set()
    clamped = []

    for line in LINES:
        stops = gather_express_stops(line)
        if not stops:
            print(f'[{line}] 급행 trainno 없음 → 스킵')
            result[line] = []
            continue

        # 인접 정차역 쌍 시간 차 수집.
        #
        # 과거: 같은 역명이 두 번 나타나면 시퀀스 전체 제외 → 1호선처럼 지선
        # 복합 노선(경원/경부/경인/병점-서동탄 등 모두 lineId='1')에서 대부분의
        # trainno 가 같은 역을 재방문해 277/284 시퀀스가 버려지는 과잉 필터.
        #
        # 개선: **첫 번째 중복 등장 이전까지만** 시퀀스를 잘라서 정방향 부분만
        # 사용한다. 이후 회송/반환 부분은 버림. 정방향 급행 정차 순서는 보존.
        pair_times = defaultdict(list)  # (fromStn, toStn) -> [seconds]
        for (_tno, _dir), seq in stops.items():
            seen = set()
            trimmed = []
            for name, t in seq:
                if name in seen:
                    break
                seen.add(name)
                trimmed.append((name, t))
            for i in range(len(trimmed) - 1):
                f_stn, f_t = trimmed[i]
                t_stn, t_t = trimmed[i + 1]
                if f_stn == t_stn:
                    continue
                gap = t_t - f_t
                # 종착/시발 분리로 인한 비현실적 gap 제외 (30분 초과)
                if 0 < gap < 1800:
                    pair_times[(f_stn, t_stn)].append(gap)

        print(f'[{line}] 급행 정차쌍 {len(pair_times)}개')

        adj, name_to_id = build_line_graph(line, conns, stations)

        # 빈도가 낮은 쌍은 임시 열차/회송 가능성이 높아 제외
        # (각 평일 시간표에 동일 trainno 1개씩만 등장하므로 3 이상 등장 = 정기 운행)
        MIN_FREQUENCY = _MIN_FREQUENCY.get(line, 3)

        line_edges = []
        skipped_low_freq = 0
        skipped_unrealistic = 0
        skipped_no_path = 0
        for (f_stn, t_stn), gaps in pair_times.items():
            if len(gaps) < MIN_FREQUENCY:
                skipped_low_freq += 1
                continue
            gaps.sort()
            median = gaps[len(gaps) // 2]
            f_id = name_to_id.get(f_stn)
            t_id = name_to_id.get(t_stn)
            if not f_id or not t_id:
                skipped_no_path += 1
                continue
            skipped_ids = bfs_station_ids(f_id, t_id, adj)
            if skipped_ids is None:
                skipped_no_path += 1
                continue
            # 물리 sanity: 역 1개당 최소 25초(이동 + 정차) 가정.
            # skip된 역이 N개면 최소 (N+1)*25 초가 필요. 이보다 짧으면 비현실적
            # (회송/지선 분기에서 잘못 매칭된 trainno 등). 인접역(skipped 0)은
            # 그래프 연결성 보존을 위해 sanity 무시하고 살림.
            min_realistic = max(60, (len(skipped_ids) + 1) * 25)
            if len(skipped_ids) > 0 and median < min_realistic:
                skipped_unrealistic += 1
                continue
            # 불변식: 같은 구간에서 급행이 완행보다 느릴 수는 없다.
            # 표본이 적은 인접쌍(경춘 신내→갈매 는 하행 3편성뿐)에서 급행 편성이
            # 주요역에 오래 정차하면 중앙값이 완행을 넘을 수 있다. 30초 격자
            # 해상도 안의 오차이므로 완행 값으로 눌러, 급행 탭의 총시간이 완행보다
            # 길어 보이는 역전을 막는다. `_apply_manual` 과 같은 정책이다.
            seconds = int(median)
            local_sum = 0
            chain = [f_id, *skipped_ids, t_id]
            tt = _travel_time_lookup(line, conns)
            for k in range(len(chain) - 1):
                local_sum += tt.get((chain[k], chain[k + 1]), 0)
            if local_sum > 0 and seconds > local_sum:
                clamped.append((line, f_id, t_id, seconds, local_sum))
                seconds = local_sum
            line_edges.append({
                'lineId': line,
                'fromStationId': f_id,
                'toStationId': t_id,
                'seconds': seconds,
                'skippedStationIds': skipped_ids,
            })

        # === 수동 매핑 skip edges 병합 ===
        #
        # data.go.kr API 가 1호선 처럼 etrnYn 만으로 정차역을 구분 못 하는 경우
        # `tool/manual_express_stops.json` 의 정차역 순서를 그대로 사용해 skip edge
        # 를 강제 생성한다. seconds 는 `_CURATED_MANUAL_SECONDS` 에 실측값이 있으면
        # 그 값, 없으면 연결된 완행 경로의 travelTimeSeconds 합에
        # MANUAL_EXPRESS_RATIO 를 곱한 값. 어느 쪽이든 완행 합을 상한으로 한다.
        manual_added, curated_used = _apply_manual(
            line=line,
            adj=adj,
            conns=conns,
            name_to_id=name_to_id,
            existing_keys={
                (e['fromStationId'], e['toStationId']) for e in line_edges
            },
            line_edges=line_edges,
            curated_hits=curated_hits,
            clamped=clamped,
        )

        # 정렬: fromStationId → toStationId (재실행 시 diff 안정화)
        line_edges.sort(
            key=lambda e: (e['fromStationId'], e['toStationId']),
        )
        result[line] = line_edges
        total_edges += len(line_edges)
        print(f'  {len(line_edges)}개 skip edge 생성 '
              f'(빈도부족 {skipped_low_freq}, 비현실 {skipped_unrealistic}, '
              f'경로없음 {skipped_no_path}, 수동 +{manual_added}, '
              f'실측고정 {curated_used})')

    # === 수동 전용 노선 처리 (자동 수집 LINES 에 없는 MANUAL_LINES 항목) ===
    #
    # 1호선 같이 API 정확도가 낮은 노선은 LINES 에서 빼고 MANUAL_LINES 에만 둔다.
    # 이 노선은 자동 수집 skip edge 가 없고 오로지 manual_express_stops.json 만
    # 사용된다. 이로써 `_E` 가상 노드는 **실제 급행 정차역에만** 생성되고, 사용자
    # 관찰("급행 13역")처럼 Dijkstra 가 통과역 `_E` 노드를 거쳐가는 현상이 없다.
    for line in MANUAL_LINES:
        if line in result:
            continue  # 이미 자동 수집에서 처리됨
        adj, name_to_id = build_line_graph(line, conns, stations)
        line_edges = []
        manual_added, curated_used = _apply_manual(
            line=line,
            adj=adj,
            conns=conns,
            name_to_id=name_to_id,
            existing_keys=set(),
            line_edges=line_edges,
            curated_hits=curated_hits,
            clamped=clamped,
        )
        line_edges.sort(
            key=lambda e: (e['fromStationId'], e['toStationId']),
        )
        result[line] = line_edges
        total_edges += len(line_edges)
        print(f'[{line}] (수동 전용) {len(line_edges)}개 skip edge 생성 '
              f'(수동 +{manual_added}, 실측고정 {curated_used})')

    OUTPUT_JSON.write_text(
        json.dumps(result, ensure_ascii=False, indent=2),
        encoding='utf-8',
    )
    print(f'\n{OUTPUT_JSON.relative_to(ROOT)} 생성: 총 {total_edges}개 edge')

    # 어느 skip edge 에도 붙지 않은 curated 키 경고.
    # 정차역 매핑이 바뀌어 키가 죽으면 조용히 0.7 근사로 돌아가므로 드러내 준다.
    applied = {f'{l}_{a}_{b}' for l, a, b in curated_hits}
    applied |= {f'{l}_{b}_{a}' for l, a, b in curated_hits}
    unused = sorted(set(_CURATED_MANUAL_SECONDS) - applied)
    print(f'실측 고정값 {len(_CURATED_MANUAL_SECONDS)}개 중 '
          f'{len(_CURATED_MANUAL_SECONDS) - len(unused)}개 적용')
    if unused:
        print(f'  ⚠ 미사용 curated 키 {len(unused)}개 (매핑과 어긋남): '
              f'{", ".join(unused)}')
    id_to_name = {(s['lineId'], s['id']): s['name'] for s in stations}
    for line, a, b, was, now in clamped:
        f_nm = id_to_name.get((line, a), a)
        t_nm = id_to_name.get((line, b), b)
        print(f'  · 완행 상한 적용 [{line}] {f_nm}({a})→{t_nm}({b}): '
              f'{was} → {now}')


if __name__ == '__main__':
    main()
