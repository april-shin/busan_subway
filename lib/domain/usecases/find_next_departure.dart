import '../entities/line_schedule.dart';

/// 배차간격 기반 시간표에서 다음 출발 시각을 계산한다.
///
/// [schedule]: 해당 노선의 스케줄 데이터
/// [now]: 현재 시각
/// [isDown]: 하행/외선 여부 (기본값 false = 상행/내선)
/// [stationId]: 역 ID (역별 시간표가 있는 노선에서 사용)
///
/// 역별 시간표([DaySchedule.stationDepartures])가 있고 해당 역 데이터가
/// 존재하면 이진탐색으로 정확한 다음 출발시각을 반환한다.
/// 없으면 기존 배차간격 기반 추정으로 폴백한다.
///
/// 운행 시간 내이면 현재 시각 + 남은 대기시간을 반환하고,
/// 운행 시간 외이면 null을 반환한다.
DateTime? findNextDeparture({
  required LineSchedule schedule,
  required DateTime now,
  bool isDown = false,
  String? stationId,
}) {
  final daySchedule = schedule.getSchedule(now, isDown: isDown);
  final currentMinutes = now.hour * 60 + now.minute;

  // 역별 시간표가 있으면 정확한 출발시각 반환
  if (stationId != null && daySchedule.stationDepartures != null) {
    final departures = daySchedule.stationDepartures![stationId];
    if (departures != null && departures.isNotEmpty) {
      return _findNextInSortedList(departures, now);
    }
  }

  // 폴백: 배차간격 기반 추정
  return _findNextByHeadway(daySchedule, now, currentMinutes);
}

/// 정렬된 출발분 목록에서 현재 시각 이후 가장 빠른 출발시각을 이진탐색한다.
///
/// 현재 시각 이후에 출발이 없으면 null을 반환한다 (운행 종료).
DateTime? _findNextInSortedList(List<int> sortedMinutes, DateTime base) {
  final current = base.hour * 60 + base.minute;
  // 이진탐색: current 초과인 첫 번째 값 (같은 분의 열차는 이미 출발로 간주)
  var lo = 0;
  var hi = sortedMinutes.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (sortedMinutes[mid] <= current) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo >= sortedMinutes.length) return null;
  return _minutesToDateTime(base, sortedMinutes[lo]);
}

/// 배차간격 기반으로 다음 출발 시각을 추정한다.
DateTime? _findNextByHeadway(
  DaySchedule daySchedule,
  DateTime now,
  int currentMinutes,
) {
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

/// 현재 시각 기준 예상 대기시간(분)을 반환한다.
///
/// 역별 시간표가 있으면 다음 출발까지 정확한 대기시간을 계산한다.
/// 없으면 배차간격의 절반(평균 대기시간)을 반환한다.
int getExpectedWaitMinutes({
  required LineSchedule schedule,
  required DateTime now,
  bool isDown = false,
  String? stationId,
}) {
  final daySchedule = schedule.getSchedule(now, isDown: isDown);
  final currentMinutes = now.hour * 60 + now.minute;

  // 역별 시간표가 있으면 정확한 대기시간 계산
  if (stationId != null && daySchedule.stationDepartures != null) {
    final departures = daySchedule.stationDepartures![stationId];
    if (departures != null && departures.isNotEmpty) {
      final nextDeparture = _findNextInSortedList(departures, now);
      if (nextDeparture != null) {
        final waitMinutes = nextDeparture.difference(now).inMinutes;
        return waitMinutes < 1 ? 1 : waitMinutes;
      }
      // 운행 종료 → 기본값
      return 0;
    }
  }

  // 폴백: 배차간격의 절반 (올림)
  final headway = _getHeadwayForTime(daySchedule, currentMinutes);
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
