// 서울교통공사 공식 "서울 도시철도 환승정보" 데이터셋을 파싱해
// `data/transfer_guides.csv` (v2 스키마)를 생성하는 빌드 도구.
//
// 사용법:
//   dart run tool/import_official_transfer_guides.dart
//
// 배경: 나무위키 파서(`tool/parse_namuwiki_transfer.py`)는 (1) 방향 판정
// 로직을 파이썬으로 이중 구현해야 해서 `lib/core/utils/line_direction.dart`
// 와 드리프트할 위험이 있고, (2) 나무위키 값 자체가 공식 데이터와 대조 시
// 45%(336건 중 153건) 불일치했다. 공식 데이터셋(공공데이터포털 15098252
// `서울교통공사_서울 도시철도 환승정보`, `tool/data/seoul_metro_transfer_guides_official.csv`)
// 을 주 소스로 전환한다.
//
// 이 도구를 **Dart** 로 쓴 핵심 이유: `lib/core/utils/line_direction.dart`
// 의 `isDownBetween` 을 직접 import 해서 재사용한다. 방향 판정 로직을 다시
// 파이썬으로 미러링하지 않는다 — 미러 드리프트가 이번 마이그레이션 이전
// 오안내 버그(9호선/공항철도 반전, 사당 목적방향 뭉개짐)의 근본 원인이었다.
//
// ─────────────────────────────────────────────────────────────────────────
// 공식 CSV 스키마 (UTF-8 BOM):
//   고유번호,환승시작역,환승시작 코드,환승시작 호선,하차 열차 방면,
//   하차위치(호차),하차위치(문),환승종료역,환승 열차 방면,
//   환승 승차위치(호차),환승 승차위치(문),소요시간
//
// 핵심 성질(사용자 확인, 재조사 불필요):
//   - "하차 열차 방면"/"환승 열차 방면"은 **종착역이 아니라 바로 옆 역
//     이름**이다. 따라서 `isDownBetween(현재역ID, 옆역ID, 노선)` 에 그대로
//     넣으면 상/하행이 나온다 — 종착역 역추적이 필요 없다(나무위키 파서의
//     `find_first_hop_id` BFS가 여기서는 불필요).
//   - "환승종료역"은 목적지 **역** 코드가 아니라 (같은 물리 역의) 목적
//     **노선/승강장** 코드다. 앞 2자리가 노선을 식별한다(01=1호선, 04=4호선,
//     41=9호선, 42=공항철도 등). 역명만으로 목적 노선을 못 가르는 경우
//     (예: 총신대입구가 4·7호선 양쪽에 있음)에 한해 이 접두어로 판별한다.
//     하드코딩하지 않고 "역명 인접 판정이 유일 후보로 나온 행"들로부터
//     접두어→노선ID 매핑을 **데이터에서 유도**한다 ([_buildCodePrefixMap]).
//   - 이번 라운드는 **하차위치만** 쓴다. "환승 승차위치"(공식 CSV에 있음)는
//     의도적으로 읽지 않는다 — UI는 "빠른 환승 N-N"(하차위치)만 표시하는
//     현행을 유지하고, 승차위치는 이번에 도입하지 않는다.
//   - 일부 위치 셀은 숫자가 아니라 `All`(모든 문) — car/door 를 비우고
//     note 에 "모든 문"을 남긴다.
//
// CSV v2 5-tuple/4-tuple 선택 규칙 (요구사항):
//   같은 (역, 도착노선, 도착방향, 목적노선) 그룹에서 목적 방향별 하차위치가
//   - 다르면 → 방향별 5-tuple 행.
//   - 같으면(혹은 한쪽 방향만 관측되면) → destination_direction 을 비운
//     4-tuple 로 합친다.
//   한 그룹에 5-tuple 과 4-tuple 이 공존하지 않는다 — 구체 키가 런타임
//   폴백 조회를 가리기 때문이다(`lib/core/utils/transfer_guide_key.dart`
//   `lookupTransferGuide` 참고).
//
// 기존 데이터(나무위키/수기) 처리:
//   공식이 커버하지 않는 (역, 도착노선, 도착방향, 목적노선) 4-tuple 조합은
//   `data/transfer_guides_manual.csv` 에 별도 보관한다 — 이 CSV 는 v2 와
//   동일 스키마이며, 다음에 공식 CSV 를 갱신해도 손대지 않는 "수기 출처"
//   전용 파일이다. 이 도구는 그 파일을 읽어 공식이 커버하지 못하는 그룹만
//   병합하고, 공식과 겹치는 그룹은 **공식 값으로 완전히 대체**한다(45%
//   불일치 검증 결과 공식을 기준으로 채택).
//
// 산출: `data/transfer_guides.csv` (9컬럼 v2 스키마). 이 파일이 여전히
// `tool/import_transfer_guides.dart`(→ `assets/json/transfer_guides.json`)
// 의 유일 입력이다 — 이 도구는 그 전 단계에서 CSV 를 조립할 뿐, JSON 을
// 직접 만들지 않는다.

