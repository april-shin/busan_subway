// 서울 열린데이터광장 "1~8호선 역간 거리 및 소요시간" API로
// 모든 역 구간의 공식 소요시간 데이터를 받아 connections.json을 갱신한다.
//
// API: http://openapi.seoul.go.kr:8088/{KEY}/json/StationDstncReqreTimeHm/{start}/{end}/
//
// 응답: 노선별로 순서대로 정렬된 역 행들. 각 행의 HM은 "이전 역에서 이 역까지의 시간".
//   첫 행은 항상 0:00 (시작점).
//
// 사용법:
//   dart run tool/fetch_inter_station.dart           # 전체 갱신
//   dart run tool/fetch_inter_station.dart --dry-run # 통계만

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

const _apiKey = '50734449667365753437686c417447';
const _cachePath = 'data/inter_station.json';
const _connsPath = 'assets/json/connections.json';

void main(List<String> args) async {
  final dryRun = args.contains('--dry-run');

  // 1. API 데이터 수집 (또는 캐시 사용)
  final List<Map<String, dynamic>> rows;
  final cacheFile = File(_cachePath);
  if (cacheFile.existsSync() && !args.contains('--force')) {
    rows = (json.decode(cacheFile.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    print('캐시 사용: $_cachePath (${rows.length}행)');
  } else {
    rows = await _fetchAll();
    Directory('data').createSync(recursive: true);
    cacheFile.writeAsStringSync(json.encode(rows), encoding: utf8);
    print('수집 완료: ${rows.length}행 → $_cachePath');
  }

  // 2. stations.json으로 역명 → ID 매핑
  final stationsRaw =
      json.decode(File('assets/json/stations.json').readAsStringSync())
          as List;
  final lineNameToId = <String, Map<String, String>>{};  // lineId → {name: id}
  for (final s in stationsRaw) {
    final lid = s['lineId'] as String;
    lineNameToId.putIfAbsent(lid, () => {})[s['name'] as String] = s['id'] as String;
  }

  // 3. connections.json 로드
  final connsRaw =
      json.decode(File(_connsPath).readAsStringSync()) as List;
  final conns = connsRaw.cast<Map<String, dynamic>>();
  // (lineId, fromId, toId) → 인덱스 (양방향)
  final connIndex = <String, Map<String, dynamic>>{};
  for (final c in conns) {
    if (c['isTransfer'] == true) continue;
    final lid = c['lineId'] as String;
    final f = c['fromStationId'] as String;
    final t = c['toStationId'] as String;
    connIndex['$lid|$f|$t'] = c;
    connIndex['$lid|$t|$f'] = c;  // 역방향도 같은 connection
  }

  // 4. 순회: 같은 노선의 직전 행과 매칭하여 (이전 역 → 이 역) 소요시간 적용
  var updated = 0;
  var skipped = 0;
  var notFound = 0;
  final perLine = <String, List<int>>{};
  String? prevLine;
  String? prevName;
  for (final row in rows) {
    final lineNum = row['SBWY_ROUT_LN']?.toString() ?? '';
    final stnName = row['SBWY_STNS_NM']?.toString() ?? '';
    final hm = row['HM']?.toString() ?? '';
    if (lineNum.isEmpty || stnName.isEmpty) continue;

    // 첫 행(0:00) 또는 노선 변경 시: 시작점이라 이전 매칭 없음
    if (prevLine != lineNum) {
      prevLine = lineNum;
      prevName = stnName;
      continue;
    }

    final seconds = _parseHm(hm);
    if (seconds == null) {
      skipped++;
      prevName = stnName;
      continue;
    }

    final lineId = lineNum;  // '1'~'8'
    final lineMap = lineNameToId[lineId];
    if (lineMap == null) {
      notFound++;
      prevName = stnName;
      continue;
    }
    final fromId = lineMap[prevName];
    final toId = lineMap[stnName];
    if (fromId == null || toId == null) {
      notFound++;
      prevName = stnName;
      continue;
    }
    final c = connIndex['$lineId|$fromId|$toId'];
    if (c == null) {
      notFound++;
      prevName = stnName;
      continue;
    }
    final old = c['travelTimeSeconds'] as int;
    if (old != seconds) {
      c['travelTimeSeconds'] = seconds;
      updated++;
    }
    perLine.putIfAbsent(lineId, () => []).add(seconds);
    prevName = stnName;
  }

  print('\n=== 노선별 통계 ===');
  for (final lid in perLine.keys.toList()..sort()) {
    final vals = perLine[lid]!..sort();
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    print('  $lid: ${vals.length}개, 평균 ${avg.toStringAsFixed(1)}s, '
        '범위 ${vals.first}~${vals.last}s');
  }
  print('\n전체: 갱신 $updated건, 스킵 $skipped, 미매칭 $notFound');

  if (dryRun) {
    print('(dry-run, 파일 변경 없음)');
    return;
  }
  File(_connsPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(connsRaw),
  );
  print('✓ $_connsPath 갱신');
}

Future<List<Map<String, dynamic>>> _fetchAll() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));
  // 한 번에 1000건 (실제 278건이라 충분)
  final url = 'http://openapi.seoul.go.kr:8088/$_apiKey/json/'
      'StationDstncReqreTimeHm/1/1000/';
  final res = await dio.get<String>(url);
  final body = json.decode(res.data!) as Map<String, dynamic>;
  final root = body['StationDstncReqreTimeHm'] as Map<String, dynamic>?;
  if (root == null) {
    throw Exception('응답 구조 이상: ${res.data!.substring(0, 200)}');
  }
  final result = root['RESULT'] as Map<String, dynamic>?;
  if (result?['CODE'] != 'INFO-000') {
    throw Exception('API 오류: ${result?['MESSAGE']}');
  }
  final rows = root['row'];
  if (rows is! List) return [];
  dio.close();
  return rows.cast<Map<String, dynamic>>();
}

/// "M:SS" 또는 "MM:SS" 형식을 초로 변환
int? _parseHm(String hm) {
  if (hm.isEmpty || hm == '0:00') return null;
  final p = hm.split(':');
  if (p.length != 2) return null;
  final m = int.tryParse(p[0]);
  final s = int.tryParse(p[1]);
  if (m == null || s == null) return null;
  return m * 60 + s;
}
