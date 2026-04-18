#!/usr/bin/env python3
"""급행이 중간역을 스킵하는 노선(9호선 등)의 expressTimeSeconds 보강.

알고리즘:
    1. 각 노선의 시간표 캐시에서 `etrnYn=='Y'` 열차의 (역, 출발시각) 수집
    2. 같은 trainno로 묶어 **정차 순서** 구성 (시간 오름차순)
    3. 각 trainno의 인접 정차역 쌍에 대해 시간 차 = 구간 급행 시간
    4. 여러 trainno에서 나온 동일 쌍은 중앙값 채택
    5. 각 구간 (A, B)에 대해 connections.json의 인접 역 경로를 찾아
       구간 급행 시간을 **완행 시간 비율**로 분배하여 각 connection의
       `expressTimeSeconds`에 기록
    6. 기존에 expressTimeSeconds가 있으면 유지(compute_travel_times 우선)

compute_travel_times.dart 실행 후 보조적으로 실행한다:
    dart run tool/compute_travel_times.dart
    python3 tool/compute_express_skip.py
"""
import json
import re
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / 'data' / 'timetables'
CONN_JSON = ROOT / 'assets' / 'json' / 'connections.json'
STATIONS_JSON = ROOT / 'assets' / 'json' / 'stations.json'

# 급행 운영 노선 (시간표 API에서 etrnYn=Y가 존재)
LINES = ['1', '9', '경춘', '수인분당']


def parse_sec(s: str):
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


def gather_express_stops(line: str):
    """같은 노선의 모든 시간표 캐시를 읽어 trainno별 정차 순서를 돌려준다.

    Returns: { (trainno, direction): [(stnNm, time_sec), ...] (시간 오름차순) }
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


def build_line_graph(line: str, conns: list, stations: list):
    """노선 내 인접 관계와 이름↔ID 매핑 구성."""
    id_to_name = {s['id']: s['name'] for s in stations if s['lineId'] == line}
    name_to_id = {}
    for s in stations:
        if s['lineId'] == line:
            # 같은 이름의 다른 노선이 겹치면 우선 이 노선 것 사용.
            name_to_id[s['name']] = s['id']
    adj = defaultdict(list)  # stationId -> [(neighbor, travelTime, conn_ref)]
    for c in conns:
        if c['lineId'] != line or c.get('isTransfer'):
            continue
        adj[c['fromStationId']].append((c['toStationId'], c['travelTimeSeconds'], c))
        adj[c['toStationId']].append((c['fromStationId'], c['travelTimeSeconds'], c))
    return adj, id_to_name, name_to_id


def bfs_path(start: str, end: str, adj):
    """start→end 최단 경로의 connection 리스트 (방향 무관)."""
    if start == end:
        return []
    q = deque([(start, [])])  # (node, edges so far)
    visited = {start}
    while q:
        cur, edges = q.popleft()
        for nb, _t, c in adj.get(cur, []):
            if nb in visited:
                continue
            visited.add(nb)
            new_edges = edges + [c]
            if nb == end:
                return new_edges
            q.append((nb, new_edges))
    return None


def main():
    conns = json.loads(CONN_JSON.read_text(encoding='utf-8'))
    stations = json.loads(STATIONS_JSON.read_text(encoding='utf-8'))

    total_skipped = 0
    total_updated = 0

    for line in LINES:
        stops = gather_express_stops(line)
        if not stops:
            print(f'[{line}] 급행 trainno 없음 → 스킵')
            continue

        # 인접 정차역 쌍 시간 차 수집
        pair_times = defaultdict(list)  # (fromStn, toStn) -> [seconds]
        for (_tno, _dir), seq in stops.items():
            for i in range(len(seq) - 1):
                f_stn, f_t = seq[i]
                t_stn, t_t = seq[i + 1]
                gap = t_t - f_t
                # 종착/시발 분리로 인한 비현실적 gap 제외 (30분 초과)
                if 0 < gap < 1800:
                    pair_times[(f_stn, t_stn)].append(gap)

        print(f'━━━ [{line}] 급행 정차쌍 {len(pair_times)}개 ━━━')

        adj, _id_to_name, name_to_id = build_line_graph(line, conns, stations)

        # 각 쌍의 중앙값 시간을 구한 뒤, 구간 경로의 인접 connection들에
        # 완행 시간 비율로 분배
        # 여러 쌍에서 동일 connection에 제안된 express 시간은 추후 중앙값 채택.
        proposals = defaultdict(list)  # conn_key -> [proposed express seconds]

        for (f_stn, t_stn), gaps in pair_times.items():
            gaps.sort()
            median = gaps[len(gaps) // 2]
            f_id = name_to_id.get(f_stn)
            t_id = name_to_id.get(t_stn)
            if not f_id or not t_id:
                total_skipped += 1
                continue
            edges = bfs_path(f_id, t_id, adj)
            if not edges:
                total_skipped += 1
                continue
            local_sum = sum(e['travelTimeSeconds'] for e in edges)
            if local_sum <= 0:
                continue
            for e in edges:
                ratio = e['travelTimeSeconds'] / local_sum
                proposed = max(1, int(round(median * ratio)))
                key = (
                    e['lineId'],
                    frozenset({e['fromStationId'], e['toStationId']}),
                )
                proposals[key].append(proposed)

        # connection key → 실제 connection 객체
        conn_map = {
            (c['lineId'], frozenset({c['fromStationId'], c['toStationId']})): c
            for c in conns
            if c['lineId'] == line and not c.get('isTransfer')
        }

        line_updated = 0
        for key, times in proposals.items():
            times.sort()
            med = times[len(times) // 2]
            c = conn_map.get(key)
            if c is None:
                continue
            # 기존 값이 있으면 유지 (compute_travel_times.dart 결과 우선)
            if 'expressTimeSeconds' in c:
                continue
            c['expressTimeSeconds'] = med
            line_updated += 1
            total_updated += 1

        print(f'  {line_updated}개 connection에 급행 시간 분배 완료')

    CONN_JSON.write_text(
        json.dumps(conns, ensure_ascii=False, indent=2), encoding='utf-8',
    )
    print(f'\n✓ connections.json 갱신: 총 {total_updated}개 connection 신규 분배, '
          f'{total_skipped}개 pair 스킵')


if __name__ == '__main__':
    main()