import 'dart:convert';
import 'dart:io';

import 'package:seoul_subway/core/utils/line_direction.dart';

const _officialCsvPath =
    'tool/data/seoul_metro_transfer_guides_official.csv';
const _manualCsvPath = 'data/transfer_guides_manual.csv';
const _outputCsvPath = 'data/transfer_guides.csv';

/// 공식 데이터셋의 **확인된 결손**을 보정한다.
/// 키: `{역}|{도착노선}|{arrivalIsDown}|{목적노선}|{destIsDown 또는 공란}`,
/// 값: `(칸, 문)`.
///
/// 공식 데이터셋이 주 소스지만 무오류는 아니다. 차량 번호는 편성 방향과 함께
/// 뒤집히므로(6칸 편성이면 칸 6 ↔ 칸 1, 4-door 차량이면 문 4 ↔ 문 1) 같은
/// 환승의 두 도착 방향은 하차위치가 서로 달라야 한다. 실제로 공식 491그룹 중
/// 249건이 문번호 미러(합=5) 관계이고, 양방향 완전 동일은 32건뿐이다.
///
/// **동작역 9호선**이 그 32건에 속한다. 원문은 9호선 출발 4행이 방면 구분 없이
/// 전부 `6-4` 인데, 같은 역 4호선 출발 행은 방면별로 `8-4`/`2-4` 로 정상 분화돼
/// 있다 — 한 방향 값만 기록하고 반대 방향에 복제한 결손으로 판단된다. 6칸 편성
/// 미러를 적용하면 `6-4` 의 반대는 정확히 `1-1` 이고, 이는 (1) 사용자 실측 제보,
/// (2) 나무위키("중앙보훈병원 방면 → 4호선 = 1-1")와 모두 일치한다.
/// 따라서 개화 방면(down)만 공식 `6-4` 를 유지하고, 중앙보훈병원 방면(up)은
/// `1-1` 로 보정한다.
///
/// ⚠ 나머지 31건의 의심 그룹은 **미검증이라 건드리지 않는다**(실행 로그에
/// "결손 의심"으로 출력된다). 미러 규칙을 일괄 적용하면 근거 없는 추정값이
/// 대량 유입되므로, 실측·원문 근거가 확보된 항목만 이 표에 등록할 것.
const _officialDefectOverrides = <String, (int, int)>{
  // 동작 9호선 상행(중앙보훈병원 방면) → 4호선. 위 근거 참조.
  '동작|9|false|4|': (1, 1),
};

/// up/down 이분법으로 두 방면이 같은 키에 접힐 때 **어느 방면 관측을 채택할지**.
/// 키: `{역}|{도착노선}|{arrivalIsDown}|{목적노선}`, 값: 우선할 목적 방면(옆 역) 이름.
///
/// 신도림 2호선은 본선(문래 방면)과 신정지선(도림천 방면)이 같은 노선 ID 를
/// 공유하는데, `isDownBetween` 상 두 방면이 같은 극성으로 계산돼 구분되지 않는다
/// (`line_direction.dart` 의 성수지선 특례는 노선 레벨 처리라 이 케이스를 못 잡는다).
/// 둘 중 하나는 버려야 하므로, 환승객 대다수가 향하는 **본선**을 채택한다.
///
/// 표에 없는 새 충돌은 경고만 남기고 종전대로 마지막 관측값을 쓴다 — 어느 값이든
/// 무안내보다는 유용하기 때문이다. 경고가 뜨면 이 표에 등록할지 판단할 것.
const _conflictPreferredDestNeighbor = <String, String>{
  '신도림|1|false|2': '문래', // 본선(영등포 방면 상행에서 하차) — 신정지선 도림천 대신
  '신도림|1|true|2': '문래', // 본선(구로 방면 하행에서 하차)
};

const _stationsJsonPath = 'assets/json/stations.json';
const _connectionsJsonPath = 'assets/json/connections.json';
const _linesJsonPath = 'assets/json/lines.json';

const _csvHeader = [
  'station',
  'arrival_line',
  'direction',
  'destination_line',
  'destination_direction',
  'door_side',
  'car',
  'door',
  'note',
];

