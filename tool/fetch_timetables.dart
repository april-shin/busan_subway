// 모든 노선·역의 평일 시간표를 data.go.kr API로 수집하여
// `data/timetables/{lineId}_{stnNm}_{dir}.json`으로 캐시한다.
//
// 사용법:
//   dart run tool/fetch_timetables.dart [--line=1호선] [--force]
//
//   --line: 특정 노선만 (없으면 stations.json의 모든 노선)
//   --force: 캐시 무시하고 재호출
//
// API: https://apis.data.go.kr/B553766/schedule/getTrainSch
//   파라미터: serviceKey, lineNm, stnNm, upbdnbSe(상행/하행), wkndSe(평일), dataType=JSON

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

// 프로젝트 lineId → API lineNm 매핑 (이미 검증된 호선만)
const Map<String, String> LINE_API_NAME = {
  '1': '1호선',
  '3': '3호선',
  '4': '4호선',
  '5': '5호선',
  '7': '7호선',
  '8': '8호선',
  '9': '9호선',
  'SB': '신분당선',
  '경의중앙': '경의중앙선',
  '경춘': '경춘선',
  '공항철도': '공항철도',
  '수인분당': '수인분당선',
  '신림': '신림선',
  '인천1': '인천1호선',
  '인천2': '인천2호선',
  '김포골드': '김포골드라인',
  '서해': '서해선',
  '의정부': '의정부경전철',
  '우이신설': '우이신설선',
  // 2호선은 '서울2호선'/'서울 2호선' 모두 미지원으로 확인됨 → 제외
  // 6호선, GTX-A, 에버라인은 별도 확인 필요
};

void main(List<String> args) async {
  final env = File('.env').readAsStringSync();
  final apiKey =
      RegExp(r'KOREA_API_KEY=(.+)').firstMatch(env)!.group(1)!.trim();

  String? onlyLine;
  var force = false;
  for (final a in args) {
    if (a.startsWith('--line=')) onlyLine = a.substring('--line='.length);
    if (a == '--force') force = true;
  }

  final stations = json.decode(File('assets/json/stations.json').readAsStringSync())
      as List<dynamic>;
  // 노선별 역 이름 목록
  final byLine = <String, Set<String>>{};
  for (final s in stations) {
    final lid = s['lineId'] as String;
    byLine.putIfAbsent(lid, () => <String>{}).add(s['name'] as String);
  }

  Directory('data/timetables').createSync(recursive: true);

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  var totalCalls = 0;
  var skipped = 0;
  var failed = 0;
  final startTime = DateTime.now();

  for (final lineId in byLine.keys) {
    if (onlyLine != null && lineId != onlyLine) continue;
    final apiName = LINE_API_NAME[lineId];
    if (apiName == null) {
      print('⊘ [$lineId] API 미지원 (스킵)');
      continue;
    }
    final stnNames = byLine[lineId]!.toList()..sort();
    print('━━━ [$lineId → $apiName] ${stnNames.length}개 역 ━━━');

    for (final stnNm in stnNames) {
      for (final dir in ['상행', '하행']) {
        final cachePath =
            'data/timetables/${lineId}_${stnNm}_$dir.json';
        if (!force && File(cachePath).existsSync()) {
          skipped++;
          continue;
        }

        try {
          final url = Uri.parse(
            'https://apis.data.go.kr/B553766/schedule/getTrainSch',
          ).replace(queryParameters: {
            'serviceKey': apiKey,
            'tmprTmtblYn': 'N',
            'upbdnbSe': dir,
            'wkndSe': '평일',
            'lineNm': apiName,
            'stnNm': stnNm,
            'dataType': 'JSON',
            'numOfRows': '1000',
            'pageNo': '1',
          });
          final res = await dio.getUri<String>(url);
          final body = json.decode(res.data!) as Map<String, dynamic>;
          final items = body['response']?['body']?['items']?['item'];
          final list = items is List ? items : <dynamic>[];

          File(cachePath).writeAsStringSync(
            json.encode(list),
            encoding: utf8,
          );
          totalCalls++;
          if (totalCalls % 20 == 0) {
            final elapsed = DateTime.now().difference(startTime).inSeconds;
            print('  ... $totalCalls 완료 ($elapsed초 경과)');
          }
        } catch (e) {
          failed++;
          if (failed <= 5) {
            print('  ✗ $lineId/$stnNm/$dir: $e');
          }
        }
      }
    }
  }

  final elapsed = DateTime.now().difference(startTime).inSeconds;
  print('\n=== 완료 ===');
  print('호출: $totalCalls, 스킵(캐시): $skipped, 실패: $failed');
  print('소요: ${elapsed}초');
  dio.close();
}
