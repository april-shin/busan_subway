// 캐시된 시간표(`data/timetables/`)에서 인접 역간 실제 평균 소요시간을
// 계산하여 `assets/json/connections.json`을 갱신한다.
//
// 알고리즘:
//   1. 각 (노선, 방향, 역) 시간표를 로드
//   2. 같은 trainno(열차번호)에 대해 **다음역 trainArvlTm − 현재역 trainDptreTm**
//      = 순수 주행시간(dwell 제외). 양방향을 모두 수집한다 — `from→to` 순서의
//      열차는 `to.arvl − from.dptre`, 역순 열차는 `from.arvl − to.dptre`.
//   3. 인접 역 쌍별로 다수 열차의 **중앙값**을 사용 (outlier에 강건)
//   4. connections.json의 travelTimeSeconds 갱신
//
// 양방향 수집이 중요한 이유:
//   - 9호선 흑석→동작 상행만 수집하면 급행 대피 대기시간이 포함된 값이 잡히지만,
//     하행(동작→흑석)이 누락되어 비대칭 outlier로 굳어진다.
//   - 양방향을 합치면 표본이 커져 중앙값이 인근 구간과 정합한다.
//
// ── dwell 규약 (2026-08 전환) ──────────────────────────────────────────────
//   edge 값은 **순수 주행시간**(dwell 제외)이다. 앱이 경로 총시간을
//   "edge 주행합 + 중간역 × dwellTimeSeconds(30)"(`lib/core/constants/
//   dwell_time.dart`)로 계산하기 때문이다.
//
//   과거 이 도구는 출발시각 차(`dptre → dptre`)를 썼는데, 그 값에는 다음 역의
//   정차시간(~30초)이 포함돼 **전 노선에서 역당 ~30초 dwell 이중 가산**이
//   발생했다(실측: 전 노선 524개 대조 구간 중 511개가 dptre 기준값, 오이도→수원
//   47.5분 vs 실제 편성 41.2분 = +6.2분 ≈ 중간역 12개 × 30초). 손으로 넣던
//   구간(금정·일산선·경강선·장항선·수인선·경부선 구로 이남)만 arvl 규약이라
//   재실행 시 그 구간들이 dwell 포함 값으로 되돌아가는 충돌도 있었다.
//   지금은 도구 자체가 arvl 규약이므로 재실행이 손 실측값을 **재현**한다 —
//   회귀 가드: `test/data/geumjeong_transfer_test.dart`,
//   `test/data/gyeongbu_line_order_test.dart`, `test/data/ilsan_line_order_test.dart`,
//   `test/data/janghang_line_order_test.dart`, `test/data/suin_line_order_test.dart`,
//   `test/data/gyeonggang_line_test.dart`.
//
//   arvl 이 없는 표본(기점역 출발 등)은 버린다 — dptre 폴백을 두면 dwell 포함
//   값이 섞여 규약이 다시 오염된다. 캐시가 없어 갱신 불가한 노선(2호선·경의중앙
//   등)은 기존 값을 유지하므로 dptre 시절 값이 남는다. 아래 실행 로그의
//   "미갱신" 카운트로 추적한다.
//
// ⛔ 급행은 이 도구가 다루지 않는다 (구 모델 폐지, 2026-08).
//   과거 이 도구는 `etrnYn=='Y'` 열차의 인접쌍 중앙값을 `expressTimeSeconds` 로
//   기록했다(구 급행 모델). 그 필드와 배관(`GraphEdge.expressWeightSeconds` →
//   `RouteSegment.expressDurationSeconds` → `RouteResult.totalExpressTimeSeconds`)
//   은 전부 제거됐다. 급행은 `tool/extract_express_skip_edges.py` →
//   `assets/json/express_skip_edges.json` → 가상 노선 `{base}E` 로만 표현한다.
//   이제 이 도구는 `Y` 표본을 **버리고**, 에셋에 남은 잔재 키를 걷어낸다.
//
//   폐지 사유 1 — 원리적 한계. 이 알고리즘은 "인접 두 역" 쌍에서만 trainno
//   매칭을 하므로, 역을 **건너뛰는** 급행은 애초에 잡히지 않는다. 건너뛴 역에는
//   해당 trainno 레코드가 없기 때문이다(9호선 급행 김포공항↔마곡나루 직통 →
//   김포공항↔공항시장 인접 쌍에 급행 trainno 없음).
//
//   폐지 사유 2 — `etrnYn` 은 급행 지표가 아니다. 실측(`data/timetables/`):
//     · 1호선: Y 편성 대부분이 전 역에 레코드를 가진 사실상 완행(경부 corridor
//       50개 중 47개, 경인선은 194편 전부). 93개 값 중 68개가 급행 미운행
//       구간(경원선·경인선·인천/서동탄 지선·천안 이남)에 붙고 그중 36개는 완행보다
//       빠르다고 표시했다(녹양→가능 60s vs 완행 120s — 물리적으로 불가능).
//       급행이 실제 다니는 인접 정차쌍 25개 중에서도 14개가 실측과 어긋났다.
//     · 경춘: Y 편성 5개(K8401~K8405) 전부 24역 전역 정차. 값 23개가 신 모델
//       skip edge 와 완전 중복이었다(같은 원천·같은 median).
//     · 수인분당: Y 편성 22개 중 14개 전역 정차. 나머지 8개는 원인재 1역만
//       "통과" 하는데 그 역은 시간표 캐시 파일 자체가 없다(통과가 아니라 공백).
//       값 49개 중 31개가 완행보다 느리거나 같았다.
//     · 9호선: 유일하게 `etrnYn` 이 신뢰 가능하지만(Y 편성 232개 전부 실제
//       건너뜀), 그 때문에 사유 1 이 걸려 값이 1개(봉은사→종합운동장)뿐이었고
//       그마저 완행과 똑같은 155s 였다.
//
//   회귀 가드: `test/data/connections_no_express_asset_test.dart` (에셋 수기
//   패치로 키가 되살아나는 반대 방향을 막는다).
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
      // 구 급행 모델 잔재 제거 — 어떤 경로로 되살아나도 여기서 걷어낸다.
      // 아래 조기 continue 들보다 **앞에** 두어야 stale 값이 잔존하지 않는다.
      if (c.remove('expressTimeSeconds') != null) expressStripped++;

      final fromId = c['fromStationId'] as String;
      final toId = c['toStationId'] as String;
      final fromName = idToName[fromId];
      final toName = idToName[toId];
      if (fromName == null || toName == null) {
        skipped++;
        continue;
      }

      // 두 방향 모두 시도.
      final localGaps = <int>[];
      final terminalGaps = <int>[];
      for (final dir in ['상행', '하행']) {
        final fromFile = File('data/timetables/${lid}_${fromName}_$dir.json');
        final toFile = File('data/timetables/${lid}_${toName}_$dir.json');
        if (!fromFile.existsSync() || !toFile.existsSync()) continue;

        final fromList = json.decode(fromFile.readAsStringSync()) as List;
        final toList = json.decode(toFile.readAsStringSync()) as List;
        if (fromList.isEmpty || toList.isEmpty) continue;

        // trainno → (arvl, dptre) 맵.
        // [데이터 오염 방어] fetch_timetables.dart 의 substring 검색이 "양재" 로
        // 양재시민의숲까지 끌어와 한 파일에 두 역 데이터가 섞이는 케이스가 있다.
        // stnNm 이 정확히 대상 역명과 일치하는 레코드만 채택하여 차단.
        Map<String, (int?, int?, String, bool)> collect(List list, String name) {
          final out = <String, (int?, int?, String, bool)>{};
          for (final i in list) {
            final m = i as Map;
            if (m['stnNm']?.toString() != name) continue;
            final tno = m['trainno']?.toString();
            if (tno == null) continue;
            final arvl = _parseSec(m['trainArvlTm']?.toString() ?? '');
            final dptre = _parseSec(m['trainDptreTm']?.toString() ?? '');
            final etrn = (m['etrnYn']?.toString() ?? '').trim().toUpperCase();
            // 이 역이 해당 편성의 **종착역**인가 — 종착 도착시각(arvl)에는 회차
            // 여유시분이 섞여 실주행보다 크게 잡힌다(의정부 송산→탑석 143s vs
            // 비종착 방향 실측 32~34s, 4.3배). 종착 도착 표본은 후순위 버킷으로
            // 내리고, 비종착 표본이 하나도 없는 구간에서만 폴백으로 쓴다.
            final isTerminal = m['arvlStnNm']?.toString() == name;
            out[tno] = (arvl, dptre, etrn, isTerminal);
          }
          return out;
        }

        final fromMap = collect(fromList, fromName);
        final toMap = collect(toList, toName);

        for (final tno in fromMap.keys) {
          final f = fromMap[tno];
          final t = toMap[tno];
          if (f == null || t == null) continue;
          // `etrnYn=='Y'` 표본은 **버린다**(급행 값을 만들지도 않는다).
          // 완행 median 에 섞지 않는 이유: 기존 travelTimeSeconds 가 Y 제외
          // median 으로 산출된 값이므로, 섞으면 재실행마다 전 노선 완행 시간이
          // 흔들린다. 급행 취급은 위 헤더의 "구 모델 폐지" 항목 참조.
          if (f.$3 == 'Y' || t.$3 == 'Y') {
            expressSamplesDropped++;
            continue;
          }
          // 순수 주행시간 = 뒤 역 도착 − 앞 역 출발 (dwell 제외).
          // connections.json 은 `from→to` 한쪽만 저장하지만 이동시간은 방향
          // 대칭이므로, 같은 timetable 안의 역순 열차(`to→from`)도 수집한다.
          // dptre→dptre 폴백은 두지 않는다 — dwell 포함 값이 섞이면 규약이
          // 오염된다(헤더의 "dwell 규약" 참조).
          for (final (dep, arr, arrTerminal) in [
            (f.$2, t.$1, t.$4),
            (t.$2, f.$1, f.$4),
          ]) {
            if (dep == null || arr == null) continue;
            final gap = arr - dep;
            // 0 이하는 역순 매칭 또는 파싱 오류. 600s 이상은 종착/회차 케이스.
            if (gap <= 0 || gap >= 600) continue;
            // 종착 도착 표본은 별도 버킷 — collect() 주석 참조.
            (arrTerminal ? terminalGaps : localGaps).add(gap);
          }
        }
      }

      // 비종착 표본이 없으면 종착 도착 표본으로 폴백한다(광명 셔틀처럼 양쪽이
      // 전부 종착인 구간). 회차 여유가 섞여 상한 추정이 되지만 값이 없는 것보다
      // 낫고, 폴백 사용은 아래 로그로 드러난다.
      final usedTerminalFallback = localGaps.isEmpty && terminalGaps.isNotEmpty;
      if (usedTerminalFallback) {
        localGaps.addAll(terminalGaps);
        print('  [종착 폴백] ${idToName[fromId]}↔${idToName[toId]}: '
            '비종착 표본 0, 종착 도착 표본 ${terminalGaps.length}개 사용');
      }

      if (localGaps.isEmpty) {
        skipped++;
        continue;
      }

      // 완행 갱신
      {
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
