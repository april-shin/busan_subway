import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/arrival_info.dart';
import '../../../domain/entities/connection.dart';
import '../../../domain/entities/line_schedule.dart';
import '../../../domain/entities/route_result.dart';
import '../../../domain/entities/station.dart';
import 'departure_candidates.dart';
import 'departure_query_time.dart';
import 'departure_time_calculator.dart';

/// 경로 하나의 "언제 타서 언제 도착하나" 타임라인.
///
/// 결과 화면의 헤더(출발/도착/소요)와 탭 순서 판정이 **같은 값**을 보게 하려고
/// 계산을 한곳으로 모은 것이다. 둘이 각자 계산하면 화면에 보이는 도착시각과
/// 순서를 정한 근거가 갈라진다.
class RouteTiming {
  /// 실제 탑승 시각 (첫 세그먼트 열차의 출발).
  final DateTime departure;

  /// 목적지 도착 시각 (마지막 세그먼트 출발 + 그 구간 소요시간).
  final DateTime arrival;

  /// [departure] 의 근거 — 실시간/시간표/없음.
  final DepartureSource source;

  /// 세그먼트별 출발 시각 (환승 후 재승차 포함).
  final List<DateTime> segmentDepartures;

  const RouteTiming({
    required this.departure,
    required this.arrival,
    required this.source,
    required this.segmentDepartures,
  });

  /// 화면에 찍히는 "소요 N분" — 탑승부터 도착까지.
  ///
  /// 탑승 전 승강장 대기는 포함하지 않는다(헤더의 `출발 ~ 도착` 표기와 일치).
  /// 그래서 이 값은 서로 다른 경로를 비교하는 척도가 **아니다** — 비교는
  /// [arrival] 로 한다. 자세한 이유는 [compareByArrival] 참조.
  int get totalMinutes => arrival.difference(departure).inMinutes;
}

/// 사용자가 고른 출발시각이 이 경로에서 그대로 성립하는지 판정한다.
///
/// 성립하면(= 그 시각에 실제로 이 경로 첫 구간 열차가 있으면) 탐색 없이 그
/// 시각을 확정한다. `findNextDeparture` 는 기준 시각 **이후**의 열차를 찾으므로,
/// 고른 시각에 정확히 열차가 있어도 다음 배차로 밀린다 — 그것을 막는 장치다.
///
/// 결과 화면과 탭 순서 판정이 서로 다른 시각을 쓰지 않도록 두 곳이 이 함수를
/// 공유한다.
DateTime? resolveRouteChosenDeparture({
  required RouteResult routeResult,
  required DepartureQueryTime query,
  required Map<String, LineSchedule> schedules,
  required DateTime wallClock,
}) {
  final context = resolveDepartureContext(routeResult);
  if (context == null) return null;
  final schedule = schedules[context.baseLine];
  if (schedule == null) return null;

  final candidates = buildDepartureCandidates(
    schedule: schedule,
    anchorDate: anchorDateFor(query.dayType, wallClock),
    isDown: context.isDown,
    stationId: context.segment.stations.first.id,
    express: context.express,
  );
  return resolveChosenDeparture(
    query: query,
    candidates: candidates,
    now: wallClock,
  );
}

/// 경로 하나의 타임라인을 계산한다. 세그먼트가 없으면 null.
///
/// 실시간 도착정보는 "지금 출발"(`query.isNow`) 조회에서만 쓴다. 고정 시각
/// 조회에 현재 열차 위치를 섞으면 명백히 틀린 값이 나오므로, 그 경우 빈 데이터로
/// 대체해 시간표 경로로 떨어뜨린다.
///
/// [departureArrival]/[transferArrivals] 를 넘기지 않으면 시간표만으로 계산한다 —
/// 탭 순서 판정이 이 형태를 쓴다(실시간 갱신마다 탭이 나타났다 사라지지 않도록).
RouteTiming? computeRouteTiming({
  required RouteResult routeResult,
  required DepartureQueryTime query,
  required DateTime wallClock,
  required Map<String, LineSchedule> schedules,
  AsyncValue<List<ArrivalInfo>> departureArrival =
      const AsyncValue<List<ArrivalInfo>>.data([]),
  Map<String, AsyncValue<List<ArrivalInfo>>> transferArrivals = const {},
  List<Station> stations = const [],
  List<Connection> connections = const [],
}) {
  if (routeResult.segments.isEmpty) return null;

  final useRealtime = query.isNow;
  const noArrivals = AsyncValue<List<ArrivalInfo>>.data([]);
  final effectiveArrival = useRealtime ? departureArrival : noArrivals;
  final effectiveTransferArrivals = useRealtime
      ? transferArrivals
      : const <String, AsyncValue<List<ArrivalInfo>>>{};

  final now = resolveQueryDateTime(query, wallClock);
  final context = resolveDepartureContext(routeResult);
  final departureSchedule =
      context == null ? null : schedules[context.baseLine];

  final chosen = resolveRouteChosenDeparture(
    routeResult: routeResult,
    query: query,
    schedules: schedules,
    wallClock: wallClock,
  );
  final departureResult = chosen != null
      ? (departure: chosen, source: DepartureSource.timetable)
      : computeDepartureTimeDetailed(
          arrivalAsync: effectiveArrival,
          routeResult: routeResult,
          now: now,
          lineSchedule: departureSchedule,
          stations: stations,
          connections: connections,
        );

  final segmentDepartures = computeSegmentDepartures(
    routeResult: routeResult,
    initialDeparture: departureResult.departure,
    schedules: schedules,
    transferArrivals: effectiveTransferArrivals,
    now: now,
    stations: stations,
    connections: connections,
  );

  final arrival = segmentDepartures.last.add(
    Duration(seconds: routeResult.segments.last.durationSeconds),
  );

  return RouteTiming(
    departure: departureResult.departure,
    arrival: arrival,
    source: departureResult.source,
    segmentDepartures: segmentDepartures,
  );
}

/// 두 경로를 **도착 시각**으로 비교한다. [a] 가 먼저 도착하면 음수.
///
/// 경로 비교에 "소요시간"을 쓰면 비대칭이 생긴다 — 탑승 전 승강장 대기는
/// 총시간 밖(출발 시각이 곧 탑승 시각)인데 환승 대기는 총시간 안에 있어서,
/// 환승이 있는 경로만 대기를 떠안는다. 두 후보가 서로 다른 노선·방향에서
/// 출발하면 첫 대기 길이도 달라 비교가 더 흐트러진다.
///
/// 도착 시각은 같은 조회 시각을 기준으로 재므로 두 대기를 모두 포함한다 —
/// "지금 나서면 언제 도착하나"라는 사용자 질문에 그대로 대응한다.
///
/// 어느 한쪽이라도 시각을 구하지 못했으면(`unavailable`) 비교할 근거가 없다는
/// 뜻이므로 null 을 반환한다. 호출측은 이 경우 순서를 바꾸지 않는다.
int? compareByArrival(RouteTiming? a, RouteTiming? b) {
  if (a == null || b == null) return null;
  if (a.source == DepartureSource.unavailable ||
      b.source == DepartureSource.unavailable) {
    return null;
  }
  return a.arrival.compareTo(b.arrival);
}
