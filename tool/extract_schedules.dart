import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// data.go.kr API에서 실제 시간표를 추출하여 line_schedules.json을 생성하는 스크립트
/// 상행/하행 양방향 데이터를 수집하여 컴팩트 포맷으로 저장한다.
///
/// 사용법: dart run tool/extract_schedules.dart
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
    receiveTimeout: const Duration(seconds: 60),
  ));

  // 앱 lineId → API lineNm 매핑
  // upDir/dnDir: 상행/하행 방향명 (2호선은 내선/외선)
  final lineConfigs = <Map<String, String>>[
    {'lineId': '1', 'apiLineName': '1호선', 'station': '서울역', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '2', 'apiLineName': '2호선', 'station': '시청', 'upDir': '내선', 'dnDir': '외선'},
    {'lineId': '3', 'apiLineName': '3호선', 'station': '교대', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '4', 'apiLineName': '4호선', 'station': '서울역', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '5', 'apiLineName': '5호선', 'station': '광화문', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '6', 'apiLineName': '6호선', 'station': '삼각지', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '7', 'apiLineName': '7호선', 'station': '고속터미널', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '8', 'apiLineName': '8호선', 'station': '잠실', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '9', 'apiLineName': '9호선', 'station': '여의도', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': 'SB', 'apiLineName': '신분당선', 'station': '강남', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '경의중앙', 'apiLineName': '', 'station': '', 'upDir': '', 'dnDir': ''},
    {'lineId': '경춘', 'apiLineName': '경춘선', 'station': '상봉', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '공항철도', 'apiLineName': '공항철도', 'station': '서울역', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '수인분당', 'apiLineName': '수인분당선', 'station': '왕십리', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '신림', 'apiLineName': '신림선', 'station': '보라매', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '에버라인', 'apiLineName': '용인경전철', 'station': '기흥', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '인천1', 'apiLineName': '', 'station': '', 'upDir': '', 'dnDir': ''},
    {'lineId': '인천2', 'apiLineName': '인천2호선', 'station': '검암', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '김포골드', 'apiLineName': '', 'station': '', 'upDir': '', 'dnDir': ''},
    {'lineId': '서해', 'apiLineName': '서해선', 'station': '소사', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '의정부', 'apiLineName': '의정부경전철', 'station': '범골', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '우이신설', 'apiLineName': '', 'station': '', 'upDir': '', 'dnDir': ''},
    {'lineId': 'GTX-A', 'apiLineName': 'GTX-A', 'station': '삼성', 'upDir': '상행', 'dnDir': '하행'},
  ];

  final schedules = <Map<String, dynamic>>[];

  for (final config in lineConfigs) {
    final lineId = config['lineId']!;
    final apiLineName = config['apiLineName']!;

    if (apiLineName.isEmpty) {
      print('[$lineId] API에 없음 → 추정치 사용');
      schedules.add(_getEstimatedSchedule(lineId));
      continue;
    }

    print('[$lineId] $apiLineName 양방향 시간표 추출 중...');

    try {
      final result = await _extractBidirectionalSchedule(
        dio: dio,
        apiKey: apiKey,
        config: config,
      );
      schedules.add(result);
      print('  ✓ 완료');
    } catch (e) {
      print('  ✗ 에러: $e → 추정치 사용');
      schedules.add(_getEstimatedSchedule(lineId));
    }

    // API 호출 제한 방지
    await Future.delayed(const Duration(milliseconds: 300));
  }

  // 컴팩트 JSON 파일 저장
  final encoder = const JsonEncoder.withIndent('  ');
  final outputPath = 'assets/json/line_schedules.json';
  File(outputPath).writeAsStringSync(encoder.convert(schedules));
  print('\n✓ $outputPath에 ${schedules.length}개 노선 시간표 저장 완료');

  dio.close();
}

