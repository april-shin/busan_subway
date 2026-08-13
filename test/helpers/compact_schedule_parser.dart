import 'package:seoul_subway/domain/entities/line_schedule.dart';

/// `assets/json/line_schedules.json` 의 컴팩트 스키마를 [LineSchedule] 로 파싱한다.
///
/// `TimetableDataSource` 의 파서와 **동일 로직**이지만, 그쪽은 `rootBundle` 에
/// 묶여 있어 순수 Dart 테스트에서 쓸 수 없다. 실데이터 테스트가 각자 파서를
/// 복제하면(한때 세 벌이었다) 방향 인덱스나 `pD` 폴백 규칙이 조용히 갈라져
/// **다른 데이터를 검증하면서 통과하는** 테스트가 된다. 그래서 여기로 모았다.
///
/// ⚠ `TimetableDataSource._parseCompactSchedule` 을 고치면 이 파일도 함께 고칠
/// 것. 근본 해결은 그 파서를 rootBundle 과 분리해 공개하는 것이지만, 그때까지의
/// 단일 지점이다.
///
/// 스키마 요약(자세히는 `.claude/docs/timetable.md`):
/// - `f`/`l` = [상행, 하행] 첫차·막차, `p` = 공유 배차간격, `pD` = 하행 전용
/// - `t`/`tE` = 완행·급행 역별 시간표. `{역ID: [상행분목록, 하행분목록]}`
/// - 상하행이 같고 `pD`/`t`/`tE` 가 없으면 하행 스케줄은 null (상행으로 폴백)
LineSchedule parseCompactSchedule(Map<String, dynamic> json) {
  final wd = json['wd'] as Map<String, dynamic>;
  final we = (json['we'] as Map<String, dynamic>?) ?? wd;
  return LineSchedule(
    lineId: json['id'] as String,
    weekday: compactDayAt(wd, 0),
    weekend: compactDayAt(we, 0),
    weekdayDown: compactDayDown(wd),
    weekendDown: compactDayDown(we),
  );
}

/// 여러 노선을 한 번에 파싱한다 — `line_schedules.json` 최상위 배열 그대로.
Map<String, LineSchedule> parseCompactSchedules(List<dynamic> raw) {
  return {
    for (final item in raw)
      (item as Map<String, dynamic>)['id'] as String:
          parseCompactSchedule(item),
  };
}

/// [dir] 방향(0=상행, 1=하행) 스케줄. 배차간격은 공유 `p` 를 쓴다.
DaySchedule compactDayAt(Map<String, dynamic> day, int dir) {
  return DaySchedule(
    firstTrain: (day['f'] as List)[dir] as String,
    lastTrain: (day['l'] as List)[dir] as String,
    periods: _periods(day['p'] as List),
    stationDepartures: _departures(day, dir, 't'),
    expressStationDepartures: _departures(day, dir, 'tE'),
  );
}

/// 하행 전용 스케줄. 상행과 구분할 근거가 없으면 null (상행으로 폴백).
DaySchedule? compactDayDown(Map<String, dynamic> day) {
  final f = day['f'] as List;
  final l = day['l'] as List;
  if (f.length < 2) return null;
  final hasStations = day.containsKey('t') || day.containsKey('tE');
  final hasPeriods = day.containsKey('pD');
  if (!hasPeriods && !hasStations && f[0] == f[1] && l[0] == l[1]) return null;
  return DaySchedule(
    firstTrain: f[1] as String,
    lastTrain: l[1] as String,
    periods: _periods(day['pD'] as List? ?? day['p'] as List),
    stationDepartures: _departures(day, 1, 't'),
    expressStationDepartures: _departures(day, 1, 'tE'),
  );
}

Map<String, List<int>>? _departures(
  Map<String, dynamic> day,
  int dir,
  String key,
) {
  final raw = day[key] as Map<String, dynamic>?;
  if (raw == null || raw.isEmpty) return null;
  final result = <String, List<int>>{};
  for (final entry in raw.entries) {
    final dirList = entry.value as List;
    if (dir >= dirList.length) continue;
    final minutes = dirList[dir];
    if (minutes == null) continue;
    result[entry.key] = (minutes as List).cast<int>();
  }
  return result.isEmpty ? null : result;
}

List<TimePeriod> _periods(List<dynamic> raw) {
  return raw.map((p) {
    final arr = p as List;
    return TimePeriod(
      start: arr[0] as String,
      end: arr[1] as String,
      headwayMinutes: arr[2] as int,
    );
  }).toList();
}
