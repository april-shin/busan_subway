import 'package:flutter/foundation.dart';

/// 시간표 조회 기준 요일 타입.
///
/// `line_schedules.json` 의 `wd`(평일) / `we`(주말) 구분과 1:1 대응한다.
/// (데이터상 `we` 는 일요일·공휴일 기준이며 토요일은 별도 모델링돼 있지 않다.)
enum DepartureDayType {
  weekday('평일'),
  weekend('주말');

  const DepartureDayType(this.label);

  final String label;
}

/// 사용자가 고른 경로 조회 기준 시각.
///
/// [minutes] 는 **운영일 자정 기준 분**이다. 자정을 넘긴 심야 열차는 1440 이상
/// 값을 갖는다(예: 1489 = 24:49 = 익일 00:49). `DaySchedule.stationDepartures`
/// 의 값 체계와 동일하므로, 시간표에서 고른 값을 그대로 담으면 된다.
///
/// [minutes] 가 null 이면 "지금 출발"(실시간 기준)이다.
@immutable
class DepartureQueryTime {
  final int? minutes;
  final DepartureDayType dayType;

  const DepartureQueryTime({
    this.minutes,
    required this.dayType,
  });

  /// "지금 출발" 상태를 만든다. 요일 타입은 [clock] 기준으로 새로 잡는다.
  ///
  /// [dayType] 은 [isNow] 일 때 계산에 전혀 쓰이지 않으므로(=`resolveQueryDateTime`
  /// 이 곧바로 현재 시각을 반환), 이전에 고른 값을 그대로 물고 있으면 조용히
  /// 남아 있다가 **다음에 시트를 열 때** 엉뚱한 요일 시간표를 먼저 보여준다.
  /// 예: 주말 20:29 를 골랐다가 "지금 출발로" 되돌리면, 화요일인데도 시트가
  /// 주말 탭으로 열린다. 그래서 되돌릴 때는 요일도 함께 오늘로 되돌린다.
  factory DepartureQueryTime.nowAt(DateTime clock) =>
      DepartureQueryTime(dayType: dayTypeOf(clock));

  /// "지금 출발" 여부. true 면 화면은 실시간 도착정보를 사용한다.
  bool get isNow => minutes == null;

  /// 이 조회가 실제로 가리키는 요일 타입. [clock] 은 현재 벽시계.
  ///
  /// [isNow] 일 때 [dayType] 을 그대로 믿으면 안 된다 — 위 [nowAt] 주석이 설명한
  /// 대로 그 상태의 [dayType] 은 계산에 쓰이지 않아 낡은 값이 남아 있을 수 있다.
  /// "이 조회는 어느 요일 시간표를 봐야 하나"를 묻는 곳은 모두 이 메서드를 쓴다
  /// (출발시각 시트의 초기 요일 판정, 급행 운행 요일 판정). 규칙을 호출부마다
  /// 복제하면 두 판정이 어긋나 "시트는 평일을 여는데 탭 판정은 주말 기준"이 된다.
  DepartureDayType effectiveDayType(DateTime clock) =>
      isNow ? dayTypeOf(clock) : dayType;

