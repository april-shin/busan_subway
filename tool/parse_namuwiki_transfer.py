#!/usr/bin/env python3
"""나무위키 "수도권 전철 환승 정보" HTML을 파싱하여 transfer_guides.csv에 채운다.

사용법:
    python3 tool/parse_namuwiki_transfer.py <input_html> [--dry-run]

동작:
    1. HTML에서 h2/h3/h4 헤더를 추출 ("XX역 (A호선-B호선)" 패턴)
    2. 각 데이터 테이블을 직전 헤더의 역에 귀속
    3. 각 행을 "A호선 (방면) → B호선 [(방면)] | m-n" 형태로 파싱
    4. 방면 이름을 프로젝트의 up/down으로 매핑
    5. data/transfer_guides.csv에 door_side/car/door/note 채움
       (door_side는 이 소스에서 구하지 못하므로 공란 유지)

주의:
    - 파일 직접 수정을 원하지 않으면 --dry-run 옵션 사용
    - 매칭 실패 행은 warnings에 출력하고 스킵
"""
import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

# 프로젝트 루트 기준 경로
ROOT = Path(__file__).resolve().parent.parent
STATIONS_JSON = ROOT / 'assets' / 'json' / 'stations.json'
CONNECTIONS_JSON = ROOT / 'assets' / 'json' / 'connections.json'
CSV_PATH = ROOT / 'data' / 'transfer_guides.csv'

# 나무위키 노선 표기 → 프로젝트 노선 ID
LINE_ALIAS = {
    '1호선': '1',
    '2호선': '2',
    '3호선': '3',
    '4호선': '4',
    '5호선': '5',
    '6호선': '6',
    '7호선': '7',
    '8호선': '8',
    '9호선': '9',
    '신분당선': 'SB',
    '경의·중앙선': '경의중앙',
    '경의중앙선': '경의중앙',
    '경춘선': '경춘',
    '공항철도': '공항철도',
    '인천국제공항철도': '공항철도',
    '수인·분당선': '수인분당',
    '수인분당선': '수인분당',
    '신림선': '신림',
    '에버라인': '에버라인',
    '인천 1호선': '인천1',
    '인천1호선': '인천1',
    '인천 2호선': '인천2',
    '인천2호선': '인천2',
    '김포 도시철도': '김포골드',
    '김포골드라인': '김포골드',
    '서해선': '서해',
    '의정부경전철': '의정부',
    '의정부 경전철': '의정부',
    '우이신설경전철': '우이신설',
    '우이신설선': '우이신설',
    'GTX-A': 'GTX-A',
    'GTX A': 'GTX-A',
}

# 2호선 순환선 방면 → 방향 수동 매핑
LINE2_DIRECTION = {
    '외선': 'down',
    '내선': 'up',
    '외선순환': 'down',
    '내선순환': 'up',
}

# 방면 이름 중 데이터로 자동 매칭되지 않는 수동 매핑 (노선별)
MANUAL_DIR = {
    ('신림', '관악산'): 'down',  # 신림선 관악산(서울대벤처타운)은 남쪽 종점
    # 별내, 모란 등 8호선 복잡한 경우는 역 ID로 자동 처리됨
}


def parse_numeric(s):
    m = re.search(r'(\d+)$', s)
    return int(m.group(1)) if m else None


# 별칭 → 정식명 역매핑 (station_index가 별칭으로도 lookup 되도록 보완)
ALIAS_TO_OFFICIAL: dict[str, str] = {}


def load_station_index():
    """역 이름 → {노선: ID} 인덱스.

    괄호 표기 별칭(예: "총신대입구(이수)"의 "이수")도 정식명으로 매핑되어
    파서가 나무위키의 약식 표기를 자동 인식한다.
    별칭으로 매칭된 경우 정식명을 알아야 CSV 키와 일치하므로
    `ALIAS_TO_OFFICIAL` 역매핑을 함께 채운다.
    """
    with STATIONS_JSON.open('r', encoding='utf-8') as f:
        stations = json.load(f)
    index = defaultdict(dict)  # name -> {lineId: id}
    line_stations = defaultdict(dict)  # lineId -> {name: id}
    ALIAS_TO_OFFICIAL.clear()
    for s in stations:
        official = s['name']
        index[official][s['lineId']] = s['id']
        line_stations[s['lineId']][official] = s['id']

        # 괄호 안/밖 별칭도 같은 ID로 매핑
        # 예: "총신대입구(이수)" → 별칭 "이수", "총신대입구"
        for alias in _extract_aliases(official):
            if alias and alias != official:
                index[alias][s['lineId']] = s['id']
                line_stations[s['lineId']].setdefault(alias, s['id'])
                ALIAS_TO_OFFICIAL[alias] = official
    return index, line_stations


