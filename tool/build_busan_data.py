#!/usr/bin/env python3
"""부산 지하철 정적 데이터 + 노선도 SVG 생성기 (유일 소스).

입력
  tool/data/busan_humetro_cyberstation.txt   역·노선·노선도 좌표 (부산교통공사 사이버스테이션)
  tool/data/busan_humetro_travel_times.txt   역간 누적 소요시간·환승시간 (같은 사이트 경로 검색)
출력
  assets/svg/busan_metro_map.svg
  assets/json/{stations,lines,connections,transfer_times,line_schedules,
               express_skip_edges,transfer_guides,svg_station_coords}.json

실행: python3 tool/build_busan_data.py  →  이어서 dart run tool/build_map_html.dart

⚠️ 근거가 약한 값(자세한 내용은 .claude/docs/pending-data.md):
  - latitude/longitude 는 실제 좌표가 아니라 노선도 좌표를 선형 변환한 **의사 좌표**다.
    동명이역 판정(same_station.dart, 2km 반경)이 동작하도록 1px = 50m 로 잡았다.
  - line_schedules.json 의 첫차·막차·배차간격은 **추정치**다(역별 시간표 `t` 없음).
  - 환승시간은 분 단위 검색값의 차라 ±1분 오차가 있다.
  - express_skip_edges / transfer_guides 는 비어 있다(부산 데이터 미수집).
"""
import json
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'tool/data/busan_humetro_cyberstation.txt'
TIMES = ROOT / 'tool/data/busan_humetro_travel_times.txt'
SVG_OUT = ROOT / 'assets/svg/busan_metro_map.svg'
JSON_DIR = ROOT / 'assets/json'

# 사이트 노선코드 → (앱 lineId, 표시명, SVG data-line 코드)
LINE_META = {
    '1': ('1', '1호선', 'B1'),
    '2': ('2', '2호선', 'B2'),
    '3': ('3', '3호선', 'B3'),
    '4': ('4', '4호선', 'B4'),
    '8': ('동해', '동해선', 'DH'),
    '9': ('부산김해', '부산김해경전철', 'BG'),
}

# 지도 캔버스는 기존 지도 HTML 의 고정값(2416x1560, 초기 중심 1040,618)을 그대로 쓴다.
# 사이트 좌표(1680x980)를 1.5배 키워 노선도 중심이 초기 중심에 오도록 옮긴다.
CANVAS_W, CANVAS_H = 2416, 1560
SCALE, SHIFT_X, SHIFT_Y = 1.5, -160, -162
DWELL_SECONDS, MIN_RUN_SECONDS = 30, 30  # dwell_time.dart 의 dwellTimeSeconds 와 같아야 한다
# 노선 곡선: 베지어 제어점 거리(구간 길이 대비)와 직선 근사 간격(px).
CURVE_TENSION, CURVE_STEP_PX = 0.38, 4.0
LABEL_LINE_GAP = 14.0  # 여러 줄 라벨의 줄 간격(px)
CENTER_OFFSET = {'P': (5.5, 5.0), 'T': (7.5, 13.0), 'R': (13.0, 7.5)}

# 캔버스 좌표 수동 지정(역번호 → x,y). 동해선 부전은 사이트 좌표로는 1호선 부전과 32px
# 떨어져, 두 역을 덮는 알약 마커의 중심이 양쪽에서 14px(편집기 마커 앵커 반경)를 넘는다.
# 1호선 부전(1122,746) 쪽으로 당겨 24px 간격으로 둔다.
CANVAS_OVERRIDES = {'801': (1098.0, 746.0)}

# 이름이 같아도 다른 역(사이트에서 환승역이 아님) — 역번호로 지정.
DISTINCT_SAME_NAME = {'816', '805'}  # 동해선 좌천, 동해선 동래
# 이름이 달라도 같은 환승역 — 역번호 묶음.
ALIAS_GROUPS = [('205', '810')]  # 벡스코(시립미술관) ↔ 벡스코

