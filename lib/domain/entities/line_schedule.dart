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
@freezed
class DaySchedule with _$DaySchedule {
  const DaySchedule._();

  const factory DaySchedule({
    required String firstTrain,
    required String lastTrain,
    required List<TimePeriod> periods,
    Map<String, List<int>>? stationDepartures,
  }) = _DaySchedule;

  factory DaySchedule.fromJson(Map<String, dynamic> json) =>
      _$DayScheduleFromJson(json);

  /// firstTrain을 분 단위로 반환 (예: "05:30" → 330)
  int get firstTrainMinutes => parseTimeToMinutes(firstTrain);

  /// lastTrain을 분 단위로 반환 (예: "00:00" → 1440, "00:50" → 1490)
  ///
  /// 자정 이후 막차(예: "00:30"~"00:59")는 firstTrain보다 작은 값으로
  /// 파싱되므로, firstTrain **이하**이면 다음날로 넘어간 것으로 보고 1440을
  /// 더한다("00:00"도 0 ≤ firstTrain 이라 1440으로 보정됨).
  /// firstTrain 자체가 자정 근처인 데이터 이상 케이스(예: 1호선 "00:00",
  /// 서해 상행 "00:01")는 lastTrain이 firstTrain보다 커서 걸리지 않는다.
  ///
  /// 여기서는 등호(`<=`)를 쓴다 — [TimePeriod.endMinutes]는 길이 0(start==end)
  /// 구간을 보존해야 해서 `<` 를 쓰지만, 막차는 first==last 퇴화 데이터를
  /// "종일 운행"으로 완화(롤오버)하는 편이 안전하며 이를 걸러내는 소비처도 없다.
  int get lastTrainMinutes {
    final minutes = parseTimeToMinutes(lastTrain);
    return minutes <= firstTrainMinutes ? minutes + 1440 : minutes;
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

  /// end를 분 단위로 반환 (예: "00:00" → 1440, "00:40" → 1480)
  ///
  /// "00:00"은 하루의 끝(자정) = 1440 관례를 유지한다. 그 외 종료 시각이
  /// 시작 시각보다 작으면 자정을 넘긴 시간대로 보고 1440을 더한다.
  /// 예: "16:30"~"00:40" period 는 end=40 < start(990) 이므로 1480.
  ///
  /// start == end 인 길이 0(비정상) 구간은 보정하지 않는다 —
  /// [DaySchedule.lastTrainMinutes] 와 동일한 규칙이며, 이 구간을 걸러내는
  /// 상위 소비처(headway_estimator의 `end <= start` 가드)를 무력화하지 않기 위함.
  int get endMinutes {
    final minutes = parseTimeToMinutes(end);
    if (minutes == 0) return 1440;
    return minutes < startMinutes ? minutes + 1440 : minutes;
  }
}
