#!/usr/bin/env python3
"""assets/json/line_schedules.json 의 경의중앙선 시간표를 코레일 엑셀에서 주입한다.

역별 시간표(`t`)가 주 산출물이고, 거기서 노선 대표값 `f`/`l`(첫차·막차)과
`p` 첫 band 의 시작 시각까지 도출해 함께 기록한다(아래 `derive_first_last`).

경의중앙선(K01~K56)은 두 시간표 API 모두 미제공이라(서울 열린데이터광장은 서울교통공사
운영 노선만, getTrainSch 는 국가철도공단 제공분만) 코레일이 공개하는 엑셀을 유일 소스로 쓴다.

데이터 출처
-----------
코레일 "열차운임/시간표" 게시판 https://www.korail.com/ticket/reserve/train-timeTable
  - "경의중앙선, 경춘선(ITX-청춘), 서해선 전동열차 평일 시각표(<시행일>부터)"
  - "경의중앙선, 경춘선(ITX-청춘), 서해선 전동열차 휴일 시각표(<시행일>부터)"
게시판의 `다운로드` 링크는 `/file/cubedata/COMMON/jfile/...xlsx` 직링크다.
받은 파일은 assets/excel/ 에 `center_line_{wd,we}<시행일 YYMMDD>.xlsx` 로 둔다
(assets/excel 은 pubspec assets 에 없어 앱 번들에 들어가지 않는다).

⚠ 2026-09-01 시행분부터 워크북 구조가 바뀌었다. 그 이전(center_line260228.xlsx)은
  평일·휴일이 한 파일에 8시트(`경의중앙선 상행(평일)` 식)였고, 지금은 평일/휴일이
  파일로 갈리며 시트명에 요일이 없다. 이 도구는 **신 구조만** 읽는다.

엑셀 구조
---------
한 시트 = 한 노선의 한 방향. 열 = 열차 1편, 행 = 역.
    (0행) 조정안                     ← 신 구조에만 있는 머리글. 위치로 찾지 않는다.
    시발역 | 청량리 | 덕소 | ...
    종착역 | 문산   | 문산 | ...
    열차번호 | K5002 | K5004 | ...   ← 이 행을 찾아 기준점으로 삼는다
    지평   | (도착시각들)            ← 역명이 있는 행 = **도착**
           | (출발시각들)            ← 바로 다음 역명 없는 행 = **출발**
시각은 엑셀 serial(1.0 = 24시간) 소수이거나 "H:MM[:SS]" 문자열이다.

우리가 담는 값은 **출발시각**이다. 역명 행만 있고 다음 행이 비어있지 않으면 그 역엔
출발 자체가 없다는 뜻이라 건너뛴다(종착역·경유표시역). 종착역은 도착시각만 있으므로
자연히 빠진다 — getTrainSch 계열 도구의 "당역종착 제외"와 같은 효과다.

분 단위 변환은 **반올림(half-up)** 이다. 실측상 초 단위는 :00 과 :30 뿐이라
05:04:30 → 305 가 된다. 내림을 쓰면 기존 데이터와 1분씩 어긋난다.

방향 매핑 (t 인덱스 0=상행/1=하행은 앱 기준이며 코레일 라벨과 다르다)
-----------------------------------------------------------------
앱의 `t` 인덱스는 "역ID 감소 방향 = 0, 증가 방향 = 1" 이다(`line_direction.dart`).
코레일 라벨은 노선마다 기준이 달라 시트별로 뒤집힌다:
    경의중앙선 상행(→문산, K52→K01 = ID 감소)          → idx 0
    경의중앙선 하행(→지평/용문, ID 증가)                → idx 1
    경의선     상행(→서울역, K01→K54 = ID 증가)         → idx 1
    경의선     하행(→문산/운천/임진강, ID 감소)          → idx 0
두 시트의 값은 역 단위로 합친다(문산~가좌 구간은 두 계통이 함께 지난다).

검증 (2026-09-11)
----------------
이 파일의 추출 로직(`extract_sheet`/`cell_to_minutes`/`collect`)을 구 엑셀
(`assets/excel/center_line260228.xlsx`)에 적용해, 그 엑셀로 만들어졌던 그때의
JSON 과 **56역 × 2방향 × 2요일 224건 전부 일치**함을 확인한 뒤 신 엑셀로 넘어갔다.

⚠ 이 검증은 **지금 이 도구를 그대로 실행해서는 재현되지 않는다.** 두 가지 이유다:
  (1) 구 워크북은 시트명이 `경의중앙선 상행(평일)` 형식이라 `SHEET_DIRECTION` 에 없다.
  (2) JSON 이 이미 신 데이터로 갱신돼 비교 대상이 사라졌다.
다시 확인해야 한다면 `SHEET_DIRECTION` 을 아래 구 시트명 표로 바꿔 `collect()` 를
호출하고, 결과를 `git show <구 커밋>:assets/json/line_schedules.json` 의 경의중앙
`t` 와 비교하면 된다(요일별로 워크북이 같으므로 두 번 호출):
    평일: {'경의중앙선 상행(평일)': 0, '경의중앙선 하행(평일)': 1,
           '경의선 상행(평일)': 1, '경의선 하행(평일)': 0}
    휴일: 같은 이름의 (휴일) 판

실행
----
    python3 tool/build_center_line_timetable.py \
        --wd=assets/excel/center_line_wd260901.xlsx \
        --we=assets/excel/center_line_we260901.xlsx
    python3 tool/build_center_line_timetable.py --dry-run   # 쓰지 않고 요약만

4원칙 무관 — 실시간 열차 애니메이션과 무관한 정적 데이터 생성기다.
"""