# 의사 좌표: 서면(사이트 좌표 854.5, 652)을 실제 서면 부근에 두고 1px = 50m.
ANCHOR_PX, ANCHOR_GEO, METERS_PER_PX = (854.5, 652.0), (35.1577, 129.0591), 50.0

# 추정 운행 정보: (첫차, 막차, [(시작, 끝, 배차 분)]) — 평일/휴일 공통.
# 막차는 일부러 늦게(00:30) 잡는다 — 실시간이 꺼져 있어 추정 막차가 이르면 앱이
# 실제로 열차가 다니는 시각에 "운행하는 열차가 없습니다"를 단정하기 때문이다.
_URBAN = ('05:00', '00:30', [('05:00', '07:00', 8), ('07:00', '09:00', 5),
                             ('09:00', '17:00', 7), ('17:00', '20:00', 5),
                             ('20:00', '23:59', 8)])
SCHEDULE_ESTIMATE = {
    '1': _URBAN, '2': _URBAN, '3': _URBAN, '4': _URBAN,
    '동해': ('05:00', '00:30', [('05:00', '07:00', 30), ('07:00', '09:00', 15),
                              ('09:00', '17:00', 30), ('17:00', '20:00', 15),
                              ('20:00', '23:59', 30)]),
    '부산김해': ('05:00', '00:30', [('05:00', '07:00', 8), ('07:00', '09:00', 5),
                                ('09:00', '17:00', 8), ('17:00', '20:00', 5),
                                ('20:00', '23:59', 9)]),
}


def to_canvas(x, y):
    return float(round(x * SCALE + SHIFT_X)), float(round(y * SCALE + SHIFT_Y))


def parse_map():
    lines, cur = [], None
    for raw in SRC.read_text(encoding='utf-8').splitlines():
        if not raw or raw.startswith('#'):
            continue
        f = raw.split('|')
        if f[0] == 'L':
            line_id, name, code = LINE_META[f[1]]
            cur = {'site': f[1], 'id': line_id, 'name': name, 'code': code,
                   'color': f[3], 'stations': []}
            lines.append(cur)
        elif f[0] == 'S':
            x, y = (float(v) for v in f[3].split(','))
            dx, dy = CENTER_OFFSET[f[4]]
            px, py = x + dx, y + dy
            cx, cy = CANVAS_OVERRIDES.get(f[1]) or to_canvas(px, py)
            label = None if f[5] == '-' else [float(v) for v in f[5].split(',')]
            cur['stations'].append({
                'id': f[1], 'name': f[2].replace('/', ''), 'kind': f[4],
                'label_lines': f[2].split('/'),
                'px': px, 'py': py, 'cx': cx, 'cy': cy, 'label': label,
                'lineId': cur['id'],
            })
        else:
            raise ValueError(f'알 수 없는 줄: {raw}')
    return lines


def parse_times(lines):
    by_site = {ln['site']: ln for ln in lines}
    seg, transfers = {}, []
    for raw in TIMES.read_text(encoding='utf-8').splitlines():
        if not raw or raw.startswith('#'):
            continue
        f = raw.split('|')
        if f[0] == 'C':
            ln = by_site[f[1]]
            ids = [s['id'] for s in ln['stations']]
            if ids[0] != f[3]:
                raise ValueError(f'{ln["name"]} 기점 불일치: {ids[0]} != {f[3]}')
            cum = [0] + [int(v) * (60 if f[2] == 'm' else 1) for v in f[4].split(',')]
            if len(cum) != len(ids):
                raise ValueError(f'{ln["name"]} 누적값 {len(cum) - 1}개, 구간 {len(ids) - 1}개')
            for i in range(1, len(ids)):
                sec = cum[i] - cum[i - 1]
                if sec <= 0:
                    raise ValueError(f'{ln["name"]} {ids[i - 1]}→{ids[i]} 소요시간 {sec}')
                # 사이트 값은 정차시간을 포함한다. 앱은 중간역마다 정차시간을 따로 더하므로
                # (lib/core/constants/dwell_time.dart) 구간값에서 한 번씩 뺀다.
                seg[(ids[i - 1], ids[i])] = max(MIN_RUN_SECONDS, sec - DWELL_SECONDS)
        elif f[0] == 'T':
            transfers.append((f[1], by_site[f[2]]['id'], by_site[f[3]]['id'], int(f[4])))
        else:
            raise ValueError(f'알 수 없는 줄: {raw}')
    return seg, transfers


