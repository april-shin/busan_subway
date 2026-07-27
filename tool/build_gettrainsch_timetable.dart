// assets/json/line_schedules.json 에 국토교통부 열차운행시각(getTrainSch) 기반
// 비(非)서울교통공사 노선의 역별 시간표(완행 t / 급행 tE)를 주입한다.
//
// 서울교통공사 API(SearchSTNTimeTableByIDService, → tool/build_metro_timetable.dart)가
// 다루지 못하는 노선(신분당·경춘·공항철도·수인분당·신림·에버라인·인천2·서해·
// 의정부·우이신설·GTX-A)을 공공데이터포털 getTrainSch 로 수집한다.
// 김포골드도 조회 가능하나(lineNm="김포도시철도") 기본 대상에서 제외 — 아래 실행 예시 참고.
//
// 데이터 출처: 공공데이터포털 "국가철도공단_열차운행시각"
//   https://apis.data.go.kr/B553766/schedule/getTrainSch
//   - serviceKey: .env 의 KOREA_API_KEY
//   - upbdnbSe: 상행 / 하행,  wkndSe: 평일 / 주말
//   - lineNm: 노선명(아래 _lineConfig),  stnNm: 역명
//   - dataType=JSON, tmprTmtblYn=N
//   주요 응답 필드: trainDptreTm(출발시각), upbdnbSe(방향), etrnYn(급행 Y/N),
//     stnNm(역명), arvlStnNm(종착), crtrYmd(기준일자), vldBgngDt(유효시작일)
//
// 방향 매핑 (실증 검증됨): API upbdnbSe 를 앱 t 인덱스로 변환.
//   - 정합 노선: 하행→idx1(앱 하행), 상행→idx0(앱 상행)
//   - 반전 노선(_reversed = 공항철도·의정부·우이신설): getTrainSch 하행 라벨이
//     앱 isDownBetween(상행)에 해당하므로 뒤집는다. 하행→idx0, 상행→idx1.
//     (공항철도는 앱이 하행=서울역 방면(ID감소)으로 반전; 의정부·우이신설은 앱 일반규칙
//      ID증가=하행이 getTrainSch 하행 라벨과 반대 방향이라 반전.)
//   근거: 각 노선 하행 종착역 앱ID를 중간역 앱ID와 대조해 확인.
//
// 행 제외 규칙 2가지:
//   1) 당역종착 — arvlStnNm 이 조회역이면 버린다. 진짜 종점에서는 API 가 trainDptreTm 을
//      null 로 주지만 구간운행 회차역에서는 종착 열차에도 출발시각을 채워 넣어,
//      "그 방향으로 가지 않는 유령 출발"이 생긴다(김포골드 구래 158·신분당 정자 4·
//      수인분당 죽전 2편 확인. 공항철도 검암·수인분당 왕십리/고색·서해 대곡/일산·
//      경춘 상봉/평내호평은 API 가 이미 null 처리해 무영향).
//   2) 비영업편성 — _excludedTrainnoPrefixes 참고.
//   제외 건수는 노선별로 로그에 출력한다.
//
// 완행/급행: etrnYn=="Y" → tE, 그 외 → t.
// 요일: wkndSe=평일 → wd, 주말 → we.
// 시각: trainDptreTm "HH:MM:SS", 자정 이후는 "24:xx"(→1440+). h<4 는 익일 정규화.
//
// 키잉 주의: t/tE 키는 앱 역ID. 역은 앱 역명으로 조회하며(괄호 폴백 포함),
//   getTrainSch 역명이 앱과 다르면(예: 관악산 vs 서울대벤처타운) 해당 역은
//   데이터 없음으로 로그되고 배차간격 폴백된다.
//
// 병합: 노선·요일별로 기존 t/tE 에 역 단위 병합. 한 방향이라도 실패한 역·요일은
//   기록을 스킵해 기존 데이터를 보존한다. 응답 stnNm 을 앱 역명과 정확일치로 필터해
//   getTrainSch 부분일치(예: "논현"→"신논현") 오염을 막는다.
//
// 실행:
//   dart run tool/build_gettrainsch_timetable.dart                 # 기본 대상 노선(_defaultLines)
//   dart run tool/build_gettrainsch_timetable.dart --lines=SB,서해  # 특정 노선
//   dart run tool/build_gettrainsch_timetable.dart --lines=김포골드 --stations=P10
//                                                                  # 특정 노선의 특정 역만
//   --stations 는 앱 역ID(stations.json id) 목록. 지정 시 해당 역만 조회·병합하므로
//   같은 노선의 다른 역 기존 데이터는 건드리지 않는다(수동 수집 데이터 보존용).
//
// 4원칙 무관 — 실시간 열차 애니메이션과 무관한 정적 데이터 생성기다.

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

