import '../entities/line_schedule.dart';

/// 배차간격 기반 시간표에서 다음 출발 시각을 계산한다.
///
/// [schedule]: 해당 노선의 스케줄 데이터
/// [now]: 현재 시각
/// [isDown]: 하행/외선 여부 (기본값 false = 상행/내선)
/// [stationId]: 역 ID (역별 시간표가 있는 노선에서 사용)
/// [express]: 급행 모드 여부 (기본값 false = 완행)
///
/// 역별 시간표가 있고 해당 역 데이터가 존재하면 이진탐색으로 정확한 다음
/// 출발시각을 반환한다. 없으면 기존 배차간격 기반 추정으로 폴백한다.
///
/// [express]가 true이면 급행 역별 시간표([DaySchedule.expressStationDepartures])만
/// 조회한다. 해당 역에 급행 데이터가 없으면(급행 미정차역 등) 완행 시간표로
/// 섞지 않고 곧바로 배차간격 폴백으로 넘어간다.
/// [express]가 false이면 완행 시간표([DaySchedule.stationDepartures])를 조회한다.
///
/// 운행 시간 내이면 현재 시각 + 남은 대기시간을 반환하고,
/// 운행 시간 외이면 null을 반환한다.
DateTime? findNextDeparture({
  required LineSchedule schedule,
  required DateTime now,
  bool isDown = false,
  String? stationId,
  bool express = false,
}) {
  final daySchedule = schedule.getSchedule(now, isDown: isDown);
  final currentMinutes = now.hour * 60 + now.minute;

  // 역별 시간표가 있으면 정확한 출발시각 반환 (모드에 맞는 맵만 조회)
  final departureMap = express
      ? daySchedule.expressStationDepartures
      : daySchedule.stationDepartures;
  if (stationId != null && departureMap != null) {
    final departures = departureMap[stationId];
    if (departures != null && departures.isNotEmpty) {
      return _nextStationDeparture(
        schedule: schedule,
        now: now,
        isDown: isDown,
        express: express,
        stationId: stationId,
        daySchedule: daySchedule,
        departures: departures,
      );
    }
  }

  // 폴백: 배차간격 기반 추정
  // (급행이지만 해당 역 급행 데이터가 없는 경우도 여기로 온다)
  return _findNextByHeadway(schedule, daySchedule, now, currentMinutes, isDown);
}

/// 역별 시간표에서 다음 출발 시각을 찾는다.
///
/// 자정 직후~오늘 첫차 사이(심야) 구간에서는, 오늘 스케줄의 자체 리스트에는
/// 아직 출발이 없더라도 "전날 운영일"이 자정을 넘겨 운행한 열차
/// (stationDepartures 내 1440분 이상 값)가 있을 수 있다. 이 경우 전날
/// 운영일의 요일 타입(평일/주말)으로 스케줄을 다시 선택해 우선 매칭한다.
/// 예: 토요일 00:10 조회 → 금요일(평일) 스케줄의 1440+ 출발분을 확인.
///
/// 전날 운영일에 실제로 자정 이후 출발분이 없으면(1440분 미만만 존재)
/// 기존과 동일하게 오늘 스케줄에서 첫차를 찾는다.
///
/// [express]가 true이면 전날 조회도 급행 시간표만 본다(완행과 섞지 않음).
DateTime? _nextStationDeparture({
  required LineSchedule schedule,
  required DateTime now,
  required bool isDown,
  required bool express,
  required String stationId,
  required DaySchedule daySchedule,
  required List<int> departures,
}) {
  final currentMinutes = now.hour * 60 + now.minute;

  if (currentMinutes < daySchedule.firstTrainMinutes) {
    final yesterday = now.subtract(const Duration(days: 1));
    final prevDaySchedule = schedule.getSchedule(yesterday, isDown: isDown);
    // 전날 운영일도 조회 모드(급행/완행)에 맞는 맵을 봐야 한다 —
    // 급행 조회가 완행 전날 출발분으로 폴백되면 안 된다.
    final prevMap = express
        ? prevDaySchedule.expressStationDepartures
        : prevDaySchedule.stationDepartures;
    final prevDepartures = prevMap?[stationId];
    if (prevDepartures != null &&
        prevDepartures.isNotEmpty &&
        prevDepartures.last >= 1440) {
      final prevResult = _findNextInSortedList(
        prevDepartures,
        currentMinutes + 1440,
        yesterday,
      );
      if (prevResult != null) return prevResult;
    }
  }

  return _findNextInSortedList(departures, currentMinutes, now);
}

/// 정렬된 출발분 목록에서 currentMinutes 초과인 가장 빠른 출발시각을 이진탐색한다.
///
/// [referenceDate]는 minutes=0(자정)이 가리키는 달력일이다. 오늘 스케줄
/// 조회 시에는 오늘 날짜를, 전날 운영일의 자정 이후(1440+) 출발분을 조회할
/// 때는 전날 날짜를 전달한다 — DateTime 생성자가 시/분 오버플로우를 자동으로
/// 다음날로 정규화하므로 실제 달력일이 올바르게 계산된다.
///
/// 현재 시각 이후에 출발이 없으면 null을 반환한다 (운행 종료).
DateTime? _findNextInSortedList(
  List<int> sortedMinutes,
  int currentMinutes,
  DateTime referenceDate,
) {
  // 이진탐색: currentMinutes 초과인 첫 번째 값 (같은 분의 열차는 이미 출발로 간주)
  var lo = 0;
  var hi = sortedMinutes.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (sortedMinutes[mid] <= currentMinutes) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo >= sortedMinutes.length) return null;
  return _minutesToDateTime(referenceDate, sortedMinutes[lo]);
}