/// 공식 CSV "환승시작 호선"/"환승종료역 코드 접두" 표기 → 프로젝트 lineId.
/// 확인된 표기만 나열(사용자 지시). 여기 없는 표기는 스킵하고 집계한다.
const _lineAlias = <String, String>{
  '1': '1', '2': '2', '3': '3', '4': '4', '5': '5', '6': '6', '7': '7',
  '8': '8', '9': '9',
  '경의선': '경의중앙',
  '수인분당선': '수인분당',
  '공항철도': '공항철도',
  '경춘선': '경춘',
  '서해선': '서해',
  '신분당선': 'SB',
  '인천선': '인천1',
  '인천2': '인천2',
  '신림선': '신림',
  '우이신설경전철': '우이신설',
  '경강선': '경강',
  '의정부경전철': '의정부',
};

void main() {
  final lines = jsonDecode(File(_linesJsonPath).readAsStringSync())
      as List<dynamic>;
  final knownLineIds = lines.map((l) => l['id'] as String).toSet();

  final stations = jsonDecode(File(_stationsJsonPath).readAsStringSync())
      as List<dynamic>;
  // nameOrAlias -> {lineId: stationId}
  final stationIndex = <String, Map<String, String>>{};
  // (lineId, stationId) -> 정식명 (출력용 표준화 + 인접역 이름 비교용)
  final officialNameByNode = <String, String>{};
  // alias -> 정식명
  final aliasToOfficial = <String, String>{};

  for (final s in stations) {
    final name = s['name'] as String;
    final lineId = s['lineId'] as String;
    final id = s['id'] as String;
    officialNameByNode['$lineId:$id'] = name;
    stationIndex.putIfAbsent(name, () => {})[lineId] = id;
    for (final alias in _extractAliases(name)) {
      if (alias.isEmpty || alias == name) continue;
      stationIndex.putIfAbsent(alias, () => {})[lineId] = id;
      aliasToOfficial.putIfAbsent(alias, () => name);
    }
  }

  final connections = jsonDecode(File(_connectionsJsonPath).readAsStringSync())
      as List<dynamic>;
  // lineId -> stationId -> Set<neighborStationId> (환승 제외)
  final adjacency = <String, Map<String, Set<String>>>{};
  for (final c in connections) {
    if (c['isTransfer'] == true) continue;
    final lineId = c['lineId'] as String;
    final from = c['fromStationId'] as String;
    final to = c['toStationId'] as String;
    adjacency
        .putIfAbsent(lineId, () => {})
        .putIfAbsent(from, () => {})
        .add(to);
    adjacency
        .putIfAbsent(lineId, () => {})
        .putIfAbsent(to, () => {})
        .add(from);
  }

  final rows = _readCsv(_officialCsvPath);
  final header = rows.first;
  _expectHeader(header, [
    '고유번호', '환승시작역', '환승시작 코드', '환승시작 호선', '하차 열차 방면',
    '하차위치(호차)', '하차위치(문)', '환승종료역', '환승 열차 방면',
    '환승 승차위치(호차)', '환승 승차위치(문)', '소요시간',
  ]);
  final dataRows = rows.skip(1).toList();

  // ── Phase 1: 노선 판정이 유일한 행만 먼저 처리 + 코드 접두어 매핑 유도.
  final codePrefixVotes = <String, Map<String, int>>{}; // prefix -> lineId -> count

  final resolvedRows = <_ResolvedRow>[];
  final ambiguousRows = <_PendingRow>[];
  var skippedUnknownLine = 0;
  var skippedStartStationMatch = 0;
  var skippedArrivalAdjacency = 0;
  var skippedDestNoCandidate = 0;

  for (final cols in dataRows) {
    if (cols.length != header.length) continue;
    final rawLine = cols[3].trim();
    final arrivalLineId = _lineAlias[rawLine];
    if (arrivalLineId == null || !knownLineIds.contains(arrivalLineId)) {
      skippedUnknownLine++;
      continue;
    }

    final rawStationName = cols[1].trim();
    final canonicalName = aliasToOfficial[rawStationName] ?? rawStationName;
    final arrivalStationId = stationIndex[rawStationName]?[arrivalLineId];
    if (arrivalStationId == null) {
      skippedStartStationMatch++;
      continue;
    }

    final arrivalDirName = _stripBound(cols[4]);
    final arrivalNeighborId = _findNeighborByName(
      adjacency,
      officialNameByNode,
      aliasToOfficial,
      lineId: arrivalLineId,
      stationId: arrivalStationId,
      targetName: arrivalDirName,
    );
    if (arrivalNeighborId == null) {
      skippedArrivalAdjacency++;
      continue;
    }
    final arrivalIsDown =
        isDownBetween(arrivalStationId, arrivalNeighborId, arrivalLineId);

    final destDirName = _stripBound(cols[8]);
    final candidates = <String>[];
    final candidateNeighbor = <String, String>{}; // lineId -> neighborStationId
    for (final lineId2 in knownLineIds) {
      if (lineId2 == arrivalLineId) continue;
      final nodeId = stationIndex[rawStationName]?[lineId2];
      if (nodeId == null) continue;
      final neighborId = _findNeighborByName(
        adjacency,
        officialNameByNode,
        aliasToOfficial,
        lineId: lineId2,
        stationId: nodeId,
        targetName: destDirName,
      );
      if (neighborId != null) {
        candidates.add(lineId2);
        candidateNeighbor[lineId2] = neighborId;
      }
    }

    if (candidates.isEmpty) {
      skippedDestNoCandidate++;
      continue;
    }

    final destCode = cols[7].trim();
    final prefix = destCode.length >= 2 ? destCode.substring(0, 2) : destCode;

    if (candidates.length == 1) {
      final destLineId = candidates.single;
      codePrefixVotes.putIfAbsent(prefix, () => {}).update(
            destLineId,
            (v) => v + 1,
            ifAbsent: () => 1,
          );
      final destStationId = stationIndex[rawStationName]![destLineId]!;
      final destNeighborId = candidateNeighbor[destLineId]!;
      final destIsDown =
          isDownBetween(destStationId, destNeighborId, destLineId);
      resolvedRows.add(_ResolvedRow(
        station: canonicalName,
        arrivalLine: arrivalLineId,
        arrivalIsDown: arrivalIsDown,
        destLine: destLineId,
        destIsDown: destIsDown,
        carRaw: cols[5].trim(),
        doorRaw: cols[6].trim(),
        arrivalDirName: arrivalDirName,
        destDirName: destDirName,
      ));
    } else {
      ambiguousRows.add(_PendingRow(
        station: canonicalName,
        rawStationName: rawStationName,
        arrivalLineId: arrivalLineId,
        arrivalIsDown: arrivalIsDown,
        candidates: candidates,
        candidateNeighbor: candidateNeighbor,
        codePrefix: prefix,
        carRaw: cols[5].trim(),
        doorRaw: cols[6].trim(),
        arrivalDirName: arrivalDirName,
        destDirName: destDirName,
      ));
    }
  }

  // 접두어 → 노선ID: **순수 접두어만** 채택한다(다수결 금지).
  //
  // 처음에는 다수결(득표 최다 노선)을 시도했으나, 실제 값을 까보면 같은
  // 2자리 접두어가 서로 다른 노선에 걸쳐 재사용되는 경우가 있었다(예: 접두
  // "10" 은 1호선/경의중앙/수인분당/서해에, "17" 은 4호선/1호선에 걸쳐
  // 관측됨 — 아마도 코드 뒷자리 대역까지 봐야 구분되는 하위 스킴일 것이나
  // 확인할 공식 문서가 없다). 이런 접두어에서 다수결로 소수 노선 표를
  // 뭉개면, 그 소수 노선에 실제로 걸리는 모호 행에 **틀린 목적노선을
  // 확정**시켜버린다 — 무응답보다 나쁘다("여기서 틀리면 구체 키가 정확히
  // 반대에 매칭돼 지금보다 나빠진다"). 그래서 접두어가 학습 데이터에서
  // **단 하나의 노선으로만** 관측된 경우에만 매핑을 신뢰하고, 둘 이상의
  // 노선이 섞인 접두어는 판별에 쓰지 않는다(그 접두어에 걸리는 모호 행은
  // 미해석으로 남겨 집계한다).
  final codePrefixMap = <String, String>{};
  final impurePrefixes = <String>{};
  codePrefixVotes.forEach((prefix, votes) {
    if (votes.length == 1) {
      codePrefixMap[prefix] = votes.keys.single;
    } else {
      impurePrefixes.add(prefix);
    }
  });

  var resolvedAmbiguous = 0;
  var skippedDestAmbiguous = 0;
  for (final p in ambiguousRows) {
    final destLineId = codePrefixMap[p.codePrefix];
    if (destLineId == null || !p.candidates.contains(destLineId)) {
      skippedDestAmbiguous++;
      continue;
    }
    final destStationId = stationIndex[p.rawStationName]![destLineId]!;
    final destNeighborId = p.candidateNeighbor[destLineId]!;
    final destIsDown = isDownBetween(destStationId, destNeighborId, destLineId);
    resolvedRows.add(_ResolvedRow(
      station: p.station,
      arrivalLine: p.arrivalLineId,
      arrivalIsDown: p.arrivalIsDown,
      destLine: destLineId,
      destIsDown: destIsDown,
      carRaw: p.carRaw,
      doorRaw: p.doorRaw,
      arrivalDirName: p.arrivalDirName,
      destDirName: p.destDirName,
    ));
    resolvedAmbiguous++;
  }

  stdout.writeln('=== 공식 데이터 해석 통계 ===');
  stdout.writeln('전체 행: ${dataRows.length}');
  stdout.writeln(
      '자동 해석 성공: ${resolvedRows.length} (1차 유일후보 ${resolvedRows.length - resolvedAmbiguous} + 코드접두 판별 $resolvedAmbiguous)');
  stdout.writeln('스킵 — 노선 미상: $skippedUnknownLine');
  stdout.writeln('스킵 — 출발역 매칭 실패: $skippedStartStationMatch');
  stdout.writeln('스킵 — 하차방면 인접 실패: $skippedArrivalAdjacency');
  stdout.writeln('스킵 — 목적노선 매칭 실패(후보 0): $skippedDestNoCandidate');
  stdout.writeln(
      '스킵 — 목적노선 모호(코드접두 판별 불가): $skippedDestAmbiguous (후보 ${ambiguousRows.length}건 중)');
  stdout.writeln('코드 접두어 → 노선 매핑 (순수 접두어만 채택, ${codePrefixMap.length}개):');
  final sortedPrefixes = codePrefixMap.keys.toList()..sort();
  for (final p in sortedPrefixes) {
    stdout.writeln('  $p -> ${codePrefixMap[p]} (표 ${codePrefixVotes[p]})');
  }
  if (impurePrefixes.isNotEmpty) {
    stdout.writeln('혼재(불신) 접두어 — 판별에 미사용, ${impurePrefixes.length}개:');
    final sortedImpure = impurePrefixes.toList()..sort();
    for (final p in sortedImpure) {
      stdout.writeln('  $p -> 미사용 (표 ${codePrefixVotes[p]})');
    }
  }

  // ── 5-tuple/4-tuple 결정: (station, arrivalLine, arrivalDir, destLine) 로
  // 묶어 destDir 별 값이 갈리는지 확인한다.
  final grouped = <String, Map<bool, _Value>>{}; // groupKey -> destIsDown -> value
  // 충돌 시 어느 방면이 이겼는지 추적하기 위해 채택된 행의 방면 표기를 함께 기억한다.
  final groupedSource = <String, Map<bool, String>>{};
  for (final r in resolvedRows) {
    final groupKey =
        '${r.station}|${r.arrivalLine}|${r.arrivalIsDown}|${r.destLine}';
    final value = _Value.fromRaw(r.carRaw, r.doorRaw);
    final byDest = grouped.putIfAbsent(groupKey, () => {});
    final bySrc = groupedSource.putIfAbsent(groupKey, () => {});
    final label = '${r.arrivalDirName}→${r.destDirName}';
    if (byDest.containsKey(r.destIsDown) && byDest[r.destIsDown] != value) {
      // up/down 이분법으로 접히는 Y자 분기(신도림 본선 문래 vs 신정지선 도림천
      // 등)에서 한쪽 관측이 반드시 버려진다. 스키마가 이진값인 한 구조적으로
      // 못 고치므로, (1) 승자를 CSV 행 순서가 아니라 명시 표로 정하고,
      // (2) 무엇이 유실됐는지 방면 이름과 함께 남긴다.
      final preferred = _conflictPreferredDestNeighbor[groupKey];
      final keepExisting = preferred != null && r.destDirName != preferred;
      final winner = keepExisting ? bySrc[r.destIsDown] : label;
      final loser = keepExisting ? label : bySrc[r.destIsDown];
      final winnerValue = keepExisting ? byDest[r.destIsDown] : value;
      final loserValue = keepExisting ? value : byDest[r.destIsDown];
      stderr.writeln(
          '경고: 방면 충돌 $groupKey destIsDown=${r.destIsDown} — '
          '유실 $loser=$loserValue / 채택 $winner=$winnerValue '
          '(${preferred == null ? "마지막 관측값 — 우선순위 미등록" : "본선 우선 표"})');
      if (keepExisting) continue; // 기존(우선) 값을 유지.
    }
    byDest[r.destIsDown] = value;
    bySrc[r.destIsDown] = label;
  }

  final officialOutput = <_OutRow>[];
  var splitGroups = 0;
  var collapsedGroups = 0;
  for (final entry in grouped.entries) {
    final parts = entry.key.split('|');
    final station = parts[0];
    final arrivalLine = parts[1];
    final arrivalIsDown = parts[2] == 'true';
    final destLine = parts[3];
    final byDest = entry.value;

    final distinctValues = byDest.values.toSet();
    if (distinctValues.length <= 1) {
      // 값이 하나뿐(양방향 동일 관측 포함) → 4-tuple 폴백.
      collapsedGroups++;
      final value = byDest.values.first;
      officialOutput.add(_OutRow(
        station: station,
        arrivalLine: arrivalLine,
        arrivalIsDown: arrivalIsDown,
        destLine: destLine,
        destIsDown: null,
        value: value,
      ));
    } else {
      splitGroups++;
      byDest.forEach((destIsDown, value) {
        officialOutput.add(_OutRow(
          station: station,
          arrivalLine: arrivalLine,
          arrivalIsDown: arrivalIsDown,
          destLine: destLine,
          destIsDown: destIsDown,
          value: value,
        ));
      });
    }
  }

  stdout.writeln('\n=== 5/4-tuple 결정 ===');
  stdout.writeln('그룹 수: ${grouped.length} (분할 $splitGroups / 통합 $collapsedGroups)');
  stdout.writeln('공식 출력 행: ${officialOutput.length}');

  // ── 공식 데이터 결손 보정 (아래 [_officialDefectOverrides] 근거 참조).
  var overridden = 0;
  for (var i = 0; i < officialOutput.length; i++) {
    final r = officialOutput[i];
    final key = '${r.station}|${r.arrivalLine}|${r.arrivalIsDown}|${r.destLine}'
        '|${r.destIsDown ?? ""}';
    final ov = _officialDefectOverrides[key];
    if (ov == null) continue;
    officialOutput[i] = _OutRow(
      station: r.station,
      arrivalLine: r.arrivalLine,
      arrivalIsDown: r.arrivalIsDown,
      destLine: r.destLine,
      destIsDown: r.destIsDown,
      value: _Value(car: ov.$1, door: ov.$2, note: r.value.note,
          doorSide: r.value.doorSide),
    );
    overridden++;
    stdout.writeln(
        '  보정: $key ${r.value.car}-${r.value.door} → ${ov.$1}-${ov.$2}');
  }
  if (overridden > 0) {
    stdout.writeln('공식 결손 보정 적용: $overridden건');
  }

  // ── 결손 의심 그룹 리포트: 같은 (역·도착노선·목적노선)에서 **도착 방향이 달라도
  // 하차위치가 완전히 동일**한 경우다. 차량 번호는 편성 방향과 함께 뒤집히므로
  // (칸 N ↔ 칸 총수+1−N, 문 D ↔ 문 5−D) 양방향 동일값은 물리적으로 드물다.
  // 실제로 491그룹 중 미러 관계가 249건인데 완전 동일은 32건뿐이고, 그중 동작역은
  // 실측으로 결손이 확인됐다(아래 override). 나머지는 미검증이므로 값을 건드리지
  // 않고 **눈에 보이게만** 남긴다 — 추정으로 고치면 근거 없는 값이 된다.
  final suspicious = <String>[];
  final byStationLineDest = <String, Map<bool, _Value>>{};
  for (final r in officialOutput) {
    final k = '${r.station}|${r.arrivalLine}|${r.destLine}'
        '|${r.destIsDown ?? ""}';
    final m = byStationLineDest.putIfAbsent(k, () => {});
    m[r.arrivalIsDown] = r.value;
  }
  byStationLineDest.forEach((k, m) {
    if (m.length == 2 && m[true] == m[false] && m[true]!.car != null) {
      suspicious.add('$k = ${m[true]!.car}-${m[true]!.door}');
    }
  });
  if (suspicious.isNotEmpty) {
    stdout.writeln(
        '\n⚠ 결손 의심(도착 방향이 달라도 하차위치 동일) ${suspicious.length}건 — 값 미변경, 확인 필요:');
    for (final s in suspicious..sort()) {
      stdout.writeln('  $s');
    }
  }

  // ── 수기(나무위키/이전 교정) 잔여 데이터 병합: 공식이 커버하지 못하는
  // (station, arrivalLine, arrivalDir, destLine) 4-tuple 그룹만 채택한다.
  final officialGroupKeys =
      officialOutput.map((r) => '${r.station}|${r.arrivalLine}|${r.arrivalIsDown}|${r.destLine}').toSet();

  final manualFile = File(_manualCsvPath);
  final manualOutput = <_OutRow>[];
  if (manualFile.existsSync()) {
    final manualRows = _readCsv(_manualCsvPath);
    _expectHeader(manualRows.first, _csvHeader);
    var manualSkippedOverridden = 0;
    for (final cols in manualRows.skip(1)) {
      if (cols.length != _csvHeader.length) continue;
      final station = cols[0];
      final arrivalLine = cols[1];
      final destLine = cols[3];
      final destDirRaw = cols[4];
      // 이 파일은 사람이 수기로 편집한다. `up`/`down` 외의 값(오타·공란)을
      // 조용히 `up` 으로 둔갑시키면 안내가 정반대가 되므로 명시 검증한다.
      if (cols[2] != 'up' && cols[2] != 'down') {
        stderr.writeln(
            '오류: 수기 CSV direction 값이 up/down 이 아니다 — '
            '"$station,$arrivalLine,${cols[2]},$destLine" (행 스킵)');
        continue;
      }
      if (destDirRaw.isNotEmpty && destDirRaw != 'up' && destDirRaw != 'down') {
        stderr.writeln(
            '오류: 수기 CSV destination_direction 값이 up/down/공란이 아니다 — '
            '"$station,$arrivalLine,${cols[2]},$destLine,$destDirRaw" (행 스킵)');
        continue;
      }
      final arrivalIsDown = cols[2] == 'down';
      final groupKey = '$station|$arrivalLine|$arrivalIsDown|$destLine';
      if (officialGroupKeys.contains(groupKey)) {
        manualSkippedOverridden++;
        continue; // 공식이 이 그룹을 커버 — 공식 값으로 완전히 대체.
      }
      manualOutput.add(_OutRow(
        station: station,
        arrivalLine: arrivalLine,
        arrivalIsDown: arrivalIsDown,
        destLine: destLine,
        destIsDown: destDirRaw.isEmpty ? null : destDirRaw == 'down',
        value: _Value(
          car: cols[6].isEmpty ? null : int.tryParse(cols[6]),
          door: cols[7].isEmpty ? null : int.tryParse(cols[7]),
          note: cols[8],
          doorSide: cols[5],
        ),
      ));
    }
    stdout.writeln('\n=== 수기(비공식) 데이터 병합 ===');
    stdout.writeln('수기 CSV 총 행: ${manualRows.length - 1}');
    stdout.writeln('공식에 덮여 스킵: $manualSkippedOverridden');
    stdout.writeln('최종 병합된 수기 행: ${manualOutput.length}');
  } else {
    stdout.writeln('\n(수기 CSV 없음: $_manualCsvPath — 공식 데이터만 사용)');
  }

  final allOutput = [...officialOutput, ...manualOutput];
  allOutput.sort((a, b) {
    final ka = '${a.station}|${a.arrivalLine}|${a.destLine}|${a.arrivalIsDown}|${a.destIsDown}';
    final kb = '${b.station}|${b.arrivalLine}|${b.destLine}|${b.arrivalIsDown}|${b.destIsDown}';
    return ka.compareTo(kb);
  });

  final buffer = StringBuffer();
  buffer.writeln(_csvHeader.join(','));
  for (final r in allOutput) {
    final fields = [
      r.station,
      r.arrivalLine,
      r.arrivalIsDown ? 'down' : 'up',
      r.destLine,
      r.destIsDown == null ? '' : (r.destIsDown! ? 'down' : 'up'),
      r.value.doorSide,
      r.value.car?.toString() ?? '',
      r.value.door?.toString() ?? '',
      r.value.note,
    ];
    // 인용 없이 join 하므로 콤마·따옴표가 섞이면 **읽기는 되고 쓰기에서 열이
    // 밀린다**(조용한 오염). 현재 데이터에는 없지만 수기 CSV 의 note 는 사람이
    // 자유롭게 쓰는 필드라 언제든 들어올 수 있어, 조용히 넘기지 않고 즉시 중단한다.
    for (final f in fields) {
      if (f.contains(',') || f.contains('"') || f.contains('\n')) {
        stderr.writeln(
            '오류: CSV 필드에 콤마/따옴표/개행이 있어 안전하게 쓸 수 없다 — '
            '"${r.station},${r.arrivalLine}" 의 필드 "$f". '
            '해당 값을 고치거나 인용 지원 writer 를 도입할 것.');
        exit(1);
      }
    }
    buffer.writeln(fields.join(','));
  }

  File(_outputCsvPath).writeAsStringSync(buffer.toString());
  stdout.writeln('\n✓ $_outputCsvPath 에 ${allOutput.length}행 기록 (헤더 제외)');
}

