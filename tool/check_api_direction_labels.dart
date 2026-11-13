// 서울 API `updnLine` 라벨 ↔ 앱 `isDownBetween` 판정 대조 진단 도구.
//
// 왜 있는가
// ---------
// `lib/core/utils/line_direction.dart` 의 `_apiLabelReversedLines` 는 "서울 API 라벨이
// 앱 일반 규칙(ID 증가 = 하행)과 반대인 노선" 목록이다. 우이신설이 이 목록에서 빠져
// 있던 것을 아무도 몰랐고, 그 노선 열차가 지도에서 거의 전부 안 그려지고 있었다
// (2026-10-20 발견 — 전혀 다른 질문에서 파생된 조사로 **우연히**). 이 도구는 같은
// 종류의 버그를 다음엔 자동으로 잡기 위한 것이다.
//
// `test/core/utils/line_direction_api_label_test.dart` 는 **탐지기가 아니다.** 현재
// 동작을 고정(lock-in)할 뿐이라 API 가 반대 라벨을 주기 시작해도 계속 통과한다.
// 이 도구가 그 빈자리를 메운다 — 수동/주기 실행용이며 `flutter test` 에 넣지 않는다
// (네트워크·API 키가 필요하고 API 변덕으로 CI 가 깨진다).
//
// 실행
// ----
//   dart run tool/check_api_direction_labels.dart                  # 전 24개 노선, 보고만(종료 코드 0)
//   dart run tool/check_api_direction_labels.dart --strict         # 이상 판정이 있으면 종료 코드 1
//   dart run tool/check_api_direction_labels.dart --lines 우이신설,9
//   dart run tool/check_api_direction_labels.dart --per-line 12    # 노선당 표본 역 수 상향(기본 가변)
//   dart run tool/check_api_direction_labels.dart --verbose        # 모든 노선의 불일치 사례 출력
//
// API 키는 프로젝트 루트 `.env` 의 `BUSAN_SUBWAY_API_KEY` 에서만 읽으며 출력에 남기지
// 않는다. 호출 수는 전 노선 1회 실행당 **약 180건**(실측 183건. 서울 열린데이터 일일
// 한도는 1,000건/일 이라 하루 5회가 상한이다) — 한도가 빠듯하면 `--lines` 로 좁힐 것.
// 실제 질의 수는 실행 첫 줄 "질의 대상 N개 역명" 에 찍힌다.
//
// 종료 코드
// ---------
//   0  보고 완료(기본은 이상이 있어도 0 — API 는 시각·정비·일시 장애로 변덕스럽다)
//   1  `--strict` 이고 "누락 의심 / 반전 해제 의심 / 혼재 / 국소 불일치 / API 개통 의심"
//      판정이 하나 이상
//   2  도구 자체가 돌 수 없었음(키 없음·네트워크 전멸·입력 JSON 오류). 이건 "문제 없음"
//      이 아니라 "확인 못 함" 이라 0 으로 둘 수 없다.
//   3  `--strict` 이고 이상은 없었지만 **확인도 못 한** 노선이 있음(표본 부족·표본 없음).
//      1 과 0 사이의 자리다 — 심야·API 장애·일일 한도 초과로 표본이 비면 전 노선이
//      여기로 떨어지는데, 그걸 0 으로 내보내면 "오늘도 이상 없음" 으로 읽힌다.
//
// 무엇을 대조하는가
// -----------------
// 앱이 라벨을 쓰는 곳(지도 방향 게이트 `isDownDirectionString(label) != routeFilter.isDown`,
// 출발 시각 후보 필터)은 "열차가 **조회역으로 다가오는** 방향" 과 라벨이 같은지를 본다.
// 그래서 1차 기준은 **접근 방향** = `isDownBetween(현재역 arvlMsg3 → 조회역 statnNm)` 이다.
// 순환선(2호선)·분기선은 행선지(bstatnNm)만으로는 방향이 안 정해지므로 행선지를 1차로
// 쓰면 오탐이 많다.
// 현재역 == 조회역(승강장 위 열차)이면 접근 방향이 없으므로 `현재역 → 행선지` 로 판정한다.
// 행선지 기준은 1차 기준이 가능한 행에도 **교차 검증**으로 함께 계산해 상세 섹션에 낸다.
//
// "일반규칙" 열: 앱이 반전 목록에 넣은 노선은 앱 판정의 부정이 곧 일반 규칙(ID 증가 =
// 하행) 판정이다. 그래서 한 번의 대조로 "반전 목록에 없는데 라벨과 어긋나는 노선(= 누락)"
// 과 "목록에 있는데 일반 규칙이 라벨과 더 맞는 노선(= 더는 반전이 아님)" 을 둘 다 짚는다.
//
// 판정 불가는 불일치와 섞지 않고 따로 센다:
//   - API 미응답: 질의가 INFO-200(데이터 없음)이거나 오류/타임아웃
//   - 이름 미해석: 현재역·조회역·(필요 시)행선지가 그 노선 역으로 안 읽힘
//   - 종착 회차·순환: 현재역==조회역==노선 종점, 행선지==현재역, 종점으로 들어오는 열차가 회차해
//     행선지로 돌아가는 경우, 또는 승강장 위 열차인데 순환 구간(2호선 본선·6호선 응암 순환)이라
//     행선지로 방향이 안 정해지는 경우. 종점에서는 "들어오는
//     방향" 과 "나가는 방향" 이 서로 반대인데 API 가 어느 쪽 라벨을 쓰는지 행마다
//     갈린다(우이신설 신설동의 `상행|북한산우이행|신설동 출발` 이 그 예).
//   - 라벨 이상: `updnLine` 이 상행/하행/내선/외선이 아님
//
// ⚠ 이 도구는 **보고만 한다.** 새 불일치를 찾아도 `lib/` 를 고치지 않는다 — 규칙·시간표
// (`line_schedules.json` 방향 인덱스)·환승 가이드가 한 묶음으로 움직여야 해서(우이신설
// 수정 때의 삼중 보정) 사용자 결정 사안이다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busan_subway/core/constants/api_constants.dart';
import 'package:busan_subway/core/constants/subway_id_mapping.dart';
import 'package:busan_subway/core/utils/line_direction.dart';

// ---------------------------------------------------------------------------
// 판정 임계
// ---------------------------------------------------------------------------

/// 판정에 필요한 최소 표본 수. 이보다 적으면 "표본 부족" — 노선 전체가 반전인 경우
/// 불일치율이 90% 이상이므로 소수 표본으로도 구분되지만, 1~2건으로 단정하진 않는다.
const _minEvaluable = 6;

/// 불일치율이 이 이하면 OK. 5% — 8호선 `arvlMsg3` 오보고 같은 데이터 노이즈 여유.
const _okMaxRate = 0.05;

/// 불일치율이 이 이상이면 "라벨 극성이 앱과 반대" 로 본다. 70% — 노선 전체가 반전이면
/// 종점 회차 등 일부 노이즈가 있어도 이 위로 나온다. 5%~70% 사이는 "혼재".
const _flipMinRate = 0.70;

/// 노선당 표본 역의 기본 중간 지점 수 범위(양 종점 외).
const _minMid = 3;
const _maxMid = 6;

/// 역 수가 이 이하인 짧은 노선은 전 역을 표본으로 쓴다(GTX-A 처럼 종점 회차 행이
/// 표본을 잠식하는 노선에서 평가 가능 행을 확보하기 위함).
const _fullSampleMaxStations = 10;

/// 한 번에 날리는 동시 질의 수. 서울 API 에 과하지 않게 낮게 유지.
const _concurrency = 4;

const _queryTimeout = Duration(seconds: 10);



/// 서울 도착정보 API 가 `arvlMsg3` 에 붙이는 상태 접미사(DTO `_extractStationName` 과 동일).
const _statusSuffixes = {'출발', '도착', '진입', '전역'};

