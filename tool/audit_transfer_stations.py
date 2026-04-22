#!/usr/bin/env python3
# 환승역 데이터 정합성 감사 스크립트.
#
# assets/json/stations.json, connections.json, transfer_times.json 을 교차 검사하여
# "원인재" 같은 누락된 환승역 케이스를 식별한다. 자동 수정은 하지 않고 리포트만 출력.
#
# 검출 항목:
#   1) transferLines 에 등재된 노선인데 해당 (name, lineId) Station 레코드가 없음
#   2) isTransfer=true 로 표시된 역 쌍인데 transfer_times 키 누락
#   3) connections.json 노선의 인접 역 간 travelTimeSeconds 가 주변 중앙값 대비
#      이상치(> 2.5× median) — 중간 역이 누락됐을 가능성
#
# 사용: python3 tool/audit_transfer_stations.py

import json
import os
import statistics
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATIONS = json.load(open(os.path.join(ROOT, 'assets/json/stations.json')))
CONNS = json.load(open(os.path.join(ROOT, 'assets/json/connections.json')))
TRANSFERS = json.load(open(os.path.join(ROOT, 'assets/json/transfer_times.json')))


def report(title, rows):
    print(f'\n=== {title} ({len(rows)}건) ===')
    for r in rows:
        print(f'  • {r}')
    if not rows:
        print('  (정상)')


def main():
    # (name, lineId) → Station
    by_name_line = {(s['name'], s['lineId']): s for s in STATIONS}
    # name → {lineId set}
    lines_by_name = defaultdict(set)
    for s in STATIONS:
        lines_by_name[s['name']].add(s['lineId'])

    # === 감사 1: transferLines 에 있는 lineId 의 Station 레코드 누락 ===
    missing_variant = []
    for s in STATIONS:
        tls = s.get('transferLines') or []
        for lid in tls:
            if (s['name'], lid) not in by_name_line:
                missing_variant.append(
                    f"{s['name']} (등록: {s['lineId']}) ← transferLines 에 '{lid}' "
                    f"있지만 {s['name']}_{lid} Station 레코드 없음"
                )
    report('환승역 중 소속 노선 Station 레코드 누락', missing_variant)

    # === 감사 2: isTransfer=true 인데 다른 variant 는 isTransfer=false 인 비대칭 ===
    asymmetric_transfer = []
    processed_names = set()
    for s in STATIONS:
        if s['name'] in processed_names:
            continue
        variants = [v for v in STATIONS if v['name'] == s['name']]
        if len(variants) < 2:
            continue
        processed_names.add(s['name'])
        flags = {v['lineId']: v.get('isTransfer', False) for v in variants}
        if len(set(flags.values())) > 1:
            asymmetric_transfer.append(
                f"{s['name']} isTransfer 비대칭: {flags}"
            )
    report('환승역 isTransfer 플래그 비대칭', asymmetric_transfer)

    # === 감사 3: 환승역인데 transfer_times 키 없음 ===
    missing_transfer_times = []
    processed_pairs = set()
    for s in STATIONS:
        if not s.get('isTransfer'):
            continue
        tls = s.get('transferLines') or []
        for other_lid in tls:
            if other_lid == s['lineId']:
                continue
            pair_key = tuple(sorted([s['lineId'], other_lid]))
            key = (s['name'], pair_key)
            if key in processed_pairs:
                continue
            processed_pairs.add(key)
            forward = f"{s['name']}_{s['lineId']}_{other_lid}"
            reverse = f"{s['name']}_{other_lid}_{s['lineId']}"
            if forward not in TRANSFERS and reverse not in TRANSFERS:
                missing_transfer_times.append(f'{forward} (또는 {reverse})')
    report('transfer_times 키 누락', missing_transfer_times)

    # === 감사 4: 노선별 인접 edge travelTime 이상치 (중간 역 누락 의심) ===
    outlier_edges = []
    by_line_conn = defaultdict(list)
    for c in CONNS:
        if c.get('isTransfer'):
            continue
        by_line_conn[c['lineId']].append(c)
    for lid, edges in by_line_conn.items():
        times = [e['travelTimeSeconds'] for e in edges]
        if len(times) < 3:
            continue
        med = statistics.median(times)
        # 주변 중앙값 대비 2.5x 초과 = 이상치
        threshold = med * 2.5
        for e in edges:
            if e['travelTimeSeconds'] > threshold:
                frm = next((s['name'] for s in STATIONS
                            if s['id'] == e['fromStationId']
                            and s['lineId'] == lid), e['fromStationId'])
                to = next((s['name'] for s in STATIONS
                           if s['id'] == e['toStationId']
                           and s['lineId'] == lid), e['toStationId'])
                outlier_edges.append(
                    f'[{lid}] {frm}({e["fromStationId"]})→{to}({e["toStationId"]}) '
                    f'{e["travelTimeSeconds"]}s (중앙값 {med:.0f}s, 임계 {threshold:.0f}s)'
                )
    report('인접 edge travelTime 이상치 (중간 역 누락 의심)', outlier_edges)

    total = len(missing_variant) + len(asymmetric_transfer) + \
        len(missing_transfer_times) + len(outlier_edges)
    print(f'\n총 {total}건 감사 결과. 각 항목 수동 검토 후 별도 수정.')
    sys.exit(0 if total == 0 else 1)


if __name__ == '__main__':
    main()