  /// [minutes] 는 nullable 이라 null 전달로 "비우기"를 표현할 수 없다 —
  /// `copyWith(minutes: null)` 은 **기존 값 유지**다. "지금 출발"로 되돌리려면
  /// [DepartureQueryTime.nowAt] 를 쓴다(요일까지 함께 정리된다).
  DepartureQueryTime copyWith({
    int? minutes,
    DepartureDayType? dayType,
  }) {
    return DepartureQueryTime(
      minutes: minutes ?? this.minutes,
      dayType: dayType ?? this.dayType,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DepartureQueryTime &&
      other.minutes == minutes &&
      other.dayType == dayType;

  @override
  int get hashCode => Object.hash(minutes, dayType);

  @override
  String toString() =>
      'DepartureQueryTime(minutes: $minutes, dayType: $dayType)';
}

/// 달력일의 요일 타입을 판정한다.
///
/// `LineSchedule.getSchedule` 과 동일한 규칙(토·일 → 주말)을 쓴다.
DepartureDayType dayTypeOf(DateTime date) {
  return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday
      ? DepartureDayType.weekend
      : DepartureDayType.weekday;
}

/// [type] 에 해당하는 조회 기준 달력일(시각 00:00)을 고른다.
///
/// 단순히 "요일 타입이 맞는 날"이면 되는 게 아니라 **그 전날도 같은 타입**이어야
/// 한다. `findNextDeparture` 가 심야(첫차 이전) 조회에서 `now.subtract(1 day)` 로
/// 전날 운영일 스케줄을 다시 보기 때문이다
/// (`_nextStationDeparture` / `_nextDepartureFromPrevOperatingDay`).
/// 전날이 다른 타입이면 24:xx 열차 조회가 엉뚱한 요일 시간표로 폴백된다.
///
/// - 평일: 화~금 (월요일은 전날이 일요일이라 제외)
/// - 주말: 일요일 (토요일은 전날이 금요일이라 제외)
///
/// 조건을 만족하면 오늘을, 아니면 조건을 만족하는 가장 가까운 이후 날짜를
/// 반환한다. 화면 표기는 `HH:mm` 뿐이라 이 날짜 자체는 사용자에게 노출되지 않는다.
DateTime anchorDateFor(DepartureDayType type, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (var offset = 0; offset < 7; offset++) {
    final candidate = today.add(Duration(days: offset));
    if (_isValidAnchor(type, candidate)) return candidate;
  }
  // 7일 안에 반드시 존재하므로 도달하지 않는다.
  return today;
}

/// 앵커일 조건: 해당일과 그 전날이 모두 [type] 과 같은 요일 타입.
bool _isValidAnchor(DepartureDayType type, DateTime date) {
  return dayTypeOf(date) == type &&
      dayTypeOf(date.subtract(const Duration(days: 1))) == type;
}

/// 조회 기준 시각을 계산기(`computeDepartureTimeDetailed` 등)에 넘길 `DateTime`
/// 으로 해석한다.
///
/// "지금 출발"이면 [now] 를 그대로 돌려준다.
///
/// 고정 시각이면 **선택한 시각보다 1분 이른 시각**을 돌려준다. 시간표 탐색
/// (`_findNextInSortedList`)이 strict `>` 비교라 "같은 분의 열차는 이미 출발"로
/// 간주하기 때문이다. 1분을 빼야 `findNextDeparture` 가 사용자가 고른 바로 그
/// 열차를 반환한다.
///
/// 1440 이상(자정 넘김) 값은 `DateTime` 생성자의 분 오버플로 정규화로 다음
/// 달력일이 된다. 이때 요일 타입이 뒤집혀도(예: 일요일 24:49 → 월요일 00:49)
/// 기존 전날-운영일 폴백이 올바른 시간표를 되찾는다.
///
/// [minutes] 가 0 인 경우 — 실데이터에 존재한다(경의중앙 K22 평일 상행,
/// K17·K32 주말 하행). 이 노선은 자정 넘김을 1440+ 가 아니라 0~1439 로
/// 인코딩하기 때문이다. 1분 빼기가 언더플로해 앵커 **전날** 23:59 가 되지만,
/// `anchorDateFor` 가 "앵커일과 전날이 같은 요일 타입"을 보장하므로 조회하는
/// 시간표 자체는 어긋나지 않는다.
///
/// 다만 이 경로로는 00:00 열차를 찾지 못한다(전날 23:59 이후 첫 열차를 찾게
/// 되므로). 그래서 사용자가 고른 시각은 이 함수가 아니라
/// `resolveChosenDeparture` 가 탐색 없이 확정한다 — 그쪽이 정상 경로다.
/// 여기로 오는 것은 "다른 탭에서 고른 시각이 넘어온" 폴백뿐이다.
DateTime resolveQueryDateTime(DepartureQueryTime query, DateTime now) {
  final minutes = query.minutes;
  if (minutes == null) return now;

  final anchor = anchorDateFor(query.dayType, now);
  return DateTime(anchor.year, anchor.month, anchor.day, 0, minutes - 1);
}

/// 선택한 출발시각을 **탐색 없이** 그대로 `DateTime` 으로 만든다.
///
/// 사용자가 시간표에서 고른 시각이 그 경로의 실제 출발시각이라는 것이 이미
/// 확인된 경우에만 쓴다. `findNextDeparture` 로 다시 찾게 하면 안 되는 이유:
///
/// - `_nextStationDeparture` 의 심야 폴백 가드가 `currentMinutes <
///   firstTrainMinutes` 인데, GTX-A 처럼 첫차가 자정 직후("00:06")인 노선은
///   24:27 을 골라도 이 조건이 거짓이 되어 폴백이 건너뛰어지고 **당일 아침
///   첫차**가 잡힌다.
/// - 노선마다 자정 넘김 인코딩이 달라(1440+ vs 0~1439) 탐색 기준 시각을
///   맞추기 어렵다. 경의중앙은 00:01 을 `1`로 담는다.
///
/// 이미 아는 답을 다시 찾지 않는 것이 두 경우 모두에 대한 근본 해결이다.
/// [DepartureQueryTime.minutes] 가 null 이면(= 지금 출발) null 을 반환한다.
DateTime? materializeQueryDeparture(DepartureQueryTime query, DateTime now) {
  final minutes = query.minutes;
  if (minutes == null) return null;

  final anchor = anchorDateFor(query.dayType, now);
  return DateTime(anchor.year, anchor.month, anchor.day, 0, minutes);
}

/// 운영일 기준 분을 `HH:mm` 로 포맷한다. 1440 이상은 24시간으로 감싼다.
/// 예: 492 → "08:12", 1489 → "00:49".
String formatOperatingMinutes(int minutes) {
  final hour = (minutes ~/ 60) % 24;
  final minute = minutes % 60;
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

/// 선택 상태를 사용자에게 보여줄 한 줄 라벨로 만든다.
/// 예: "지금 출발", "평일 08:12 출발".
String describeQueryTime(DepartureQueryTime query) {
  final minutes = query.minutes;
  if (minutes == null) return '지금 출발';
  return '${query.dayType.label} ${formatOperatingMinutes(minutes)} 출발';
}
