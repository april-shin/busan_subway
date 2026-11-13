// PoC: 서울 열린데이터광장 SearchSTNTimeTableByIDService API
// data.go.kr 미지원 노선(2,6,GTX-A,에버라인,인천1) 시간표를 보강할 수 있는지 검증.
//
// API: http://swopenapi.seoul.go.kr/api/subway/{KEY}/json/SearchSTNTimeTableByIDService/{start}/{end}/{stationCode}/{day}/{direction}
//   stationCode: 4자리 (예: 0202 = 시청 2호선)
//   day: 1=평일, 2=토, 3=일/공휴일
//   direction: 1=상행/내선, 2=하행/외선

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final env = File('.env').readAsStringSync();
  final apiKey =
      RegExp(r'BUSAN_SUBWAY_API_KEY=(.+)').firstMatch(env)!.group(1)!.trim();

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  // 2호선 시청(0202), 강남(0222), 잠실(0216) 코드로 시도
  // 우리 stations.json은 201~ 같은 3자리. 서울 API는 0201~ 4자리일 가능성
  final tests = [
    ('0201', '시청', '2호선'),
    ('0202', '을지로입구', '2호선'),
    ('0222', '강남', '2호선'),
    ('0216', '잠실', '2호선'),
    ('0631', '신내', '6호선'),
  ];

  for (final (code, name, line) in tests) {
    print('━━━ $line $name ($code) ━━━');
    for (final dir in [1, 2]) {
      try {
        final url = 'http://swopenapi.seoul.go.kr/api/subway/$apiKey/json/'
            'SearchSTNTimeTableByIDService/0/100/$code/1/$dir';
        final res = await dio.get<String>(url);
        final body = json.decode(res.data!) as Map<String, dynamic>;
        final code_ = body['SearchSTNTimeTableByIDService']?['RESULT']?['CODE'];
        final msg = body['SearchSTNTimeTableByIDService']?['RESULT']?['MESSAGE'];
        final list = body['SearchSTNTimeTableByIDService']?['row'];
        final count = list is List ? list.length : 0;
        print('  방향$dir: code=$code_, msg="$msg", row=$count');
        if (list is List && list.isNotEmpty) {
          final first = list.first as Map;
          print('    샘플 키: ${first.keys.toList()}');
          print('    샘플 첫 행: $first');
        }
      } catch (e) {
        print('  방향$dir: ERROR $e');
      }
    }
  }
  dio.close();
}
