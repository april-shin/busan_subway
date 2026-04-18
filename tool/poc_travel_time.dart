// PoC: 인접 두 역의 시간표에서 같은 열차번호(trainno) 매칭으로
// 실제 역간 소요시간을 계산할 수 있는지 검증.
//
// 1호선 seoul(133) → cityHall(132) 상행 평일 데이터로 검증.

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final env = File('.env').readAsStringSync();
  final apiKey = RegExp(r'KOREA_API_KEY=(.+)').firstMatch(env)!.group(1)!.trim();

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Future<List<Map<String, dynamic>>> fetch(String stnNm, String dir) async {
    final url = Uri.parse(
      'https://apis.data.go.kr/B553766/schedule/getTrainSch',
    ).replace(queryParameters: {
      'serviceKey': apiKey,
      'tmprTmtblYn': 'N',
      'upbdnbSe': dir,
      'wkndSe': '평일',
      'lineNm': '1호선',
      'stnNm': stnNm,
      'dataType': 'JSON',
      'numOfRows': '1000',
      'pageNo': '1',
    });
    final res = await dio.getUri<String>(url);
    final body = json.decode(res.data!) as Map<String, dynamic>;
    final items = body['response']?['body']?['items']?['item'];
    if (items is List) return items.cast<Map<String, dynamic>>();
    return [];
  }

  print('=== 1호선 seoul + cityHall 상행 시간표 매칭 ===');
  final seoul = await fetch('서울역', '상행');
  final cityHall = await fetch('시청', '상행');
  print('seoul 상행: ${seoul.length}편, cityHall 상행: ${cityHall.length}편');

  // trainno 매칭
  final cityHallMap = {for (final i in cityHall) i['trainno']: i};
  final gaps = <int>[];
  var matched = 0;
  for (final s in seoul) {
    final tno = s['trainno'];
    final c = cityHallMap[tno];
    if (c == null) continue;
    final sTime = _parseSec(s['trainDptreTm']?.toString() ?? '');
    final cTime = _parseSec(c['trainDptreTm']?.toString() ?? '');
    if (sTime == null || cTime == null) continue;
    final gap = cTime - sTime;
    if (gap > 0 && gap < 600) {
      gaps.add(gap);
      matched++;
    }
  }
  print('매칭된 열차: $matched');
  if (gaps.isNotEmpty) {
    gaps.sort();
    final avg = gaps.reduce((a, b) => a + b) / gaps.length;
    final median = gaps[gaps.length ~/ 2];
    print('평균: ${avg.toStringAsFixed(1)}초, 중앙값: $median초');
    print('범위: ${gaps.first} ~ ${gaps.last}초');
    print('현재 connections.json: ');
    final conns = json.decode(File('assets/json/connections.json').readAsStringSync()) as List;
    for (final c in conns) {
      if (c['lineId'] == '1' &&
          ((c['fromStationId'] == '133' && c['toStationId'] == '132') ||
              (c['fromStationId'] == '132' && c['toStationId'] == '133'))) {
        print('  ${c['fromStationId']}→${c['toStationId']}: ${c['travelTimeSeconds']}초');
      }
    }
  }
  dio.close();
}

int? _parseSec(String s) {
  // "HH:MM:SS" or "HHMMSS" 형식
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