class _Value {
  final int? car;
  final int? door;
  final String note;
  final String doorSide;

  _Value({required this.car, required this.door, this.note = '', this.doorSide = ''});

  factory _Value.fromRaw(String carRaw, String doorRaw) {
    final isAll = carRaw.toLowerCase() == 'all' || doorRaw.toLowerCase() == 'all';
    if (isAll) return _Value(car: null, door: null, note: '모든 문');
    return _Value(car: int.tryParse(carRaw), door: int.tryParse(doorRaw));
  }

  @override
  bool operator ==(Object other) =>
      other is _Value && other.car == car && other.door == door && other.note == note;

  @override
  int get hashCode => Object.hash(car, door, note);

  @override
  String toString() => '$car-$door${note.isNotEmpty ? " ($note)" : ""}';
}

class _ResolvedRow {
  final String station;
  final String arrivalLine;
  final bool arrivalIsDown;
  final String destLine;
  final bool destIsDown;
  final String carRaw;
  final String doorRaw;

  /// 공식 CSV 원문의 방면 표기(옆 역 이름). 값 판정에는 쓰이지 않고
  /// **충돌 경고의 추적성**에만 쓴다 — 같은 (역·노선·방향) 키에 서로 다른
  /// 값이 관측될 때(신도림 본선 문래 vs 신정지선 도림천처럼 up/down 이분법으로
  /// 접히는 Y자 분기) 어느 방면이 채택되고 어느 쪽이 유실됐는지 로그로 알 수
  /// 있어야 재조사가 가능하다.
  final String arrivalDirName;
  final String destDirName;