def _extract_aliases(name: str) -> list[str]:
    """역명에서 괄호 안/밖 별칭을 추출.

    예: "총신대입구(이수)" → ["총신대입구", "이수"]
        "사우 (김포시청)" → ["사우", "김포시청"]
        "관악산(서울대)" → ["관악산", "서울대"]
    """
    m = re.match(r'^([^(]+?)\s*\(([^)]+)\)', name)
    if not m:
        return []
    return [m.group(1).strip(), m.group(2).strip()]


def load_adjacency():
    """노선별 인접 관계: {lineId: {stationId: set(neighborIds)}}"""
    with CONNECTIONS_JSON.open('r', encoding='utf-8') as f:
        conns = json.load(f)
    adj = defaultdict(lambda: defaultdict(set))
    for c in conns:
        if c.get('isTransfer'):
            continue
        lid = c['lineId']
        f_id = c['fromStationId']
        t_id = c['toStationId']
        adj[lid][f_id].add(t_id)
        adj[lid][t_id].add(f_id)
    return adj


def find_first_hop_id(line_id, from_id, target_id, adj):
    """from_id에서 target_id로 가는 경로의 첫 인접 역 ID를 BFS로 찾는다.

    Returns: 첫 인접 역 ID (같은 노선 내), 못 찾으면 None.
    """
    if from_id == target_id:
        return None
    graph = adj.get(line_id, {})
    if not graph:
        return None

    from collections import deque
    # 각 이웃을 시작으로 BFS 하여 target 도달 가능 여부 확인.
    # 가장 빨리 도달하는 이웃을 선택.
    neighbors = list(graph.get(from_id, []))
    if not neighbors:
        return None
    best_hop = None
    best_dist = float('inf')
    for start in neighbors:
        visited = {from_id, start}
        q = deque([(start, 1)])
        while q:
            node, dist = q.popleft()
            if node == target_id:
                if dist < best_dist:
                    best_dist = dist
                    best_hop = start
                break
            for nb in graph.get(node, []):
                if nb in visited:
                    continue
                visited.add(nb)
                q.append((nb, dist + 1))
    return best_hop


def clean_html(h):
    """태그 제거 → 파이프 구분 텍스트."""
    t = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', h, flags=re.DOTALL)
    t = re.sub(r'<[^>]+>', '|', t)
    t = re.sub(r'&nbsp;', ' ', t)
    t = re.sub(r'&amp;', '&', t)
    t = re.sub(r'&lt;', '<', t)
    t = re.sub(r'&gt;', '>', t)
    t = re.sub(r'&#91;|&#93;', '', t)
    t = re.sub(r'&[^;]+;', ' ', t)
    t = re.sub(r'[\|\s]+', '|', t)
    return t.strip('|')


