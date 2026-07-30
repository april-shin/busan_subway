import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/subway_id_mapping.dart';
import '../../../core/utils/route_branch.dart';
import '../../../domain/entities/arrival_info.dart';
import '../../../domain/entities/connection.dart';
import '../../../domain/entities/line_schedule.dart';
import '../../../domain/entities/route_result.dart';
import '../../../domain/entities/station.dart';
import '../../../domain/usecases/find_next_departure.dart';
import 'direction_resolver.dart';

/// 출발 시각이 어느 소스에서 결정됐는지 나타낸다.
///
/// - [realtime]: 실시간 도착정보로 확정
/// - [timetable]: 역별 시간표 또는 배차간격 추정으로 확정
/// - [unavailable]: 둘 다 실패 — 운행 시간 외이거나 시간표 데이터 없음.
///   이 경우 반환된 시각은 조회 기준 시각 그대로이며 **실제 열차가 아니다.**
enum DepartureSource { realtime, timetable, unavailable }

/// 출발 시각 조회에 필요한 첫 세그먼트 컨텍스트.
///
/// 실제 계산(`computeDepartureTimeDetailed`)과 UI 의 선택 가능 시각 목록
/// (`buildDepartureCandidates`)이 **같은 (역, 방향, 급행여부, 노선)** 을 쓰도록
/// 단일 진실 공급원으로 추출했다. 둘이 어긋나면 "목록에 보이는데 고르면 다른
/// 열차가 잡히는" 현상이 생긴다.
///
/// 특히 `baseLine` 은 반드시 이 컨텍스트에서 가져와야 한다. 출발역이 환승역이라
/// 첫 세그먼트가 1역뿐이면 `segments.first.lineId` 는 방향 판별에 쓰인 세그먼트와
/// **다른 노선**이고, 모드 전환(`9M`)이면 시간표 맵에 아예 없는 키가 된다.
typedef DepartureContext = ({
  RouteSegment segment,
  bool isDown,
  bool express,
  String baseLine,
});

/// [DepartureContext] 를 추출한다.
/// 방향 판별이 가능한 세그먼트(역 2개 이상)가 없으면 null.
DepartureContext? resolveDepartureContext(RouteResult routeResult) {
  if (routeResult.segments.isEmpty) return null;

  // 방향 판별이 가능한 세그먼트를 찾는다 (역 2개 이상)
  final validSeg = findFirstDirectionalSegment(routeResult);
  if (validSeg == null) return null;

  return (
    segment: validSeg,
    isDown: isDownDirection(validSeg),
    express: isExpressLineId(validSeg.lineId),
    baseLine: baseLineId(validSeg.lineId),
  );
}

/// 시간표 기반 + 실시간 보정 방식으로 출발 시각과 그 **출처**를 계산한다.
///
/// 1순위: 실시간 도착정보가 있으면 이를 사용 (가장 정확, 방향+모드 필터)
/// 2순위: 시간표(배차간격)에서 다음 출발 시각을 추정 (방향별)
/// 3순위: 둘 다 없으면 조회 기준 시각을 그대로 반환 ([DepartureSource.unavailable])
///
/// 첫 세그먼트의 lineId가 `E`로 끝나는 가상 급행 노선이면 실시간 필터에서
/// `급행` trainType만 매칭한다.
///
/// 3순위 폴백은 "그 시각에 운행하는 열차가 없다"는 뜻이라, 사용자가 시각을 직접
/// 고르는 경우 화면이 이를 구분해 안내해야 한다. 반환 시각만으로는 구분할 수
/// 없어 [DepartureSource] 를 함께 돌려준다.
///
/// [stations]/[connections] 를 넘기면 실시간 필터에 **지선 판정**이 추가된다
/// (`천호 → 굽은다리` 경로의 5호선 하행 "마천행"처럼 노선·방향·모드가 같아도
/// 경로를 태워주지 않는 열차 제외). 로딩 전이라 비어 있으면 필터가 적용되지
/// 않는다 — fail-open.
({DateTime departure, DepartureSource source}) computeDepartureTimeDetailed({
  required AsyncValue<List<ArrivalInfo>> arrivalAsync,
  required RouteResult routeResult,
  required DateTime now,
  LineSchedule? lineSchedule,
  List<Station> stations = const [],
  List<Connection> connections = const [],
}) {
  final context = resolveDepartureContext(routeResult);
  if (context == null) {
    return (departure: now, source: DepartureSource.unavailable);
  }

  // 1순위: 실시간 도착정보로 보정 (방향+모드+지선 필터 적용)
  final realtimeDeparture = _getRealtimeDeparture(
    arrivalAsync: arrivalAsync,
    lineId: context.baseLine,
    isDown: context.isDown,
    now: now,
    expressOnly: context.express,
    staysOnRouteBranch: makeDestinationBranchFilter(
      // 급행 세그먼트는 정차역만 담고 있지만 판정이 "부분수열" 규칙이라 그대로
      // 넘겨도 안전하다(`trainPathCoversRoute` 참조). 역 ID 는 가상 급행
      // 노선에서도 base 노선의 것이므로 `baseLine` 과 짝이 맞는다.
      routeStationIds: [for (final s in context.segment.stations) s.id],
      lineId: context.baseLine,
      isDown: context.isDown,
      stations: stations,
      connections: connections,
    ),
  );
  if (realtimeDeparture != null) {
    return (departure: realtimeDeparture, source: DepartureSource.realtime);
  }

  // 2순위: 시간표 기반 추정 (방향별, 역별 시간표 포함)
  if (lineSchedule != null) {
    final timetableDeparture = findNextDeparture(
      schedule: lineSchedule,
      now: now,
      isDown: context.isDown,
      stationId: context.segment.stations.first.id,
      express: context.express,
    );
    if (timetableDeparture != null) {
      return (departure: timetableDeparture, source: DepartureSource.timetable);
    }
  }

  // 3순위: 현재 시각 반환 (운행 시간 외이거나 데이터 없음)
  return (departure: now, source: DepartureSource.unavailable);
}