  _ResolvedRow({
    required this.station,
    required this.arrivalLine,
    required this.arrivalIsDown,
    required this.destLine,
    required this.destIsDown,
    required this.carRaw,
    required this.doorRaw,
    required this.arrivalDirName,
    required this.destDirName,
  });
}

class _PendingRow {
  final String station;
  final String rawStationName;
  final String arrivalLineId;
  final bool arrivalIsDown;
  final List<String> candidates;
  final Map<String, String> candidateNeighbor;
  final String codePrefix;
  final String carRaw;
  final String doorRaw;

  /// 충돌 경고 추적용 원문 방면 표기. [_ResolvedRow.arrivalDirName] 참조.
  final String arrivalDirName;
  final String destDirName;

  _PendingRow({
    required this.station,
    required this.rawStationName,
    required this.arrivalLineId,
    required this.arrivalIsDown,
    required this.candidates,
    required this.candidateNeighbor,
    required this.codePrefix,
    required this.carRaw,
    required this.doorRaw,
    required this.arrivalDirName,
    required this.destDirName,
  });
}

class _OutRow {
  final String station;
  final String arrivalLine;
  final bool arrivalIsDown;
  final String destLine;
  final bool? destIsDown;
  final _Value value;

  _OutRow({
    required this.station,
    required this.arrivalLine,
    required this.arrivalIsDown,
    required this.destLine,
    required this.destIsDown,
    required this.value,
  });
}

