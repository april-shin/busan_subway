import '../../../domain/entities/line_schedule.dart';
import 'departure_query_time.dart';

/// 출발역에서 실제로 선택 가능한 출발시각 목록(운영일 자정 기준 분)을 반환한다.
///
/// 조회 경로는 `findNextDeparture` 의 1순위 분기와 **정확히 동일**하다:
/// `getSchedule(anchorDate, isDown:)` → `express ? expressStationDepartures :
/// stationDepartures` → `[stationId]`. 두 경로가 어긋나면 "목록에 보이는데 고르면
/// 다른 열차가 잡히는" 현상이 생기므로 반드시 같이 유지해야 한다.
///
/// 역별 정확한 시간표가 없으면 **빈 리스트**를 반환한다. 배차간격(`periods`)으로
/// 추정 목록을 만들지 않는다 — 추정치를 시간표처럼 보여주면 사용자가 존재하지
/// 않는 열차를 고르게 되기 때문이다. 호출측은 빈 리스트를 "선택 불가"로 처리한다.
List<int> buildDepartureCandidates({
  required LineSchedule? schedule,
  required DateTime anchorDate,
  required bool isDown,
  required String stationId,
  required bool express,
}) {
  if (schedule == null) return const [];

  final daySchedule = schedule.getSchedule(anchorDate, isDown: isDown);
  final departureMap = express
      ? daySchedule.expressStationDepartures
      : daySchedule.stationDepartures;

  final departures = departureMap?[stationId];
  if (departures == null || departures.isEmpty) return const [];

  // 자정 넘김 열차의 인코딩이 노선마다 다르다 — 1440 이상으로 담는 노선(GTX-A
  // 24:27 → 1467)도 있고, 0~1439 로 담는 노선(경의중앙 00:01 → 1)도 있다.
  // 후자는 정렬상 목록 맨 앞으로 와서, 그리드에서 심야 열차가 첫차인 것처럼
  // 보인다. 종이 시간표 관례대로 뒤로 돌려 표시 순서를 통일한다.
  // **값 자체는 바꾸지 않는다** — 선택 시 그대로 써야 한다.
  final beforeCutoff = departures.where(_isLateNightEncoded).toList();
  if (beforeCutoff.isEmpty) return List.unmodifiable(departures);

  return List.unmodifiable([
    ...departures.where((m) => !_isLateNightEncoded(m)),
    ...beforeCutoff,
  ]);
}

/// 운행 공백 시간대(대략 01:00~05:00) 기준 고정 컷오프 — 04:00.
///
/// `daySchedule.firstTrainMinutes` 를 경계로 쓰면 안 된다. 그 값은 **노선 전체**
/// 첫차라서 역별 출발시각의 하한이 아니다. 차량기지 출고로 중간역이 노선 첫차보다
/// 먼저 출발하는 경우가 데이터에 대량으로 있다(2호선 202 상행 05:30 < 노선 05:39).
/// 그걸 경계로 쓰면 실제 아침 첫차 수천 건이 심야로 오판돼 목록 끝으로 밀리고,
/// 사용자가 그리드 맨 위 "05" 행에서 자기 첫차를 못 찾게 된다.
///
/// 실측(전 노선·전 역): 0~1439 로 인코딩된 심야 값은 전부 0시대(최대 00:39),
/// 아침 첫 출발은 최소 05:00 이라 04:00 컷오프는 양쪽에 충분한 여유가 있다.
/// (39, 300) 구간이 완전히 비어 있어 아래위로 각각 200분·60분 여유가 있다.
///
/// 시트의 초기 스크롤도 "지금이 심야인가"를 같은 기준으로 판정하므로 공개한다.
const lateNightCutoffMinutes = 240;

/// 자정 넘김인데 1440+ 가 아니라 0~1439 로 인코딩된 값인지.
/// 1440 이상 값은 이미 목록 끝에 정렬돼 있으므로 대상이 아니다.
bool _isLateNightEncoded(int minutes) => minutes < lateNightCutoffMinutes;

