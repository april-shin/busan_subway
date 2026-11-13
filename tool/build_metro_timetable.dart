// assets/json/line_schedules.json 에 서울교통공사 운영 노선(1·3~9호선)의
// 역별 시간표(완행 t / 급행 tE)를 주입한다.
//
// 데이터 출처: 서울 열린데이터광장 "역코드로 지하철 열차 시간표 검색"
//   서비스: SearchSTNTimeTableByIDService (OA-101)
//   http://openapi.seoul.go.kr:8088/{KEY}/json/SearchSTNTimeTableByIDService
//        /{start}/{end}/{STATION_CD}/{WEEK_TAG}/{INOUT_TAG}
//   - KEY: .env 의 BUSAN_GENERAL_API_KEY
//   - WEEK_TAG: 1=평일, 2=토요일, 3=일요일/공휴일
//   - INOUT_TAG: 1=상행, 2=하행
//   역코드(STATION_CD)는 SearchInfoBySubwayNameService/{역명} 응답에서 취득한다.
//
// 방향 매핑 (실증 검증됨): API INOUT_TAG 1=상행 → t index 0, 2=하행 → index 1.
//   전 대상 노선에서 API 하행의 물리 방향이 앱 isDownBetween(하행)과 일치한다
//   (1호선 남행=ID증가, 4호선 오이도=_isLine4Down, 9호선 개화=규칙반전 등 모두 확인).
//   따라서 데이터는 "API 상행→idx0 / API 하행→idx1"로 단순 저장하면 되고,
//   노선별 방향 반전은 앱의 line_direction.dart 가 담당한다.
//
// 키잉 주의: `t`/`tE` 의 키는 **앱 역ID**(stations.json 의 id)다.
//   1~8호선은 FR_CODE(서울교통공사 외부코드) 와 앱 역ID 가 다르므로
//   (예: 종로3가 FR_CODE=130, 앱ID=131) 반드시 앱 역ID 로 키잉한다.
//   역 매칭은 "역명 + 노선" 으로 하고, 매칭 실패 역은 로그로 남긴다
//   (코레일 위탁구간 등 서울교통공사 미운영 역은 시간표가 없어 배차간격 폴백).
//
// 급행/완행: EXPRESS_YN=="D" → tE, 그 외("G") → t.
//
// 병합 안전성: 노선·요일별로 기존 t/tE 에 역 단위로 병합(overwrite)한다.
//   이번 실행에서 수집 실패한 역의 기존 데이터는 보존된다.
//
// 컴팩트 스키마 계약: wd/we 안에
//   t  = { "앱역ID": [상행분목록|null, 하행분목록|null] }   // 완행
//   tE = { "앱역ID": [상행분목록|null, 하행분목록|null] }   // 급행 (미정차역은 키 생략)
//   분 목록은 자정 기준 분(int) 오름차순. 자정 이후는 1440+ (24:49 → 1489).
//   WEEK_TAG=1 → wd, WEEK_TAG=3 → we. 토요일(WEEK_TAG=2)은 미반영(주말 1종 한계).
//
// 실행:
//   dart run tool/build_metro_timetable.dart              # 기본: 1,3,4,5,6,7,8
//   dart run tool/build_metro_timetable.dart --lines=9    # 특정 노선만
//   dart run tool/build_metro_timetable.dart --lines=1,3,9
//
//   ⚠ 2호선(순환선)은 2026-07 갱신으로 신규 제공됨. 방향은 INOUT 1→idx0(상행/내선).
//
// 4원칙 무관 — 실시간 열차 애니메이션과 무관한 정적 데이터 생성기다.

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

const _baseUrl = 'http://openapi.seoul.go.kr:8088';

/// 앱 lineId → API LINE_NUM.
/// (2호선은 2026-07 데이터셋 갱신으로 신규 제공 시작 — 순환선이라 방향은
///  INOUT 1=상행/내선→idx0, 2=하행/외선→idx1로 앱 _isLine2DownBetween과 정합.)
const _apiLineNum = {
  '1': '01호선',
  '2': '02호선',
  '3': '03호선',
  '4': '04호선',
  '5': '05호선',
  '6': '06호선',
  '7': '07호선',
  '8': '08호선',
  '9': '09호선',
};

const _defaultLines = ['1', '2', '3', '4', '5', '6', '7', '8'];

/// WEEK_TAG → 컴팩트 스키마 요일 키
const _weekTagToDay = {1: 'wd', 3: 'we'};

late final String _apiKey;

