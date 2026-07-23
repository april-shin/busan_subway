import 'package:freezed_annotation/freezed_annotation.dart';

part 'line_schedule.freezed.dart';
part 'line_schedule.g.dart';

/// "HH:mm" 형식의 시간 문자열을 분 단위로 변환한다.
/// "00:00"은 0을 반환한다 (자정 처리는 호출측에서 수행).
int parseTimeToMinutes(String time) {
  final parts = time.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// 노선 운행 스케줄 (배차간격 기반 시간표)
///
/// weekday/weekend는 상행(내선) 스케줄을 저장한다.
/// weekdayDown/weekendDown은 하행(외선) 전용 스케줄이며,
/// null이면 상행 스케줄과 동일하다는 의미이다.
@freezed
class LineSchedule with _$LineSchedule {
  const LineSchedule._();

  const factory LineSchedule({
    required String lineId,
    required DaySchedule weekday,
    required DaySchedule weekend,
    DaySchedule? weekdayDown,
    DaySchedule? weekendDown,
  }) = _LineSchedule;

  factory LineSchedule.fromJson(Map<String, dynamic> json) =>
      _$LineScheduleFromJson(json);

  /// 방향과 요일에 맞는 스케줄을 반환한다.
  /// [isDown]이 true이면 하행/외선 스케줄을 반환하되,
  /// 하행 전용 데이터가 없으면 상행 스케줄로 폴백한다.
  DaySchedule getSchedule(DateTime now, {bool isDown = false}) {
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    if (isDown) {
      return isWeekend ? (weekendDown ?? weekend) : (weekdayDown ?? weekday);
    }
    return isWeekend ? weekend : weekday;
  }
}

/// 요일별 운행 스케줄
///
/// [stationDepartures]는 역별 정확한 출발시각(자정 기준 분) 맵이다.
/// 키는 stationId, 값은 정렬된 분 단위 정수 배열이다.
/// 이 값이 있고 해당 역 데이터가 존재하면 배차간격 대신 정확한 시간표를 사용한다.
/// null이면 기존 배차간격([periods]) 기반 추정으로 폴백한다.
///
/// [expressStationDepartures]는 급행(9호선 등) 역별 정확한 출발시각 맵이다.
/// 구조는 [stationDepartures]와 동일하며, 완행(`t`)과 나란히 저장된다
/// (JSON의 `tE` 키). 급행 미정차역은 키 자체가 없거나 값이 제외된다.
/// 급행 모드 조회 시에만 사용하며, 급행 데이터가 없는 노선/역이면 null이다.
@freezed
class DaySchedule with _$DaySchedule {
  const DaySchedule._();

  const factory DaySchedule({
    required String firstTrain,
    required String lastTrain,
    required List<TimePeriod> periods,
    Map<String, List<int>>? stationDepartures,
    Map<String, List<int>>? expressStationDepartures,
  }) = _DaySchedule;

  factory DaySchedule.fromJson(Map<String, dynamic> json) =>
      _$DayScheduleFromJson(json);

  /// firstTrain을 분 단위로 반환 (예: "05:30" → 330)
  int get firstTrainMinutes => parseTimeToMinutes(firstTrain);

  /// lastTrain을 분 단위로 반환 (예: "00:00" → 1440)
  int get lastTrainMinutes {
    final minutes = parseTimeToMinutes(lastTrain);
    // "00:00"은 자정 = 1440분 (다음날)
    return minutes == 0 ? 1440 : minutes;
  }
}

/// 시간대별 배차간격
@freezed
class TimePeriod with _$TimePeriod {
  const TimePeriod._();

  const factory TimePeriod({
    required String start,
    required String end,
    required int headwayMinutes,
  }) = _TimePeriod;

  factory TimePeriod.fromJson(Map<String, dynamic> json) =>
      _$TimePeriodFromJson(json);

  /// start를 분 단위로 반환
  int get startMinutes => parseTimeToMinutes(start);

  /// end를 분 단위로 반환 (00:00 → 1440)
  int get endMinutes {
    final minutes = parseTimeToMinutes(end);
    return minutes == 0 ? 1440 : minutes;
  }
}