import argparse
import glob
import json
import math
import os
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

# CWD 와 무관하게 저장소 루트를 기준으로 삼는다(tool/extract_express_skip_edges.py 관례).
ROOT = Path(__file__).resolve().parent.parent

LINE_ID = '경의중앙'
SCHEDULES = ROOT / 'assets/json/line_schedules.json'
STATIONS = ROOT / 'assets/json/stations.json'
# 인자를 주지 않으면 **파일명 정렬상 가장 최신** 시행분을 쓴다. 파일명이
# center_line_{wd,we}<YYMMDD>.xlsx 라 사전순 = 시행일순이다. 특정 파일을
# 못박지 않는 이유: 다음 개정판을 --wd/--we 로 적용한 뒤 문서의 무인자 명령을
# 그대로 실행하면 옛 엑셀로 최신 JSON 을 덮어쓰기 때문(역 집합이 같아
# 손실 가드도 발동하지 않는다).
WD_GLOB = str(ROOT / 'assets/excel/center_line_wd*.xlsx')
WE_GLOB = str(ROOT / 'assets/excel/center_line_we*.xlsx')

# 시트명 → t 인덱스. 위 "방향 매핑" 주석 참고. 없는 시트는 실행을 중단시킨다
# (파일만 바뀌고 시트명이 달라진 것을 침묵으로 넘기지 않기 위해).
SHEET_DIRECTION = {
    '경의중앙선 상행': 0,
    '경의중앙선 하행': 1,
    '경의선 상행': 1,
    '경의선 하행': 0,
}

# 엑셀 역명(칸 너비 때문에 줄여 적힘) → 앱 역명(stations.json).
ABBREV = {
    '1양정': '양정',
    '1양원': '양원',
    '효창공': '효창공원앞',
    '홍대입': '홍대입구',
    '디엠시': '디지털미디어시티',
    '항공대': '한국항공대',
    '서울': '서울역',
}

# 앱 노선 데이터에 없는 역·행. 도라산(민통선 내)과 경의선 신촌은 stations.json 에 없다.
# '연계열번'은 역이 아니라 연계 열차번호 표기 행으로, 신 엑셀엔 없지만 **구 엑셀로
# 재현 검증을 돌릴 때**(헤더 "검증" 항목) 필요해 남겨 둔다.
IGNORED = {'도라산', '신촌', '연계열번'}

NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
RNS = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'


# ── 의존성 없는 최소 xlsx 리더 ────────────────────────────────────────────────
# openpyxl 을 쓰지 않는다: 이 저장소는 파이썬 가상환경을 전제하지 않으며,
# 필요한 기능이 "문자열/숫자 셀 읽기"뿐이라 표준 라이브러리로 충분하다.

def _shared_strings(z):
    try:
        blob = z.read('xl/sharedStrings.xml')
    except KeyError:
        return []
    return [''.join(t.text or '' for t in si.iter(f'{NS}t'))
            for si in ET.fromstring(blob).findall(f'{NS}si')]