/// 상행/하행 양방향 데이터를 수집하여 컴팩트 포맷으로 반환한다.
Future<Map<String, dynamic>> _extractBidirectionalSchedule({
  required Dio dio,
  required String apiKey,
  required Map<String, String> config,
}) async {
  final lineId = config['lineId']!;
  final apiLineName = config['apiLineName']!;
  final station = config['station']!;
  final upDir = config['upDir']!;
  final dnDir = config['dnDir']!;

  // 평일 상행/하행
  final wdUp = await _extractDaySchedule(
    dio: dio, apiKey: apiKey, apiLineName: apiLineName,
    station: station, dir: upDir, wkndSe: '평일',
  );
  await Future.delayed(const Duration(milliseconds: 200));
  final wdDn = await _extractDaySchedule(
    dio: dio, apiKey: apiKey, apiLineName: apiLineName,
    station: station, dir: dnDir, wkndSe: '평일',
  );
  await Future.delayed(const Duration(milliseconds: 200));

  // 주말 상행/하행
  final weUp = await _extractDaySchedule(
    dio: dio, apiKey: apiKey, apiLineName: apiLineName,
    station: station, dir: upDir, wkndSe: '주말',
  );
  await Future.delayed(const Duration(milliseconds: 200));
  final weDn = await _extractDaySchedule(
    dio: dio, apiKey: apiKey, apiLineName: apiLineName,
    station: station, dir: dnDir, wkndSe: '주말',
  );

  // 폴백 처리
  final wdUpData = wdUp ?? _defaultDayData();
  final wdDnData = wdDn ?? wdUpData;
  final weUpData = weUp ?? _defaultDayData();
  final weDnData = weDn ?? weUpData;

  return _buildCompactEntry(lineId, wdUpData, wdDnData, weUpData, weDnData);
}

/// 컴팩트 엔트리를 생성한다. 양방향 배차간격이 동일하면 p만, 다르면 pD 추가.
Map<String, dynamic> _buildCompactEntry(
  String lineId,
  Map<String, dynamic> wdUp,
  Map<String, dynamic> wdDn,
  Map<String, dynamic> weUp,
  Map<String, dynamic> weDn,
) {
  final wdPeriods = _toCompactPeriods(wdUp['periods'] as List);
  final wdDnPeriods = _toCompactPeriods(wdDn['periods'] as List);
  final wePeriods = _toCompactPeriods(weUp['periods'] as List);
  final weDnPeriods = _toCompactPeriods(weDn['periods'] as List);

  final wd = <String, dynamic>{
    'f': [wdUp['firstTrain'], wdDn['firstTrain']],
    'l': [wdUp['lastTrain'], wdDn['lastTrain']],
    'p': wdPeriods,
  };
  if (!_periodsEqual(wdPeriods, wdDnPeriods)) {
    wd['pD'] = wdDnPeriods;
  }

  final we = <String, dynamic>{
    'f': [weUp['firstTrain'], weDn['firstTrain']],
    'l': [weUp['lastTrain'], weDn['lastTrain']],
    'p': wePeriods,
  };
  if (!_periodsEqual(wePeriods, weDnPeriods)) {
    we['pD'] = weDnPeriods;
  }

  return {'id': lineId, 'wd': wd, 'we': we};
}

/// periods 리스트를 컴팩트 배열 형태로 변환 [[시작, 종료, 배차분], ...]
List<List<dynamic>> _toCompactPeriods(List<dynamic> periods) {
  return periods.map((p) {
    final m = p as Map<String, dynamic>;
    return [m['start'], m['end'], m['headwayMinutes']];
  }).toList();
}

/// 두 컴팩트 배차간격 리스트가 동일한지 비교
bool _periodsEqual(List<List<dynamic>> a, List<List<dynamic>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length) return false;
    for (var j = 0; j < a[i].length; j++) {
      if (a[i][j].toString() != b[i][j].toString()) return false;
    }
  }
  return true;
}

Map<String, dynamic> _defaultDayData() {
  return {
    'firstTrain': '05:30',
    'lastTrain': '23:30',
    'periods': [
      {'start': '05:30', 'end': '23:30', 'headwayMinutes': 8}
    ],
  };
}

