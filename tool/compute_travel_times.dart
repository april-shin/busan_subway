// 캐시된 시간표(`data/timetables/`)에서 인접 역간 실제 평균 소요시간을
// 계산하여 `assets/json/connections.json`을 갱신한다.
//
// 알고리즘:
//   1. 각 (노선, 방향, 역) 시간표를 로드
//   2. 같은 trainno(열차번호)가 인접 두 역에서 출발하는 시각 차의 **절댓값** = 소요시간
//      (connections.json은 `from→to` 한쪽 방향만 기록하지만 인접 역간 이동시간은
//      방향 대칭이므로 상/하행 timetable 둘 다 양방향으로 gap 수집)
//   3. 인접 역 쌍별로 다수 열차의 **중앙값**을 사용 (outlier에 강건)
//   4. connections.json의 travelTimeSeconds 갱신
//
// 양방향 수집이 중요한 이유:
//   - 9호선 흑석→동작 상행만 수집하면 급행 대피 대기시간이 포함된 290s가 잡히지만,
//     하행(동작→흑석) 155s가 누락되어 비대칭 outlier로 굳어진다.
//   - `.abs()`로 양방향을 합치면 249건 중앙값이 인근 구간(125s)과 정합한다.
//
// ⛔ 급행은 이 도구가 다루지 않는다 (구 모델 폐지, 2026-08).
//   과거 이 도구는 `etrnYn=='Y'` 열차의 인접쌍 중앙값을 `expressTimeSeconds` 로
//   기록했다(구 급행 모델). 그 필드와 배관은 전부 제거됐다. 급행은
//   `tool/extract_express_skip_edges.py` → `assets/json/express_skip_edges.json`
//   → 가상 노선 `{base}E` 로만 표현한다.
//
//   폐지 사유 — `etrnYn` 은 급행 지표가 아니다. 실측(`data/timetables/`) 결과:
//     · 1호선: Y 편성 대부분이 전 역에 레코드를 가진 사실상 완행. 93개 값 중
//       68개가 급행 미운행 구간에 붙고 36개는 완행보다 빠르다고 표시했다.
//     · 경춘: Y 편성 5개 전부 24역 전역 정차. 값 23개가 신 모델과 완전 중복.
//     · 수인분당: Y 편성 22개 중 14개 전역 정차, 나머지 8개도 캐시가 없는
//       원인재 1역만 "통과". 값 49개 중 31개가 완행보다 느리거나 같았다.
//     · 9호선: Y 편성은 실제로 역을 건너뛰므로 인접쌍 매칭이 거의 실패해
//       값이 1개(봉은사→종합운동장)뿐이었고, 그마저 완행과 동일했다.
//   급행은 "인접 두 역" 매칭으로는 원리상 잡히지 않는다 — 건너뛴 역에는 해당
//   trainno 레코드가 없기 때문이다. skip edge 모델이 이를 대체한다.
//
// 사용법:
//   dart run tool/compute_travel_times.dart [--line=1] [--dry-run]

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  String? onlyLine;
  var dryRun = false;
  for (final a in args) {
    if (a.startsWith('--line=')) onlyLine = a.substring('--line='.length);
    if (a == '--dry-run') dryRun = true;
  }

  // 1. connections 로드
  final connsRaw = json
      .decode(File('assets/json/connections.json').readAsStringSync()) as List;
  final conns = connsRaw.cast<Map<String, dynamic>>();

  // 2. stations 로드 → id↔name 매핑
  final stationsRaw =
      json.decode(File('assets/json/stations.json').readAsStringSync()) as List;
  // (lineId, stationName) → stationId
  final nameToId = <String, String>{};
  // stationId → name
  final idToName = <String, String>{};
  for (final s in stationsRaw) {
    final lid = s['lineId'] as String;
    final name = s['name'] as String;
    final id = s['id'] as String;
    nameToId['$lid|$name'] = id;
    idToName[id] = name;
  }

  // 3. 인접 역 쌍 (같은 노선) 추출
  final pairs = <String, List<Map<String, dynamic>>>{};
  for (final c in conns) {
    if (c['isTransfer'] == true) continue;
    final lid = c['lineId'] as String;
    if (onlyLine != null && lid != onlyLine) continue;
    pairs.putIfAbsent(lid, () => []).add(c);
  }

  var updated = 0;
  var skipped = 0;
  var expressStripped = 0;
  var expressSamplesDropped = 0;
  final stats = <String, List<int>>{};

  for (final lid in pairs.keys) {
    final lineConns = pairs[lid]!;
    print('━━━ 노선 $lid: ${lineConns.length} connections ━━━');

    for (final c in lineConns) {
      final fromId = c['fromStationId'] as String;
      final toId = c['toStationId'] as String;
      final fromName = idToName[fromId];
      final toName = idToName[toId];
      if (fromName == null || toName == null) {
        skipped++;
        continue;
      }

      // 구 급행 모델 잔재 제거 — 어떤 경로로든 되살아나면 여기서 걷어낸다.
      if (c.remove('expressTimeSeconds') != null) expressStripped++;

      // 두 방향 모두 시도.
      final localGaps = <int>[];
      for (final dir in ['상행', '하행']) {
        final fromFile = File('data/timetables/${lid}_${fromName}_$dir.json');
        final toFile = File('data/timetables/${lid}_${toName}_$dir.json');
        if (!fromFile.existsSync() || !toFile.existsSync()) continue;

        final fromList = json.decode(fromFile.readAsStringSync()) as List;
        final toList = json.decode(toFile.readAsStringSync()) as List;
        if (fromList.isEmpty || toList.isEmpty) continue;

        // toList를 trainno → time 맵으로
        // [데이터 오염 방어] fetch_timetables.dart 의 substring 검색이 "양재" 로
        // 양재시민의숲까지 끌어와 한 파일에 두 역 데이터가 섞이는 케이스가 있다.
        // (예: SB_양재_상행.json 에 양재 + 양재시민의숲 326건 → 같은 trainno 의
        //  양재(06:05:13) / 양재시민의숲(06:02:59) 이 toMap 에서 덮어써져 gap 이
        //  139s/273s 로 절반씩 오염, median=259s 가 산출됨.)
        // stnNm 이 정확히 대상 역명과 일치하는 레코드만 채택하여 차단.
        final toMap = <String, int>{};
        for (final i in toList) {
          final m = i as Map;
          if (m['stnNm']?.toString() != toName) continue;
          final tno = m['trainno']?.toString();
          final t = _parseSec(m['trainDptreTm']?.toString() ?? '');
          if (tno != null && t != null) toMap[tno] = t;
        }

        // fromList의 각 열차에 대해 to에서의 시각 차이 계산
        for (final i in fromList) {
          final m = i as Map;
          if (m['stnNm']?.toString() != fromName) continue;
          final tno = m['trainno']?.toString();
          if (tno == null) continue;
          final fromTime = _parseSec(m['trainDptreTm']?.toString() ?? '');
          final toTime = toMap[tno];
          if (fromTime == null || toTime == null) continue;
          // 인접 두 역 간 이동시간은 방향 대칭으로 가정하고 절댓값 수집.
          // connections.json 은 `from→to` 한쪽만 저장하므로 상/하행 timetable 중
          // `to→from` 순서의 열차(음수 gap)도 유효한 데이터로 포함해야 한다.
          final gap = (toTime - fromTime).abs();
          // 0 이하는 동일 시각(이상) 또는 파싱 오류로 간주. 600s 이상은 종착/회차 케이스.
          if (gap <= 0 || gap >= 600) continue;
          // `etrnYn=='Y'` 표본은 **버린다**(급행 값을 만들지도 않는다).
          // 완행 median 에 섞지 않는 이유: 기존 travelTimeSeconds 가 Y 제외
          // median 으로 산출된 값이므로, 섞으면 재실행마다 전 노선 완행 시간이
          // 흔들린다. 급행 취급은 위 헤더의 "구 모델 폐지" 항목 참조.
          final etrn = (m['etrnYn']?.toString() ?? '').trim().toUpperCase();
          if (etrn == 'Y') {
            expressSamplesDropped++;
            continue;
          }
          localGaps.add(gap);
        }
      }

      if (localGaps.isEmpty) {
        skipped++;
        continue;
      }

      // 완행 갱신
      if (localGaps.isNotEmpty) {
        localGaps.sort();
        final median = localGaps[localGaps.length ~/ 2];
        stats.putIfAbsent(lid, () => []).add(median);

        final old = c['travelTimeSeconds'] as int;
        if (median != old) {
          c['travelTimeSeconds'] = median;
          updated++;
        }
      }

    }
  }

  // 통계 출력
  print('\n=== 노선별 완행 통계 ===');
  for (final lid in stats.keys) {
    final vals = stats[lid]!..sort();
    final sum = vals.reduce((a, b) => a + b);
    print('  $lid: ${vals.length}개 갱신, 평균 ${(sum / vals.length).toStringAsFixed(1)}s, '
        '중앙값 ${vals[vals.length ~/ 2]}s, 범위 ${vals.first}~${vals.last}s');
  }

  print('\n전체: 완행 갱신 $updated건, 스킵 $skipped건');
  print('급행(etrnYn=Y) 표본 $expressSamplesDropped건 폐기 — 급행은 '
      'express_skip_edges.json 이 담당한다 (헤더 주석 참조).');
  if (expressStripped > 0) {
    print('⚠ 구 모델 잔재 expressTimeSeconds $expressStripped건 제거됨.');
  }

  if (dryRun) {
    print('(dry-run, 파일 변경 없음)');
    return;
  }

  // 4. connections.json 저장
  final encoded = const JsonEncoder.withIndent('  ').convert(connsRaw);
  File('assets/json/connections.json').writeAsStringSync(encoded);
  print('✓ connections.json 갱신 완료');
}

int? _parseSec(String s) {
  if (s.contains(':')) {
    final p = s.split(':');
    if (p.length >= 2) {
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      final sec = p.length >= 3 ? int.tryParse(p[2]) ?? 0 : 0;
      return h * 3600 + m * 60 + sec;
    }
  }
  if (s.length >= 4) {
    final h = int.tryParse(s.substring(0, 2)) ?? 0;
    final m = int.tryParse(s.substring(2, 4)) ?? 0;
    final sec = s.length >= 6 ? int.tryParse(s.substring(4, 6)) ?? 0 : 0;
    return h * 3600 + m * 60 + sec;
  }
  return null;
}