/// 고정 시각 조회에서 **탐색 없이 확정 가능한** 출발 시각을 돌려준다.
///
/// 고른 시각이 [candidates](= 이 경로의 실제 출발시각 목록)에 있으면 그것이
/// 곧 답이므로 `findNextDeparture` 를 다시 태우지 않는다. 다시 태우면 첫차가
/// 자정 직후인 노선(GTX-A "00:06")에서 심야 폴백 가드가 어긋나 **아침 첫차**가
/// 잡히는 등 엉뚱한 열차가 확정된다.
///
/// null 을 반환하는 경우 — 호출측이 기존 탐색 경로를 타야 한다:
/// - "지금 출발" 조회
/// - 고른 시각이 이 경로의 출발시각이 아닌 경우
///   (탭 간 시각 공유로 다른 노선에서 고른 값이 넘어왔을 때)
DateTime? resolveChosenDeparture({
  required DepartureQueryTime query,
  required List<int> candidates,
  required DateTime now,
}) {
  final minutes = query.minutes;
  if (minutes == null) return null;
  if (!candidates.contains(minutes)) return null;
  return materializeQueryDeparture(query, now);
}

/// 운영일 흐름 순서로 비교하기 위한 정렬 키.
///
/// 자정 넘김을 1440+ 로 담는 노선과 0~1439 로 담는 노선이 섞여 있어(GTX-A vs
/// 경의중앙), 원값끼리 비교하면 심야 열차가 하루의 시작으로 오인된다. 컷오프
/// 이전 값에 1440 을 더해 "첫차부터 막차까지"의 실제 순서로 정규화한다.
/// [buildDepartureCandidates] 의 표시 순서와 동일한 기준이다.
int operatingSortKey(int minutes) =>
    minutes < lateNightCutoffMinutes ? minutes + 1440 : minutes;

/// [nowMinutes](자정 기준 분) 시점에 아직 오지 않은 가장 이른 출발을 찾는다.
///
/// [candidates] 는 [buildDepartureCandidates] 가 돌려준 표시 순서 목록이어야
/// 한다(운영일 순). 막차가 이미 지났으면 null.
int? findUpcomingDeparture(List<int> candidates, int nowMinutes) {
  final nowKey = operatingSortKey(nowMinutes);
  for (final m in candidates) {
    if (operatingSortKey(m) >= nowKey) return m;
  }
  return null;
}

/// 시트를 열 때 스크롤을 맞출 행 index 를 고른다.
///
/// 우선순위: 이미 고른 시각 → 현재 시각 이후 첫 열차 → 마지막 행(막차 이후).
///
/// 두 앵커 모두 **칩 값으로** 행을 찾는다. 시(hour) 비교로 찾으면 안 된다 —
/// 심야 열차는 표시 순서상 목록 끝으로 옮겨져 있어(경의중앙 00:01 → 0시 행이
/// 맨 뒤) `hour >= 0` 같은 조건이 첫 행에 걸려 엉뚱하게 맨 위로 스크롤된다.
///
/// [rows] 가 비어 있으면 -1.
int resolveInitialScrollRow({
  required List<({int hour, List<int> minutes})> rows,
  required int? selectedMinutes,
  required int? upcomingMinutes,
}) {
  if (rows.isEmpty) return -1;

  final anchor = selectedMinutes ?? upcomingMinutes;
  if (anchor == null) return rows.length - 1;

  final index = rows.indexWhere((row) => row.minutes.contains(anchor));
  return index < 0 ? rows.length - 1 : index;
}

/// 출발시각 목록을 "시(hour) → 분(minute) 목록" 으로 묶는다.
///
/// 시간표 그리드 렌더링용. 키는 운영일 기준 시(0~28 등 1440 초과 값 포함)이며,
/// **입력 순서(=시각 오름차순)를 유지**하므로 자정 넘김(24시, 25시) 행이 자연스럽게
/// 목록 맨 끝에 온다. 표시 라벨은 `formatOperatingMinutes` 가 `% 24` 로 감싼다.
///
/// 입력은 정렬되어 있다고 가정한다(`stationDepartures` 계약).
List<({int hour, List<int> minutes})> groupDeparturesByHour(
  List<int> departures,
) {
  final grouped = <({int hour, List<int> minutes})>[];
  for (final minutes in departures) {
    final hour = minutes ~/ 60;
    if (grouped.isEmpty || grouped.last.hour != hour) {
      grouped.add((hour: hour, minutes: <int>[minutes]));
    } else {
      grouped.last.minutes.add(minutes);
    }
  }
  // 누적용 가변 리스트가 그대로 새어나가지 않도록 봉인한다
  // (`buildDepartureCandidates` 의 반환 계약과 맞춘다).
  return List.unmodifiable([
    for (final row in grouped)
      (hour: row.hour, minutes: List<int>.unmodifiable(row.minutes)),
  ]);
}