/// `9E`처럼 `E`로 끝나는 가상 급행 노선 ID인지 판정.
///
/// 그래프 빌더가 생성하는 가상 급행 노선 ID 컨벤션은 `{base}E` (예: `9E`, `1E`).
/// 모드 전환 edge는 `{base}M` (예: `9M`)이므로 이 함수에서는 false.
/// 외부 모듈(라우터, UI, 시간표 조회 등)에서 이 컨벤션을 단일 진실 공급원에서 판정하기 위해 노출한다.
bool isExpressLineId(String lineId) => lineId.endsWith('E');

/// `9E` → `9`로 변환. 그 외는 그대로.
/// 실시간 도착정보 API와 시간표 데이터는 base 노선(`9`) 기준으로 응답하므로 매칭 시 변환 필요.
String baseLineId(String lineId) {
  if (lineId.endsWith('E')) {
    return lineId.substring(0, lineId.length - 1);
  }
  return lineId;
}

/// 경로 내 각 구간의 출발시각을 계산한다 (환승역 포함).
///
/// 출발역의 출발시각을 기준으로, 각 구간의 소요시간과 환승시간을
/// 순서대로 누적하여 구간별 출발시각 리스트를 반환한다.
///
/// [useExpress]가 true면 세그먼트의 `expressDurationSeconds`를 우선 사용한다
/// (없으면 `durationSeconds`로 폴백). 기본값은 false (완행).
///
/// 환승역에서의 출발시각 결정 우선순위:
/// 1순위: [transferArrivals]에서 해당 역의 실시간 데이터 (afterTransfer 이후 열차만)
/// 2순위: 시간표 기반 다음 출발
/// 3순위: afterTransfer 그대로 사용
///
/// [stations]/[connections] 의 역할은 [computeDepartureTimeDetailed] 와 같다
/// (환승 후 세그먼트에 지선 판정 추가, 미로딩 시 fail-open).
List<DateTime> computeSegmentDepartures({
  required RouteResult routeResult,
  required DateTime initialDeparture,
  required Map<String, LineSchedule> schedules,
  Map<String, AsyncValue<List<ArrivalInfo>>> transferArrivals = const {},
  required DateTime now,
  bool useExpress = false,
  List<Station> stations = const [],
  List<Connection> connections = const [],
}) {
  final departures = <DateTime>[initialDeparture];
  var currentTime = initialDeparture;

  for (var i = 0; i < routeResult.segments.length; i++) {
    final segment = routeResult.segments[i];
    // 구간 소요시간 (모드별)
    final durationSeconds = useExpress
        ? (segment.expressDurationSeconds ?? segment.durationSeconds)
        : segment.durationSeconds;
    // 구간 종료 시각
    final segmentEnd =
        currentTime.add(Duration(seconds: durationSeconds));

    if (i < routeResult.segments.length - 1) {
      // 환승 시간 추가
      final transferSeconds = i < routeResult.transferDurations.length
          ? routeResult.transferDurations[i]
          : 0;
      final afterTransfer =
          segmentEnd.add(Duration(seconds: transferSeconds));

      // 다음 구간 정보 (1역 세그먼트이면 방향 판별 불가 → false 폴백)
      final nextSegment = routeResult.segments[i + 1];
      final nextIsDown = nextSegment.stations.length >= 2
          ? isDownDirection(nextSegment)
          : false;
      final transferStationName = nextSegment.stations.first.name;

      // 1순위: 환승역 실시간 도착정보 (afterTransfer 이후 열차만 유효)
      // 다음 세그먼트가 급행(`{line}E`)이면 급행 trainType만 매칭한다.
      // 다음 세그먼트가 지선으로 갈라지는 노선이면, 그 구간을 태워주지 않는
      // 행선지의 열차는 제외한다(출발역과 같은 규칙).
      final arrivalAsync = transferArrivals[transferStationName];
      final nextIsExpress = isExpressLineId(nextSegment.lineId);
      final nextRealtimeLineId = baseLineId(nextSegment.lineId);
      DateTime? nextDeparture;
      if (arrivalAsync != null) {
        final minSeconds = afterTransfer.difference(now).inSeconds;
        nextDeparture = _getRealtimeDeparture(
          arrivalAsync: arrivalAsync,
          lineId: nextRealtimeLineId,
          isDown: nextIsDown,
          now: now,
          minArrivalSeconds: minSeconds,
          expressOnly: nextIsExpress,
          staysOnRouteBranch: makeDestinationBranchFilter(
            routeStationIds: [for (final s in nextSegment.stations) s.id],
            lineId: nextRealtimeLineId,
            isDown: nextIsDown,
            stations: stations,
            connections: connections,
          ),
        );
      }

      // 2순위: 시간표 기반 다음 출발 (역별 시간표 포함)
      // 시간표는 base 노선 ID로 인덱싱돼 있으므로 변환 후 조회.
      if (nextDeparture == null) {
        final nextSchedule = schedules[nextRealtimeLineId];
        if (nextSchedule != null) {
          nextDeparture = findNextDeparture(
            schedule: nextSchedule,
            now: afterTransfer,
            isDown: nextIsDown,
            stationId: nextSegment.stations.first.id,
            express: nextIsExpress,
          );
        }
      }

      // 3순위: afterTransfer 그대로 사용
      nextDeparture ??= afterTransfer;

      departures.add(nextDeparture);
      currentTime = nextDeparture;
    }
  }

  return departures;
}