/// 에러 메시지에서 API 키를 마스킹한다.
String _mask(String s) => s.replaceAll(_apiKey, '***');

// 전체 진행률 표시용(대상 노선 총 역수 대비 처리한 역수).
int _progDone = 0;
int _progTotal = 0;

/// "HH:MM:SS" 출발시각을 자정 기준 분(int)으로. 자정 이후(24/25시)는 1440+.
/// 종착(출발 없음, "00:00:00")은 null.
int? _leftTimeToMinutes(String lefttime) {
  if (lefttime.isEmpty || lefttime == '00:00:00') return null;
  final parts = lefttime.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  final total = h * 60 + m;
  // API는 자정 이후 출발을 "24:xx"/"25:xx"로 표기(h>=24 → 이미 1440+).
  // 혹시 익일 출발이 "00:xx"~"03:xx"로 오면 전날 운행분으로 보고 +1440 정규화
  // (지하철 첫차는 04시 이후이므로 h<4 는 익일로 간주해도 안전).
  return h < 4 ? total + 1440 : total;
}

Future<dynamic> _getJson(Dio dio, String path) async {
  const maxAttempts = 6;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      final res = await dio.get<String>(
        path,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (code) => code != null && code < 600,
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        return json.decode(res.data!);
      }
      if (attempt == maxAttempts - 1) {
        throw StateError('HTTP ${res.statusCode} (재시도 소진)');
      }
    } catch (e) {
      if (attempt == maxAttempts - 1) rethrow;
    }
    await Future<void>.delayed(Duration(milliseconds: 800 * (attempt + 1)));
  }
  return null;
}

/// 앱 역명 → API 조회용 후보 역명 목록.
/// 괄호 표기 차이(예: "총신대입구(이수)" → API 는 4호선 "총신대입구" / 7호선 "이수")를
/// 흡수하기 위해 원본 + 괄호제거 + 괄호내용을 순서대로 시도한다.
List<String> _nameCandidates(String name) {
  final candidates = <String>[name];
  final paren = RegExp(r'\(([^)]*)\)').firstMatch(name);
  if (paren != null) {
    final stripped = name.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
    if (stripped.isNotEmpty) candidates.add(stripped);
    final inner = paren.group(1)!.trim();
    if (inner.isNotEmpty) candidates.add(inner);
  }
  return candidates;
}

/// 역명으로 해당 노선의 STATION_CD 를 조회. 없으면 null.
/// 역명 표기 차이를 위해 여러 후보명을 시도한다.
Future<String?> _fetchStationCd(
    Dio dio, String stationName, String apiLineNum) async {
  final candidates = _nameCandidates(stationName);
  for (var i = 0; i < candidates.length; i++) {
    final candidate = candidates[i];
    final encoded = Uri.encodeComponent(candidate);
    final path = '/$_apiKey/json/SearchInfoBySubwayNameService/1/20/$encoded';
    final data = await _getJson(dio, path);
    final svc = data?['SearchInfoBySubwayNameService'];
    if (svc == null || svc['row'] == null) continue;
    for (final row in svc['row'] as List) {
      if (row['LINE_NUM'] == apiLineNum) {
        // 원본명이 아닌 폴백 후보로 매칭됐으면 로그로 남긴다(향후 역 개명·부역명 충돌 감지용).
        if (i > 0) {
          print("   ↳ 역명 폴백: '$stationName' → API '$candidate' "
              '(STATION_CD ${row['STATION_CD']})');
        }
        return row['STATION_CD'] as String;
      }
    }
  }
  return null;
}

/// 한 역·요일·방향 시간표를 조회해 (완행분, 급행분)로 반환.
Future<(List<int> normal, List<int> express)> _fetchTimetable(
    Dio dio, String stationCd, int weekTag, int inoutTag) async {
  final path =
      '/$_apiKey/json/SearchSTNTimeTableByIDService/1/600/$stationCd/$weekTag/$inoutTag';
  final data = await _getJson(dio, path);
  final svc = data?['SearchSTNTimeTableByIDService'];
  final normal = <int>[];
  final express = <int>[];
  if (svc == null) {
    // 서울 API는 쿼터 초과(ERROR-337)·키 오류 등을 HTTP 200 + 최상위 RESULT 로 반환한다.
    // 이를 "출발 없음(정상 빈 결과)"으로 오분류하면 방향이 조용히 null 로 덮이므로 예외로 승격.
    final code = (data?['RESULT']?['CODE'] ?? '').toString();
    if (code.startsWith('ERROR')) {
      throw StateError('API $code');
    }
    return (normal, express);
  }
  if (svc['row'] == null) return (normal, express); // INFO-200(결과 없음) 등 정상 빈 결과
  for (final row in svc['row'] as List) {
    final mins = _leftTimeToMinutes((row['LEFTTIME'] ?? '').toString());
    if (mins == null) continue;
    if ((row['EXPRESS_YN'] ?? '').toString() == 'D') {
      express.add(mins);
    } else {
      normal.add(mins);
    }
  }
  return (normal, express);
}