// ---------------------------------------------------------------------------
// 진입점
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final opts = _Options.parse(args);
  if (opts.help) {
    stdout.writeln(_usage);
    return;
  }

  final DateTime startedAt = DateTime.now();

  final String apiKey;
  try {
    apiKey = _readApiKey();
  } on _ToolError catch (e) {
    stderr.writeln('도구 실행 불가: ${e.message}');
    exit(2);
  }

  final _Data data;
  try {
    data = _Data.load();
  } on Object catch (e) {
    stderr.writeln('입력 JSON 로드 실패: $e');
    exit(2);
  }

  final reversedSet = _readReversedLinesFromSource();
  if (reversedSet == null) {
    stderr.writeln(
      '도구 실행 불가: lib/core/utils/line_direction.dart 에서 '
      '`_apiLabelReversedLines` 목록을 읽지 못했다. 변수명·형식이 바뀌었으면 '
      '이 도구의 _readReversedLinesFromSource 를 갱신할 것.',
    );
    exit(2);
  }

  final overrides = _Overrides.loadFromSource();
  if (overrides == null) {
    stderr.writeln(
      '도구 실행 불가: lib/core/constants/station_api_name_overrides.dart 에서 '
      '역명 치환 맵을 읽지 못했다.',
    );
    exit(2);
  }

  // 대상 노선
  final allLineIds = data.lineIds;
  final targetLines = opts.lines.isEmpty
      ? allLineIds
      : [
          for (final l in opts.lines)
            if (allLineIds.contains(l)) l else _unknownLine(l, allLineIds),
        ];

  // 표본 역 선정 — 노선별 (표시명) 목록.
  final sampleByLine = <String, List<_Sample>>{
    for (final l in targetLines) l: data.sampleStations(l, opts.perLine),
  };

  // 질의 단위(API 등록명)로 중복 제거. 같은 환승역을 여러 노선이 표본으로 뽑아도
  // 한 번만 부른다.
  final queryNames = <String>{};
  for (final samples in sampleByLine.values) {
    for (final s in samples) {
      queryNames.addAll(overrides.queryNames(s.name));
    }
  }

  stdout.writeln('질의 대상 ${queryNames.length}개 역명(중복 제거 후) — 조회 중...');
  final results = await _fetchAll(apiKey, queryNames.toList());

  // 전멸 감지: 응답을 하나도 못 받았으면 "문제 없음" 이 아니라 "확인 못 함".
  final reachable = results.values
      .where((r) => r.status == _QStatus.ok || r.status == _QStatus.noData)
      .length;
  if (reachable == 0) {
    stderr.writeln(
      '도구 실행 불가: API 응답을 하나도 받지 못했다(키 무효·네트워크·일일 한도 초과 가능). '
      '첫 오류: ${results.values.map((r) => r.detail).whereType<String>().firstOrNull ?? "없음"}',
    );
    exit(2);
  }
  final keyErrors =
      results.values.where((r) => r.status == _QStatus.authError).toList();
  if (keyErrors.isNotEmpty) {
    stderr.writeln('도구 실행 불가: API 키 오류 응답 — ${keyErrors.first.detail}');
    exit(2);
  }

  // 평가 -----------------------------------------------------------------
  final stats = <String, _LineStat>{
    for (final l in allLineIds) l: _LineStat(l),
  };
  final unknownSubwayRows = <String>[];
  final evaluator = _Evaluator(data, overrides, reversedSet);

  // 질의 결과를 한 번씩만 평가한다(노선 귀속은 행의 subwayId 로).
  for (final entry in results.entries) {
    final r = entry.value;
    if (r.status != _QStatus.ok) continue;
    for (final row in r.rows) {
      final lineId = subwayIdToLineId[row.subwayId];
      if (lineId == null) {
        unknownSubwayRows.add(
          'subwayId=${row.subwayId} ${row.statnNm} ${row.updnLine} '
          '${row.bstatnNm}행 현재=${row.arvlMsg3} (질의 ${entry.key})',
        );
        continue;
      }
      if (!stats.containsKey(lineId)) continue;
      evaluator.evaluate(stats[lineId]!, row);
    }
  }

  // 질의 단위 통계 — 노선별 "표본 역 질의가 어땠는가".
  for (final l in targetLines) {
    final st = stats[l]!;
    final apiSupported = subwayIdToLineId.containsValue(l);
    for (final s in sampleByLine[l]!) {
      final names = overrides.queryNames(s.name);
      final rs = [for (final n in names) results[n]!];
      st.queried++;
      final anyOk = rs.any((r) => r.status == _QStatus.ok);
      final allNoData = rs.every((r) => r.status == _QStatus.noData);
      if (!anyOk) {
        st.noResponse++;
        if (!allNoData) st.queryErrors++;
        continue;
      }
      // 응답은 왔는데 이 노선 행이 없음(환승역에서 다른 노선만 응답 등).
      final hasLineRow = rs.any(
        (r) => r.rows.any((x) => subwayIdToLineId[x.subwayId] == l),
      );
      if (!hasLineRow) st.noLineRows++;
      // API 미제공 노선인데 그 노선 전용 역 질의에 **미등록 subwayId** 행이 돌아왔다
      // = 열렸을 수 있음. 단순히 "행이 왔다" 로 잡으면 동명이역·인접 노선 응답까지
      // 개통으로 읽어 `--strict` 가 영구 red 가 된다(의정부 표본의 회룡은 1호선,
      // 김포골드의 김포공항은 9호선 행을 돌려준다 — 둘 다 등록된 subwayId 다).
      // 진짜 개통은 반드시 등록되지 않은 subwayId 를 동반하므로 그쪽을 신호로 쓴다.
      if (!apiSupported && !s.isTransfer) {
        for (final r in rs) {
          if (r.rows.any((x) => !subwayIdToLineId.containsKey(x.subwayId))) {
            st.suspectOpened.add(s.name);
          }
        }
      }
    }
  }

  // 판정 + 출력 ----------------------------------------------------------
  final verdicts = <String, _Verdict>{
    for (final l in targetLines)
      l: _judge(stats[l]!, inSet: reversedSet.contains(l)),
  };

  _printReport(
    startedAt: startedAt,
    data: data,
    opts: opts,
    targetLines: targetLines,
    sampleByLine: sampleByLine,
    stats: stats,
    verdicts: verdicts,
    reversedSet: reversedSet,
    unknownSubwayRows: unknownSubwayRows,
    queryCount: queryNames.length,
    results: results,
  );

  final bad = [
    for (final l in targetLines)
      if (verdicts[l]!.kind.isAlert) '$l(${verdicts[l]!.kind.text})',
  ];
  if (opts.strict && bad.isNotEmpty) {
    // 노선과 판정 종류를 같이 찍는다 — 개수만 찍으면 로그에서 "2호선 국소 불일치" 와
    // "의정부 API 개통" 이 똑같이 `이상 판정 1건` 으로 보인다.
    stdout.writeln('\n[--strict] 이상 판정 ${bad.length}건(${bad.join(", ")}) — 종료 코드 1');
    exit(1);
  }
  final unsure = [
    for (final l in targetLines)
      if (_isInconclusive(l, verdicts[l]!.kind, stats[l]!)) l,
  ];
  if (opts.strict && unsure.isNotEmpty) {
    stdout.writeln(
      '\n[--strict] 미확인 노선 ${unsure.length}건(${unsure.join(", ")}) '
      '— 종료 코드 3. 이상이 없다는 뜻이 아니라 확인을 못 했다는 뜻이다.',
    );
    exit(3);
  }
}

Never _unknownLine(String l, List<String> all) {
  stderr.writeln('알 수 없는 노선 ID: $l (가능: ${all.join(", ")})');
  exit(2);
}

const _usage = '''
사용법: dart run tool/check_api_direction_labels.dart [옵션]

  --lines a,b,c   대상 노선 ID 만(기본: 전 노선). 예: --lines 우이신설,9,SB
  --per-line N    노선당 표본 중간 역 수 상향(기본: 역수/10 을 3~6 으로 자른 값)
  --strict        이상 판정이 있으면 종료 코드 1, 확인 못 한 노선만 있으면 3
  --verbose       모든 노선의 불일치 사례를 출력(기본은 이상 판정 노선만)
  -h, --help      이 도움말
''';

// ---------------------------------------------------------------------------
// 옵션
// ---------------------------------------------------------------------------

class _Options {
  final bool strict;
  final bool verbose;
  final bool help;
  final List<String> lines;
  final int? perLine;

  _Options({
    required this.strict,
    required this.verbose,
    required this.help,
    required this.lines,
    required this.perLine,
  });

  factory _Options.parse(List<String> args) {
    var strict = false, verbose = false, help = false;
    var lines = <String>[];
    int? perLine;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      switch (a) {
        case '--strict':
          strict = true;
        case '--verbose':
          verbose = true;
        case '-h' || '--help':
          help = true;
        case '--lines':
          if (i + 1 >= args.length) _bad('--lines 에 값이 필요하다');
          lines = args[++i].split(',').where((e) => e.isNotEmpty).toList();
        case '--per-line':
          if (i + 1 >= args.length) _bad('--per-line 에 값이 필요하다');
          perLine = int.tryParse(args[++i]);
          if (perLine == null || perLine < 0) _bad('--per-line 은 0 이상의 정수');
        default:
          _bad('알 수 없는 옵션: $a');
      }
    }
    return _Options(
      strict: strict,
      verbose: verbose,
      help: help,
      lines: lines,
      perLine: perLine,
    );
  }

  static Never _bad(String m) {
    stderr.writeln('$m\n$_usage');
    exit(2);
  }
}