/// "XX 방면" → "XX". 앞뒤 공백 제거.
String _stripBound(String s) => s.trim().replaceAll(RegExp(r'\s*방면\s*$'), '').trim();

/// [lineId] 노선에서 [stationId] 의 인접역 중 이름이 [targetName] 과 일치하는
/// 역의 ID 를 찾는다(정식명·별칭 모두 비교).
String? _findNeighborByName(
  Map<String, Map<String, Set<String>>> adjacency,
  Map<String, String> officialNameByNode,
  Map<String, String> aliasToOfficial,
  {
  required String lineId,
  required String stationId,
  required String targetName,
}) {
  final neighbors = adjacency[lineId]?[stationId];
  if (neighbors == null) return null;
  final target = aliasToOfficial[targetName] ?? targetName;
  for (final n in neighbors) {
    final name = officialNameByNode['$lineId:$n'];
    if (name == null) continue;
    final normalized = aliasToOfficial[name] ?? name;
    if (normalized == target || name == targetName) return n;
  }
  return null;
}

/// "총신대입구(이수)" → ["총신대입구", "이수"]. `parse_namuwiki_transfer.py`
/// 의 `_extract_aliases` 와 동일 규칙(포맷 드리프트 방지를 위해 로직만 이관,
/// 방향 판정과 달리 이건 단순 문자열 처리라 미러 위험이 낮다).
List<String> _extractAliases(String name) {
  final m = RegExp(r'^([^(]+?)\s*\(([^)]+)\)').firstMatch(name);
  if (m == null) return const [];
  return [m.group(1)!.trim(), m.group(2)!.trim()];
}

List<List<String>> _readCsv(String path) {
  final bytes = File(path).readAsBytesSync();
  var text = utf8.decode(bytes);
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1);
  }
  final lines = const LineSplitter().convert(text);
  return lines.where((l) => l.isNotEmpty).map(_parseCsvLine).toList();
}

void _expectHeader(List<String> actual, List<String> expected) {
  final trimmedActual = actual.map((s) => s.trim()).toList();
  if (trimmedActual.length != expected.length ||
      List.generate(expected.length, (i) => trimmedActual[i] == expected[i])
          .any((eq) => !eq)) {
    stderr.writeln('오류: CSV 헤더가 예상과 다릅니다.');
    stderr.writeln('  기대: ${expected.join(",")}');
    stderr.writeln('  실제: ${trimmedActual.join(",")}');
    exit(1);
  }
}

/// 큰따옴표 이스케이프를 지원하는 최소 CSV 파서(`tool/import_transfer_guides.dart`
/// 와 동일 규칙).
List<String> _parseCsvLine(String line) {
  final result = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (c == ',' && !inQuotes) {
      result.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(c);
    }
  }
  result.add(buffer.toString());
  return result;
}