def extract_station_from_header(header_text):
    """헤더에서 역 이름 추출. "XX역 (...)" 또는 "XX역" 패턴."""
    text = re.sub(r'&nbsp;', ' ', header_text)
    text = re.sub(r'&#91;.*?&#93;', '', text)
    text = re.sub(r'&[^;]+;', '', text)
    text = re.sub(r'\[.*?\]', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    text = re.sub(r'^[\d\.]+\s*', '', text)  # 위키 헤더 번호 제거
    # 역명에 숫자가 포함된 경우(종로3가, 을지로3가, 을지로4가 등)도 매칭
    m = re.match(r'^([가-힣·\d]+역)', text)
    return m.group(1) if m else None


def resolve_direction(line_id, direction_text, station_name, station_index, line_stations, adj):
    """방면 텍스트 → up/down.

    정확성을 위해 `connections.json` 기반 BFS로 환승역에서 방면 역으로의 첫 인접
    역 ID를 찾고, 프로젝트 `isDownBetween` 로직(인접 쌍 ID 비교)과 동일하게 판정한다.
    """
    # 2호선 순환 직접 매핑
    if line_id == '2':
        for k, v in LINE2_DIRECTION.items():
            if k in direction_text:
                return v

    # 수동 매핑
    key = (line_id, direction_text.strip())
    if key in MANUAL_DIR:
        return MANUAL_DIR[key]

    # 역 이름 정규화: 먼저 원본명으로 시도, 없으면 '역' 접미 제거본으로 시도
    # (stations.json에는 대부분 접미 없이 저장되나 '서울역'처럼 접미 포함 케이스 존재)
    station_id = line_stations.get(line_id, {}).get(station_name)
    if not station_id and station_name.endswith('역'):
        station_id = line_stations.get(line_id, {}).get(station_name[:-1])
    if not station_id:
        return None

    # 방면에 여러 역이 복합 ("서울역, 용문" 등)인 경우 분리하여 각 검사
    # "방면" 단어와 괄호 제거 (역 이름의 '방', '면' 글자는 보존)
    cleaned = direction_text.replace('방면', '').replace('(', '').replace(')', '')
    cleaned = re.sub(r'\s+', '', cleaned)
    # 내부 구분자로 분리
    candidates = re.split(r'[,/·]', cleaned)
    for cand in candidates:
        cand = cand.strip()
        if not cand:
            continue
        target_id = line_stations.get(line_id, {}).get(cand)
        if not target_id:
            continue
        hop_id = find_first_hop_id(line_id, station_id, target_id, adj)
        if not hop_id:
            continue
        hop_num = parse_numeric(hop_id)
        stn_num = parse_numeric(station_id)
        if hop_num is None or stn_num is None:
            continue
        # 4호선 진접선 특수 처리: project line_direction과 동일
        if line_id == '4':
            # 진접(449+) ↔ 본선(402-448) 경계 처리
            stn_is_ext = stn_num >= 449
            hop_is_ext = hop_num >= 449
            if stn_is_ext != hop_is_ext:
                # 본선→진접: up (북쪽)
                # 진접→본선: down (남쪽)
                return 'down' if stn_is_ext and not hop_is_ext else 'up'
            # 둘 다 본선/진접이면 ID 증가 = down
        return 'down' if hop_num > stn_num else 'up'
    return None  # 매칭 실패


def parse_table(table_html, station_name, station_index, line_stations, adj):
    """테이블에서 환승 가이드 행 목록 추출.

    Returns: list of dicts { arrival_line, direction, destination_line, car, door }
    """
    text = clean_html(table_html)
    # 헤더 패턴 skip
    # 각 "|" 구분 셀을 행 단위로 재조립
    parts = text.split('|')

    rows = []
    # 데이터 행의 특징: "A호선 (방면)? → B호선 (방면)? | m-n, ..."
    # 편의상 "→" 주변 토큰을 훑어 처리
    i = 0
    while i < len(parts):
        # 현재 셀이 노선 표기인지 확인
        cell = parts[i]
        line_match = _line_match(cell)
        if not line_match:
            i += 1
            continue
        arrival_line_id = line_match
        # 이후 셀들을 모아 "→" 만나기까지 방면 탐색
        arrival_dir = ''
        j = i + 1
        while j < len(parts) and parts[j] != '→':
            arrival_dir += parts[j]
            j += 1
        if j >= len(parts):
            i += 1
            continue
        # "→" 이후: destination_line(들) + 방면
        # 청량리역처럼 "1호선 → 경의·중앙선, 경춘선, 수인·분당선 | 1-1" 같이
        # 콤마로 여러 목적 노선이 나열되는 경우를 지원한다.
        j += 1
        if j >= len(parts):
            break
        dest_line_ids = []  # 발견된 모든 목적 노선
        dest_dir = ''
        while j < len(parts) and not re.match(r'^\d{1,2}-\d{1,2}', parts[j]):
            cell_match = _line_match(parts[j])
            if cell_match:
                dest_line_ids.append(cell_match)
            else:
                dest_dir += parts[j]
            j += 1
        if not dest_line_ids:
            i = j
            continue
        if j >= len(parts):
            break
        # 객차-문 셀
        door_cell = parts[j]
        pairs = re.findall(r'(\d{1,2})-(\d{1,2})', door_cell)
        j += 1
        # 다수 쌍이면 첫 번째만 사용 (추가 쌍은 note로)
        if not pairs:
            i = j
            continue

        # 방향 해석
        arr_dir = resolve_direction(
            arrival_line_id, arrival_dir, station_name, station_index, line_stations, adj
        )
        if arr_dir is None:
            # 방면이 빈 경우 양방향으로 해석 (up, down 각각 생성)
            dirs = ['up', 'down']
        else:
            dirs = [arr_dir]

        # 각 목적 노선마다 행 생성
        for dest_line_id in dest_line_ids:
            for d in dirs:
                car, door = pairs[0]
                note = ''
                if len(pairs) > 1:
                    note = ', '.join(f'{c}-{dr}' for c, dr in pairs[1:]) + ' (추가)'
                rows.append({
                    'arrival_line': arrival_line_id,
                    'direction': d,
                    'destination_line': dest_line_id,
                    'car': int(car),
                    'door': int(door),
                    'note': note,
                })
        i = j
    return rows


def _line_match(cell):
    """셀에서 노선 이름 매칭. 예: '1호선' → '1'."""
    cell = cell.strip()
    # 긴 이름 우선
    for alias in sorted(LINE_ALIAS.keys(), key=lambda x: -len(x)):
        if cell == alias:
            return LINE_ALIAS[alias]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('input', help='나무위키 HTML 경로')
    ap.add_argument('--dry-run', action='store_true', help='CSV 수정 없이 통계만 출력')
    args = ap.parse_args()

    html_path = Path(args.input)
    if not html_path.exists():
        print(f'오류: {html_path} 없음', file=sys.stderr)
        sys.exit(1)

    with html_path.open('r', encoding='utf-8') as f:
        html = f.read()

    station_index, line_stations = load_station_index()
    adj = load_adjacency()

    # 모든 헤더의 위치와 역명
    headers = []
    for m in re.finditer(r'<h[1-6][^>]*>(.*?)</h[1-6]>', html, re.DOTALL):
        raw = m.group(1)
        header_text = re.sub(r'<[^>]+>', '', raw)
        station = extract_station_from_header(header_text)
        if station:
            headers.append((m.start(), station))

    # 모든 데이터 테이블 위치
    table_positions = []
    for m in re.finditer(r'<table[^>]*>.*?</table>', html, re.DOTALL):
        if re.search(r'\b\d{1,2}-\d{1,2}\b', m.group(0)):
            table_positions.append((m.start(), m.group(0)))

    # 각 테이블을 직전 헤더의 역에 귀속
    collected = defaultdict(list)  # key = (station, arrival, direction, destination) -> row
    unmatched_headers = set()
    parse_errors = 0

    for pos, thtml in table_positions:
        # 이전 헤더 중 가장 가까운 것
        station = None
        for hpos, sname in reversed(headers):
            if hpos < pos:
                station = sname
                break
        if not station:
            unmatched_headers.add(pos)
            continue

        rows = parse_table(thtml, station, station_index, line_stations, adj)
        for r in rows:
            # 역 이름 정규화: stations.json에 있는 정식명으로 변환.
            # 1) 헤더 원본명("이수역") 또는 '역' trim("이수")으로 인덱스 조회
            # 2) 매칭된 이름이 별칭이면 정식명("총신대입구(이수)")으로 치환
            #    → CSV 템플릿 키와 일치
            candidates = [station]
            if station.endswith('역'):
                candidates.append(station[:-1])
            st = next(
                (c for c in candidates if c in station_index),
                candidates[-1],
            )
            st = ALIAS_TO_OFFICIAL.get(st, st)
            key = (st, r['arrival_line'], r['direction'], r['destination_line'])
            if key in collected:
                # 중복 — 기존 note에 추가
                parse_errors += 1
            collected[key] = {
                'door_side': '',  # 나무위키 테이블에는 left/right 정보 없음
                'car': r['car'],
                'door': r['door'],
                # note는 사용자에게 노출되는 보조 안내문이므로 출처 표기는 넣지 않는다.
                # 추가 객차-문 쌍이 있을 때만 그 정보를 note에 보존.
                'note': r['note'] if r['note'] else '',
            }

    print(f'파싱된 고유 엔트리: {len(collected)}')
    print(f'헤더 미매칭 테이블: {len(unmatched_headers)}')
    print(f'중복 덮어쓰기: {parse_errors}')

    if args.dry_run:
        # 샘플 출력
        print('\n샘플 엔트리 20개:')
        for i, (k, v) in enumerate(sorted(collected.items())[:20]):
            print(f'  {k} → {v}')
        return

    # CSV 읽고 매칭되는 행 업데이트
    with CSV_PATH.open('r', encoding='utf-8') as f:
        lines = f.readlines()

    header = lines[0].rstrip('\n').split(',')
    col_idx = {name: i for i, name in enumerate(header)}

    updated = 0
    new_rows = [lines[0]]
    matched_keys = set()
    for line in lines[1:]:
        fields = line.rstrip('\n').split(',')
        if len(fields) < 8:
            new_rows.append(line)
            continue
        station = fields[col_idx['station']]
        arrival = fields[col_idx['arrival_line']]
        direction = fields[col_idx['direction']]
        destination = fields[col_idx['destination_line']]
        key = (station, arrival, direction, destination)
        if key in collected:
            v = collected[key]
            fields[col_idx['door_side']] = str(v['door_side'])
            fields[col_idx['car']] = str(v['car'])
            fields[col_idx['door']] = str(v['door'])
            # note가 비어있으면 덮어쓰기
            if not fields[col_idx['note']]:
                fields[col_idx['note']] = v['note']
            new_rows.append(','.join(fields) + '\n')
            matched_keys.add(key)
            updated += 1
        else:
            new_rows.append(line)

    with CSV_PATH.open('w', encoding='utf-8') as f:
        f.writelines(new_rows)

    unmatched = len(collected) - len(matched_keys)
    print(f'\n✓ CSV 업데이트: {updated}행')
    print(f'  CSV 템플릿과 매칭 실패: {unmatched}건 (역명/노선 표기 차이 가능성)')
    if unmatched > 0:
        print('  매칭 실패 전체:')
        for k, v in collected.items():
            if k not in matched_keys:
                print(f'    {k} → {v}')


if __name__ == '__main__':
    main()