/// 실시간 도착정보에서 해당 노선 + 방향의 가장 빠른 도착 열차를 찾는다.
///
/// [minArrivalSeconds]를 지정하면 해당 초 이상인 열차만 대상으로 한다.
/// 환승역에서는 사용자가 환승역에 도달하는 시점 이후의 열차만 유효하므로
/// `afterTransfer.difference(now).inSeconds`를 전달한다.
/// [expressOnly]가 true면 `trainType == '급행'`인 도착 정보만 매칭한다.
/// false면 급행/완행 구분 없이 가장 빠른 열차를 반환한다.
/// [staysOnRouteBranch]를 넘기면 행선지가 탑승 구간을 태워주지 않는 열차를
/// 제외한다 (지선 필터). null이면 지선 판정 없이 기존과 동일하게 동작한다.
DateTime? _getRealtimeDeparture({
  required AsyncValue<List<ArrivalInfo>> arrivalAsync,
  required String lineId,
  required bool isDown,
  required DateTime now,
  int minArrivalSeconds = 0,
  bool expressOnly = false,
  bool Function(String destination)? staysOnRouteBranch,
}) {
  return arrivalAsync.whenOrNull(
    data: (arrivals) {
      final matching = arrivals.where((a) {
        final mappedLineId = subwayIdToLineId[a.subwayId] ?? a.subwayId;
        if (mappedLineId != lineId) return false;
        if (isDownDirectionString(a.direction) != isDown) return false;
        if (a.arrivalSeconds == null) return false;
        if (a.arrivalSeconds! <= minArrivalSeconds) return false;
        if (expressOnly && a.trainType != '급행') return false;
        // 지선 판정은 그래프 탐색이 필요해 가장 비싸므로 맨 뒤에 둔다.
        if (staysOnRouteBranch != null &&
            !staysOnRouteBranch(a.destination)) {
          return false;
        }
        return true;
      }).toList();

      if (matching.isEmpty) return null;

      matching
          .sort((a, b) => a.arrivalSeconds!.compareTo(b.arrivalSeconds!));
      return now.add(Duration(seconds: matching.first.arrivalSeconds!));
    },
  );
}