const _baseUrl = 'https://apis.data.go.kr';

/// 앱 lineId → getTrainSch lineNm 후보(순서대로 시도).
/// 경춘은 앱이 경강선 구간(삼동~여주)을 함께 묶어두어 두 노선명을 모두 시도한다.
/// 김포골드는 getTrainSch 에서 개통 당시 명칭인 "김포도시철도"로만 조회된다
/// ("김포골드라인"은 totalCount=0).
const _lineNms = {
  'SB': ['신분당선'],
  '경춘': ['경춘선', '경강선'],
  '공항철도': ['공항철도'],
  '수인분당': ['수인분당선'],
  '신림': ['신림선'],
  '에버라인': ['용인경전철'],
  '인천2': ['인천2호선'],
  '서해': ['서해선'],
  '의정부': ['의정부경전철'],
  '우이신설': ['우이신설경전철'],
  'GTX-A': ['GTX-A'],
  '김포골드': ['김포도시철도'],
};

/// getTrainSch 하행 라벨이 앱 상행에 해당하는(방향 반전) 노선.
/// 김포골드: API 상행 = 김포공항 방면 = 앱 하행(ID 증가). 종점 앵커로 검증 —
/// 양촌(P01)은 API 상행만 출발시각 보유, 김포공항(P10)은 API 하행만 보유.
const _reversed = {'공항철도', '의정부', '우이신설', '김포골드'};

/// 비영업(회송·시운전) 편성의 trainno 접두사 — 노선별.
///
/// 김포골드: trainno 7001/7002 두 편성이 평일 04:40:00 에 양 종점(양촌·김포공항)에서
/// 동시 출발하는 것으로 제공된다. 그러나
///   - korailinfo·김포골드라인 공식 안내의 첫차는 양방향 모두 05:30 (막차 24:29 는 일치)
///   - 다음 출발까지 50분 공백이고, 다른 편성은 초 단위가 있는데(05:30:10) 이 둘만 정확히 :00
///   - 주말에는 아예 없다
/// 영업 편성은 3xxx(전구간 양촌↔김포공항)·2xxx(구간운행 구래↔김포공항)로 번대가
/// 구분되므로 7xxx 를 영업 개시 전 회송으로 보고 제외한다.
const _excludedTrainnoPrefixes = <String, Set<String>>{
  '김포골드': {'7'},
};

const _defaultLines = [
  'SB', '경춘', '공항철도', '수인분당', '신림', '에버라인',
  '인천2', '서해', '의정부', '우이신설', 'GTX-A', '김포골드',
];

/// wkndSe → 컴팩트 스키마 요일 키
const _wkndToDay = {'평일': 'wd', '주말': 'we'};

late final String _apiKey;
String _mask(String s) => s.replaceAll(_apiKey, '***');

// 전체 진행률 표시용(대상 노선 총 역수 대비 처리한 역수).
int _progDone = 0;
int _progTotal = 0;

int? _dptTimeToMinutes(String t) {
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  final total = h * 60 + m;
  // 자정 이후 출발("24:xx" → 이미 1440+). "00:xx"~"03:xx" 익일 표기 방어.
  return h < 4 ? total + 1440 : total;
}

/// 역명 비교용 정규화(공백·마침표·가운뎃점·괄호 제거).
String _norm(String s) => s.replaceAll(RegExp(r'[\s.·()]'), '');

/// 앱 역명 → 조회 후보(원본 + 괄호제거 + 괄호내용 + 점 표기 정규화).
/// getTrainSch 는 가운뎃점(·) 대신 마침표(.)를 쓰거나 구분자를 생략하기도 한다
/// (예: 앱 "전대·에버랜드" → API "전대.에버랜드").
List<String> _nameCandidates(String name) {
  final base = <String>[name];
  final paren = RegExp(r'\(([^)]*)\)').firstMatch(name);
  if (paren != null) {
    final stripped = name.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
    if (stripped.isNotEmpty) base.add(stripped);
    final inner = paren.group(1)!.trim();
    if (inner.isNotEmpty) base.add(inner);
  }
  // 각 후보에 대해 구분자(·/.) 변형을 추가
  final out = <String>[];
  for (final b in base) {
    for (final v in [b, b.replaceAll('·', '.'), b.replaceAll('.', '·'),
        b.replaceAll(RegExp('[·.]'), '')]) {
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }
  }
  return out;
}

