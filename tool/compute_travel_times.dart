// 캐시된 시간표(`data/timetables/`)에서 인접 역간 실제 평균 소요시간을
// 계산하여 `assets/json/connections.json`을 갱신한다.
//
// 알고리즘:
//   1. 각 (노선, 방향, 역) 시간표를 로드
//   2. 같은 trainno(열차번호)가 인접 두 역에서 출발하는 시각 차의 **절댓값** = 소요시간
//      (connections.json은 `from→to` 한쪽 방향만 기록하지만 인접 역간 이동시간은
//      방향 대칭이므로 상/하행 timetable 둘 다 양방향으로 gap 수집)
//   3. 인접 역 쌍별로 다수 열차의 **중앙값**을 사용 (outlier에 강건)
//   4. 완행/급행 분리: etrnYn=='N' 또는 빈 값 → 완행, 'Y' → 급행
//   5. connections.json의 travelTimeSeconds(완행) + expressTimeSeconds(급행) 갱신
//
// 양방향 수집이 중요한 이유:
//   - 9호선 흑석→동작 상행만 수집하면 급행 대피 대기시간이 포함된 290s가 잡히지만,
//     하행(동작→흑석) 155s가 누락되어 비대칭 outlier로 굳어진다.
//   - `.abs()`로 양방향을 합치면 249건 중앙값이 인근 구간(125s)과 정합한다.
//
// ⚠ dwell 규약 불일치 (재실행 전 반드시 확인):
//   이 도구는 출발시각 차(`trainDptreTm` → `trainDptreTm`)를 쓰므로 산출값에
//   **다음 역의 정차시간(약 30초)이 포함**된다. 반면 앱은 경로 총시간을
//   "edge 주행합 + 중간역 × dwell"(`lib/core/constants/dwell_time.dart`)로
//   계산하고, 최근 작업(경강선 48351f4, 금정 1호선)은 dwell 을 제외한
//   `다음역 trainArvlTm − 현재역 trainDptreTm` 을 규약으로 쓴다.
//   → 이 도구를 그대로 재실행하면 그렇게 넣은 구간이 dwell 이중 가산 값으로
//     되돌아간다:
//       1호선 명학↔금정 120→150, 금정↔군포 180→210
//       3호선 원당↔원흥 150→180, 원흥↔삼송 120→150, 삼송↔지축 150→180
//       경강선 전 구간
//     회귀 가드: `test/data/geumjeong_transfer_test.dart`,
//     `test/data/ilsan_line_order_test.dart`, `test/data/gyeonggang_line_test.dart`.
//
// 한계 (급행 데이터 커버리지):
//   - 이 알고리즘은 "인접 두 역" 쌍에서만 trainno 매칭을 수행한다.
//   - 9호선 급행처럼 여러 역을 **건너뛰는(skip)** 급행 열차는 인접 쌍의 한쪽에
//     해당 trainno가 나타나지 않아 대부분 매칭 실패한다.
//     예) 9호선 급행은 김포공항↔마곡나루 직통(공항시장·신방화 스킵). 따라서
//         김포공항↔공항시장 같은 인접 쌍에는 급행 trainno가 없음.
//   - 결과적으로 9호선은 expressTimeSeconds가 거의 수집되지 않는다(1건 수준).
//     경춘선·수인분당선은 인접 쌍 매칭이 잘 되어 정상 수집됨.
//   - 후속 개선 아이디어: graph에 "skip-edge"를 추가해 급행 정차역 시퀀스를
//     별도로 모델링하거나, 공식 시간표 PDF에서 수동 시딩.
//     → `tool/extract_express_skip_edges.py` + `assets/json/express_skip_edges.json`
//       으로 실현됨. 1호선은 그쪽이 유일 소스다(아래 참조).
//
// 사용법:
//   dart run tool/compute_travel_times.dart [--line=1] [--dry-run]

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// `expressTimeSeconds` 를 수집하지 않을 노선 — `etrnYn` 이 급행 지표가 아닌 노선.
///
/// 1호선: data.go.kr 시간표 API 가 `etrnYn='Y'` 를 실제 급행이 아닌 열차에도
/// 광범위하게 붙인다. getTrainSch 캐시 실측상 경부 corridor 의 `Y` 편성 약 50개
/// 중 47개가 전 역에 레코드를 갖는 사실상 완행이고, 경인선은 194편 **전부**가
/// 그렇다. 그래서 이 도구가 뽑은 1호선 `expressTimeSeconds` 93개는 "급행 시간"이
/// 아니라 완행 시간에 잡음이 섞인 값이었다:
///   - 68개가 급행이 아예 운행하지 않는 구간(경원선·경인선·인천/서동탄 지선·
///     천안 이남)에 붙어 있었고, 그중 36개는 완행보다 빠르다고 표시됐다
///     (녹양→가능 60s vs 완행 120s 등 물리적으로 불가능한 값).
///   - 급행이 실제로 다니는 인접 정차쌍 25개 중에서도 14개가 실측과 어긋났다.
///
/// 1호선 급행은 `assets/json/express_skip_edges.json`(가상 노선 `1E`) 이 정확히
/// 모델링하므로 이 필드는 불필요할 뿐 아니라, 두 모델을 계속 동기화해야 하는
/// 드리프트 발생원이었다. 여기서 수집을 막아 재실행해도 되살아나지 않게 한다.
///
/// 판별 근거와 실측 급행 편성(K1902·K1904·K1945)은
/// `tool/extract_express_skip_edges.py` 의 `_CURATED_MANUAL_SECONDS` 주석 참조.
const _expressUnreliableLines = {'1'};

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
  var expressUpdated = 0;
  var skipped = 0;
  final stats = <String, List<int>>{};
  final expressStats = <String, List<int>>{};

  for (final lid in pairs.keys) {
    final lineConns = pairs[lid]!;
    print('━━━ 노선 $lid: ${lineConns.length} connections ━━━');

    for (final c in lineConns) {
      // etrnYn 을 믿을 수 없는 노선은 어떤 경로로 빠져나가도 급행 필드를 남기지
      // 않는다. 아래 조기 continue 들보다 앞에 두어야 stale 값이 잔존하지 않는다.
      if (_expressUnreliableLines.contains(lid)) {
        c.remove('expressTimeSeconds');
      }

      final fromId = c['fromStationId'] as String;
      final toId = c['toStationId'] as String;
      final fromName = idToName[fromId];
      final toName = idToName[toId];
      if (fromName == null || toName == null) {
        skipped++;
        continue;
      }

      // 두 방향 모두 시도. 완행/급행 분리.
      final localGaps = <int>[];
      final expressGaps = <int>[];
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
          final etrn = (m['etrnYn']?.toString() ?? '').trim().toUpperCase();
          if (etrn == 'Y' && !_expressUnreliableLines.contains(lid)) {
            expressGaps.add(gap);
          } else if (etrn == 'Y') {
            // etrnYn 을 믿을 수 없는 노선 — 완행/급행 어느 쪽으로도 집계하지
            // 않는다. 완행에 섞으면 실제 완행 중앙값이 오염된다.
            continue;
          } else {
            // 'N' 또는 빈 값 → 완행
            localGaps.add(gap);
          }
        }
      }

      if (localGaps.isEmpty && expressGaps.isEmpty) {
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

      // 급행 갱신 (있을 때만 필드 설정, 없으면 필드 자체를 삭제하여 null 보장)
      if (expressGaps.isNotEmpty) {
        expressGaps.sort();
        final exMedian = expressGaps[expressGaps.length ~/ 2];
        expressStats.putIfAbsent(lid, () => []).add(exMedian);

        final old = c['expressTimeSeconds'];
        if (old != exMedian) {
          c['expressTimeSeconds'] = exMedian;
          expressUpdated++;
        }
      } else {
        // 데이터 없음 → 기존 필드 제거 (null 처리)
        c.remove('expressTimeSeconds');
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

  print('\n=== 노선별 급행 통계 ===');
  if (expressStats.isEmpty) {
    print('  (급행 데이터 없음)');
  } else {
    for (final lid in expressStats.keys) {
      final vals = expressStats[lid]!..sort();
      final sum = vals.reduce((a, b) => a + b);
      print('  $lid: ${vals.length}개 구간, 평균 ${(sum / vals.length).toStringAsFixed(1)}s, '
          '중앙값 ${vals[vals.length ~/ 2]}s, 범위 ${vals.first}~${vals.last}s');
    }
  }
  print(
      '\n전체: 완행 갱신 $updated건, 급행 갱신 $expressUpdated건, 스킵 $skipped건');

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