Future<Map<String, dynamic>?> _extractDaySchedule({
  required Dio dio,
  required String apiKey,
  required String apiLineName,
  required String station,
  required String dir,
  required String wkndSe,
}) async {
  try {
    final params = <String, String>{
      'serviceKey': apiKey,
      'tmprTmtblYn': 'N',
      'upbdnbSe': dir,
      'wkndSe': wkndSe,
      'lineNm': apiLineName,
      'dataType': 'JSON',
      'numOfRows': '1000',
      'pageNo': '1',
    };
    if (station.isNotEmpty) params['stnNm'] = station;

    final url = Uri.parse(
      'https://apis.data.go.kr/B553766/schedule/getTrainSch',
    ).replace(queryParameters: params);

    final res = await dio.getUri<String>(url);
    final data = json.decode(res.data!) as Map<String, dynamic>;
    final totalCount = data['response']?['body']?['totalCount'] ?? 0;

    if (totalCount == 0) {
      // 역명 없이 전체 조회 시도
      params.remove('stnNm');
      final url2 = Uri.parse(
        'https://apis.data.go.kr/B553766/schedule/getTrainSch',
      ).replace(queryParameters: params);
      final res2 = await dio.getUri<String>(url2);
      final data2 = json.decode(res2.data!) as Map<String, dynamic>;
      final items2 = data2['response']?['body']?['items']?['item'];
      if (items2 == null || items2 is! List || items2.isEmpty) {
        return null;
      }

      final firstStation = items2.first['stnNm'] as String;
      return _analyzeStationTimes(items2
          .where((item) => item['stnNm'] == firstStation)
          .toList());
    }

    final items = data['response']?['body']?['items']?['item'];
    if (items == null || items is! List || items.isEmpty) return null;

    return _analyzeStationTimes(items);
  } catch (e) {
    print('  에러 ($wkndSe $dir): $e');
    return null;
  }
}

Map<String, dynamic> _analyzeStationTimes(List<dynamic> items) {
  final times = <int>[];
  for (final item in items) {
    final t = item['trainDptreTm']?.toString() ?? '';
    final minutes = _parseMinutes(t);
    if (minutes != null) times.add(minutes);
  }
  times.sort();

  if (times.isEmpty) {
    return {
      'firstTrain': '05:30',
      'lastTrain': '23:30',
      'periods': [
        {'start': '05:30', 'end': '23:30', 'headwayMinutes': 8}
      ],
    };
  }

  final firstMin = times.first;
  final lastMin = times.last;
  final firstTrain = _minutesToTimeStr(firstMin);
  final lastTrain = lastMin >= 1440
      ? _minutesToTimeStr(lastMin - 1440)
      : _minutesToTimeStr(lastMin);

  final hourlyGaps = <int, List<int>>{};
  for (var i = 1; i < times.length; i++) {
    final gap = times[i] - times[i - 1];
    if (gap > 0 && gap < 30) {
      final hour = times[i - 1] ~/ 60;
      hourlyGaps.putIfAbsent(hour, () => []).add(gap);
    }
  }

  final periods = <Map<String, dynamic>>[];
  final sortedHours = hourlyGaps.keys.toList()..sort();

  if (sortedHours.isEmpty) {
    return {
      'firstTrain': firstTrain,
      'lastTrain': lastTrain == '00:00' ? '00:00' : lastTrain,
      'periods': [
        {'start': firstTrain, 'end': lastTrain, 'headwayMinutes': 8}
      ],
    };
  }

  var periodStart = sortedHours.first;
  var prevAvg = _avgGap(hourlyGaps[periodStart]!);

  for (var i = 1; i < sortedHours.length; i++) {
    final hour = sortedHours[i];
    final avg = _avgGap(hourlyGaps[hour]!);

    if ((avg - prevAvg).abs() > 1.5 || hour > sortedHours[i - 1] + 1) {
      periods.add({
        'start': _minutesToTimeStr(periodStart * 60),
        'end': _minutesToTimeStr(hour * 60),
        'headwayMinutes': prevAvg.round(),
      });
      periodStart = hour;
      prevAvg = avg;
    } else {
      prevAvg = (prevAvg + avg) / 2;
    }
  }

  periods.add({
    'start': _minutesToTimeStr(periodStart * 60),
    // 마지막 period의 end는 실제 막차 시각(lastTrain)으로 저장한다.
    // 이렇게 하면 (1) 자정 넘김 막차가 "00:00"으로 뭉개지지 않고,
    // (2) hour 버킷 상한이나 +1분 off-by-one 없이
    //     tool/fix_midnight_schedule_data.dart 마이그레이션 산출물과 동일한
    //     컨벤션(마지막 period end == 막차 시각)을 유지한다.
    //     ("00:00"이면 자정 정각 종료를 의미하며 endMinutes getter가 1440으로 해석).
    'end': lastTrain,
    'headwayMinutes': prevAvg.round(),
  });

  return {
    'firstTrain': firstTrain,
    'lastTrain': lastTrain == '00:00' ? '00:00' : lastTrain,
    'periods': periods,
  };
}

