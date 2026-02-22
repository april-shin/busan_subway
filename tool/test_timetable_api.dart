import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// data.go.kr 시간표 API - 노선별 데이터 추출 스크립트
void main() async {
  final envContent = File('.env').readAsStringSync();
  final match = RegExp(r'KOREA_API_KEY=(.+)').firstMatch(envContent);
  if (match == null) {
    print('.env에 KOREA_API_KEY가 없습니다.');
    exit(1);
  }
  final apiKey = match.group(1)!.trim();

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // ========================================
  // 1. 사용 가능한 노선명 목록 확인
  // ========================================
  print('=== 1. 노선명 탐색 ===');

  final lineNames = [
    '1호선', '2호선', '3호선', '4호선', '5호선', '6호선', '7호선', '8호선', '9호선',
    '서울2호선', '서울 2호선',
    '신분당선', '경의중앙선', '경춘선', '공항철도', '수인분당선',
    '신림선', '우이신설선', '에버라인', '인천1호선', '인천2호선',
    '김포골드라인', '서해선', '의정부경전철', 'GTX-A',
    '경강선', '용인경전철',
  ];

  final validLines = <String, int>{};

  for (final name in lineNames) {
    try {
      final url = Uri.parse(
        'https://apis.data.go.kr/B553766/schedule/getTrainSch',
      ).replace(queryParameters: {
        'serviceKey': apiKey,
        'tmprTmtblYn': 'N',
        'upbdnbSe': '상행',
        'wkndSe': '평일',
        'lineNm': name,
        'dataType': 'JSON',
        'numOfRows': '1',
        'pageNo': '1',
      });
      final res = await dio.getUri<String>(url);
      final data = json.decode(res.data!) as Map<String, dynamic>;
      final totalCount = data['response']?['body']?['totalCount'] ?? 0;
      if (totalCount > 0) {
        validLines[name] = totalCount as int;
        final items = data['response']?['body']?['items']?['item'] as List;
        final apiLineName = items.first['lineNm'];
        print('✓ "$name" → $totalCount건 (API lineNm: "$apiLineName")');
      } else {
        print('✗ "$name" → 0건');
      }
    } catch (e) {
      print('✗ "$name" → 에러');
    }
  }

  // ========================================
  // 2. 주요 노선의 실제 시간표 추출
  // ========================================
  print('\n=== 2. 서울 주요 노선 시간표 분석 ===');

  // 서울 2호선 찾기: 특정 역명으로 필터
  print('\n--- 서울 2호선 찾기 ---');
  for (final stnNm in ['강남', '시청', '잠실', '홍대입구']) {
    try {
      final url = Uri.parse(
        'https://apis.data.go.kr/B553766/schedule/getTrainSch',
      ).replace(queryParameters: {
        'serviceKey': apiKey,
        'tmprTmtblYn': 'N',
        'upbdnbSe': '내선',
        'wkndSe': '평일',
        'lineNm': '',
        'stnNm': stnNm,
        'dataType': 'JSON',
        'numOfRows': '5',
        'pageNo': '1',
      });
      final res = await dio.getUri<String>(url);
      final data = json.decode(res.data!) as Map<String, dynamic>;
      final totalCount = data['response']?['body']?['totalCount'] ?? 0;
      print('stnNm="$stnNm", 내선: $totalCount건');
      if (totalCount > 0) {
        final items = data['response']?['body']?['items']?['item'] as List;
        for (final item in items.take(3)) {
          print('  lineNm=${item['lineNm']}, '
              '열차=${item['trainno']}, '
              '출발=${item['trainDptreTm']}, '
              '방향=${item['upbdnbSe']}');
        }
      }
    } catch (_) {}
  }

  // 역명 없이 다양한 노선명 변형으로 서울 2호선 찾기
  print('\n--- 서울 2호선 노선명 변형 ---');
  final line2Variations = [
    '서울2호선', '서울 2호선', '도시철도2호선', '서울도시철도 2호선',
    '수도권2호선', '수도권 2호선', '서울메트로2호선',
    '02호선', '서울교통공사2호선',
  ];
  for (final name in line2Variations) {
    try {
      final url = Uri.parse(
        'https://apis.data.go.kr/B553766/schedule/getTrainSch',
      ).replace(queryParameters: {
        'serviceKey': apiKey,
        'tmprTmtblYn': 'N',
        'upbdnbSe': '상행',
        'wkndSe': '평일',
        'lineNm': name,
        'dataType': 'JSON',
        'numOfRows': '1',
        'pageNo': '1',
      });
      final res = await dio.getUri<String>(url);
      final data = json.decode(res.data!) as Map<String, dynamic>;
      final totalCount = data['response']?['body']?['totalCount'] ?? 0;
      print('"$name" → $totalCount건');
    } catch (_) {
      print('"$name" → 에러');
    }
  }

  // ========================================
  // 3. 1호선 서울역 시간표 상세 분석 (작동 확인된 노선)
  // ========================================
  print('\n=== 3. 1호선 시간표 상세 (서울역) ===');

  for (final wknd in ['평일', '주말']) {
    for (final dir in ['상행', '하행']) {
      try {
        final url = Uri.parse(
          'https://apis.data.go.kr/B553766/schedule/getTrainSch',
        ).replace(queryParameters: {
          'serviceKey': apiKey,
          'tmprTmtblYn': 'N',
          'upbdnbSe': dir,
          'wkndSe': wknd,
          'lineNm': '1호선',
          'stnNm': '서울역',
          'dataType': 'JSON',
          'numOfRows': '500',
          'pageNo': '1',
        });
        final res = await dio.getUri<String>(url);
        final data = json.decode(res.data!) as Map<String, dynamic>;
        final totalCount = data['response']?['body']?['totalCount'] ?? 0;
        final items = data['response']?['body']?['items']?['item'];

        if (items != null && items is List && items.isNotEmpty) {
          // 시간대별 배차간격 계산
          final times = <String>[];
          for (final item in items) {
            final t = item['trainDptreTm']?.toString() ?? '';
            if (t.isNotEmpty) times.add(t);
          }
          times.sort();

          print('\n[1호선 서울역 $dir $wknd] $totalCount편');
          print('  첫차: ${times.first}, 막차: ${times.last}');

          // 시간대별 간격 계산
          final hourlyGaps = <int, List<int>>{};
          for (var i = 1; i < times.length; i++) {
            final prev = _parseMinutes(times[i - 1]);
            final curr = _parseMinutes(times[i]);
            if (prev != null && curr != null && curr > prev) {
              final gap = curr - prev;
              if (gap < 30) {
                final hour = prev ~/ 60;
                hourlyGaps.putIfAbsent(hour, () => []).add(gap);
              }
            }
          }

          final sortedHours = hourlyGaps.keys.toList()..sort();
          for (final hour in sortedHours) {
            final gaps = hourlyGaps[hour]!;
            final avg = gaps.reduce((a, b) => a + b) / gaps.length;
            print('  ${hour.toString().padLeft(2, '0')}시: '
                '평균 ${avg.toStringAsFixed(1)}분 간격 '
                '(${gaps.length}편)');
          }
        } else {
          print('[1호선 서울역 $dir $wknd] 데이터 없음 ($totalCount)');
        }
      } catch (e) {
        print('[1호선 서울역 $dir $wknd] 에러: $e');
      }
    }
  }

  // ========================================
  // 4. 노선별 방향값 확인 (1호선 데이터 기준)
  // ========================================
  print('\n=== 4. 1호선 방향값 종류 ===');
  try {
    final url = Uri.parse(
      'https://apis.data.go.kr/B553766/schedule/getTrainSch',
    ).replace(queryParameters: {
      'serviceKey': apiKey,
      'tmprTmtblYn': 'N',
      'upbdnbSe': '',
      'wkndSe': '평일',
      'lineNm': '1호선',
      'stnNm': '서울역',
      'dataType': 'JSON',
      'numOfRows': '500',
      'pageNo': '1',
    });
    final res = await dio.getUri<String>(url);
    final data = json.decode(res.data!) as Map<String, dynamic>;
    final items = data['response']?['body']?['items']?['item'];
    if (items != null && items is List) {
      final directions = <String>{};
      final dayTypes = <String>{};
      for (final item in items) {
        directions.add(item['upbdnbSe']?.toString() ?? '');
        dayTypes.add(item['wkndSe']?.toString() ?? '');
      }
      print('방향값: $directions');
      print('요일값: $dayTypes');
    }
  } catch (e) {
    print('에러: $e');
  }

  dio.close();
}

int? _parseMinutes(String time) {
  try {
    final parts = time.split(':');
    if (parts.length >= 2) {
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }
  } catch (_) {}
  return null;
}