// ---------------------------------------------------------------------------
// 입력 데이터(번들 JSON) — Station/Connection 모델(freezed) 대신 raw JSON 으로 읽는다.
// ---------------------------------------------------------------------------

class _Sample {
  final String name; // 앱 표시명
  final String id;
  final bool isTransfer;
  const _Sample(this.name, this.id, this.isTransfer);
}

class _Data {
  /// lines.json 순서 그대로의 노선 ID.
  final List<String> lineIds;
  final Map<String, String> lineName; // id → "1호선"
  final Map<String, List<String>> stationIdsOfLine;
  final Map<String, Map<String, dynamic>> stationById; // 역 ID → stations.json 레코드
  final Map<String, Map<String, List<String>>> idsByName; // 노선 → 이름 → [역 ID]
  final Map<String, Set<String>> terminusIds; // 노선 → 종점(차수 ≤1) 역 ID

  /// 노선 → 역 ID → 진행 가능한 이웃. 환승 edge 제외, 단선 일방통행(`isOneWay`)은
  /// 역방향을 만들지 않는다(앱 `GraphBuilder` 와 같은 규칙).
  final Map<String, Map<String, List<String>>> adjacency;

  _Data._(
    this.lineIds,
    this.lineName,
    this.stationIdsOfLine,
    this.stationById,
    this.idsByName,
    this.terminusIds,
    this.adjacency,
  );

  factory _Data.load() {
    List<dynamic> read(String p) =>
        jsonDecode(File(p).readAsStringSync()) as List<dynamic>;
    final lines = read('assets/json/lines.json').cast<Map<String, dynamic>>();
    final stations =
        read('assets/json/stations.json').cast<Map<String, dynamic>>();
    final conns =
        read('assets/json/connections.json').cast<Map<String, dynamic>>();

    final stationById = {for (final s in stations) s['id'] as String: s};
    final lineIds = [for (final l in lines) l['id'] as String];
    final lineName = {for (final l in lines) l['id'] as String: l['name'] as String};
    final stationIdsOfLine = {
      for (final l in lines)
        l['id'] as String: (l['stationIds'] as List).cast<String>(),
    };

    final idsByName = <String, Map<String, List<String>>>{};
    for (final l in lineIds) {
      final m = <String, List<String>>{};
      for (final id in stationIdsOfLine[l]!) {
        final s = stationById[id];
        if (s == null) continue;
        (m[s['name'] as String] ??= []).add(id);
      }
      idsByName[l] = m;
    }

    // 종점 = 그 노선 비환승 연결에서 차수 ≤ 1 인 역. 순환(2호선 본선)은 해당 없음,
    // 분기 dead-end(성수지선 신설동 등)는 종점으로 잡힌다.
    final deg = <String, Map<String, int>>{};
    for (final c in conns) {
      if (c['isTransfer'] == true) continue;
      final l = c['lineId'] as String;
      final d = deg[l] ??= {};
      d[c['fromStationId'] as String] = (d[c['fromStationId']] ?? 0) + 1;
      d[c['toStationId'] as String] = (d[c['toStationId']] ?? 0) + 1;
    }
    final adjacency = <String, Map<String, List<String>>>{};
    for (final c in conns) {
      if (c['isTransfer'] == true) continue;
      final l = c['lineId'] as String;
      final a = c['fromStationId'] as String, b = c['toStationId'] as String;
      final adj = adjacency[l] ??= {};
      (adj[a] ??= []).add(b);
      if (c['isOneWay'] != true) (adj[b] ??= []).add(a);
    }
    final terminus = {
      for (final l in lineIds)
        l: {
          for (final e in (deg[l] ?? const <String, int>{}).entries)
            if (e.value <= 1) e.key,
        },
    };

    return _Data._(lineIds, lineName, stationIdsOfLine, stationById, idsByName,
        terminus, adjacency);
  }

  /// [from] 에서 [to] 로 가는 길이 **둘 이상의 서로 다른 방향**으로 열려 있는가
  /// (= [from] 이 순환 구간 위에 있어 행선지만으로는 진행 방향이 정해지지 않는가).
  ///
  /// [from] 의 이웃마다, [from] 을 지나지 않고 [to] 에 닿을 수 있는지 본다. 그런 이웃이
  /// 둘 이상이면 모호하다. 2호선 본선·6호선 응암 순환 구간이 해당하고, 2호선 성수지선처럼
  /// 가지 끝으로 가는 길은 한 방향뿐이라 해당하지 않는다.
  bool directionAmbiguous(String lineId, String from, String to) {
    final adj = adjacency[lineId];
    if (adj == null || from == to) return false;
    var open = 0;
    for (final start in adj[from] ?? const <String>[]) {
      final seen = <String>{from, start};
      final queue = [start];
      var reached = start == to;
      for (var i = 0; !reached && i < queue.length; i++) {
        for (final n in adj[queue[i]] ?? const <String>[]) {
          if (!seen.add(n)) continue;
          if (n == to) {
            reached = true;
            break;
          }
          queue.add(n);
        }
      }
      if (reached) open++;
    }
    return open >= 2;
  }

  /// [from] → [to] 경로의 **첫 이웃**. 경로가 없으면 null.
  ///
  /// `isDownBetween` 은 **인접 역 쌍**을 전제로 설계됐다(6호선 응암 순환 특례·2호선
  /// 순환 경계가 인접 edge 만 다룬다). 비인접 두 역의 ID 를 그대로 비교하면 순환 구간·
  /// 분기에서 오판하므로, 첫 한 걸음만 떼어 인접 쌍으로 판정한다.
  ///
  /// 길이 아닌 방향이 둘 이상 열려 있으면(순환 구간) 기본은 **최단 경로**다. 다만
  /// [hintHops](API `arvlMsg2` 의 "[N]번째 전역" 이 알려주는 실제 정거장 수)가 있으면
  /// 그 값에 가장 가까운 길을 고른다 — 6호선 응암 순환에서 열차가 역촌에서 순환을 한
  /// 바퀴 돌아 응암에 닿는 경우, 최단 경로(역주행 1정거장)는 실제 진행 방향이 아니다.
  ({String hop, bool confident})? firstHop(String lineId, String from, String to,
      {int? hintHops}) {
    if (from == to) return null;
    final adj = adjacency[lineId];
    if (adj == null) return null;
    final hopsByStart = <String, int>{};
    for (final start in adj[from] ?? const <String>[]) {
      // start 를 첫 걸음으로 해서 to 에 닿는 최소 정거장 수(from 은 다시 지나지 않는다).
      final dist = <String, int>{start: 1};
      final queue = [start];
      for (var i = 0; i < queue.length && !dist.containsKey(to); i++) {
        for (final n in adj[queue[i]] ?? const <String>[]) {
          if (n == from || dist.containsKey(n)) continue;
          dist[n] = dist[queue[i]]! + 1;
          queue.add(n);
        }
      }
      final hops = dist[to];
      if (hops != null) hopsByStart[start] = hops;
    }
    if (hopsByStart.isEmpty) return null;
    final ranked = hopsByStart.entries.toList()
      ..sort((a, b) {
        final sa = hintHops == null ? a.value : (a.value - hintHops).abs();
        final sb = hintHops == null ? b.value : (b.value - hintHops).abs();
        return sa.compareTo(sb);
      });
    if (ranked.length == 1) return (hop: ranked.first.key, confident: true);
    // 길이 둘 이상 — 힌트가 있으면 그 값에 확실히 더 가까운 쪽이 이기고, 힌트가 없으면
    // 한쪽이 다른 쪽의 2배+2 이상 짧아야 믿는다(2호선 본선: 근접 열차는 10정거장 안쪽,
    // 반대편 길은 30+ → 확실. 6호선 응암 순환(6역): 2 vs 4 → 확실하지 않다).
    final a = ranked[0].value, b = ranked[1].value;
    final confident = hintHops != null
        ? (a - hintHops).abs() < (b - hintHops).abs()
        : b >= 2 * a + 2;
    return (hop: ranked.first.key, confident: confident);
  }

