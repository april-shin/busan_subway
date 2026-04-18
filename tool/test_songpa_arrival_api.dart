// 송파역(8호선) 실시간 도착정보 API 원본 응답 관찰 스크립트.
//
// 실행:
//   dart run tool/test_songpa_arrival_api.dart
//
// 목적: 8호선에서 "N번째 전역" arvlMsg2 + arrivalSeconds=0 현상의 실제 API 원본을
// 확인한다. DTO 변환 전 raw JSON 필드(arvlCd, barvlDt, arvlMsg2, arvlMsg3,
// btrainSttus, btrainNo)를 그대로 출력하고, DTO 파싱 결과(arrivalSeconds 계산)를
// 함께 병기해 어느 조합이 0초로 귀결되는지 판별한다.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// 실행 시 `dart run tool/test_songpa_arrival_api.dart 노량진` 처럼 역명 전달 가능.
String _pickStation(List<String> args) => args.isNotEmpty ? args.first : '송파';

void main(List<String> args) async {
  final stationName = _pickStation(args);
  final apiKey = _readApiKey();
  final url = 'http://swopenapi.seoul.go.kr/api/subway/$apiKey'
      '/json/realtimeStationArrival/0/20/$stationName';

  stdout.writeln('요청 URL: ${_maskKey(url, apiKey)}');
  stdout.writeln('');

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
    ),
  );

  final Response<String> res;
  try {
    res = await dio.getUri<String>(Uri.parse(url));
  } on DioException catch (e) {
    stderr.writeln('HTTP 오류: ${e.message}');
    if (e.response != null) {
      stderr.writeln('응답 본문: ${e.response?.data}');
    }
    exit(1);
  }

  final Map<String, dynamic> body;
  try {
    body = json.decode(res.data ?? '') as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('JSON 파싱 실패: $e');
    stderr.writeln('원본: ${res.data}');
    exit(1);
  }

  // 최상위 에러 메시지 체크
  final status = body['errorMessage']?['status'];
  final code = body['errorMessage']?['code'];
  final msg = body['errorMessage']?['message'];
  stdout.writeln('API status=$status code=$code message=$msg');
  stdout.writeln('');

  final list = body['realtimeArrivalList'];
  if (list is! List || list.isEmpty) {
    stdout.writeln('realtimeArrivalList 비어있음 (총 응답):');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(body));
    return;
  }

  stdout.writeln('--- realtimeArrivalList (${list.length}건) ---');
  stdout.writeln('');

  for (var i = 0; i < list.length; i++) {
    final item = list[i] as Map<String, dynamic>;
    _printRaw(i, item);
    _printParsed(item);
    stdout.writeln('');
  }

  // 분석 요약
  _printSummary(list.cast<Map<String, dynamic>>());
}

String _readApiKey() {
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    stderr.writeln('.env 파일이 없습니다 (프로젝트 루트에서 실행 필요).');
    exit(1);
  }
  final match = RegExp(r'SEOUL_SUBWAY_API_KEY\s*=\s*(.+)')
      .firstMatch(envFile.readAsStringSync());
  if (match == null) {
    stderr.writeln('.env에 SEOUL_SUBWAY_API_KEY가 없습니다.');
    exit(1);
  }
  final key = match.group(1)!.trim();
  if (key.isEmpty || key.contains('your_api_key') || key.contains('<')) {
    stderr.writeln('.env의 SEOUL_SUBWAY_API_KEY가 placeholder 값입니다: $key');
    exit(1);
  }
  return key;
}

String _maskKey(String url, String apiKey) {
  if (apiKey.length < 8) return url.replaceAll(apiKey, '***');
  final masked = '${apiKey.substring(0, 4)}***${apiKey.substring(apiKey.length - 2)}';
  return url.replaceAll(apiKey, masked);
}

void _printRaw(int idx, Map<String, dynamic> item) {
  stdout.writeln('[#$idx] subwayId=${item['subwayId']} '
      'statn=${item['statnNm']} updn=${item['updnLine']} '
      'btrainSttus=${item['btrainSttus']} btrainNo=${item['btrainNo']} '
      'bstatnNm=${item['bstatnNm']}');
  stdout.writeln('      arvlCd=${item['arvlCd']} barvlDt=${item['barvlDt']} '
      'arvlMsg2="${item['arvlMsg2']}" arvlMsg3="${item['arvlMsg3']}"');
  stdout.writeln('      ordkey=${item['ordkey']} lstcarAt=${item['lstcarAt']} '
      'recptnDt=${item['recptnDt']}');
}

void _printParsed(Map<String, dynamic> item) {
  final barvlDt = item['barvlDt']?.toString();
  final arvlCd = item['arvlCd']?.toString();
  final arvlMsg2 = item['arvlMsg2']?.toString() ?? '';

  // 앱 DTO의 _parseArrivalSeconds 로직 재현
  int? parsed;
  String parseSource = '';
  final sec = int.tryParse(barvlDt ?? '');
  if (sec == null) {
    parsed = null;
    parseSource = 'barvlDt 파싱 실패';
  } else if (sec > 0) {
    parsed = sec;
    parseSource = 'barvlDt > 0';
  } else {
    // sec == 0
    final code = int.tryParse(arvlCd ?? '');
    if (code == 1) {
      parsed = 0;
      parseSource = 'barvlDt=0 + arvlCd=1(도착) → 0초';
    } else {
      parsed = null;
      parseSource = 'barvlDt=0이지만 arvlCd≠1 → null (상위 추정 위임)';
    }
  }

  // parseTimeFromMessage 재현
  if (parsed == null) {
    final m = RegExp(r'(\d+)분\s*(?:(\d+)초)?').firstMatch(arvlMsg2);
    if (m != null) {
      final min = int.parse(m.group(1)!);
      final s = m.group(2) != null ? int.parse(m.group(2)!) : 0;
      parsed = min * 60 + s;
      parseSource = 'arvlMsg2 시간 파싱: ${parsed}초';
    }
  }

  // parseStationCount 재현 (N번째 전역)
  final stCountMatch = RegExp(
    r'^(?:\[?(\d+)\]?번째 )?전역(?:\s*\(.+\))?(?:\s+(출발|도착|진입))?$',
  ).firstMatch(arvlMsg2);
  final stCount = stCountMatch != null
      ? '전역×${stCountMatch.group(1) ?? "1"} status="${stCountMatch.group(2) ?? ""}"'
      : '(매칭 안됨)';

  stdout.writeln('      → parsed arrivalSeconds=$parsed  ($parseSource)');
  stdout.writeln('      → parseStationCount: $stCount');
}

void _printSummary(List<Map<String, dynamic>> list) {
  stdout.writeln('=== 요약 ===');
  final byArvlCd = <String, int>{};
  var zeroBarvlDt = 0;
  var zeroBarvlDtWithStationMsg = 0;
  for (final it in list) {
    final cd = it['arvlCd']?.toString() ?? 'null';
    byArvlCd[cd] = (byArvlCd[cd] ?? 0) + 1;
    if (it['barvlDt']?.toString() == '0') {
      zeroBarvlDt++;
      final msg = it['arvlMsg2']?.toString() ?? '';
      if (RegExp(r'전역').hasMatch(msg)) zeroBarvlDtWithStationMsg++;
    }
  }
  stdout.writeln('arvlCd 분포: $byArvlCd');
  stdout.writeln('barvlDt=0 총 $zeroBarvlDt건 중 "전역" 메시지: $zeroBarvlDtWithStationMsg건');
}
