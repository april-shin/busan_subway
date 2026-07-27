// assets/json/line_schedules.json 에 인천1호선 역별 시간표(`t`)를 주입한다.
//
// 인천1호선은 두 시간표 API 모두 미제공이다:
//   - 서울 열린데이터광장 SearchSTNTimeTableByIDService: 서울교통공사 운영 노선만
//   - 공공데이터포털 getTrainSch: 인천2호선은 있으나 1호선은 없음
//     (lineNm 후보 인천1호선/인천도시철도1호선/인천지하철1호선/인천도시철도 전부 totalCount=0)
// 대신 인천교통공사가 공공데이터포털에 올린 **파일데이터(CSV) 4건**을 쓴다.
//
// 데이터 출처 (tool/data/incheon1/, CP949 인코딩):
//   incheon1_wd_up_15051203.csv    평일 상선 (송도달빛축제공원 → 검단호수공원)
//   incheon1_wd_down_15051204.csv  평일 하선 (검단호수공원 → 송도달빛축제공원)
//   incheon1_we_up_15051205.csv    휴일 상선
//   incheon1_we_down_15051206.csv  휴일 하선
//   https://www.data.go.kr/data/15051203/fileData.do (등록 2025-04-16, 수정 2025-08-11,
//   차기 등록 예정 2026-04-16). 오픈API 미제공이라 CSV 를 저장소에 동봉한다.
//   tool/ 은 pubspec assets 에 없으므로 앱 번들에 포함되지 않는다.
//
// CSV 스키마 (와이드 포맷, 36컬럼):
//   시발역, 종착역, 열차번호, <역1 출발시각>, <역2 출발시각>, ... <역33 출발시각>
//   - 1행 = 1열차. 시각은 "HH:MM:SS". 미정차·미운행 구간은 빈칸(구간운행).
//   - 컬럼 순서가 해당 방향의 실제 역 순서다.
//
// 요일/방향 매핑:
//   평일 → wd, 휴일 → we
//   하선(검단호수공원 → 송도달빛축제공원) = 앱 역ID 증가 = 앱 하행 → t index 1
//   상선(송도달빛축제공원 → 검단호수공원) = 앱 역ID 감소 = 앱 상행 → t index 0
//   (방향 반전 없음. 앱 일반규칙 "ID 증가 = 하행"과 정합)
//
// 당역종착 제외: `종착역` 컬럼과 같은 역의 시각은 **도착시각**이므로 버린다.
//   그대로 담으면 그 방향으로 더 가지 않는 "유령 출발"이 섞인다.
//   인천1호선은 중간종착이 많다 — 평일상선 박촌 19편·계양 2편·신연수 1편,
//   평일하선 국제업무지구 2편·동막 1편·예술회관 1편·작전 1편.
//   (getTrainSch 계열에 적용한 규칙과 동일한 취지. 여기는 종착역 컬럼이
//    명시돼 있어 더 정확하게 판별된다.)
//
// 키잉: `t` 키는 앱 역ID(stations.json id). CSV 역명 → 앱 역명 매칭 시
//   괄호를 제거해 비교한다(앱 "아라(북부법원검찰청)" ↔ CSV "아라").
//
// 실행:
//   dart run tool/build_incheon1_timetable.dart              # 병합 실행
//   dart run tool/build_incheon1_timetable.dart --dry-run     # 쓰지 않고 요약만
//
// 4원칙 무관 — 실시간 열차 애니메이션과 무관한 정적 데이터 생성기다.

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const _csvDir = 'tool/data/incheon1';

/// (파일명, 요일키, t 인덱스) — 하선=1(앱 하행), 상선=0(앱 상행)
const _sources = [
  ('incheon1_wd_up_15051203.csv', 'wd', 0),
  ('incheon1_wd_down_15051204.csv', 'wd', 1),
  ('incheon1_we_up_15051205.csv', 'we', 0),
  ('incheon1_we_down_15051206.csv', 'we', 1),
];

/// 역명 비교용 정규화(괄호·공백 제거).
String _norm(String s) =>
    s.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'\s'), '').trim();

/// "HH:MM:SS" → 자정 기준 분. 자정 이후("24:xx")는 이미 1440+.
/// "00:xx"~"03:xx" 익일 표기는 +1440 보정.
int? _toMinutes(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  final total = h * 60 + m;
  return h < 4 ? total + 1440 : total;
}

/// CP949 CSV 파싱. 인용부호 없는 단순 콤마 구분 포맷이다.
///
/// dart:convert 에 CP949(EUC-KR 확장) 디코더가 없다. 시각·구분자는 모두 ASCII 라
/// latin1 로 읽어 **바이트를 보존한 채** 구조만 분해하고, 한글이 들어가는 컬럼
/// (헤더 역명·종착역)만 [_decodeNames] 로 따로 되돌린다.
List<List<String>> _parseCsv(File f) {
  final text = latin1.decode(f.readAsBytesSync());
  return text
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty)
      .map((l) => l.split(','))
      .toList();
}