def _sheet_targets(z):
    """시트명 → zip 내부 경로."""
    rels = {r.get('Id'): r.get('Target')
            for r in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
    out = {}
    for s in ET.fromstring(z.read('xl/workbook.xml')).iter(f'{NS}sheet'):
        target = rels[s.get(f'{RNS}id')].lstrip('/')
        if not target.startswith('xl/'):
            target = 'xl/' + target
        out[s.get('name')] = target
    return out


def _col_index(ref):
    """"BC12" → 0-based 열 번호."""
    letters = re.match(r'([A-Z]+)', ref).group(1)
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def read_sheet(path, sheet):
    """시트를 2차원 문자열 배열로. 빈 행은 버린다."""
    with zipfile.ZipFile(path) as z:
        shared = _shared_strings(z)
        targets = _sheet_targets(z)
        if sheet not in targets:
            sys.exit(f'{os.path.basename(path)}: 시트 "{sheet}" 가 없습니다.\n'
                     f'  있는 시트: {sorted(targets)}\n'
                     '  워크북 구조가 또 바뀌었다면 SHEET_DIRECTION 을 고치세요.')
        rows = []
        for row in ET.fromstring(z.read(targets[sheet])).iter(f'{NS}row'):
            cells = {}
            for c in row.findall(f'{NS}c'):
                ci = _col_index(c.get('r'))
                ctype = c.get('t')
                if ctype == 'inlineStr':
                    val = ''.join(t.text or '' for t in c.iter(f'{NS}t'))
                else:
                    v = c.find(f'{NS}v')
                    if v is None:
                        val = ''
                    elif ctype == 's':
                        val = shared[int(v.text)]
                    else:
                        val = v.text or ''
                cells[ci] = val.strip()
            # 값이 하나도 없는 행(서식만 있는 셀로 이루어진 행)은 버린다.
            # 남겨 두면 역명 행과 출발 행 사이에 끼어 그 행을 출발 행으로
            # 오인하고, 진짜 출발 행은 이름 없는 행으로 건너뛰어 **예외 없이**
            # 그 역의 출발이 통째로 사라진다.
            if any(cells.values()):
                rows.append([cells.get(i, '') for i in range(max(cells) + 1)])
    return rows


# ── 추출 ────────────────────────────────────────────────────────────────────

# 시각으로 인정하는 상한(분). 심야 연장까지 봐도 30시간이면 충분하다.
MAX_MINUTES = 30 * 60


def cell_to_minutes(value):
    """셀 값 → 자정 기준 분(half-up). 시각으로 볼 수 없으면 None.

    범위를 벗어난 값은 None 이 아니라 `ValueError` 다 — 출발 행에 주석용 숫자가
    섞였다는 뜻이라 조용히 버리면 엉뚱한 시각이 들어간다('5' → 7200분).
    """
    if not value:
        return None
    text = value.strip()
    if ':' in text:
        parts = text.split(':')
        try:
            sec = int(parts[0]) * 3600 + int(parts[1]) * 60
            if len(parts) > 2:
                sec += int(parts[2])
        except ValueError:
            return None
    else:
        try:
            sec = round(float(text) * 86400)
        except ValueError:
            return None
    minutes = math.floor(sec / 60 + 0.5)
    if not 0 <= minutes <= MAX_MINUTES:
        raise ValueError(f'시각 범위를 벗어난 값: {value!r} → {minutes}분')
    return minutes


def extract_sheet(path, sheet):
    """{앱 역명: [출발분...]} — 정렬·중복제거는 호출자에서."""
    rows = read_sheet(path, sheet)
    try:
        head = next(i for i, r in enumerate(rows) if r and r[0] == '열차번호')
    except StopIteration:
        raise ValueError(f'{path}/{sheet}: "열차번호" 행을 찾지 못했습니다')

    heads = sum(1 for r in rows if r and r[0] == '열차번호')
    if heads != 1:
        print(f'⚠ {os.path.basename(path)}/{sheet}: "열차번호" 행이 {heads}개입니다 '
              '— 첫 블록만 읽습니다. 시트 구조 변경 여부를 확인하세요.')

    out = {}
    unparsed = []
    i = head + 1
    while i < len(rows):
        name = (rows[i][0] if rows[i] else '').strip()
        if not name:
            i += 1
            continue
        nxt = rows[i + 1] if i + 1 < len(rows) else None
        # 다음 행의 역명이 비어 있으면 그 행이 이 역의 출발시각 행이다.
        has_departure_row = nxt is not None and not (nxt[0] if nxt else '').strip()
        if has_departure_row and name not in IGNORED:
            station = ABBREV.get(name, name)
            for cell in nxt[1:]:
                minutes = cell_to_minutes(cell)
                if minutes is not None:
                    out.setdefault(station, []).append(minutes)
                elif cell:
                    # 비어 있지 않은데 시각으로 못 읽은 셀 — 조용히 버리면
                    # 그 편이 빠진 것을 알 수 없다.
                    unparsed.append(f'{station}: {cell!r}')
        i += 2 if has_departure_row else 1
    if unparsed:
        raise ValueError(f'{path}/{sheet}: 시각으로 읽지 못한 셀 {len(unparsed)}건 '
                         f'(앞 5건: {unparsed[:5]})')
    return out


def collect(path):
    """한 워크북(요일 하나) → {t 인덱스: {앱 역명: 정렬된 출발분}}."""
    merged = {0: {}, 1: {}}
    for sheet, idx in SHEET_DIRECTION.items():
        for station, minutes in extract_sheet(path, sheet).items():
            merged[idx].setdefault(station, []).extend(minutes)
    return {idx: {k: sorted(set(v)) for k, v in table.items()}
            for idx, table in merged.items()}


# ── 노선 대표값(f/l) 도출 ────────────────────────────────────────────────────

# 자정 넘김 인코딩 경계. `t` 는 자정 이후 출발을 1440+ 가 아니라 0~1439 로 담는
# 노선이 있고 경의중앙이 그렇다(00:39 → 39). 앱도 같은 경계를 쓴다
# (`departure_candidates.dart` 의 lateNightCutoffMinutes = 240).
LATE_NIGHT_CUTOFF = 240


def wall(m):
    """분 → 벽시계 "HH:MM"(자정 넘김은 24시간으로 접는다)."""
    return f'{(m % 1440) // 60:02d}:{(m % 1440) % 60:02d}'


def parse_minutes(hhmm):
    """"HH:MM" → 자정 기준 분."""
    h, m = hhmm.split(':')
    return int(h) * 60 + int(m)


def band_end_minutes(start, end):
    """band 끝을 운영일 분으로. `TimePeriod.endMinutes` 를 그대로 미러한다 —
    "00:00" 은 하루의 끝(1440), 그 외에는 끝이 시작보다 **작을 때만** +1440.

    ⚠ 문자열끼리 비교하면 `"05:31" >= "00:00"` 이 참이 되어 자정 넘김 band 를
    "이미 지난 band" 로 오판한다. 경의중앙 `p[0]` 끝은 현재 07:00/23:00 이라
    발동하지 않지만, 우이신설 주말처럼 단일 band 끝이 "00:00" 이 되면 문제가 된다.
    Dart 판(`tool/derive_representative.dart` 의 `bandEndMinutes`)과 같은 규칙.
    """
    e = parse_minutes(end)
    if e == 0:
        return 1440
    return e + 1440 if e < parse_minutes(start) else e


def operating_minutes(m):
    """벽시계 분 → **운영일** 분(자정 넘김은 1440+)."""
    if m >= 1440:
        return m
    return m + 1440 if m < LATE_NIGHT_CUTOFF else m


def derive_first_last(table, idx):
    """한 방향의 (첫차, 막차) 벽시계 문자열. 출발이 없으면 None.

    `f`/`l` 은 원래 `extract_schedules.dart` 가 노선마다 **앵커역 한 곳**에서
    뽑는 대표값이지만, 경의중앙은 API 가 없어 그 자리에 하드코딩 추정치
    (평일 05:10~23:40)가 들어 있었다. 실제 `t` 는 05:00 에 시작해 자정을 넘겨
    끝나므로 이름("노선 첫차·막차")과 값이 어긋났다. 유일 소스인 `t` 에서
    **노선 전체 최소/최대**로 도출해 그 어긋남을 없앤다.

    ⚠ 사용자에게 보이는 동작은 거의 바뀌지 않는다. 실측(평일·토·일 각
    56역 × 2방향 × 1440분 = 483,840 조합 전수 대조): 답이 달라진 것은 `t` 가
    없는 종점 방향 3개(K53 하행·K54 하행·K55 상행)뿐이고 — 평일 1,230건,
    토·일 각 4,137건 — `t` 를 가진 나머지 53역은 전부 동일하다. **"운행 종료"
    (null)로 바뀐 조합은 0건이다**(아래 `p[0]` 정렬 덕분. 정렬 전에는 평일
    30건·휴일 44건이 null 로 떨어졌다). 그 3개 방향엔 실제 출발 열차가 없어
    배차간격 폴백이 만들어내던 가짜 답이 달라졌을 뿐이다(주말 건수가 큰 것은
    `p[0]` 시작이 05:30 → 05:04 로 옮겨지며 배차 그리드 위상이 함께 밀리기
    때문이다).

    `t` 가 있는 역이 영향받지 않는 이유: 그 경로에서 `f` 는 "전날 자정 넘김
    분을 먼저 볼지"만 정하는데, 경의중앙 `t` 의 자정 넘김은 0~239 이고 1440 을
    넘는 값이 없어(정확히 1440 인 wd K16 상행·K38 하행은 `cur+1440` 초과가 될
    수 없어 매칭 불가) 전날 조회가 항상 빈손으로 끝나 오늘 리스트로 폴스루한다.
    ⚠ 이 작업 초기에 "`f`=05:10 이라 05:00~05:09 조회가 전날로 폴백한다"고
    진단했으나 **틀렸다**(위 이유). 같은 오진을 반복하지 말 것 — 경의중앙의
    0~1439 인코딩은 `departure_candidates.dart` 와
    `line_schedule_anchor_sanity_test.dart` 에 이미 적혀 있던 사실이다.

    고치는 이유는 값 자체의 정확성이다 — 첫차·막차를 화면에 쓰는 기능이
    생기면 그 즉시 오답이 된다(2026-08-13 앵커역 정정과 같은 사유).

    막차는 벽시계로 적는다("00:39"). `DaySchedule.lastTrainMinutes` 가
    첫차 이하이면 1440 을 더하므로 운영일 분으로 정확히 복원된다.
    """
    values = [m for dirs in table.values() if dirs[idx] for m in dirs[idx]]
    if not values:
        return None
    same_day = [m for m in values if LATE_NIGHT_CUTOFF <= m < 1440]
    if not same_day:
        # 전부 심야 인코딩인 방향 — 첫차를 정할 근거가 없다.
        return None
    first = min(same_day)
    last = max(operating_minutes(m) for m in values)
    return wall(first), wall(last)


# ── 병합 ────────────────────────────────────────────────────────────────────

def hhmm(m):
    return f'{(m // 60) % 24:02d}:{m % 60:02d}' + ('+' if m >= 1440 else '')


def latest(pattern):
    """glob 중 파일명 정렬상 마지막(= 가장 최신 시행분) 경로."""
    found = sorted(glob.glob(pattern))
    if not found:
        sys.exit(f'엑셀을 찾지 못했습니다: {pattern}')
    return found[-1]


def main():
    ap = argparse.ArgumentParser(description='경의중앙선 역별 시간표를 코레일 엑셀에서 주입')
    ap.add_argument('--wd', help='평일 시각표 xlsx (기본: center_line_wd*.xlsx 중 최신)')
    ap.add_argument('--we', help='휴일 시각표 xlsx (기본: center_line_we*.xlsx 중 최신)')
    ap.add_argument('--dry-run', action='store_true', help='파일을 쓰지 않고 요약만 출력')
    ap.add_argument('--allow-loss', action='store_true',
                    help='데이터 손실·미지 역명 경고를 무시하고 진행')
    args = ap.parse_args()

    wd_path = args.wd or latest(WD_GLOB)
    we_path = args.we or latest(WE_GLOB)
    for path in (wd_path, we_path):
        if not os.path.exists(path):
            sys.exit(f'엑셀이 없습니다: {path}')

    with open(STATIONS, encoding='utf-8') as f:
        stations = [s for s in json.load(f) if s['lineId'] == LINE_ID]
    name_to_id = {s['name']: s['id'] for s in stations}

    with open(SCHEDULES, encoding='utf-8') as f:
        schedules = json.load(f)
    line = next((s for s in schedules if str(s['id']) == LINE_ID), None)
    if line is None:
        sys.exit(f'{SCHEDULES} 에 노선 {LINE_ID} 이 없습니다')

    unknown = set()
    lost = []
    missing = []
    for day, path in (('wd', wd_path), ('we', we_path)):
        collected = collect(path)
        new_t = {}
        for idx in (0, 1):
            for station, minutes in collected[idx].items():
                sid = name_to_id.get(station)
                if sid is None:
                    unknown.add(station)
                    continue
                new_t.setdefault(sid, [None, None])[idx] = minutes
        # `t` 키 순서는 **역ID 오름차순(K01…K56)** 으로 고정한다. 엑셀 시트 순서
        # (지평→문산)를 그대로 쓰면 키 순서가 뒤집히는데, 맵 순회 순서에 의존하는
        # 소비자·테스트가 그 때문에 다른 역을 집는다(실제로
        # `departure_candidates_real_data_test` 의 심야 인코딩 가드가 깨졌다).
        # stations.json 의 파일 순서는 K55·K56 이 앞에 있어 쓰지 않는다.
        new_t = {sid: new_t[sid] for sid in sorted(new_t)}

        old_t = (line.get(day) or {}).get('t') or {}
        old_total = sum(len(v or []) for dirs in old_t.values() for v in dirs)
        new_total = sum(len(v or []) for dirs in new_t.values() for v in dirs)
        changed = [sid for sid in set(old_t) & set(new_t) if old_t[sid] != new_t[sid]]
        removed = sorted(set(old_t) - set(new_t))
        added = sorted(set(new_t) - set(old_t))
        lost.extend(f'{day}:{sid} (역 전체)' for sid in removed)
        # 방향 하나만 비는 경우는 역 집합 비교로는 안 잡힌다.
        for sid in sorted(set(old_t) & set(new_t)):
            for i in (0, 1):
                if (old_t[sid][i] or []) and not (new_t[sid][i] or []):
                    lost.append(f'{day}:{sid}[{i}]')
        # 역·방향은 남았는데 편수만 대량으로 빠지는 경우(시트 매핑 누락 등).
        if old_total and new_total < old_total * 0.9:
            lost.append(f'{day}: 총출발 {old_total} → {new_total} (10% 이상 감소)')

        print(f'━━ {day} ({os.path.basename(path)})')
        print(f'   역 {len(old_t)} → {len(new_t)}, 총출발 {old_total} → {new_total}, '
              f'시각변경 {len(changed)}역')
        if added:
            print(f'   신규 역: {added}')
        if removed:
            print(f'   ⚠ 데이터가 사라진 역: {removed}')
        for sid in sorted(changed)[:5]:
            o, n = old_t[sid], new_t[sid]
            for i in (0, 1):
                ov, nv = sorted(o[i] or []), sorted(n[i] or [])
                if ov != nv:
                    print(f'     {sid}[{i}] {len(ov)}편 → {len(nv)}편 '
                          f'({hhmm(ov[0]) if ov else "-"}~{hhmm(ov[-1]) if ov else "-"} → '
                          f'{hhmm(nv[0]) if nv else "-"}~{hhmm(nv[-1]) if nv else "-"})')

        missing.extend(f'{day}:{s["id"]}' for s in stations if s['id'] not in new_t)

        day_obj = line.get(day)
        if not isinstance(day_obj, dict):
            sys.exit(f'{LINE_ID}.{day} 객체가 없습니다')
        day_obj['t'] = new_t

        # f/l 도 같은 `t` 에서 도출한다. 방향별로 따로 뽑되, 한 방향이라도
        # 근거가 없으면 그 방향은 기존 값을 남긴다(없는 값을 지어내지 않는다).
        old_f = list(day_obj.get('f') or ['', ''])
        old_l = list(day_obj.get('l') or ['', ''])
        new_f, new_l = list(old_f), list(old_l)
        for idx in (0, 1):
            derived = derive_first_last(new_t, idx)
            if derived is None:
                if not old_f[idx] or not old_l[idx]:
                    # 빈 문자열을 남기면 앱이 parseTimeToMinutes('') 에서 죽는다.
                    sys.exit(f'{day} idx{idx}: 출발이 없고 기존 f/l 도 없어 '
                             '값을 정할 수 없습니다')
                print(f'   ⚠ {day} idx{idx}: 출발이 없어 f/l 을 도출하지 못해 '
                      '기존 값을 유지합니다.')
                continue
            new_f[idx], new_l[idx] = derived
        if (new_f, new_l) != (old_f, old_l):
            print(f'   f {old_f} → {new_f}')
            print(f'   l {old_l} → {new_l}')
        day_obj['f'] = new_f
        day_obj['l'] = new_l

        # 첫 배차 band 의 시작을 도출된 첫차에 맞춘다.
        #
        # `p` 는 이 노선에서 여전히 추정치지만, `f` 만 당기고 band 를 두면
        # 그 사이(예: 05:00~05:09)를 덮는 band 가 없어 `_findNextByHeadway` →
        # `_findPeriod` 가 null 을 돌려준다 = "운행 종료" 오판. 실측으로 평일
        # 30건·휴일 44건이 그렇게 떨어졌다(모두 `t` 가 없는 종점 방향이라
        # 실사용 영향은 없지만, f 와 p 가 어긋난 상태 자체를 남기지 않는다).
        #
        # band 의 **시작만** 옮기고 배차 간격과 끝은 건드리지 않는다.
        # ⛔ **꼬리 갭(마지막 band 끝 ~ `l`)은 의도적으로 남긴다.** 평일이면
        # 23:40~00:39 가 여전히 null 이다. 머리 갭과 달리 여기서 끝을 `l` 까지
        # 늘리면 배차간격이 **실재하지 않는 심야 출발을 지어낸다**(20분마다
        # 00:00, 00:20 …). 머리 갭은 "이미 있는 첫차를 못 찾는" 문제라 메우고,
        # 꼬리 갭은 "없는 열차를 만드는" 문제라 두는 것이다 — 같은 논리로
        # 끝까지 늘리지 말 것.
        # `p` 는 방향 공용이므로 두 방향 f 중 **이른 쪽**에 맞춘다(늦은 방향은
        # `currentMinutes < firstTrainMinutes` 게이트가 먼저 막아 준다).
        bands = day_obj.get('p')
        if isinstance(bands, list) and bands:
            earliest = min(parse_minutes(f) for f in new_f)
            first_end = bands[0][1]
            # `!=` 로 양방향 정렬한다 — 다음 시행분에서 첫차가 늦어졌는데 한쪽만
            # 당기면 `p[0].start` 가 옛 값에 남아 "도출 첫차에 맞춘다"가 깨진다.
            # 단 첫 band 의 끝을 넘기면 band 가 뒤집히므로 그때는 두고 경고한다.
            if parse_minutes(bands[0][0]) != earliest:
                if earliest >= band_end_minutes(bands[0][0], first_end):
                    print(f'   ⚠ {day}: 도출 첫차 {wall(earliest)} 가 첫 band 끝 '
                          f'{first_end} 이후라 p[0] 을 그대로 둡니다.')
                else:
                    print(f'   p[0] 시작 {bands[0][0]} → {wall(earliest)} '
                          '(도출 첫차에 맞춤)')
                    bands[0][0] = wall(earliest)

    if unknown:
        # 역 개명·약칭 변경·신설역이면 ABBREV 를 고쳐야 한다. 경고만 하고 넘어가면
        # 그 역 시간표가 통째로 빠진 채 성공처럼 보이므로 기본은 중단이다.
        known_drops = IGNORED - {'연계열번'}
        surprises = sorted(unknown - known_drops)
        print(f'\n⚠ stations.json 에 없어 버린 역명: {sorted(unknown)}')
        if surprises and not args.allow_loss:
            sys.exit(f'모르는 역명이 있습니다: {surprises}\n'
                     'ABBREV/IGNORED 를 확인하세요 (의도한 것이면 --allow-loss).')
    if lost and not args.allow_loss:
        sys.exit(f'\n기존에 있던 데이터가 비었습니다: {lost}\n'
                 '엑셀 시트나 역명 매핑을 확인하세요 (의도한 변경이면 --allow-loss).')

    if missing:
        print(f'\n⚠ 시간표가 없는 역: {missing}')

    if args.dry_run:
        print('\n--dry-run: 파일을 쓰지 않았습니다.')
        return

    with open(SCHEDULES, 'w', encoding='utf-8') as f:
        f.write(json.dumps(schedules, ensure_ascii=False, indent=2))
    print(f'\n{SCHEDULES} 갱신 완료.')


if __name__ == '__main__':
    main()