double _avgGap(List<int> gaps) {
  return gaps.reduce((a, b) => a + b) / gaps.length;
}

int? _parseMinutes(String time) {
  try {
    final parts = time.split(':');
    if (parts.length >= 2) {
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return h * 60 + m;
    }
  } catch (_) {}
  return null;
}

String _minutesToTimeStr(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// API에 데이터가 없는 노선의 추정치 (컴팩트 포맷)
Map<String, dynamic> _getEstimatedSchedule(String lineId) {
  switch (lineId) {
    case '경의중앙':
      return {
        'id': '경의중앙',
        'wd': {
          'f': ['05:10', '05:10'],
          'l': ['23:40', '23:40'],
          'p': [
            ['05:10', '07:00', 20],
            ['07:00', '09:00', 10],
            ['09:00', '17:00', 20],
            ['17:00', '19:30', 10],
            ['19:30', '23:40', 20],
          ],
        },
        'we': {
          'f': ['05:30', '05:30'],
          'l': ['23:00', '23:00'],
          'p': [
            ['05:30', '23:00', 25],
          ],
        },
      };
    case '인천1':
      return {
        'id': '인천1',
        'wd': {
          'f': ['05:00', '05:00'],
          'l': ['00:30', '00:30'],
          'p': [
            ['05:00', '07:00', 9],
            ['07:00', '09:00', 5],
            ['09:00', '17:00', 9],
            ['17:00', '19:30', 6],
            ['19:30', '00:30', 10],
          ],
        },
        'we': {
          'f': ['05:30', '05:30'],
          'l': ['23:00', '23:00'],
          'p': [
            ['05:30', '23:00', 10],
          ],
        },
      };
    case '김포골드':
      return {
        'id': '김포골드',
        'wd': {
          'f': ['05:30', '05:30'],
          'l': ['23:30', '23:30'],
          'p': [
            ['05:30', '07:00', 6],
            ['07:00', '09:00', 3],
            ['09:00', '17:00', 6],
            ['17:00', '19:30', 3],
            ['19:30', '23:30', 8],
          ],
        },
        'we': {
          'f': ['06:00', '06:00'],
          'l': ['23:00', '23:00'],
          'p': [
            ['06:00', '23:00', 8],
          ],
        },
      };
    case '우이신설':
      return {
        'id': '우이신설',
        'wd': {
          'f': ['05:30', '05:30'],
          'l': ['00:40', '00:40'],
          'p': [
            ['05:30', '07:00', 5],
            ['07:00', '09:00', 3],
            ['09:00', '17:00', 5],
            ['17:00', '19:30', 3],
            ['19:30', '00:40', 6],
          ],
        },
        'we': {
          'f': ['05:30', '05:30'],
          'l': ['00:00', '00:00'],
          'p': [
            ['05:30', '00:00', 5],
          ],
        },
      };
    default:
      return {
        'id': lineId,
        'wd': {
          'f': ['05:30', '05:30'],
          'l': ['23:30', '23:30'],
          'p': [
            ['05:30', '07:00', 8],
            ['07:00', '09:00', 5],
            ['09:00', '17:00', 8],
            ['17:00', '19:30', 5],
            ['19:30', '23:30', 10],
          ],
        },
        'we': {
          'f': ['05:30', '05:30'],
          'l': ['23:00', '23:00'],
          'p': [
            ['05:30', '23:00', 10],
          ],
        },
      };
  }
}