/// getTrainSch 호출 → item 리스트 반환(빈 결과면 []). 오류는 예외.
Future<List<Map<String, dynamic>>> _fetch(
    Dio dio, String lineNm, String stnNm, String updn, String wknd) async {
  const maxAttempts = 5;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      final res = await dio.get<String>(
        '/B553766/schedule/getTrainSch',
        queryParameters: {
          'serviceKey': _apiKey,
          'tmprTmtblYn': 'N',
          'upbdnbSe': updn,
          'wkndSe': wknd,
          'lineNm': lineNm,
          'stnNm': stnNm,
          'dataType': 'JSON',
          'numOfRows': '1000',
          'pageNo': '1',
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (c) => c != null && c < 600,
        ),
      );
      if (res.statusCode != 200 || res.data == null) {
        if (attempt == maxAttempts - 1) {
          throw StateError('HTTP ${res.statusCode}');
        }
      } else {
        final data = json.decode(res.data!);
        // 정상 응답: {"response":{"header":{"resultCode":"00"},"body":{"items":...}}}
        final response = data['response'];
        if (response == null) {
          // 쿼터초과 등 OpenAPI_ServiceResponse 형태 → 예외로 승격
          final raw = _mask(res.data!.trim());
          final snippet = raw.length > 160 ? raw.substring(0, 160) : raw;
          throw StateError('비정상 응답: $snippet');
        }
        final code = response['header']?['resultCode']?.toString() ?? '';
        if (code != '00' && code != '') {
          throw StateError('API resultCode=$code');
        }
        final items = response['body']?['items'];
        if (items == null || items == '') return [];
        final item = items['item'];
        if (item == null) return [];
        final rows = item is List ? item : [item];
        return rows.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      if (attempt == maxAttempts - 1) rethrow;
    }
    await Future<void>.delayed(Duration(milliseconds: 700 * (attempt + 1)));
  }
  return [];
}

List<int> _sortedUnique(List<int> xs) => xs.toSet().toList()..sort();

/// upbdnbSe + 반전여부 → 앱 t 인덱스(0=상행, 1=하행).
int _dirIndex(String lineId, String upbdnbSe) {
  final downLabel = upbdnbSe.contains('하');
  final appDown = _reversed.contains(lineId) ? !downLabel : downLabel;
  return appDown ? 1 : 0;
}

typedef LineResult = ({
  Map<String, Map<String, List<List<int>?>>> t,
  Map<String, Map<String, List<List<int>?>>> tE,
  int ok,
  int noData,
  int droppedTerminal,
  int droppedNonRevenue,
  List<String> failures,
});

