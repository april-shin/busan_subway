import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/line_schedule.dart';

/// 정적 시간표 데이터(line_schedules.json)를 로드하는 데이터소스
///
/// 컴팩트 JSON 포맷(id/wd/we/f/l/p/pD)을 파싱하여 LineSchedule로 변환한다.
class TimetableDataSource {
  Map<String, LineSchedule>? _schedulesCache;

  /// 모든 노선 스케줄을 lineId 기준 맵으로 로드
  Future<Map<String, LineSchedule>> loadSchedules() async {
    if (_schedulesCache != null) return _schedulesCache!;

    final jsonString =
        await rootBundle.loadString('assets/json/line_schedules.json');
    final jsonList = json.decode(jsonString) as List<dynamic>;
    _schedulesCache = {
      for (final item in jsonList)
        _extractLineId(item as Map<String, dynamic>):
            _parseSchedule(item),
    };
    return _schedulesCache!;
  }

  /// 특정 노선의 스케줄 조회
  Future<LineSchedule?> getSchedule(String lineId) async {
    final schedules = await loadSchedules();
    return schedules[lineId];
  }

  void clearCache() {
    _schedulesCache = null;
  }
}

/// JSON 객체에서 lineId를 추출한다 (컴팩트: 'id', 레거시: 'lineId')
String _extractLineId(Map<String, dynamic> json) {
  return (json['id'] ?? json['lineId']) as String;
}

/// 컴팩트 또는 레거시 포맷의 JSON을 LineSchedule로 변환한다.
LineSchedule _parseSchedule(Map<String, dynamic> json) {
  // 컴팩트 포맷 감지: 'wd' 키 존재
  if (json.containsKey('wd')) {
    return _parseCompactSchedule(json);
  }
  // 레거시 포맷: fromJson으로 처리
  return LineSchedule.fromJson(json);
}

/// 컴팩트 JSON을 LineSchedule로 파싱한다.
///
/// 포맷:
/// - id: lineId
/// - wd: 평일 (필수)
/// - we: 주말 (옵셔널, 없으면 wd와 동일)
///   - f: [상행첫차, 하행첫차]
///   - l: [상행막차, 하행막차]
///   - p: [[시작, 종료, 배차분], ...]
///   - pD: [[시작, 종료, 배차분], ...] (하행 전용, 옵셔널)
LineSchedule _parseCompactSchedule(Map<String, dynamic> json) {
  final lineId = json['id'] as String;
  final wd = json['wd'] as Map<String, dynamic>;
  // we가 없으면 wd와 동일 (의정부, GTX-A 등)
  final we = (json['we'] as Map<String, dynamic>?) ?? wd;

  return LineSchedule(
    lineId: lineId,
    weekday: _parseDayScheduleAt(wd, 0),
    weekend: _parseDayScheduleAt(we, 0),
    weekdayDown: _parseDayScheduleDown(wd),
    weekendDown: _parseDayScheduleDown(we),
  );
}

/// 특정 방향 인덱스의 DaySchedule을 파싱한다.
DaySchedule _parseDayScheduleAt(Map<String, dynamic> day, int dirIndex) {
  final f = day['f'] as List;
  final l = day['l'] as List;
  final periods = _parsePeriods(day['p'] as List);

  return DaySchedule(
    firstTrain: f[dirIndex] as String,
    lastTrain: l[dirIndex] as String,
    periods: periods,
  );
}

/// 하행 전용 DaySchedule을 파싱한다. 상행과 동일하면 null 반환.
DaySchedule? _parseDayScheduleDown(Map<String, dynamic> day) {
  final f = day['f'] as List;
  final l = day['l'] as List;
  if (f.length < 2) return null;

  // pD가 없고 첫차/막차도 동일하면 상행과 같으므로 null 반환 (폴백)
  final hasDedicatedPeriods = day.containsKey('pD');
  if (!hasDedicatedPeriods && f[0] == f[1] && l[0] == l[1]) {
    return null;
  }

  // pD(하행 전용 배차간격)가 있으면 사용, 없으면 p(공유) 사용
  final periodsRaw = day['pD'] as List? ?? day['p'] as List;
  final periods = _parsePeriods(periodsRaw);

  return DaySchedule(
    firstTrain: f[1] as String,
    lastTrain: l[1] as String,
    periods: periods,
  );
}

/// 배열 형태의 배차간격 리스트를 TimePeriod 리스트로 변환한다.
List<TimePeriod> _parsePeriods(List<dynamic> raw) {
  return raw.map((p) {
    final arr = p as List;
    return TimePeriod(
      start: arr[0] as String,
      end: arr[1] as String,
      headwayMinutes: arr[2] as int,
    );
  }).toList();
}