/// 배차간격 기반으로 다음 출발 시각을 추정한다.
DateTime? _findNextByHeadway(
  LineSchedule schedule,
  DaySchedule daySchedule,
  DateTime now,
  int currentMinutes,
  bool isDown,
) {
  final firstMin = daySchedule.firstTrainMinutes;

  if (currentMinutes < firstMin) {
    // 첫차 전(심야). 전날 운영일이 자정을 넘겨 운행하는 배차 period가
    // 아직 진행 중일 수 있으므로 우선 확인한다(예: 우이신설 "19:30~00:40").
    final prev =
        _nextDepartureFromPrevOperatingDay(schedule, now, currentMinutes, isDown);
    if (prev != null) return prev;
    // 전날 자정 넘김 운행이 없으면 → 오늘 첫차 시간 반환
    return _minutesToDateTime(now, firstMin);
  }

  final lastMin = daySchedule.lastTrainMinutes;
  if (currentMinutes >= lastMin) {
    // 막차 이후 → 운행 종료
    return null;
  }

  return _nextInPeriod(daySchedule, currentMinutes, now, currentMinutes);
}

/// 자정 직후, 전날 운영일에 편성된 "자정 넘김" 배차 period에서 다음 출발을 찾는다.
///
/// [currentMinutes](0~1439)에 1440을 더한 값으로 전날 스케줄의 period를 조회한다.
/// 자정을 넘기는 period 는 [TimePeriod.endMinutes]가 1440을 초과하므로 이
/// 보정된 시각으로만 매칭된다. 요일 타입도 전날 기준으로 재선택한다
/// (예: 토요일 00:20 조회 → 금요일=평일 스케줄). 전날에 자정 넘김 period 가
/// 없거나 이미 그 막차가 지났으면 null을 반환한다.
DateTime? _nextDepartureFromPrevOperatingDay(
  LineSchedule schedule,
  DateTime now,
  int currentMinutes,
  bool isDown,
) {
  final yesterday = now.subtract(const Duration(days: 1));
  final prevSchedule = schedule.getSchedule(yesterday, isDown: isDown);
  final boosted = currentMinutes + 1440;
  return _nextInPeriod(prevSchedule, boosted, yesterday, boosted);
}

/// [lookupMinutes]가 속한 배차 period에서 다음 출발 시각을 계산한다.
///
/// [referenceDate]는 반환 DateTime의 기준일(자정=0이 가리키는 달력일)이다.
/// 전날 운영일의 자정 넘김(1440+) 조회 시에는 전날 날짜를 넘긴다 —
/// DateTime 생성자가 24:xx 를 다음날로 정규화하므로 실제 달력일이 맞춰진다.
/// [nowMinutes]는 배차 계산의 경과시간 기준(lookupMinutes와 동일 좌표계)이다.
DateTime? _nextInPeriod(
  DaySchedule daySchedule,
  int lookupMinutes,
  DateTime referenceDate,
  int nowMinutes,
) {
  final period = _findPeriod(daySchedule, lookupMinutes);
  if (period == null) return null;

  final headwayMinutes = period.headwayMinutes;
  final periodStart = period.startMinutes;
  final elapsed = nowMinutes - periodStart;
  final intervalsPassed = elapsed ~/ headwayMinutes;
  final nextDepartureMinutes =
      periodStart + (intervalsPassed + 1) * headwayMinutes;

  // 다음 출발이 현재 시간대를 초과하면 다음 시간대 첫 열차
  if (nextDepartureMinutes >= period.endMinutes) {
    final nextPeriod = _findNextPeriod(daySchedule, period.endMinutes);
    if (nextPeriod == null) return null;
    return _minutesToDateTime(referenceDate, nextPeriod.startMinutes);
  }

  return _minutesToDateTime(referenceDate, nextDepartureMinutes);
}

/// 현재 시각 기준 예상 대기시간(분)을 반환한다.
///
/// 역별 시간표가 있으면 다음 출발까지 정확한 대기시간을 계산한다.
/// 없으면 배차간격의 절반(평균 대기시간)을 반환한다.
///
/// [express]가 true이면 급행 역별 시간표만 조회하며, 해당 역에 급행 데이터가
/// 없으면 완행과 섞지 않고 배차간격 폴백으로 넘어간다.
int getExpectedWaitMinutes({
  required LineSchedule schedule,
  required DateTime now,
  bool isDown = false,
  String? stationId,
  bool express = false,
}) {
  final daySchedule = schedule.getSchedule(now, isDown: isDown);
  final currentMinutes = now.hour * 60 + now.minute;

  // 역별 시간표가 있으면 정확한 대기시간 계산 (모드에 맞는 맵만 조회)
  final departureMap = express
      ? daySchedule.expressStationDepartures
      : daySchedule.stationDepartures;
  if (stationId != null && departureMap != null) {
    final departures = departureMap[stationId];
    if (departures != null && departures.isNotEmpty) {
      final nextDeparture = _nextStationDeparture(
        schedule: schedule,
        now: now,
        isDown: isDown,
        express: express,
        stationId: stationId,
        daySchedule: daySchedule,
        departures: departures,
      );
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
