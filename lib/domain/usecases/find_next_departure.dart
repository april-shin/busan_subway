import '../entities/line_schedule.dart';

/// 배차간격 기반 시간표에서 다음 출발 시각을 계산한다.
///
/// [schedule]: 해당 노선의 스케줄 데이터
/// [now]: 현재 시각
/// [isDown]: 하행/외선 여부 (기본값 false = 상행/내선)
///
/// 운행 시간 내이면 현재 시각 + 남은 대기시간을 반환하고,
/// 운행 시간 외이면 null을 반환한다.
DateTime? findNextDeparture({
  required LineSchedule schedule,
  required DateTime now,
  bool isDown = false,
}) {
  final daySchedule = schedule.getSchedule(now, isDown: isDown);
  // 분 단위로 계산 (초는 무시). 배차간격 추정이므로 분 단위 정밀도로 충분하다.
  final currentMinutes = now.hour * 60 + now.minute;

  // 운행 시간 외 체크
  final firstMin = daySchedule.firstTrainMinutes;
  final lastMin = daySchedule.lastTrainMinutes;
  if (currentMinutes < firstMin) {
    // 첫차 전 → 첫차 시간 반환
    return _minutesToDateTime(now, firstMin);
  }
  if (currentMinutes >= lastMin) {
    // 막차 이후 → 운행 종료
    return null;
  }

  // 현재 시간대의 배차간격 조회
  final headwayMinutes = _getHeadwayForTime(daySchedule, currentMinutes);

  // 현재 시간대 시작으로부터 배차간격으로 다음 출발 계산
  final period = _findPeriod(daySchedule, currentMinutes);
  if (period == null) return null;

  final periodStart = period.startMinutes;
  final elapsed = currentMinutes - periodStart;
  final intervalsPassed = elapsed ~/ headwayMinutes;
  final nextDepartureMinutes =
      periodStart + (intervalsPassed + 1) * headwayMinutes;

  // 다음 출발이 현재 시간대를 초과하면 다음 시간대 첫 열차
  if (nextDepartureMinutes >= period.endMinutes) {
    final nextPeriod = _findNextPeriod(daySchedule, period.endMinutes);
    if (nextPeriod == null) return null;
    return _minutesToDateTime(now, nextPeriod.startMinutes);
  }

  return _minutesToDateTime(now, nextDepartureMinutes);
}

/// 현재 시각 기준 배차간격(분)을 반환한다.
///
/// 시간표에서 특정 시간의 평균 대기시간 = 배차간격 / 2
int getExpectedWaitMinutes({
  required LineSchedule schedule,
  required DateTime now,
  bool isDown = false,
}) {
  final daySchedule = schedule.getSchedule(now, isDown: isDown);
  final currentMinutes = now.hour * 60 + now.minute;
  final headway = _getHeadwayForTime(daySchedule, currentMinutes);
  // 평균 대기시간 = 배차간격의 절반 (올림)
  return (headway / 2).ceil();
}

int _getHeadwayForTime(DaySchedule daySchedule, int currentMinutes) {
  final period = _findPeriod(daySchedule, currentMinutes);
  // 기본값: 마지막 시간대의 배차간격 또는 10분
  return period?.headwayMinutes ?? daySchedule.periods.lastOrNull?.headwayMinutes ?? 10;
}

TimePeriod? _findPeriod(DaySchedule daySchedule, int currentMinutes) {
  for (final period in daySchedule.periods) {
    if (currentMinutes >= period.startMinutes &&
        currentMinutes < period.endMinutes) {
      return period;
    }
  }
  return null;
}

TimePeriod? _findNextPeriod(DaySchedule daySchedule, int afterMinutes) {
  for (final period in daySchedule.periods) {
    if (period.startMinutes >= afterMinutes) {
      return period;
    }
  }
  return null;
}

DateTime _minutesToDateTime(DateTime base, int minutes) {
  return DateTime(base.year, base.month, base.day, minutes ~/ 60, minutes % 60);
}