def group_stations(lines):
    """같은 물리 환승역끼리 묶는다 → {역번호: [같은 묶음의 역들]}"""
    alias = {sid: g[0] for g in ALIAS_GROUPS for sid in g}
    groups = {}
    for ln in lines:
        for s in ln['stations']:
            if s['id'] in alias:
                key = ('alias', alias[s['id']])
            elif s['id'] in DISTINCT_SAME_NAME:
                key = ('id', s['id'])
            else:
                key = ('name', s['name'])
            groups.setdefault(key, []).append(s)
    return {s['id']: g for g in groups.values() for s in g}


def pseudo_geo(s):
    import math
    lat0, lon0 = ANCHOR_GEO
    m_lat = 111320.0
    m_lon = m_lat * math.cos(math.radians(lat0))
    lat = lat0 - (s['py'] - ANCHOR_PX[1]) * METERS_PER_PX / m_lat
    lon = lon0 + (s['px'] - ANCHOR_PX[0]) * METERS_PER_PX / m_lon
    return round(lat, 5), round(lon, 5)


def build_json(lines, seg, transfers, group_of):
    order = [ln['id'] for ln in lines]
    stations, connections = [], []
    for ln in lines:
        for s in ln['stations']:
            grp = group_of[s['id']]
            tl = sorted({g['lineId'] for g in grp}, key=order.index)
            lat, lon = pseudo_geo(s)
            stations.append({
                'id': s['id'], 'name': s['name'], 'lineId': ln['id'],
                'latitude': lat, 'longitude': lon,
                'svgX': s['cx'], 'svgY': s['cy'],
                'isTransfer': len(tl) > 1, 'transferLines': tl,
            })
        for a, b in zip(ln['stations'], ln['stations'][1:]):
            connections.append({
                'fromStationId': a['id'], 'toStationId': b['id'], 'lineId': ln['id'],
                'travelTimeSeconds': seg[(a['id'], b['id'])], 'isTransfer': False,
            })
    by_id = {s['id']: s for s in stations}
    transfer_times = {}
    for name, la, lb, sec in transfers:
        members = [s for s in stations
                   if s['isTransfer'] and s['lineId'] in (la, lb)
                   and (s['name'] == name or s['name'].startswith(name + '('))]
        if {m['lineId'] for m in members} != {la, lb}:
            raise ValueError(f'환승역 {name} {la}↔{lb} 를 역 데이터에서 찾지 못함')
        a = next(m for m in members if m['lineId'] == la)
        b = next(m for m in members if m['lineId'] == lb)
        if a['name'] == b['name']:
            transfer_times[f'{name}_{la}_{lb}'] = sec
        else:  # 이름이 다른 환승역은 이름 기반 환승 간선이 안 생기므로 연결로 직접 넣는다.
            for x, y in ((a, b), (b, a)):
                connections.append({
                    'fromStationId': x['id'], 'toStationId': y['id'], 'lineId': x['lineId'],
                    'travelTimeSeconds': sec, 'isTransfer': True,
                })
    # 환승 묶음마다 환승시간이 빠짐없이 있는지 확인.
    for sid, grp in group_of.items():
        ids = sorted({g['lineId'] for g in grp}, key=order.index)
        if len(ids) < 2:
            continue
        names = {by_id[g['id']]['name'] for g in grp}
        if len(names) == 1:
            n = next(iter(names))
            for i, la in enumerate(ids):
                for lb in ids[i + 1:]:
                    if f'{n}_{la}_{lb}' not in transfer_times:
                        raise ValueError(f'환승시간 누락: {n} {la}↔{lb}')
        else:  # 이름이 다른 묶음은 양방향 환승 연결이 있어야 한다.
            for x in grp:
                for y in grp:
                    if x['id'] != y['id'] and not any(
                            c['isTransfer'] and c['fromStationId'] == x['id']
                            and c['toStationId'] == y['id'] for c in connections):
                        raise ValueError(f"환승 연결 누락: {x['id']}→{y['id']}")
    lines_json = [{
        'id': ln['id'], 'name': ln['name'], 'colorValue': int(ln['color'][1:], 16),
        'stationIds': [s['id'] for s in ln['stations']],
    } for ln in lines]

    def day(est):
        first, last, bands = est
        return {'f': [first, first], 'l': [last, last], 'p': [list(b) for b in bands]}
    schedules = [{'id': ln['id'], 'wd': day(SCHEDULE_ESTIMATE[ln['id']]),
                  'we': day(SCHEDULE_ESTIMATE[ln['id']])} for ln in lines]
    coords = {}
    for ln in lines:
        for s in ln['stations']:
            coords.setdefault(s['name'], {'name': s['name'], 'dataLine': ln['code'],
                                          'svgX': s['cx'], 'svgY': s['cy'], 'distance': 0})
    return {
        'stations': stations, 'lines': lines_json, 'connections': connections,
        'transfer_times': dict(sorted(transfer_times.items())),
        'line_schedules': schedules, 'express_skip_edges': {}, 'transfer_guides': {},
        'svg_station_coords': coords,
    }