List<int> _sortedUnique(List<int> xs) => xs.toSet().toList()..sort();

/// 노선별 수집 결과.
/// - [t]/[tE]: day -> {stationId: [ [up]|null, [down]|null ]}
/// - [ok]: 시간표를 얻은 역 수, [noData]: 서울교통공사 미운영 등으로 데이터 없는 역 수,
///   [codeFail]: 역코드 조회 자체가 예외로 실패한 역 수(미운영과 구분),
///   [failures]: 실패 상세 메시지 목록
typedef LineResult = ({
  Map<String, Map<String, List<List<int>?>>> t,
  Map<String, Map<String, List<List<int>?>>> tE,
  int ok,
  int noData,
  int codeFail,
  List<String> failures,
});

/// 한 노선의 t/tE 를 수집해 반환한다.
Future<LineResult> _collectLine(
    Dio dio, String lineId, List<(String, String)> stations) async {
  final apiLineNum = _apiLineNum[lineId]!;
  final t = {'wd': <String, List<List<int>?>>{}, 'we': <String, List<List<int>?>>{}};
  final tE = {'wd': <String, List<List<int>?>>{}, 'we': <String, List<List<int>?>>{}};
  var ok = 0, noData = 0, codeFail = 0;
  final failures = <String>[];

  for (final (id, name) in stations) {
    _progDone++;
    final pct = _progTotal == 0 ? 100 : (_progDone * 100 / _progTotal).round();
    print('  [$pct% $_progDone/$_progTotal] $lineId $name');
    String? cd;
    var lookupThrew = false;
    try {
      cd = await _fetchStationCd(dio, name, apiLineNum);
    } catch (e) {
      lookupThrew = true;
      failures.add('$name($id) 코드조회: ${_mask(e.toString())}');
    }
    // 역코드 조회 예의상 지연(연속 호출 rate-limit 회피)
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (cd == null) {
      // 조회 예외(codeFail)와 정상 미운영(noData)을 통계상 구분
      if (lookupThrew) {
        codeFail++;
      } else {
        noData++; // 서울교통공사 미운영(코레일 위탁 등) 또는 역명 불일치
      }
      continue;
    }

    var gotAny = false;
    for (final weekTag in _weekTagToDay.keys) {
      final day = _weekTagToDay[weekTag]!;
      final normalDirs = <List<int>?>[null, null];
      final expressDirs = <List<int>?>[null, null];
      var dayFailed = false;
      for (final inout in [1, 2]) {
        try {
          final (normal, express) =
              await _fetchTimetable(dio, cd, weekTag, inout);
          final idx = inout - 1;
          if (normal.isNotEmpty) normalDirs[idx] = _sortedUnique(normal);
          if (express.isNotEmpty) expressDirs[idx] = _sortedUnique(express);
        } catch (e) {
          dayFailed = true;
          failures.add('$name($id) wk=$weekTag io=$inout: ${_mask(e.toString())}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      // 한 방향이라도 실패하면 이 역·요일 기록을 스킵한다.
      // (부분 데이터로 역 엔트리를 덮어써 기존 다른 방향 데이터를 잃지 않도록 — 병합 계약 보존)
      if (dayFailed) continue;
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
    codeFail: codeFail,
    failures: failures
  );
}

/// dir 리스트를 JSON 직렬화 가능한 형태로 (`List<int>?` → `List<dynamic>?` 유지).
List<dynamic> _dirsToJson(List<List<int>?> dirs) => [dirs[0], dirs[1]];

/// 노선·요일별 t/tE 를 기존 JSON 객체에 역 단위로 병합.
void _mergeInto(Map<String, dynamic> dayObj, String key,
    Map<String, List<List<int>?>> newData) {
  if (newData.isEmpty) return;
  final existing = (dayObj[key] as Map?)?.cast<String, dynamic>() ??
      <String, dynamic>{};
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
  // 주석(#) 줄은 건너뛰고, 값의 양쪽 따옴표도 제거한다.
  final keyMatch = RegExp(r'^\s*BUSAN_GENERAL_API_KEY\s*=\s*(.+)$',
          multiLine: true)
      .firstMatch(envFile.readAsStringSync());
  if (keyMatch == null) {
    print('.env 에 BUSAN_GENERAL_API_KEY 가 없습니다.');
    exit(1);
  }
  _apiKey = keyMatch.group(1)!.trim().replaceAll(RegExp('^["\']|["\']\$'), '');

  var targetLines = _defaultLines;
  for (final a in args) {
    if (a.startsWith('--lines=')) {
      targetLines = a.substring('--lines='.length).split(',').map((s) => s.trim()).toList();
    }
  }
  // 지원 노선만 필터
  final invalid = targetLines.where((l) => !_apiLineNum.containsKey(l)).toList();
  if (invalid.isNotEmpty) {
    print('⚠ 미지원 노선 무시: ${invalid.join(', ')}');
    targetLines = targetLines.where(_apiLineNum.containsKey).toList();
  }
  print('대상 노선: ${targetLines.join(', ')}');

  // 노선별 앱 역 목록
  final allStations = json
      .decode(File('assets/json/stations.json').readAsStringSync()) as List;
  final byLine = <String, List<(String, String)>>{};
  for (final s in allStations) {
    final lid = s['lineId'].toString();
    byLine.putIfAbsent(lid, () => []).add((s['id'].toString(), s['name'].toString()));
  }
  for (final l in byLine.values) {
    l.sort((a, b) => a.$1.compareTo(b.$1));
  }

  final dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  // 결과를 노선별로 모은 뒤 마지막에 한 번에 JSON 병합·기록
  _progTotal =
      targetLines.fold(0, (sum, l) => sum + (byLine[l]?.length ?? 0));
  final collected = <String, LineResult>{};

  for (final lineId in targetLines) {
    final stations = byLine[lineId] ?? [];
    if (stations.isEmpty) {
      print('━━ $lineId호선: stations.json 에 역 없음, 스킵');
      continue;
    }
    print('━━ $lineId호선 (${stations.length}역) 수집 시작 ━━');
    final r = await _collectLine(dio, lineId, stations);
    collected[lineId] = r;
    final tE = r.tE['wd']!.keys.toList()..sort();
    print('   완료: 시간표보유 ${r.ok}역, 데이터없음 ${r.noData}역, 급행정차 ${tE.length}역'
        '${tE.isEmpty ? '' : ' $tE'}');
    if (r.failures.isNotEmpty) {
      print('   ⚠ 실패 ${r.failures.length}건 (앞 5건): ${r.failures.take(5).join(' | ')}');
    }
  }

  // JSON 병합
  final schedFile = File('assets/json/line_schedules.json');
  final schedules = json.decode(schedFile.readAsStringSync()) as List;
  final schedById = <String, Map<String, dynamic>>{};
  for (final s in schedules) {
    schedById[(s as Map)['id'].toString()] = s.cast<String, dynamic>();
  }

  var mergedLines = 0;
  collected.forEach((lineId, r) {
    final sch = schedById[lineId];
    if (sch == null) {
      print('⚠ $lineId호선: line_schedules.json 에 객체 없음, 병합 스킵');
      return;
    }
    for (final day in ['wd', 'we']) {
      final dayObj = sch[day];
      if (dayObj is! Map) continue;
      final dObj = dayObj.cast<String, dynamic>();
      _mergeInto(dObj, 't', r.t[day]!);
      _mergeInto(dObj, 'tE', r.tE[day]!);
    }
    mergedLines++;
  });

  const encoder = JsonEncoder.withIndent('  ');
  schedFile.writeAsStringSync(encoder.convert(schedules));

  print('\n━━━ 전체 완료 ━━━');
  print('병합된 노선: $mergedLines');
  collected.forEach((lineId, r) {
    print('  $lineId호선: 완행 ${r.t['wd']!.length}역, 급행 ${r.tE['wd']!.length}역, '
        '데이터없음 ${r.noData}역, 코드조회실패 ${r.codeFail}역');
  });

  // 실패가 있으면 전체 목록을 출력하고 비정상 종료 코드로 알린다.
  // (기록은 실패 방향을 스킵하므로 기존 데이터는 보존된 상태로 파일에 반영됨)
  final allFailures = [
    for (final r in collected.values) ...r.failures,
  ];
  if (allFailures.isNotEmpty) {
    print('\n⚠ 수집 실패 ${allFailures.length}건 (해당 역·방향은 기존 데이터 보존):');
    for (final f in allFailures) {
      print('  - $f');
    }
    exit(1);
  }
}
