#!/usr/bin/env python3
"""시간표 수집 진행 상황 실시간 대시보드.

사용법:
    python3 tool/dashboard.py            # 1초마다 새로고침
    python3 tool/dashboard.py --once     # 한 번만 출력
    python3 tool/dashboard.py --interval=2  # 2초 간격
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATIONS_JSON = ROOT / 'assets' / 'json' / 'stations.json'
TIMETABLES_DIR = ROOT / 'data' / 'timetables'

# parse_namuwiki_transfer.py와 동일한 매핑
LINE_API_NAME = {
    '1': '1호선',
    '3': '3호선',
    '4': '4호선',
    '5': '5호선',
    '7': '7호선',
    '8': '8호선',
    '9': '9호선',
    'SB': '신분당선',
    '경의중앙': '경의중앙선',
    '경춘': '경춘선',
    '공항철도': '공항철도',
    '수인분당': '수인분당선',
    '신림': '신림선',
    '인천1': '인천1호선',
    '인천2': '인천2호선',
    '김포골드': '김포골드라인',
    '서해': '서해선',
    '의정부': '의정부경전철',
    '우이신설': '우이신설선',
}

# ANSI 색상
RESET = '\033[0m'
BOLD = '\033[1m'
GREEN = '\033[32m'
YELLOW = '\033[33m'
RED = '\033[31m'
BLUE = '\033[34m'
GRAY = '\033[90m'
CYAN = '\033[36m'


def get_line_targets():
    """노선별 (역 수, 예상 호출 수, 역 이름 셋) 반환."""
    with STATIONS_JSON.open('r', encoding='utf-8') as f:
        stations = json.load(f)
    by_line = defaultdict(set)
    for s in stations:
        by_line[s['lineId']].add(s['name'])
    targets = {}
    for lid, names in by_line.items():
        if lid in LINE_API_NAME:
            targets[lid] = (len(names), len(names) * 2, names)  # 상행+하행
        else:
            targets[lid] = (len(names), 0, names)  # API 미지원
    return targets


def scan_cache(targets):
    """노선별 (수집된 수, 빈 응답 수) 반환."""
    if not TIMETABLES_DIR.exists():
        return {}
    pattern = re.compile(r'^([^_]+)_(.+)_(상행|하행)\.json$')
    by_line = defaultdict(lambda: {'count': 0, 'empty': 0, 'last_mtime': 0})

    for f in TIMETABLES_DIR.iterdir():
        if not f.is_file() or not f.name.endswith('.json'):
            continue
        m = pattern.match(f.name)
        if not m:
            continue
        lid = m.group(1)
        size = f.stat().st_size
        mtime = f.stat().st_mtime
        by_line[lid]['count'] += 1
        by_line[lid]['last_mtime'] = max(by_line[lid]['last_mtime'], mtime)
        # 빈 응답: 파일 크기가 작음 (보통 "[]" = 2bytes ~ 50bytes)
        if size < 100:
            by_line[lid]['empty'] += 1
    return by_line


def is_fetcher_running():
    """fetch_timetables.dart 프로세스 확인."""
    try:
        out = subprocess.run(
            ['ps', 'aux'], capture_output=True, text=True, timeout=2
        ).stdout
        for line in out.split('\n'):
            if 'fetch_timetables' in line and 'grep' not in line:
                return True
    except Exception:
        pass
    return False


def fmt_bar(filled, total, width=20):
    if total == 0:
        return GRAY + ('─' * width) + RESET + f' {GRAY}N/A{RESET}'
    ratio = filled / total
    fill = int(ratio * width)
    bar = GREEN + '█' * fill + GRAY + '░' * (width - fill) + RESET
    pct = f'{ratio * 100:5.1f}%'
    return f'{bar} {pct}'


def fmt_age(mtime):
    if mtime == 0:
        return GRAY + '   -   ' + RESET
    age = time.time() - mtime
    if age < 60:
        return f'{int(age)}초 전'
    if age < 3600:
        return f'{int(age / 60)}분 전'
    return f'{int(age / 3600)}시간 전'


def render(start_time):
    targets = get_line_targets()
    cache = scan_cache(targets)
    running = is_fetcher_running()

    lines = []
    now = datetime.now().strftime('%H:%M:%S')
    elapsed = int(time.time() - start_time)
    elapsed_str = f'{elapsed // 60}분 {elapsed % 60}초'

    lines.append(f'{BOLD}━━━ 시간표 수집 대시보드 ━━━{RESET}  {GRAY}{now}{RESET}')
    status = (GREEN + '● 실행 중' + RESET) if running else (RED + '● 정지' + RESET)
    lines.append(f'fetch_timetables.dart: {status}   대시보드 가동: {elapsed_str}')
    lines.append('')

    total_done = sum(c['count'] for c in cache.values())
    total_target = sum(t[1] for t in targets.values() if t[1] > 0)
    total_empty = sum(c['empty'] for c in cache.values())
    overall_pct = total_done / total_target * 100 if total_target else 0
    lines.append(
        f'{BOLD}전체 진행:{RESET} {total_done:>5}/{total_target} 호출  '
        f'({CYAN}{overall_pct:5.1f}%{RESET})  '
        f'빈 응답 {YELLOW}{total_empty}{RESET}'
    )
    lines.append('')

    # 노선별 표
    lines.append(
        f'{BOLD}{"노선":<6} {"진행":<32} {"역수":<6} {"빈응답":<6} {"마지막":<10}{RESET}'
    )
    lines.append(GRAY + '─' * 68 + RESET)

    for lid in sorted(LINE_API_NAME.keys(), key=lambda x: (
        # 1~9호선 먼저, 그 다음 다른 노선
        (0, int(x)) if x.isdigit() else (1, x)
    )):
        if lid not in targets:
            continue
        station_count, target_count, _ = targets[lid]
        c = cache.get(lid, {'count': 0, 'empty': 0, 'last_mtime': 0})
        bar = fmt_bar(c['count'], target_count)
        age = fmt_age(c['last_mtime'])
        line_name = LINE_API_NAME[lid]
        empty_str = f"{YELLOW}{c['empty']}{RESET}" if c['empty'] else f"{GRAY}0{RESET}"
        lines.append(
            f'{lid:<6} {bar}  {station_count:>3}    {empty_str:<6}    {age:<10}'
        )

    # 미지원 노선
    unsupported = sorted(lid for lid in targets if lid not in LINE_API_NAME)
    if unsupported:
        lines.append('')
        lines.append(f'{GRAY}API 미지원: {", ".join(unsupported)}{RESET}')

    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--once', action='store_true', help='한 번만 출력')
    ap.add_argument('--interval', type=float, default=1.0, help='새로고침 간격(초)')
    args = ap.parse_args()

    start_time = time.time()
    if args.once:
        print(render(start_time))
        return

    try:
        while True:
            # 화면 클리어
            os.system('clear' if os.name != 'nt' else 'cls')
            print(render(start_time))
            print()
            print(f'{GRAY}Ctrl+C로 종료. 새로고침 간격 {args.interval}초.{RESET}')
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print('\n종료.')
        sys.exit(0)


if __name__ == '__main__':
    main()