def smooth_polyline(stations):
    """역 중심들을 **모두 지나는** 부드러운 곡선을 짧은 직선들로 근사한 점 목록.

    지도 빌드(`build_map_html`)는 data-line path 에 M/L 만 허용하므로 베지어를 직접 쓰지 않고
    [CURVE_STEP_PX] 간격으로 잘라 L 로 내보낸다. 역마다 접선 방향을 정해 구간을 3차 베지어로 잇는다
    — 일직선 구간은 접선이 현과 나란해 그대로 직선이 되고, 꺾이는 구간만 둥글게 휜다.
    """
    import math
    n = len(stations)

    def unit(dx, dy):
        length = math.hypot(dx, dy)
        return (dx / length, dy / length) if length else (0.0, 0.0)

    dirs = [unit(b[0] - a[0], b[1] - a[1]) for a, b in zip(stations, stations[1:])]

    def aligned(u, v):  # 두 구간이 사실상 일직선인가(약 4도 이내)
        return u[0] * v[0] + u[1] * v[1] > 0 and abs(u[0] * v[1] - u[1] * v[0]) < 0.07

    # 역의 접선: 일직선 구간(run)의 끝에 있는 역은 그 직선 방향을 유지해, 직선 구간이
    # 출렁이지 않고 꺾이는 구간 안에서만 휘게 한다. 양쪽 다 꺾이면 두 방향의 이등분선.
    tangents = []
    for i in range(n):
        if i == 0 or i == n - 1:
            tangents.append(dirs[0] if i == 0 else dirs[-1])
            continue
        din, dout = dirs[i - 1], dirs[i]
        run_in = i >= 2 and aligned(dirs[i - 2], din)
        run_out = i <= n - 3 and aligned(dout, dirs[i + 1])
        if run_in and not run_out and not aligned(din, dout):
            tangents.append(din)
        elif run_out and not run_in and not aligned(din, dout):
            tangents.append(dout)
        else:
            tangents.append(unit(din[0] + dout[0], din[1] + dout[1]))
    out = [stations[0]]
    for i in range(n - 1):
        (x0, y0), (x1, y1) = stations[i], stations[i + 1]
        chord = math.hypot(x1 - x0, y1 - y0)
        cx, cy = unit(x1 - x0, y1 - y0)
        (t0x, t0y), (t1x, t1y) = tangents[i], tangents[i + 1]
        straight = (abs(t0x * cy - t0y * cx) < 0.02 and abs(t1x * cy - t1y * cx) < 0.02)
        if not straight:
            k = chord * CURVE_TENSION
            c0 = (x0 + t0x * k, y0 + t0y * k)
            c1 = (x1 - t1x * k, y1 - t1y * k)
            steps = max(2, round(chord / CURVE_STEP_PX))
            for j in range(1, steps):
                t = j / steps
                u = 1 - t
                out.append((
                    round(u ** 3 * x0 + 3 * u * u * t * c0[0] + 3 * u * t * t * c1[0] + t ** 3 * x1, 1),
                    round(u ** 3 * y0 + 3 * u * u * t * c0[1] + 3 * u * t * t * c1[1] + t ** 3 * y1, 1),
                ))
        out.append((x1, y1))
    return out