Future<LineResult> _collectLine(
    Dio dio, String lineId, List<(String, String)> stations) async {
  final lineNmCandidates = _lineNms[lineId]!;
  final excludedPrefixes =
      _excludedTrainnoPrefixes[lineId] ?? const <String>{};
  final t = {'wd': <String, List<List<int>?>>{}, 'we': <String, List<List<int>?>>{}};
  final tE = {'wd': <String, List<List<int>?>>{}, 'we': <String, List<List<int>?>>{}};
  var ok = 0, noData = 0;
  var droppedTerminal = 0, droppedNonRevenue = 0;
  final failures = <String>[];

  for (final (id, name) in stations) {
    _progDone++;
    final pct = _progTotal == 0 ? 100 : (_progDone * 100 / _progTotal).round();
    print('  [$pct% $_progDone/$_progTotal] $lineId $name');
    var gotAny = false;
    for (final wknd in _wkndToDay.keys) {
      final day = _wkndToDay[wknd]!;
      final normalDirs = <List<int>?>[null, null];
      final expressDirs = <List<int>?>[null, null];
      final normalAcc = <int, List<int>>{0: [], 1: []};
      final expressAcc = <int, List<int>>{0: [], 1: []};
      var dayFailed = false;
      for (final updn in ['상행', '하행']) {
        List<Map<String, dynamic>> rows = [];
        // getTrainSch stnNm 은 부분일치 검색이라 이웃 역(예: "논현" 조회 시 "신논현")이
        // 섞여 나온다. 응답 stnNm 을 앱 역명 후보와 정확일치로 필터해 오염을 막는다.
        final validNames = _nameCandidates(name).map(_norm).toSet();
        try {
          // 노선명 후보 × 역명 후보를 순서대로 시도(첫 성공 사용)
          outer:
          for (final lnm in lineNmCandidates) {
            for (final cand in _nameCandidates(name)) {
              final raw = await _fetch(dio, lnm, cand, updn, wknd);
              final filtered = raw
                  .where((r) =>
                      validNames.contains(_norm((r['stnNm'] ?? '').toString())))
                  .toList();
              if (filtered.isNotEmpty) {
                rows = filtered;
                break outer;
              }
            }
          }
        } catch (e) {
          dayFailed = true;
          failures.add('$name($id) $wknd/$updn: ${_mask(e.toString())}');
        }
        for (final r in rows) {
          final mins = _dptTimeToMinutes((r['trainDptreTm'] ?? '').toString());
          if (mins == null) continue;
          // 이 역에서 종착하는 열차는 더 나아가지 않으므로 출발로 세지 않는다.
          // getTrainSch 는 진짜 종점에서는 trainDptreTm 을 null 로 주지만,
          // 구간운행 회차역에서는 종착 열차에도 출발시각을 채워 넣는다
          // (김포골드 구래 158편·신분당 정자 4편·수인분당 죽전 2편 확인).
          // 그대로 담으면 "그 방향으로 가지 않는 유령 출발"이 섞인다.
          final arvl = _norm((r['arvlStnNm'] ?? '').toString());
          if (arvl.isNotEmpty && validNames.contains(arvl)) {
            droppedTerminal++;
            continue;
          }
          final trainno = (r['trainno'] ?? '').toString();
          if (trainno.isNotEmpty && excludedPrefixes.any(trainno.startsWith)) {
            droppedNonRevenue++;
            continue;
          }
          final idx = _dirIndex(lineId, (r['upbdnbSe'] ?? updn).toString());
          final express = (r['etrnYn'] ?? 'N').toString() == 'Y';
          (express ? expressAcc : normalAcc)[idx]!.add(mins);
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (dayFailed) continue;
      for (final idx in [0, 1]) {
        if (normalAcc[idx]!.isNotEmpty) normalDirs[idx] = _sortedUnique(normalAcc[idx]!);
        if (expressAcc[idx]!.isNotEmpty) expressDirs[idx] = _sortedUnique(expressAcc[idx]!);
      }
      if (normalDirs[0] != null || normalDirs[1] != null) {
        t[day]![id] = normalDirs;
        gotAny = true;
      }
      if (expressDirs[0] != null || expressDirs[1] != null) {
        tE[day]![id] = expressDirs;
      }
    }
    if (gotAny) {
      ok++;
    } else {
      noData++;
    }
  }
  return (
    t: t,
    tE: tE,
    ok: ok,
    noData: noData,
    droppedTerminal: droppedTerminal,
    droppedNonRevenue: droppedNonRevenue,
    failures: failures,
  );
}

List<dynamic> _dirsToJson(List<List<int>?> dirs) => [dirs[0], dirs[1]];

void _mergeInto(Map<String, dynamic> dayObj, String key,
    Map<String, List<List<int>?>> newData) {
  if (newData.isEmpty) return;
  final existing =
      (dayObj[key] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  newData.forEach((stationId, dirs) {
    existing[stationId] = _dirsToJson(dirs);
  });
  dayObj[key] = existing;
}

void main(List<String> args) async {
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('.env 파일이 없습니다.');
    exit(1);
  }
  final keyMatch = RegExp(r'^\s*KOREA_API_KEY\s*=\s*(.+)$', multiLine: true)
      .firstMatch(envFile.readAsStringSync());
  if (keyMatch == null) {
    print('.env 에 KOREA_API_KEY 가 없습니다.');
    exit(1);
  }
  _apiKey = keyMatch.group(1)!.trim().replaceAll(RegExp('^["\']|["\']\$'), '');

  var targetLines = _defaultLines;
  var targetStations = <String>{};
  for (final a in args) {
    if (a.startsWith('--lines=')) {
      targetLines = a
          .substring('--lines='.length)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (a.startsWith('--stations=')) {
      targetStations = a
          .substring('--stations='.length)
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
    }
  }
  final invalid = targetLines.where((l) => !_lineNms.containsKey(l)).toList();
  if (invalid.isNotEmpty) {
    print('⚠ 미지원 노선 무시: ${invalid.join(', ')}');
    targetLines = targetLines.where(_lineNms.containsKey).toList();
  }
  if (targetLines.isEmpty) {
    print('수집할 노선이 없습니다.');
    exit(1);
  }
  print('대상 노선: ${targetLines.join(', ')}');
  if (targetStations.isNotEmpty) {
    print('대상 역 한정: ${targetStations.join(', ')}');
  }

  final allStations =
      json.decode(File('assets/json/stations.json').readAsStringSync()) as List;
  final byLine = <String, List<(String, String)>>{};
  for (final s in allStations) {
    byLine
        .putIfAbsent(s['lineId'].toString(), () => [])
        .add((s['id'].toString(), s['name'].toString()));
  }
  for (final l in byLine.values) {
    l.sort((a, b) => a.$1.compareTo(b.$1));
  }
  if (targetStations.isNotEmpty) {
    final known = {
      for (final l in targetLines)
        for (final (id, _) in byLine[l] ?? const <(String, String)>[]) id,
    };
    final unknown = targetStations.difference(known);
    if (unknown.isNotEmpty) {
      print('⚠ 대상 노선에 없는 역ID 무시: ${unknown.join(', ')}');
    }
    if (known.intersection(targetStations).isEmpty) {
      print('--stations 로 지정한 역이 대상 노선에 없습니다.');
      exit(1);
    }
    byLine.updateAll((_, l) =>
        l.where((s) => targetStations.contains(s.$1)).toList());
  }

  final dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  _progTotal =
      targetLines.fold(0, (sum, l) => sum + (byLine[l]?.length ?? 0));
  final collected = <String, LineResult>{};
  for (final lineId in targetLines) {
    final stations = byLine[lineId] ?? [];
    if (stations.isEmpty) {
      print('━━ $lineId: 대상 역 없음(stations.json/--stations 확인), 스킵');
      continue;
    }
    final rev = _reversed.contains(lineId) ? ' (방향반전)' : '';
    print('━━ $lineId → ${_lineNms[lineId]!.join("/")} (${stations.length}역)$rev 수집 ━━');
    final r = await _collectLine(dio, lineId, stations);
    collected[lineId] = r;
    final tEcnt = r.tE['wd']!.length;
    print('   완료: 시간표 ${r.ok}역, 데이터없음 ${r.noData}역'
        '${tEcnt > 0 ? ', 급행 $tEcnt역' : ''}');
    if (r.droppedTerminal > 0 || r.droppedNonRevenue > 0) {
      print('   제외: 당역종착 ${r.droppedTerminal}행'
          ', 비영업편성 ${r.droppedNonRevenue}행');
    }
    if (r.failures.isNotEmpty) {
      print('   ⚠ 실패 ${r.failures.length}건 (앞 3): ${r.failures.take(3).join(' | ')}');
    }
  }

  final schedFile = File('assets/json/line_schedules.json');
  final schedules = json.decode(schedFile.readAsStringSync()) as List;
  final schedById = <String, Map<String, dynamic>>{};
  for (final s in schedules) {
    schedById[(s as Map)['id'].toString()] = s.cast<String, dynamic>();
  }

  var merged = 0;
  collected.forEach((lineId, r) {
    final sch = schedById[lineId];
    if (sch == null) {
      print('⚠ $lineId: line_schedules.json 에 객체 없음, 병합 스킵');
      return;
    }
    for (final day in ['wd', 'we']) {
      final dayObj = sch[day];
      if (dayObj is! Map) continue;
      final dObj = dayObj.cast<String, dynamic>();
      _mergeInto(dObj, 't', r.t[day]!);
      _mergeInto(dObj, 'tE', r.tE[day]!);
    }
    merged++;
  });

  const encoder = JsonEncoder.withIndent('  ');
  schedFile.writeAsStringSync(encoder.convert(schedules));

  print('\n━━━ 전체 완료 ━━━');
  print('병합된 노선: $merged');
  collected.forEach((lineId, r) {
    print('  $lineId: 완행 ${r.t['wd']!.length}역, 급행 ${r.tE['wd']!.length}역, '
        '데이터없음 ${r.noData}역');
  });

  final allFailures = [for (final r in collected.values) ...r.failures];
  if (allFailures.isNotEmpty) {
    print('\n⚠ 수집 실패 ${allFailures.length}건 (해당 역·방향 기존 데이터 보존):');
    for (final f in allFailures) {
      print('  - $f');
    }
    exit(1);
  }
}
