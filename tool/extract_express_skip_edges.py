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

# 수동 매핑도 대상 노선 목록 — 여기엔 1호선 포함.
MANUAL_LINES = ['1', '9', '경춘', '수인분당']

# 수동 매핑에서 skip edge 의 seconds 를 완행 시간 합에 곱할 비율.
# 1호선 경인선/경부선 급행은 통상 완행 대비 65~75% 시간으로 운행.
MANUAL_EXPRESS_RATIO = 0.7


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


def _apply_manual(*, line, adj, conns, name_to_id, existing_keys, line_edges):
    """`manual_express_stops.json` 의 해당 노선 항목을 skip edge 로 변환해 병합.

    Returns: 추가된 edge 수.
    """
    if not MANUAL_JSON.exists():
        return 0
    try:
        data = json.loads(MANUAL_JSON.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        return 0
    manual_for_line = data.get(line, [])
    if not manual_for_line:
        return 0

    tt_lookup = _travel_time_lookup(line, conns)
    added = 0
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
            # 완행 travelTime 합계 산출
            local_sum = 0
            for k in range(len(full_path) - 1):
                local_sum += tt_lookup.get(
                    (full_path[k], full_path[k + 1]), 0,
                )
            if local_sum <= 0:
                continue
            seconds = max(60, int(round(local_sum * MANUAL_EXPRESS_RATIO)))
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
    return added


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
        MIN_FREQUENCY = 3

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
            line_edges.append({
                'lineId': line,
                'fromStationId': f_id,
                'toStationId': t_id,
                'seconds': int(median),
                'skippedStationIds': skipped_ids,
            })

        # === 수동 매핑 skip edges 병합 ===
        #
        # data.go.kr API 가 1호선 처럼 etrnYn 만으로 정차역을 구분 못 하는 경우
        # `tool/manual_express_stops.json` 의 정차역 순서를 그대로 사용해 skip edge
        # 를 강제 생성한다. seconds 는 연결된 완행 경로의 travelTimeSeconds 합에
        # MANUAL_EXPRESS_RATIO 를 곱한 값.
        manual_added = _apply_manual(
            line=line,
            adj=adj,
            conns=conns,
            name_to_id=name_to_id,
            existing_keys={
                (e['fromStationId'], e['toStationId']) for e in line_edges
            },
            line_edges=line_edges,
        )

        # 정렬: fromStationId → toStationId (재실행 시 diff 안정화)
        line_edges.sort(
            key=lambda e: (e['fromStationId'], e['toStationId']),
        )
        result[line] = line_edges
        total_edges += len(line_edges)
        print(f'  {len(line_edges)}개 skip edge 생성 '
              f'(빈도부족 {skipped_low_freq}, 비현실 {skipped_unrealistic}, '
              f'경로없음 {skipped_no_path}, 수동 +{manual_added})')

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
        manual_added = _apply_manual(
            line=line,
            adj=adj,
            conns=conns,
            name_to_id=name_to_id,
            existing_keys=set(),
            line_edges=line_edges,
        )
        line_edges.sort(
            key=lambda e: (e['fromStationId'], e['toStationId']),
        )
        result[line] = line_edges
        total_edges += len(line_edges)
        print(f'[{line}] (수동 전용) {len(line_edges)}개 skip edge 생성 '
              f'(수동 +{manual_added})')

    OUTPUT_JSON.write_text(
        json.dumps(result, ensure_ascii=False, indent=2),
        encoding='utf-8',
    )
    print(f'\n{OUTPUT_JSON.relative_to(ROOT)} 생성: 총 {total_edges}개 edge')


if __name__ == '__main__':
    main()