def text_width(name):
    """12px sans-serif 기준 라벨 폭 근사(한글 전각 12px, 그 외 기호·숫자·영문은 좁게)."""
    return sum(12.0 if ord(ch) >= 0x1100 else (4.0 if ch in '·()' else 7.0) for ch in name)


def marker_box(s, group_of):
    """역 마커가 차지하는 사각형 (x0, y0, x1, y1) — 일반역은 원, 환승역은 묶음 알약."""
    grp = group_of[s['id']]
    if len({g['lineId'] for g in grp}) < 2:
        return (s['cx'] - 5.5, s['cy'] - 5.5, s['cx'] + 5.5, s['cy'] + 5.5)
    xs, ys = [g['cx'] for g in grp], [g['cy'] for g in grp]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span_x, span_y = max(xs) - min(xs), max(ys) - min(ys)
    if span_x > span_y or any(g['kind'] == 'R' for g in grp):
        w, h = max(24.0, span_x + 12.0), 8.0
    else:
        w, h = 8.0, max(24.0, span_y + 12.0)
    return (cx - w / 2 - 1, cy - h / 2 - 1, cx + w / 2 + 1, cy + h / 2 + 1)


def place_labels(lines, group_of, polylines):
    """역명 라벨 자리를 정한다 → [{name, code, x, y, anchor}].

    사이트의 라벨 위치를 1순위로 쓰되, 다른 라벨·역 마커·노선 선과 겹치면 역 주변 8방향
    후보 중 겹침 비용이 가장 낮은 자리로 옮긴다. 캔버스를 1.5배 키우면서 글자 크기는
    그대로라 대부분은 사이트 자리 그대로 들어간다.
    """
    import math
    H = 13.0  # 라벨 한 줄 높이(12px 글자 + 여유)

    def box_of(x, y, anchor, w, extra=0.0):
        # y 는 첫 줄의 기준선, extra 는 둘째 줄부터 더해지는 높이.
        x0 = x if anchor == 'start' else (x - w if anchor == 'end' else x - w / 2)
        return (x0, y - 10.5, x0 + w, y - 10.5 + H + extra)

    def overlap(a, b, pad=0.0):
        w = min(a[2], b[2]) - max(a[0], b[0]) + pad
        h = min(a[3], b[3]) - max(a[1], b[1]) + pad
        return w * h if w > 0 and h > 0 else 0.0

    # 장애물: 모든 역 마커, 노선 선(3px 간격 표본점).
    markers = []
    for ln in lines:
        for s in ln['stations']:
            markers.append(marker_box(s, group_of))
    line_pts = []
    for pts in polylines:
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = max(1, int(math.hypot(x1 - x0, y1 - y0) // 3))
            line_pts.extend((x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n) for i in range(n + 1))

    def static_cost(box):
        cost = sum(8.0 + overlap(box, m) for m in markers if overlap(box, m) > 0)
        grown = (box[0] - 2.5, box[1] - 2.5, box[2] + 2.5, box[3] + 2.5)
        hits = sum(1 for (x, y) in line_pts
                   if grown[0] < x < grown[2] and grown[1] < y < grown[3])
        return cost + hits * 3.0

    labels = []
    for ln in lines:
        for s in ln['stations']:
            if s['label'] is None:
                continue
            lx, ly, lw, lh = s['label']
            if lx + lw <= s['px']:
                anchor, tx = 'end', lx + lw
            elif lx >= s['px']:
                anchor, tx = 'start', lx
            else:
                anchor, tx = 'middle', lx + lw / 2
            x, y = to_canvas(tx, ly + lh / 2)
            texts = s['label_lines']
            w = max(text_width(t) for t in texts)
            extra = LABEL_LINE_GAP * (len(texts) - 1)
            m = marker_box(s, group_of)
            mx, my = (m[0] + m[2]) / 2, (m[1] + m[3]) / 2
            hw, hh = (m[2] - m[0]) / 2 + 4, (m[3] - m[1]) / 2 + 4
            cands = [(x, y + 4.0 - extra / 2, anchor, 0.0)]  # 사이트 자리(비용 가산 없음)
            for dx, dy, anc, pen in (
                    (1, 0, 'start', 1.0), (-1, 0, 'end', 1.0), (0, 1, 'middle', 1.5),
                    (0, -1, 'middle', 1.5), (1, -1, 'start', 2.5), (1, 1, 'start', 2.5),
                    (-1, -1, 'end', 2.5), (-1, 1, 'end', 2.5)):
                cx = mx + dx * hw if dx else mx
                cy = (my + 4.5 - extra / 2 if dy == 0
                      else (my + hh + 10.5 if dy > 0 else my - hh - 2.5 - extra))
                if dx and dy:  # 대각선은 마커 모서리에 붙인다
                    cx = mx + dx * (hw - 3)
                cands.append((round(cx, 1), round(cy, 1), anc, pen))
            # 한 줄 더 떨어진 위·아래(빽빽한 곳의 마지막 수단).
            cands.append((round(mx, 1), round(my + hh + 10.5 + H, 1), 'middle', 4.0))
            cands.append((round(mx, 1), round(my - hh - 2.5 - H - extra, 1), 'middle', 4.0))
            labels.append({'name': s['name'], 'code': ln['code'], 'w': w, 'cands': cands,
                           'pick': 0, 'texts': texts, 'extra': extra})

    def cur_box(lab):
        x, y, anc, _ = lab['cands'][lab['pick']]
        return box_of(x, y, anc, lab['w'], lab['extra'])

    moved = set()
    for _ in range(4):  # 서로 밀어내며 수렴할 때까지 몇 번 반복
        changed = False
        for i, lab in enumerate(labels):
            others = [cur_box(o) for j, o in enumerate(labels) if j != i]
            best, best_cost = None, None
            for k, (x, y, anc, pen) in enumerate(lab['cands']):
                box = box_of(x, y, anc, lab['w'], lab['extra'])
                cost = static_cost(box) + sum(
                    10.0 + overlap(box, o, 1.0) for o in others if overlap(box, o, 1.0) > 0)
                if cost > 0:
                    cost += pen
                if best_cost is None or cost < best_cost - 1e-9:
                    best, best_cost = k, cost
            if best != lab['pick']:
                lab['pick'], changed = best, True
                moved.add(lab['name'])
        if not changed:
            break
    left = []
    for i, lab in enumerate(labels):
        box = cur_box(lab)
        if static_cost(box) > 0 or any(
                overlap(box, cur_box(o), 1.0) > 0 for j, o in enumerate(labels) if j != i):
            left.append(lab['name'])
    print(f"라벨 {len(labels)}개: {len(moved)}개를 옮김"
          + (f" ({', '.join(sorted(moved))})" if moved else '')
          + f", 겹침이 남은 라벨 {len(left)}개" + (f" ({', '.join(left)})" if left else ''))
    result = []
    for lab in labels:
        x, y, anc, _ = lab['cands'][lab['pick']]
        result.append({'name': lab['name'], 'code': lab['code'], 'x': x, 'y': y, 'anchor': anc,
                       'texts': lab['texts']})
    return result


def build_svg(lines, group_of):
    out = [
        "<?xml version='1.0' encoding='utf-8'?>",
        f'<svg xmlns="http://www.w3.org/2000/svg" version="1.1" '
        f'viewBox="0 0 {CANVAS_W}.0 {CANVAS_H}.0" width="100%" height="100%" '
        'style="background: white;">',
    ]
    polylines = []
    for ln in lines:
        pts = smooth_polyline([(s['cx'], s['cy']) for s in ln['stations']])
        polylines.append(pts)
        d = ' '.join(f"{'M' if i == 0 else 'L'} {x} {y}" for i, (x, y) in enumerate(pts))
        out.append(
            f'<path d="{d}" fill="none" stroke="{ln["color"]}" stroke-width="3" '
            'stroke-linejoin="round" stroke-linecap="round" '
            'style="fill:none;stroke-linejoin:round;stroke-linecap:round" '
            f'data-line="{ln["code"]}" />')
    drawn = set()
    for ln in lines:
        for s in ln['stations']:
            grp = group_of[s['id']]
            if len({g['lineId'] for g in grp}) < 2:
                out.append(
                    f'<circle cx="{s["cx"]}" cy="{s["cy"]}" r="4.5" fill="{ln["color"]}" '
                    'style="stroke:white;stroke-width:1" />')
                continue
            key = min(g['id'] for g in grp)
            if key in drawn:
                continue
            drawn.add(key)
            # 묶음의 마커 중심들을 모두 덮는 알약 하나.
            xs, ys = [g['cx'] for g in grp], [g['cy'] for g in grp]
            cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
            span_x, span_y = max(xs) - min(xs), max(ys) - min(ys)
            if span_x > span_y or any(g['kind'] == 'R' for g in grp):
                w, h = max(24.0, span_x + 12.0), 8.0
            else:
                w, h = 8.0, max(24.0, span_y + 12.0)
            out.append(
                f'<rect x="{cx - w / 2}" y="{cy - h / 2}" width="{w}" height="{h}" '
                'rx="4" ry="4" style="stroke:#333;stroke-width:1.5;fill:white" />')
    for lab in place_labels(lines, group_of, polylines):
        texts = [escape(t) for t in lab['texts']]
        # 여러 줄 라벨은 기존 지도 SVG 형식을 따른다: data-station 은 줄바꿈(&#10;)으로 잇고
        # 줄마다 <tspan> (지도 빌드가 줄바꿈을 떼고 역명과 맞춘다).
        body = texts[0] if len(texts) == 1 else ''.join(
            f'<tspan x="{lab["x"]}" dy="{0 if i == 0 else int(LABEL_LINE_GAP)}">{t}</tspan>'
            for i, t in enumerate(texts))
        out.append(
            f'<text x="{lab["x"]}" y="{lab["y"]}" style="font-family:sans-serif;font-size:12px" '
            f'text-anchor="{lab["anchor"]}" data-line="{lab["code"]}" '
            f'data-station="{"&#10;".join(texts)}">{body}</text>')
    out.append('</svg>')
    return '\n'.join(out) + '\n'


def main():
    lines = parse_map()
    seg, transfers = parse_times(lines)
    group_of = group_stations(lines)
    data = build_json(lines, seg, transfers, group_of)
    for name, value in data.items():
        (JSON_DIR / f'{name}.json').write_text(
            json.dumps(value, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    SVG_OUT.write_text(build_svg(lines, group_of), encoding='utf-8')
    st = data['stations']
    print(f"역 {len(st)}개(환승 레코드 {sum(s['isTransfer'] for s in st)}개), "
          f"노선 {len(lines)}개, 연결 {len(data['connections'])}개, "
          f"환승시간 {len(data['transfer_times'])}건")
    for ln in lines:
        total = sum(seg[(a['id'], b['id'])] for a, b in zip(ln['stations'], ln['stations'][1:]))
        print(f"  {ln['name']}: {len(ln['stations'])}개 역, 주행 합 {total // 60}분(정차 제외)")


if __name__ == '__main__':
    main()