  /// 표본 역 선정: 양 종점(lines.json `stationIds` 의 처음·끝) + 그 사이 등간격 중간 역.
  ///
  /// 중간 역 수는 노선 길이/10 을 [_minMid, _maxMid] 로 자른 값(`--per-line` 으로 덮어쓰기).
  /// 역 수 [_fullSampleMaxStations] 이하 노선은 전 역. 여기에 dead-end 안쪽 이웃 역을 더한다.
  /// 종점은 열차 밀도가 낮고 회차 행이 섞이지만 "노선 전체가 반전" 인 경우를 가장 잘
  /// 드러내는 구간(양 끝에서 라벨 극성이 가장 뚜렷)이라 반드시 넣고, 중간 역은 열차
  /// 밀도가 높은 곳을 노려 표본 수를 확보한다. 인덱스는 결정적이라 재실행 때 같은 역이
  /// 나온다 — 시각만 달라질 뿐 표본 편향은 일정하다.
  List<_Sample> sampleStations(String lineId, int? perLine) {
    final ids = stationIdsOfLine[lineId]!;
    if (ids.isEmpty) return const [];
    final n = ids.length;
    final mid = perLine ?? (n ~/ 10).clamp(_minMid, _maxMid);
    final idx = <int>{0, n - 1};
    if (perLine == null && n <= _fullSampleMaxStations) {
      idx.addAll([for (var i = 0; i < n; i++) i]);
    } else {
      for (var i = 1; i <= mid; i++) {
        idx.add((i * (n - 1) / (mid + 1)).round());
      }
    }
    final out = <_Sample>[];
    final seen = <String>{};
    void add(String id) {
      final s = stationById[id];
      if (s == null || !seen.add(id)) return;
      out.add(_Sample(
        s['name'] as String,
        s['id'] as String,
        s['isTransfer'] == true,
      ));
    }

    for (final i in idx.toList()..sort()) {
      add(ids[i]);
    }
    // 지선·분기 dead-end 의 **안쪽 이웃 역**. 노선 양 끝과 등간격 표본만으로는 짧은
    // 지선(2호선 성수지선·신정지선, 1호선 광명 등)이 표본에서 빠지고, 지선 하나가 통째로
    // 반대 극성이어도 노선 전체 불일치율에 묻힌다(2026-10-27 성수지선이 실제로 그랬다).
    // dead-end 자체는 회차 행이 대부분이라 안쪽 이웃(접근 열차가 많은 곳)을 고른다.
    final adj = adjacency[lineId] ?? const <String, List<String>>{};
    for (final e in (terminusIds[lineId] ?? const <String>{})) {
      final ns = adj[e];
      if (ns != null && ns.length == 1) add(ns.first);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// 소스에서 읽는 값 — flutter 의존(`station_api_name_overrides.dart` 는 flutter/foundation
// 을 임포트) 때문에 `dart run` 에서 import 할 수 없어 소스 텍스트를 파싱한다. 단일
// 진실 원천을 유지하려는 것이고, 형식이 바뀌어 파싱이 실패하면 조용히 틀리지 않고
// 도구가 멈춘다(종료 코드 2).
// ---------------------------------------------------------------------------

/// `line_direction.dart` 의 `_apiLabelReversedLines` 리터럴을 읽는다.
/// Dart 소스에서 주석(`//…`, `/*…*/`)만 벗긴다. 문자열 리터럴 안의 `//` 는 그대로
/// 둔다. 항목을 잠시 끄는 가장 흔한 방법이 주석 처리(`// '우이신설',`)인데, 벗기지
/// 않으면 **꺼 둔 항목이 살아 있는 것으로** 읽혀 판정 라벨이 거꾸로 붙는다
/// ("누락 의심" ↔ "반전 해제 의심"). 반대로 URL 이 든 문자열을 잘라 먹으면 그 자체가
/// 새 오독이라 리터럴은 건드리지 않는다.
///
/// 한계: 삼중 따옴표(`'''`)와 문자열 보간 안의 따옴표는 모르는 단순 스캐너다. 대상
/// 두 파일에는 현재 없고, 형식이 바뀌어 파싱이 깨지면 조용히 틀리는 대신 종료 코드
/// 2 로 멈춘다. 근본 해법은 `line_direction.dart` 에 `isApiLabelReversedLine` 을
/// 공개해 파싱을 없애는 것인데, `lib/` 변경이라 사용자 승인 사안이다.
String _stripDartComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == "'" || c == '"') {
      out.write(c);
      i++;
      while (i < src.length) {
        if (src[i] == r'\' && i + 1 < src.length) {
          out.write(src.substring(i, i + 2));
          i += 2;
          continue;
        }
        final ch = src[i];
        out.write(ch);
        i++;
        if (ch == c || ch == '\n') break; // 닫힘, 또는 닫히지 않은 채 줄 끝
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i = (i + 2).clamp(0, src.length);
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

Set<String>? _readReversedLinesFromSource() {
  final f = File('lib/core/utils/line_direction.dart');
  if (!f.existsSync()) return null;
  final m = RegExp(r'const _apiLabelReversedLines\s*=\s*\{([^}]*)\}')
      .firstMatch(_stripDartComments(f.readAsStringSync()));
  if (m == null) return null;
  final items = RegExp(r"'([^']+)'").allMatches(m.group(1)!);
  final out = {for (final i in items) i.group(1)!};
  return out.isEmpty ? null : out;
}

class _Overrides {
  /// 표시명 → API 등록명(아웃바운드).
  final Map<String, String> outbound;

  /// API 등록명 → 표시명(인바운드).
  final Map<String, String> inbound;

  /// 등록명이 노선별로 갈린 역: 표시명 → 질의명 전체.
  final Map<String, List<String>> split;

  _Overrides(this.outbound, this.inbound, this.split);

  static _Overrides? loadFromSource() {
    final f = File('lib/core/constants/station_api_name_overrides.dart');
    if (!f.existsSync()) return null;
    final src = _stripDartComments(f.readAsStringSync());

    final mapBody = RegExp(
      r'const Map<String, String> arrivalApiStationNameOverrides\s*=\s*\{(.*?)\n\};',
      dotAll: true,
    ).firstMatch(src);
    if (mapBody == null) return null;
    final outbound = <String, String>{};
    for (final m in RegExp(r"^\s*'([^']+)':\s*'([^']+)',", multiLine: true)
        .allMatches(mapBody.group(1)!)) {
      outbound[m.group(1)!] = m.group(2)!;
    }
    if (outbound.length < 10) return null; // 파싱이 깨진 것

    final splitBody = RegExp(
      r'const Map<String, List<String>> arrivalApiSplitRegistrationNames\s*=\s*\{(.*?)\n\};',
      dotAll: true,
    ).firstMatch(src);
    final split = <String, List<String>>{};
    if (splitBody != null) {
      for (final m in RegExp(r"^\s*'([^']+)':\s*\[([^\]]*)\]", multiLine: true)
          .allMatches(splitBody.group(1)!)) {
        split[m.group(1)!] = [
          for (final n in RegExp(r"'([^']+)'").allMatches(m.group(2)!))
            n.group(1)!,
        ];
      }
    }
    return _Overrides(
      outbound,
      {for (final e in outbound.entries) e.value: e.key},
      split,
    );
  }

  List<String> queryNames(String display) =>
      split[display] ?? [outbound[display] ?? display];

  /// 응답에 나온 등록명을 표시명으로(없으면 그대로). 응답 텍스트 전체 치환이 아니라
  /// 이름 한 토큰용이다.
  String toDisplay(String apiName) => inbound[apiName] ?? apiName;
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

String _readApiKey() {
  final f = File('.env');
  if (!f.existsSync()) {
    throw _ToolError('.env 가 없다(프로젝트 루트에서 실행할 것)');
  }
  for (final raw in f.readAsLinesSync()) {
    final line = raw.trim();
    if (line.startsWith('#') || !line.contains('=')) continue;
    final i = line.indexOf('=');
    if (line.substring(0, i).trim() != 'BUSAN_SUBWAY_API_KEY') continue;
    var v = line.substring(i + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    if (v.isEmpty || v == 'your_api_key_here') {
      throw _ToolError('BUSAN_SUBWAY_API_KEY 가 비었거나 placeholder 다');
    }
    return v;
  }
  throw _ToolError('.env 에 BUSAN_SUBWAY_API_KEY 가 없다');
}

class _ToolError implements Exception {
  final String message;
  _ToolError(this.message);
}

enum _QStatus { ok, noData, authError, error }

class _ApiRow {
  final String subwayId;
  final String updnLine;
  final String statnNm;
  final String bstatnNm;
  final String arvlMsg2;
  final String arvlMsg3;
  final String arvlCd;
  final String btrainNo;
  _ApiRow({
    required this.subwayId,
    required this.updnLine,
    required this.statnNm,
    required this.bstatnNm,
    required this.arvlMsg2,
    required this.arvlMsg3,
    required this.arvlCd,
    required this.btrainNo,
  });

  /// 같은 열차를 두 질의 응답에서 받았는지 가르는 키. 종점 T 와 그 안쪽 이웃 N 이
  /// **둘 다 표본**이라(`sampleStations` 의 dead-end 규칙) T 로 다가오는 열차 1대가
  /// T 응답·N 응답에 같은 `arvlMsg3` 로 실린다. 둘의 `firstHop` 첫 걸음이 같아
  /// 간선 키까지 같아지므로, 세지 않으면 1대가 2건으로 잡혀 간선 임계를 혼자 넘는다.
  /// `btrainNo` 가 비는 노선은 "방향+현재역+행선지" 조합으로 대신한다 — 바로 그
  /// 이중 보고가 세 값이 모두 같다는 점을 이용한 것이다.
  String get trainKey => btrainNo.isNotEmpty
      ? btrainNo
      : '$updnLine|$arvlMsg3|$bstatnNm';

  factory _ApiRow.fromJson(Map<String, dynamic> j) => _ApiRow(
        subwayId: '${j['subwayId'] ?? ''}',
        updnLine: '${j['updnLine'] ?? ''}',
        statnNm: '${j['statnNm'] ?? ''}',
        bstatnNm: '${j['bstatnNm'] ?? ''}',
        arvlMsg2: '${j['arvlMsg2'] ?? ''}',
        arvlMsg3: '${j['arvlMsg3'] ?? ''}',
        arvlCd: '${j['arvlCd'] ?? ''}',
        btrainNo: '${j['btrainNo'] ?? ''}',
      );
}

class _QResult {
  final _QStatus status;
  final List<_ApiRow> rows;
  final String? detail;
  _QResult(this.status, {this.rows = const [], this.detail});
}

Future<Map<String, _QResult>> _fetchAll(String apiKey, List<String> names) async {
  final client = HttpClient()..connectionTimeout = _queryTimeout;
  final out = <String, _QResult>{};
  try {
    for (var i = 0; i < names.length; i += _concurrency) {
      final batch = names.sublist(
        i,
        i + _concurrency > names.length ? names.length : i + _concurrency,
      );
      final rs = await Future.wait(batch.map((n) => _fetchOne(client, apiKey, n)));
      for (var j = 0; j < batch.length; j++) {
        out[batch[j]] = rs[j];
      }
    }
  } finally {
    client.close(force: true);
  }
  return out;
}

Future<_QResult> _fetchOne(HttpClient client, String apiKey, String name) async {
  // 일시 장애 1회 재시도. 이름이 틀려서 INFO-200 인 것과 구분되도록 오류만 재시도한다.
  for (var attempt = 0; attempt < 2; attempt++) {
    final r = await _fetchOnce(client, apiKey, name);
    if (r.status != _QStatus.error) return r;
    if (attempt == 1) return r;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return _QResult(_QStatus.error, detail: 'unreachable');
}

Future<_QResult> _fetchOnce(HttpClient client, String apiKey, String name) async {
  // URL(키 포함)은 어떤 출력에도 싣지 않는다. 예외 메시지에 URL 이 섞일 수 있어
  // 키를 가린 뒤에만 detail 로 보관한다.
  String redact(Object e) => '$e'.replaceAll(apiKey, '***');
  try {
    final uri = Uri(
      scheme: 'http',
      host: Uri.parse(ApiConstants.subwayBaseUrl).host,
      pathSegments: [
        'api',
        'subway',
        apiKey,
        'json',
        'realtimeStationArrival',
        '0',
        '${ApiConstants.arrivalRowLimit}',
        name,
      ],
    );
    final req = await client.getUrl(uri).timeout(_queryTimeout);
    final resp = await req.close().timeout(_queryTimeout);
    final body = await resp.transform(utf8.decoder).join().timeout(_queryTimeout);
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) {
      return _QResult(_QStatus.error, detail: '응답이 JSON 객체가 아님');
    }
    final err = data['errorMessage'];
    if (err is Map<String, dynamic>) {
      final code = '${err['code'] ?? ''}';
      if (code == 'INFO-200') return _QResult(_QStatus.noData);
      // 키 무효(INFO-100)·인증 실패 계열은 전 질의가 같은 결과라 별도 처리.
      if (code == 'INFO-100' || code.startsWith('ERROR-3')) {
        return _QResult(_QStatus.authError,
            detail: redact('$code ${err['message'] ?? ''}'));
      }
      if (code != 'INFO-000' && data['realtimeArrivalList'] == null) {
        return _QResult(_QStatus.error,
            detail: redact('$code ${err['message'] ?? ''}'));
      }
    }
    final list = data['realtimeArrivalList'];
    if (list == null) return _QResult(_QStatus.noData);
    return _QResult(
      _QStatus.ok,
      rows: [
        for (final e in list as List<dynamic>)
          _ApiRow.fromJson(e as Map<String, dynamic>),
      ],
    );
  } on Object catch (e) {
    return _QResult(_QStatus.error, detail: redact(e));
  }
}

// ---------------------------------------------------------------------------
// 평가
// ---------------------------------------------------------------------------

class _LineStat {
  final String lineId;

  // 질의 단위
  int queried = 0; // 표본 역 수
  int noResponse = 0; // INFO-200/오류로 응답 없음
  int queryErrors = 0; // 그 중 INFO-200 이 아닌 오류(타임아웃 등)
  int noLineRows = 0; // 응답은 왔으나 이 노선 행 없음
  final Set<String> suspectOpened = {}; // API 미제공 노선인데 행이 돌아온 역

  // 행 단위
  int rows = 0;
  int match = 0;
  int mismatch = 0;
  int unresolved = 0; // 이름 미해석
  int turnaround = 0; // 종착 회차
  int turnaroundMatch = 0;
  int turnaroundMismatch = 0;
  int badLabel = 0;

  // 라벨별 (평가 가능 행)
  int upMatch = 0, upMismatch = 0, downMatch = 0, downMismatch = 0;

  // 행선지 기준 교차 검증(1차 기준이 가능했던 행 중 행선지도 해석된 행)
  int destChecked = 0;
  int destMismatch = 0;

  final Map<String, int> unresolvedNames = {};

  /// 조회역(표시명)별 [일치, 불일치] — 노선 일부(지선)만 반대 극성인 경우를 찾는 용도.
  final Map<String, List<int>> byQuery = {};

  /// **실제로 극성을 판정한 인접 간선**(`현재역→다음역` 이름)별 [일치, 불일치].
  /// 조회역 키만으로는 1역 지선을 놓친다 — 광명↔금천구청·서동탄↔병점은 표본 역이
  /// 지선 역이 아니라 **본선 분기역**이라, 지선 행 1~2건이 본선 행 10여 건에 섞여
  /// 70% 선을 못 넘는다. 간선으로 가르면 `광명→금천구청` 과 `영등포→금천구청` 이
  /// 분리돼 2건만으로 걸린다. (지선 길이가 2 이상인 성수지선은 안쪽 이웃이 지선
  /// 역이라 조회역 키로도 걸렸다 — 두 키가 서로를 보완한다.)
  final Map<String, List<int>> byEdge = {};

  /// 간선별 **불일치를 낸 서로 다른 열차**. 간선 키는 조회역 키보다 분모가 작아
  /// 그대로 두면 열차 한 대가 혼자 임계를 넘는다 — 종점 T 와 안쪽 이웃 N 이 둘 다
  /// 표본이라 T 로 다가오는 열차 1대가 두 응답에 실리고, 두 `firstHop` 의 첫 걸음이
  /// 같아 간선 키까지 같아지기 때문이다(실측: 우이신설 `정릉→가오리` + `정릉→
  /// 삼양사거리`). 그래서 간선 hotspot 은 **열차 2대 이상**을 추가로 요구한다.
  final Map<String, Set<String>> byEdgeBadTrains = {};
  final List<String> mismatchSamples = [];
  final List<String> turnaroundSamples = [];

  _LineStat(this.lineId);

  /// 국소 이상: 한 지점(조회역 **또는** 판정한 인접 간선)에서 평가 가능 행의 70%
  /// 이상이 어긋나고 불일치가 2건 이상인 곳. 1건짜리 이탈(1호선 신도림에 개봉 열차
  /// 오보고 등)은 데이터 노이즈라 잡지 않는다.
  List<String> get hotspots => [
        for (final e in byQuery.entries)
          if (_isHot(e.value)) '${e.key}(${e.value[1]}/${e.value[0] + e.value[1]})',
        for (final e in byEdge.entries)
          if (_isHot(e.value) && _trainsOn(e.key) >= 2)
            '${e.key}(${e.value[1]}/${e.value[0] + e.value[1]}, 열차 ${_trainsOn(e.key)}대)',
      ];

  /// 간선 임계는 넘었지만 **열차가 1대뿐**이라 판정을 바꾸지 않은 것. 1역 지선
  /// (광명↔금천구청, 서동탄↔병점)의 셔틀은 한 번에 1대라 대개 여기로만 나온다 —
  /// 종료 코드로 울리기엔 근거가 얇고, 묻어 두기엔 아까워 눈으로 보게 남긴다.
  List<String> get edgeNotes => [
        for (final e in byEdge.entries)
          if (_isHot(e.value) && _trainsOn(e.key) < 2)
            '${e.key}(${e.value[1]}/${e.value[0] + e.value[1]}, 열차 1대 — 판정 미반영)',
      ];

  int _trainsOn(String edge) => byEdgeBadTrains[edge]?.length ?? 0;

  static bool _isHot(List<int> v) =>
      v[1] >= 2 && v[1] / (v[0] + v[1]) >= _flipMinRate;

  int get evaluable => match + mismatch;
  double get mismatchRate => evaluable == 0 ? 0 : mismatch / evaluable;
}

class _Evaluator {
  final _Data data;
  final _Overrides ov;
  final Set<String> reversedSet;
  _Evaluator(this.data, this.ov, this.reversedSet);

  /// `arvlMsg3` 같은 필드에서 순수 역명 후보를 뽑는다("솔샘 도착" → "솔샘").
  String _stripStatus(String raw) {
    final parts = raw.trim().split(' ');
    if (parts.length >= 2 && _statusSuffixes.contains(parts.last)) {
      return parts.sublist(0, parts.length - 1).join(' ');
    }
    return raw.trim();
  }

  /// `arvlMsg3` 의 상태 접미사("솔샘 도착" → "도착"). 접미사가 없으면 null.
  String? _statusOf(String raw) {
    final parts = raw.trim().split(' ');
    if (parts.length >= 2 && _statusSuffixes.contains(parts.last)) {
      return parts.last;
    }
    return null;
  }

  static final _alias = RegExp(r'\s*\([^)]*\)\s*');

  /// `arvlMsg2` 에서 "몇 정거장 앞인가": "[3]번째 전역 (…)" → 3, "전역 도착/출발/진입" → 1.
  /// 그 외("4분 30초 후 (용답)" 등)는 알 수 없어 null.
  static int? _stationCountHint(String msg2) {
    final m = RegExp(r'\[(\d+)\]번째 전역').firstMatch(msg2);
    if (m != null) return int.parse(m.group(1)!);
    if (msg2.startsWith('전역 ')) return 1;
    return null;
  }

  /// 이름 → 그 노선의 역 ID. 못 찾거나 모호(동명 2개 이상)면 null.
  ///
  /// 앱(`live_train_provider`)과 같은 순서: 정확 일치 → 등록명 역치환 → 부역명 괄호 제거.
  String? _resolve(String lineId, String raw) {
    if (raw.isEmpty) return null;
    final byName = data.idsByName[lineId]!;
    final base = _stripStatus(raw);
    final candidates = <String>[
      base,
      ov.toDisplay(base),
      base.replaceAll(_alias, '').trim(),
      ov.toDisplay(base.replaceAll(_alias, '').trim()),
    ];
    // 2호선 지선 행선지는 역명이 아니라 "성수지선"·"신도림지선" 이다. 지선 열차가 돌아가는
    // 분기역(성수·신도림)으로 읽는다.
    if (base.endsWith('지선')) {
      candidates.add(base.substring(0, base.length - 2));
    }
    for (final c in candidates) {
      final ids = byName[c];
      if (ids != null && ids.length == 1) return ids.first;
    }
    return null;
  }

  void evaluate(_LineStat st, _ApiRow row) {
    st.rows++;
    final l = st.lineId;

    final label = row.updnLine;
    if (!const {'상행', '하행', '내선', '외선'}.contains(label)) {
      st.badLabel++;
      return;
    }
    final labelDown = label == '하행' || label == '외선'; // 앱 isDownDirectionString 과 동일

    final qId = _resolve(l, row.statnNm);
    final rawCId = _resolve(l, row.arvlMsg3);
    if (qId == null || rawCId == null) {
      st.unresolved++;
      final bad = qId == null ? row.statnNm : row.arvlMsg3;
      st.unresolvedNames[bad] = (st.unresolvedNames[bad] ?? 0) + 1;
      return;
    }
    var cId = rawCId;
    final dId = _resolve(l, row.bstatnNm);
    final terminus = data.terminusIds[l] ?? const <String>{};

    // `arvlMsg3 = "X 전역"` 은 "X 에 있다" 가 아니라 **X 직전 역에 있다** 는 뜻이다
    // (`arrival_info_dto.dart` 의 같은 해석 참조). 비종점에서는 현재→행선지 극성이
    // 접근 극성과 같아 판정이 어긋나지 않지만, **종점**에서는 `cId == qId` 가 되어
    // 아래 "종착 회차" 제외에 걸린다 — 행선지가 곧 종점인, 가장 깨끗한 접근 행이
    // 통째로 버려진다(심야에 표본이 얇은 종점일수록 손실이 크다). 종점은 이웃이
    // 하나뿐이라 직전 역이 유일하게 정해지므로 그 경우에만 보정한다. 이웃이 둘
    // 이상이면 어느 쪽에서 오는지 알 수 없으니 손대지 않는다.
    if (cId == qId) {
      final ns = data.adjacency[l]?[qId];
      // `ns.length == 1` 만으로는 부족하다 — `adjacency` 는 일방통행 간선의 역방향을
      // 만들지 않으므로, 새 일방통행 구간이 생기면 **비종점**도 이웃 1개로 보이고
      // 그때 `ns.first` 는 직전역이 아니라 **다음역**이라 극성이 거꾸로 붙는다.
      // 현재 데이터에는 그런 역이 없지만(일방통행은 6호선 구산→응암 1건) 조용히
      // 틀리는 종류라 종점 조건을 같이 건다.
      if (_statusOf(row.arvlMsg3) == '전역' &&
          terminus.contains(qId) &&
          ns != null &&
          ns.length == 1) {
        cId = ns.first;
      }
    }

    final desc = '$label | 현재=${row.arvlMsg3.isEmpty ? "?" : row.arvlMsg3} '
        '→ 조회=${row.statnNm} | 행선=${row.bstatnNm}';

    var lastConfident = true;
    String? lastEdge;

    /// `from → to` 방향을 앱 규칙으로 판정. 경로가 없으면 null. 순환 구간에서 진행
    /// 방향을 확신할 수 없으면 [lastConfident] 가 false 가 된다. [lastEdge] 에는
    /// `isDownBetween` 에 실제로 넘긴 **인접 쌍**을 남긴다(국소 집계용).
    bool? appDirection(String from, String to, {int? hint}) {
      final r = data.firstHop(l, from, to, hintHops: hint);
      if (r == null) return null;
      lastConfident = r.confident;
      lastEdge = '${data.stationById[from]?["name"]}→${data.stationById[r.hop]?["name"]}';
      // 앱이 **라벨을 읽는 방식** 그대로여야 한다. 부산 전환으로 구간 단위 라벨
      // 반전(서울 2호선 성수지선)은 제거됐고 앱은 `isDownBetween` 만으로 라벨을
      // 읽는다. 반전 구간이 다시 필요해지면 여기도 같이 맞출 것.
      return isDownBetween(from, r.hop, l);
    }

    void noPath(String from, String to) {
      st.unresolved++;
      final k = '경로없음(${data.stationById[from]?['name']}→${data.stationById[to]?['name']})';
      st.unresolvedNames[k] = (st.unresolvedNames[k] ?? 0) + 1;
    }

    bool appDown; // 앱 판정(1차)
    String how;
    String? edgeKey; // 1차 판정에 쓴 인접 간선. 교차 검증이 덮기 전에 붙잡아 둔다.
    if (cId != qId) {
      // 종점으로 들어오는 열차가 회차해 행선지로 돌아가는 경우(행선지 != 종점 조회역):
      // 종점에 닿은 뒤의 방향과 닿기 전의 방향이 반대라 API 라벨이 어느 쪽인지 행마다
      // 갈린다 — 6호선 신내 접근 열차가 `상행|행선=응암순환` 으로 오는 것이 실측 예.
      if (terminus.contains(qId) && dId != null && dId != qId) {
        st.turnaround++;
        final a = appDirection(cId, qId);
        if (a == null) return;
        if (a == labelDown) {
          st.turnaroundMatch++;
        } else {
          st.turnaroundMismatch++;
          _addSample(st.turnaroundSamples, '$desc (종점 접근 후 회차)');
        }
        return;
      }
      // 접근 방향: 열차가 현재역에서 조회역으로 다가온다.
      final a = appDirection(cId, qId, hint: _stationCountHint(row.arvlMsg2));
      if (a == null) {
        noPath(cId, qId);
        return;
      }
      if (!lastConfident) {
        // 순환 구간에서 두 길이 비슷해 열차가 어느 쪽으로 도는지 알 수 없다.
        st.turnaround++;
        _addSample(st.turnaroundSamples, '$desc (순환 구간 — 진행 방향 불명)');
        return;
      }
      appDown = a;
      how = '접근';
      edgeKey = lastEdge;
      // 교차 검증: 현재역 → 행선지. 순환 구간은 행선지로 방향이 정해지지 않아 제외한다.
      if (dId != null &&
          dId != cId &&
          !data.directionAmbiguous(l, cId, dId)) {
        final d = appDirection(cId, dId);
        if (d != null) {
          st.destChecked++;
          if (d != labelDown) st.destMismatch++;
        }
      }
    } else {
      // 승강장 위 열차: 접근 방향이 없다 → 현재역 → 행선지.
      if (dId == null) {
        st.unresolved++;
        st.unresolvedNames[row.bstatnNm] =
            (st.unresolvedNames[row.bstatnNm] ?? 0) + 1;
        return;
      }
      final loopy = dId != cId && data.directionAmbiguous(l, cId, dId);
      if (dId == cId || terminus.contains(cId) || loopy) {
        // 종착 회차 또는 순환 구간 — 방향이 모호하다. 일치 여부는 참고로만 센다.
        st.turnaround++;
        if (dId != cId && !loopy) {
          final a = appDirection(cId, dId);
          if (a != null) {
            if (a == labelDown) {
              st.turnaroundMatch++;
            } else {
              st.turnaroundMismatch++;
              _addSample(st.turnaroundSamples, '$desc (종점 회차)');
            }
          }
        }
        return;
      }
      final a = appDirection(cId, dId);
      if (a == null) {
        noPath(cId, dId);
        return;
      }
      appDown = a;
      how = '행선';
      edgeKey = lastEdge;
    }

    final ok = appDown == labelDown;
    if (ok) {
      st.match++;
    } else {
      st.mismatch++;
      _addSample(
        st.mismatchSamples,
        '$desc  [$how판정=${appDown ? "하행" : "상행"}]',
      );
    }
    final q = (st.byQuery[row.statnNm] ??= [0, 0]);
    q[ok ? 0 : 1]++;
    if (edgeKey != null) {
      (st.byEdge[edgeKey] ??= [0, 0])[ok ? 0 : 1]++;
      if (!ok) (st.byEdgeBadTrains[edgeKey] ??= {}).add(row.trainKey);
    }
    if (labelDown) {
      ok ? st.downMatch++ : st.downMismatch++;
    } else {
      ok ? st.upMatch++ : st.upMismatch++;
    }
  }

  static void _addSample(List<String> into, String s) {
    if (into.length < 12 && !into.contains(s)) into.add(s);
  }
}

// ---------------------------------------------------------------------------
// 판정
// ---------------------------------------------------------------------------

enum _Kind {
  ok('OK'),
  missing('누락 의심'),
  stale('반전 해제 의심'),
  mixed('혼재'),
  local('국소 불일치'),
  few('표본 부족'),
  noApi('API 미제공'),
  opened('API 개통 의심'),
  noRows('표본 없음');

  final String text;
  const _Kind(this.text);

  /// `--strict` 로 실패시키는 판정(종료 코드 1). 표본 부족·표본 없음은 "확인 못 함"
  /// 이지 이상이 아니라서 여기 넣지 않는다 — 대신 종료 코드 3 으로 따로 내보낸다
  /// (`_isInconclusive`). 0 으로 뭉개면 cron 이 "오늘도 이상 없음" 으로 읽는다.
  ///
  /// [opened] 는 앱 쪽 이상이 아니라 **사람이 해야 할 등록 작업**이지만, 바로 그
  /// "조용한 노후화" 를 깨려고 만든 도구라 알림 대상이다. 의정부·김포골드의 API 가
  /// 열려도 종료 코드가 0 이면 신호가 stdout 본문에만 남는다.
  bool get isAlert =>
      this == missing ||
      this == stale ||
      this == mixed ||
      this == local ||
      this == opened;
}

/// "이상은 없었지만 확인도 못 한" 노선 — API 지원 노선인데 평가 가능 표본이 모자라거나
/// 아예 없는 경우. 심야·API 장애·일일 한도 초과가 실행 중간에 걸리면 전 노선이 여기로
/// 떨어지는데, 전멸 가드(`reachable == 0`)는 INFO-200 을 "응답" 으로 세기 때문에
/// 걸리지 않는다. 종료 코드 3 이 그 구멍을 막는다.
///
/// `ok` 인데도 "확인 못 함" 으로 치는 경우가 있다 — 질의 일부가 **오류**(INFO-200 이
/// 아니라 네트워크·한도 초과)로 빠진 채 남은 표본만으로 임계를 넘긴 경우다. 지선
/// 탐지는 dead-end 안쪽 이웃 질의 **1건**에 걸려 있고 그 표본은 질의 순서상 뒤쪽이라,
/// 일일 한도가 실행 중간에 걸리면 성수지선·광명 신호부터 사라진 채 OK 가 된다.
bool _isInconclusive(String lineId, _Kind kind, _LineStat st) =>
    subwayIdToLineId.containsValue(lineId) &&
    (kind == _Kind.few ||
        kind == _Kind.noRows ||
        (kind == _Kind.ok && st.queryErrors > 0));

class _Verdict {
  final _Kind kind;
  final String note;
  _Verdict(this.kind, this.note);
}

_Verdict _judge(_LineStat s, {required bool inSet}) {
  final apiSupported = subwayIdToLineId.containsValue(s.lineId);
  if (!apiSupported) {
    final opened = s.suspectOpened.isNotEmpty
        ? ' ⚠ 전용 역 ${s.suspectOpened.join(",")} 에서 행이 돌아옴 — API 가 열렸을 수 있음(미등록 subwayId 절 확인)'
        : '';
    return _Verdict(
      s.suspectOpened.isEmpty ? _Kind.noApi : _Kind.opened,
      '질의 ${s.queried}건 중 ${s.noResponse}건 미응답(INFO-200)$opened',
    );
  }
  if (s.rows == 0) {
    return _Verdict(
      _Kind.noRows,
      s.noResponse == s.queried
          ? '표본 역 전부 미응답 — 재실행 필요'
          : '응답에 이 노선 행이 없음(운행 시간대·표본 역 확인)',
    );
  }
  if (s.evaluable < _minEvaluable) {
    return _Verdict(_Kind.few, '평가 가능 ${s.evaluable}건 < $_minEvaluable — 재실행/`--per-line` 상향');
  }
  final r = s.mismatchRate;
  final hot = s.hotspots;
  if (r < _flipMinRate && hot.isNotEmpty) {
    return _Verdict(
      _Kind.local,
      '노선 전체는 대체로 맞지만 일부 역에서 라벨과 반대 — ${hot.join(", ")} '
      '(지선·분기 극성 가능, 불일치 사례 확인)',
    );
  }
  if (r <= _okMaxRate) {
    return _Verdict(_Kind.ok, inSet ? '반전 유효(앱 판정이 라벨과 일치)' : '일반 규칙 유효');
  }
  if (r >= _flipMinRate) {
    return inSet
        ? _Verdict(_Kind.stale,
            '반전 목록에 있는데 라벨은 일반 규칙(ID 증가=하행) 쪽 — 반전 해제 검토')
        : _Verdict(_Kind.missing,
            '반전 목록에 없는데 라벨이 앱과 반대 — `_apiLabelReversedLines` 추가 검토');
  }
  return _Verdict(
    _Kind.mixed,
    '일부만 어긋남 — 분기·순환·데이터 오보고 가능, 사례 확인'
    '${hot.isEmpty ? "" : " (집중 역: ${hot.join(", ")})"}',
  );
}

// ---------------------------------------------------------------------------
// 출력
// ---------------------------------------------------------------------------

void _printReport({
  required DateTime startedAt,
  required _Data data,
  required _Options opts,
  required List<String> targetLines,
  required Map<String, List<_Sample>> sampleByLine,
  required Map<String, _LineStat> stats,
  required Map<String, _Verdict> verdicts,
  required Set<String> reversedSet,
  required List<String> unknownSubwayRows,
  required int queryCount,
  required Map<String, _QResult> results,
}) {
  String ts(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  final failed = results.values.where((r) => r.status == _QStatus.error).length;
  final noData = results.values.where((r) => r.status == _QStatus.noData).length;

  stdout.writeln('');
  stdout.writeln('=== API updnLine ↔ 앱 isDownBetween 대조 ===');
  stdout.writeln('측정 시작: ${ts(startedAt)} (로컬)   질의 $queryCount건 '
      '(응답 ${queryCount - noData - failed} / INFO-200 $noData / 오류 $failed)');
  stdout.writeln('앱 반전 목록(_apiLabelReversedLines): ${(reversedSet.toList()..sort()).join(", ")}');
  stdout.writeln('임계: 평가가능≥$_minEvaluable, OK≤${(_okMaxRate * 100).round()}%, '
      '반전 의심≥${(_flipMinRate * 100).round()}%, 그 사이=혼재');
  // 표를 끝까지 읽지 않는 사람에게 "OK 18개" 와 "미확인 6개" 가 같은 무게로 보여야 한다.
  var nOk = 0, nAlert = 0, nUnsure = 0, nNoApi = 0;
  for (final l in targetLines) {
    final k = verdicts[l]!.kind;
    if (k.isAlert) {
      nAlert++;
    } else if (_isInconclusive(l, k, stats[l]!)) {
      nUnsure++;
    } else if (k == _Kind.ok) {
      nOk++;
    } else {
      nNoApi++;
    }
  }
  stdout.writeln('노선 ${targetLines.length}개 — OK $nOk · 이상 $nAlert · '
      '미확인 $nUnsure(표본 부족·표본 없음: 확인 못 한 것이지 이상 없는 것이 아니다) · '
      'API 미제공 $nNoApi');
  stdout.writeln('');

  // 표 --------------------------------------------------------------------
  const headers = [
    '노선',
    '반전',
    '질의',
    '미응답',
    '표본',
    '일치',
    '불일치',
    '앱불일치율',
    '일반규칙불일치율',
    '판정불가(이름/회차/라벨)',
    '판정',
  ];
  final table = <List<String>>[headers];
  for (final l in targetLines) {
    final s = stats[l]!;
    final v = verdicts[l]!;
    final inSet = reversedSet.contains(l);
    String pct(double x) => '${(x * 100).toStringAsFixed(0)}%';
    final hasEval = s.evaluable > 0;
    table.add([
      '$l(${data.lineName[l]})',
      inSet ? 'Y' : '-',
      '${s.queried}',
      '${s.noResponse}',
      '${s.evaluable}',
      hasEval ? '${s.match}' : '-',
      hasEval ? '${s.mismatch}' : '-',
      hasEval ? pct(s.mismatchRate) : '-',
      // 일반규칙 = 반전 목록 노선이면 앱 판정의 부정, 아니면 앱 판정과 같다.
      hasEval ? pct(inSet ? 1 - s.mismatchRate : s.mismatchRate) : '-',
      '${s.unresolved}/${s.turnaround}/${s.badLabel}',
      v.kind.text,
    ]);
  }
  _printTable(table);

  stdout.writeln('');
  stdout.writeln('열 설명: 질의=표본 역 수, 미응답=INFO-200/오류로 응답 없던 표본 역 수, '
      '표본=평가 가능 행(일치+불일치).');
  stdout.writeln('       판정불가는 불일치에 포함되지 않는다(이름 미해석 / 종착 회차 / 라벨 이상).');

  // 요약 ------------------------------------------------------------------
  stdout.writeln('');
  stdout.writeln('--- 판정 요약 ---');
  final byKind = <_Kind, List<String>>{};
  for (final l in targetLines) {
    (byKind[verdicts[l]!.kind] ??= []).add(l);
  }
  for (final k in _Kind.values) {
    final ls = byKind[k];
    if (ls == null) continue;
    stdout.writeln('${k.text} (${ls.length}): ${ls.join(", ")}');
  }

  // 상세 ------------------------------------------------------------------
  stdout.writeln('');
  stdout.writeln('--- 노선별 상세 ---');
  for (final l in targetLines) {
    final s = stats[l]!;
    final v = verdicts[l]!;
    // 불일치 사례는 드물고 출력은 싸다. "OK" 뒤에 1건짜리 지선 신호가 묻히는 것이
    // 이 도구의 가장 현실적인 거짓 안심 경로라, 판정과 무관하게 항상 보여 준다.
    final show = opts.verbose || v.kind.isAlert || s.mismatch > 0;
    stdout.writeln('');
    stdout.writeln('[$l ${data.lineName[l]}] ${v.kind.text} — ${v.note}');
    stdout.writeln('  표본 역: ${sampleByLine[l]!.map((e) => e.name).join(", ")}');
    stdout.writeln('  질의 ${s.queried} / 미응답 ${s.noResponse}'
        '${s.queryErrors > 0 ? " (그 중 오류 ${s.queryErrors})" : ""}'
        ' / 응답은 왔으나 이 노선 행 없음 ${s.noLineRows}');
    if (s.rows > 0) {
      stdout.writeln('  행 ${s.rows}: 일치 ${s.match} · 불일치 ${s.mismatch} · '
          '이름 미해석 ${s.unresolved} · 종착 회차 ${s.turnaround}'
          '${s.turnaround > 0 ? "(참고: 일치 ${s.turnaroundMatch}/불일치 ${s.turnaroundMismatch})" : ""}'
          ' · 라벨 이상 ${s.badLabel}');
      stdout.writeln('  라벨별: 상행/내선 일치 ${s.upMatch}·불일치 ${s.upMismatch}, '
          '하행/외선 일치 ${s.downMatch}·불일치 ${s.downMismatch}');
      if (s.destChecked > 0) {
        stdout.writeln('  행선지 기준 교차 검증: ${s.destChecked}건 중 불일치 ${s.destMismatch}');
      }
      if (s.unresolvedNames.isNotEmpty) {
        final top = s.unresolvedNames.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        stdout.writeln('  이름 미해석: '
            '${top.take(8).map((e) => "${e.key}×${e.value}").join(", ")}');
      }
    }
    if (show) {
      final badQ = [
        for (final e in s.byQuery.entries)
          if (e.value[1] > 0) '${e.key} ${e.value[1]}/${e.value[0] + e.value[1]}',
      ];
      if (badQ.isNotEmpty) {
        stdout.writeln('  조회역별 불일치(불일치/평가가능): ${badQ.join(", ")}');
      }
      if (s.edgeNotes.isNotEmpty) {
        stdout.writeln('  간선 주의(열차 1대라 판정에 반영 안 함): ${s.edgeNotes.join(", ")}');
      }
      for (final m in s.mismatchSamples.take(opts.verbose ? 12 : 5)) {
        stdout.writeln('    불일치 예) $m');
      }
      if (s.turnaroundSamples.isNotEmpty) {
        for (final m in s.turnaroundSamples.take(3)) {
          stdout.writeln('    판정 제외 사례) $m');
        }
      }
    }
  }

  // 미등록 subwayId ------------------------------------------------------
  if (unknownSubwayRows.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('--- 미등록 subwayId 행 ${unknownSubwayRows.length}건 '
        '(subway_id_mapping.dart 에 없는 노선 — API 가 새 노선을 열었을 수 있음) ---');
    for (final r in unknownSubwayRows.take(10)) {
      stdout.writeln('  $r');
    }
  } else {
    stdout.writeln('');
    stdout.writeln('미등록 subwayId 행: 없음(모든 응답 행이 등록된 노선으로 귀속됨)');
  }

  // 오류 질의 --------------------------------------------------------------
  final errs = results.entries
      .where((e) => e.value.status == _QStatus.error)
      .toList();
  if (errs.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('--- 오류 질의 ${errs.length}건 ---');
    for (final e in errs.take(10)) {
      stdout.writeln('  ${e.key}: ${e.value.detail}');
    }
  }
}

/// 한글(전각) 폭을 2칸으로 계산해 열을 맞춘다.
int _width(String s) {
  var w = 0;
  for (final r in s.runes) {
    w += (r >= 0x1100 && r <= 0x11FF) ||
            (r >= 0x2E80 && r <= 0xD7FF) ||
            (r >= 0xF900 && r <= 0xFAFF) ||
            (r >= 0xFF00 && r <= 0xFF60)
        ? 2
        : 1;
  }
  return w;
}

String _padRight(String s, int w) => s + ' ' * (w - _width(s)).clamp(0, 1 << 20);

void _printTable(List<List<String>> rows) {
  final cols = rows.first.length;
  final widths = List<int>.generate(
    cols,
    (c) => rows.map((r) => _width(r[c])).reduce((a, b) => a > b ? a : b),
  );
  for (var i = 0; i < rows.length; i++) {
    final line = [
      for (var c = 0; c < cols; c++) _padRight(rows[i][c], widths[c]),
    ].join(' | ');
    stdout.writeln(line.trimRight());
    if (i == 0) {
      stdout.writeln([for (final w in widths) '-' * w].join('-+-'));
    }
  }
}