/// latin1 로 보존한 바이트열을 iconv 로 CP949 → UTF-8 변환한다.
/// 개행으로 이어 한 번에 처리한다(역명에 개행은 없다).
List<String> _decodeNames(List<String> latin1Names) {
  if (latin1Names.isEmpty) return const [];
  final tmp = File('${Directory.systemTemp.path}/incheon1_names_$pid.txt');
  tmp.writeAsBytesSync(latin1.encode(latin1Names.join('\n')));
  try {
    final res = Process.runSync('iconv', ['-f', 'CP949', '-t', 'UTF-8', tmp.path]);
    if (res.exitCode != 0) {
      throw StateError('iconv 실패(exit ${res.exitCode}): ${res.stderr}');
    }
    final out = (res.stdout as String).split('\n');
    if (out.length < latin1Names.length) {
      throw StateError('iconv 결과 행수 불일치: '
          '${out.length} < ${latin1Names.length}');
    }
    return out;
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');

  final stations =
      json.decode(File('assets/json/stations.json').readAsStringSync()) as List;
  // 앱 인천1 역: 정규화 역명 → 역ID
  final idByName = <String, String>{};
  for (final s in stations) {
    if (s['lineId'].toString() != '인천1') continue;
    idByName[_norm(s['name'].toString())] = s['id'].toString();
  }
  print('앱 인천1 역 ${idByName.length}개');

  // stationId → [상행분목록, 하행분목록], 요일별
  final t = {
    'wd': <String, List<Set<int>>>{},
    'we': <String, List<Set<int>>>{},
  };
  var droppedTerminal = 0;
  var unmatched = <String>{};

  for (final (fileName, day, dirIndex) in _sources) {
    final f = File('$_csvDir/$fileName');
    if (!f.existsSync()) {
      print('⚠ 없음: ${f.path}');
      exitCode = 1;
      return;
    }
    final rows = _parseCsv(f);
    final headerRaw = rows.first;
    final header = _decodeNames(headerRaw);
    // 각 행의 종착역(1번 컬럼)도 한글이라 일괄 디코딩한다.
    final terminals =
        _decodeNames([for (final r in rows.skip(1)) r.length > 1 ? r[1] : '']);
    final stationCols = header.sublist(3);

    var rowCount = 0;
    for (var ri = 1; ri < rows.length; ri++) {
      final r = rows[ri];
      final terminal = _norm(terminals[ri - 1]);
      rowCount++;
      for (var ci = 0; ci < stationCols.length; ci++) {
        final colIdx = 3 + ci;
        if (colIdx >= r.length) continue;
        final mins = _toMinutes(r[colIdx]);
        if (mins == null) continue;
        final stnName = _norm(stationCols[ci]);
        if (stnName == terminal) {
          droppedTerminal++; // 당역종착 = 도착시각
          continue;
        }
        final id = idByName[stnName];
        if (id == null) {
          unmatched.add(stationCols[ci]);
          continue;
        }
        final slot = t[day]!.putIfAbsent(id, () => [<int>{}, <int>{}]);
        slot[dirIndex].add(mins);
      }
    }
    print('  $fileName: $rowCount열차, ${stationCols.length}역 컬럼');
  }

  if (unmatched.isNotEmpty) {
    print('⚠ 앱 역과 매칭 실패: $unmatched');
    exitCode = 1;
    return;
  }
  print('당역종착 제외: $droppedTerminal행');

  // 컴팩트 스키마로 변환
  final compact = <String, Map<String, List<List<int>?>>>{};
  for (final day in ['wd', 'we']) {
    compact[day] = {};
    t[day]!.forEach((id, dirs) {
      final up = dirs[0].toList()..sort();
      final down = dirs[1].toList()..sort();
      compact[day]![id] = [
        up.isEmpty ? null : up,
        down.isEmpty ? null : down,
      ];
    });
  }

  print('\n역별 편수(평일 상행/하행):');
  final ids = compact['wd']!.keys.toList()..sort();
  for (final id in ids) {
    final d = compact['wd']![id]!;
    final name = stations.firstWhere((s) => s['id'] == id)['name'];
    print('  $id ${name.toString().padRight(10)} '
        '${(d[0]?.length ?? 0).toString().padLeft(4)} / '
        '${(d[1]?.length ?? 0).toString().padLeft(4)}');
  }

  if (dryRun) {
    print('\n[DRY RUN] 병합하지 않았습니다.');
    return;
  }

  final schedFile = File('assets/json/line_schedules.json');
  final schedules = json.decode(schedFile.readAsStringSync()) as List;
  Map<String, dynamic>? target;
  for (final s in schedules) {
    if ((s as Map)['id'].toString() == '인천1') {
      target = s.cast<String, dynamic>();
    }
  }
  if (target == null) {
    print('⚠ line_schedules.json 에 인천1 항목이 없습니다.');
    exitCode = 1;
    return;
  }
  for (final day in ['wd', 'we']) {
    final dayObj = target[day];
    if (dayObj is! Map) continue;
    dayObj.cast<String, dynamic>()['t'] = {
      for (final e in compact[day]!.entries) e.key: [e.value[0], e.value[1]],
    };
  }
  schedFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(schedules));
  print('\n병합 완료: 인천1 wd ${compact['wd']!.length}역, we ${compact['we']!.length}역');
}
