import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// data.go.kr API에서 노선 **대표값**(첫차·막차·배차간격)을 추출해
/// line_schedules.json 의 `f`/`l`/`p`/`pD` 를 갱신하는 스크립트.
/// 상행/하행 양방향 데이터를 수집하여 컴팩트 포맷으로 저장한다.
///
/// ⚠ **역별 시간표(`t`/`tE`)는 이 도구가 만들지 않는다.** 그 데이터는
/// `build_metro_timetable.dart`(1~9호선) · `build_gettrainsch_timetable.dart`
/// (비서울교통공사 12개) · `build_incheon1_timetable.dart` · 경의중앙 엑셀
/// 파이프라인의 산출물이며, 이 도구는 **기존 파일에서 그대로 물려받는다**.
/// 예전에는 결과를 통째로 덮어써서 한 번 실행하면 23개 노선의 역별 시간표가
/// 전부 사라졌다(복원 불가 — 각 수집 도구를 다시 돌려야 했다).
///
/// ⚠ **앵커역은 반드시 "양방향 전구간 운행역"으로 고른다.** 회차역을 쓰면 그
/// 방향의 대표값이 소수 편성만으로 계산돼 무너진다 — 수인분당 왕십리(상행 168행
/// 중 159편이 당역종착 → `trainDptreTm=null`)는 첫차·막차가 07:32~18:51 로,
/// 경춘 상봉은 배차 band 가 한 시간짜리 하나로 기록됐다(2026-08-13 정정).
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
    // 앵커: 망우(상봉 옆). 상봉은 회차역이라 상행 대표값이 무너진다.
    {'lineId': '경춘', 'apiLineName': '경춘선', 'station': '망우', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '경강', 'apiLineName': '경강선', 'station': '이매', 'upDir': '상행', 'dnDir': '하행'},
    {'lineId': '공항철도', 'apiLineName': '공항철도', 'station': '서울역', 'upDir': '상행', 'dnDir': '하행'},
    // 앵커: 서울숲(왕십리 옆). 왕십리는 회차역이라 상행 대표값이 무너진다.
    {'lineId': '수인분당', 'apiLineName': '수인분당선', 'station': '서울숲', 'upDir': '상행', 'dnDir': '하행'},
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

  // 기존 파일의 역별 시간표(t/tE)를 물려받아 저장한다.
  final outputPath = 'assets/json/line_schedules.json';
  final carried = _carryOverStationTimetables(outputPath, schedules);

  final encoder = const JsonEncoder.withIndent('  ');
  File(outputPath).writeAsStringSync(encoder.convert(schedules));
  print('\n✓ $outputPath에 ${schedules.length}개 노선 대표값 저장 완료'
      ' (기존 값 $carried개 노선 보존)');

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

/// API에 데이터가 없는 노선의 추정치 (컴팩트 포맷).
///
/// ⚠ 경의중앙의 `f`/`l` 은 실제 `t` 와 어긋난 값이다(추정 05:10~23:40 vs 실측
/// 05:00~00:39). [_representativeCarryOverLines] 덕분에 기존 파일이 있으면
/// 덮어쓰지 않으므로, 이 값은 **파일이 아예 없을 때의 초기값**으로만 쓰인다.
/// `f`/`l` 을 고칠 일이 있으면 `tool/build_center_line_timetable.py` 를 실행하는
/// 쪽이 맞다. **`p`/`pD` 는 그 도구도 도출하지 않으므로**(경의중앙은 56역 전부
/// `t` 를 보유해 배차간격 경로가 사실상 죽어 있다) 바꾸려면 JSON 을 직접
/// 패치해야 한다 — 여기 추정치를 고쳐도 carry-over 가 기존 값을 덮어쓴다.
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

/// 대표값(`f`/`l`/`p`/`pD`)까지 기존 파일에서 물려받는 노선.
///
/// 경의중앙·김포골드는 API 가 없어 이 도구가 [_getEstimatedSchedule] 의 **하드코딩
/// 추정치**를 쓰는데, 그 값이 실제 `t` 와 어긋나 "노선 첫차·막차"라는 이름과 맞지
/// 않았다 — 경의중앙 평일 05:10~23:40(실측 05:00~00:39), 김포골드 평일 막차
/// 23:30(실측 24:58)·주말 첫차 06:00(실측 05:26).
/// 지금은 각 노선의 `t` 수집 도구가 `f`/`l` 을 도출해 넣으므로 — 경의중앙은
/// `tool/build_center_line_timetable.py`, 김포골드는
/// `tool/build_gettrainsch_timetable.dart` 의 `_deriveRepresentative` — 이 도구가
/// 그 값을 추정치로 되돌리지 않도록 함께 물려받는다.
/// (`p`/`pD` 는 아직 추정치가 유일한 출처지만, `f`/`l` 만 물려받고 `p` 를
///  덮어쓰면 두 값이 서로 어긋나므로 같이 보존한다.)
const _representativeCarryOverLines = {'경의중앙', '김포골드'};

/// 기존 `line_schedules.json` 의 역별 시간표(`t`/`tE`)를 새 엔트리에 옮겨 담는다.
///
/// 이 도구는 노선 대표값(`f`/`l`/`p`/`pD`)만 계산한다. 역별 시간표는 별개 수집
/// 도구들의 산출물이라 여기서 재현할 수 없으므로, 덮어쓰기 전에 반드시 물려받아야
/// 한다. 물려받지 않으면 한 번 실행으로 23개 노선의 역별 시간표가 사라진다.
///
/// [_representativeCarryOverLines] 의 노선은 대표값까지 물려받는다.
///
/// 기존 파일이 없으면(최초 생성) 아무것도 하지 않는다. 파싱에 실패하면 **예외를
/// 던져 중단한다** — 조용히 빈 손으로 덮어쓰는 것이 가장 위험한 실패다.
///
/// 반환값은 무언가를 물려받은 노선 수(로그용). 대부분은 역별 시간표이지만,
/// [_representativeCarryOverLines] 의 노선은 대표값만으로도 집계된다.
int _carryOverStationTimetables(
  String path,
  List<Map<String, dynamic>> schedules,
) {
  final file = File(path);
  if (!file.existsSync()) {
    print('  (기존 파일 없음 — 역별 시간표 물려받기 생략)');
    return 0;
  }

  final decoded = json.decode(file.readAsStringSync());
  if (decoded is! List) {
    throw StateError('$path 형식이 배열이 아니다 — 덮어쓰면 역별 시간표가 사라진다');
  }

  final existing = <String, Map<String, dynamic>>{};
  for (final entry in decoded) {
    if (entry is Map<String, dynamic> && entry['id'] is String) {
      existing[entry['id'] as String] = entry;
    }
  }

  var carried = 0;
  for (final entry in schedules) {
    final prev = existing[entry['id']];
    if (prev == null) continue;
    var touched = false;
    for (final dayKey in const ['wd', 'we']) {
      final prevDay = prev[dayKey];
      final newDay = entry[dayKey];
      if (prevDay is! Map<String, dynamic> || newDay is! Map<String, dynamic>) {
        continue;
      }
      final keys = _representativeCarryOverLines.contains(entry['id'])
          ? const ['t', 'tE', 'f', 'l', 'p', 'pD']
          : const ['t', 'tE'];
      for (final tableKey in keys) {
        final table = prevDay[tableKey];
        if (table != null) {
          newDay[tableKey] = table;
          touched = true;
        }
      }
    }
    if (touched) carried++;
  }
  return carried;
}
