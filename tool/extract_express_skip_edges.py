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

# 급행 운영 노선
LINES = ['1', '9', '경춘', '수인분당']


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
    for key in ts:
        ts[key].sort(key=lambda x: x[1])
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

        # 인접 정차역 쌍 시간 차 수집 + trainno 회송/비정상 시퀀스 필터링
        pair_times = defaultdict(list)  # (fromStn, toStn) -> [seconds]
        for (_tno, _dir), seq in stops.items():
            # 시퀀스 검증: 같은 역명이 두 번 이상 나타나면 회송/혼선 패턴
            # → 해당 trainno의 정차 시퀀스 전체를 신뢰할 수 없어 제외
            names = [name for name, _t in seq]
            if len(set(names)) != len(names):
                continue
            for i in range(len(seq) - 1):
                f_stn, f_t = seq[i]
                t_stn, t_t = seq[i + 1]
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

        # 정렬: fromStationId → toStationId (재실행 시 diff 안정화)
        line_edges.sort(
            key=lambda e: (e['fromStationId'], e['toStationId']),
        )
        result[line] = line_edges
        total_edges += len(line_edges)
        print(f'  {len(line_edges)}개 skip edge 생성 '
              f'(빈도부족 {skipped_low_freq}, 비현실 {skipped_unrealistic}, '
              f'경로없음 {skipped_no_path})')

    OUTPUT_JSON.write_text(
        json.dumps(result, ensure_ascii=False, indent=2),
        encoding='utf-8',
    )
    print(f'\n{OUTPUT_JSON.relative_to(ROOT)} 생성: 총 {total_edges}개 edge')


if __name__ == '__main__':
    main()
