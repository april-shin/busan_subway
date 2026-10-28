import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/subway_id_mapping.dart';
import '../../../core/utils/ghost_train.dart';
import '../../../core/utils/line_direction.dart';
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
/// [stations]/[connections] 를 넘기면 실시간 필터에 **구간 완주 판정**이 추가된다
/// — 노선·방향·모드가 같아도 탑승 구간을 끝까지 태워주지 않는 열차는 제외한다
/// (`천호 → 굽은다리` 경로의 5호선 하행 "마천행"처럼 갈라지는 열차, `내방 → 장암`
/// 경로의 7호선 상행 "도봉산행"처럼 하차역 앞에서 끝나는 중간 종착 열차).
/// 로딩 전이라 비어 있으면 필터가 적용되지 않는다 — fail-open.
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
    routeStationIds: [for (final s in context.segment.stations) s.id],
    stations: stations,
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
    isGhostTrain: makeGhostTrainDetector(
      boardingStationId: context.segment.stations.first.id,
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
/// 급행 세그먼트는 가상 노선(`{base}E`)의 skip edge 가중치로 만들어지므로
/// `durationSeconds` 자체가 이미 급행 소요시간이다 — 모드별 분기가 필요 없다.
///
/// 환승 기준 시각은 "이전 구간 종료 + **환승 도보시간**"(afterWalk)이다.
/// `transferDurations` 에 섞여 있는 배차간격/2 대기 추정을 여기서 더하면,
/// 그 뒤에 다시 찾는 다음 열차 대기와 이중 계상된다.
///
/// 환승역에서의 출발시각 결정 우선순위:
/// 1순위: [transferArrivals]에서 해당 역의 실시간 데이터 (afterWalk 이후 열차만)
/// 2순위: 시간표 기반 다음 출발 (afterWalk 이후)
/// 3순위: 근거가 없을 때만 대기 추정 포함값(`transferDurations`)으로 폴백
///
/// [stations]/[connections] 의 역할은 [computeDepartureTimeDetailed] 와 같다
/// (환승 후 세그먼트에 구간 완주 판정 추가, 미로딩 시 fail-open).
List<DateTime> computeSegmentDepartures({
  required RouteResult routeResult,
  required DateTime initialDeparture,
  required Map<String, LineSchedule> schedules,
  Map<String, AsyncValue<List<ArrivalInfo>>> transferArrivals = const {},
  required DateTime now,
  List<Station> stations = const [],
  List<Connection> connections = const [],
}) {
  final departures = <DateTime>[initialDeparture];
  var currentTime = initialDeparture;

  for (var i = 0; i < routeResult.segments.length; i++) {
    final segment = routeResult.segments[i];
    // 구간 종료 시각
    final segmentEnd =
        currentTime.add(Duration(seconds: segment.durationSeconds));

    if (i < routeResult.segments.length - 1) {
      // 환승 도보시간만 더해 "승강장 도착 시각"을 만든다.
      //
      // `transferDurations`(= 환승 edge 가중치)에는 그래프 빌더가 얹은
      // 배차간격/2 대기 추정이 이미 섞여 있다. 그 값을 기준으로 다음 열차를
      // 다시 찾으면 "추정 대기 + 실제 다음 열차까지의 대기"가 이중 계상돼,
      // 환승 경로의 표시 시간만 부풀고 "최단시간이 최소환승보다 오래 걸린다"는
      // 역전이 화면에 노출된다(역삼→왕십리 등). 실제 대기는 아래 1·2순위가
      // 시각표/실시간으로 산출하므로 여기서는 도보시간만 더한다.
      final transferSeconds = i < routeResult.transferDurations.length
          ? routeResult.transferDurations[i]
          : 0;
      final walkSeconds = i < routeResult.transferWalkDurations.length
          ? routeResult.transferWalkDurations[i]
          : transferSeconds; // 레거시(도보 미분리) 데이터는 기존 동작 유지
      final afterWalk = segmentEnd.add(Duration(seconds: walkSeconds));

      // 다음 구간 정보 (1역 세그먼트이면 방향 판별 불가 → false 폴백)
      final nextSegment = routeResult.segments[i + 1];
      final nextIsDown = nextSegment.stations.length >= 2
          ? isDownDirection(nextSegment)
          : false;
      final transferStationName = nextSegment.stations.first.name;

      // 1순위: 환승역 실시간 도착정보 (afterWalk 이후 열차만 유효)
      // 다음 세그먼트가 급행(`{line}E`)이면 급행 trainType만 매칭한다.
      // 그 구간을 끝까지 태워주지 않는 행선지의 열차(지선 분기·중간 종착)는
      // 제외한다(출발역과 같은 규칙).
      final arrivalAsync = transferArrivals[transferStationName];
      final nextIsExpress = isExpressLineId(nextSegment.lineId);
      final nextRealtimeLineId = baseLineId(nextSegment.lineId);
      DateTime? nextDeparture;
      if (arrivalAsync != null) {
        final minSeconds = afterWalk.difference(now).inSeconds;
        nextDeparture = _getRealtimeDeparture(
          arrivalAsync: arrivalAsync,
          lineId: nextRealtimeLineId,
          isDown: nextIsDown,
          now: now,
          routeStationIds: [for (final s in nextSegment.stations) s.id],
          stations: stations,
          minArrivalSeconds: minSeconds,
          expressOnly: nextIsExpress,
          staysOnRouteBranch: makeDestinationBranchFilter(
            routeStationIds: [for (final s in nextSegment.stations) s.id],
            lineId: nextRealtimeLineId,
            isDown: nextIsDown,
            stations: stations,
            connections: connections,
          ),
          isGhostTrain: makeGhostTrainDetector(
            boardingStationId: nextSegment.stations.first.id,
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
            now: afterWalk,
            isDown: nextIsDown,
            stationId: nextSegment.stations.first.id,
            express: nextIsExpress,
          );
        }
      }

      // 3순위: 실시간·시간표 모두 없을 때만 그래프의 대기 추정(배차간격/2)이
      // 포함된 `transferSeconds` 로 폴백한다. 이 분기에는 실제 대기를 알려줄
      // 근거가 없으므로 추정치를 쓰는 편이 도보시간만 세는 것보다 낫다.
      nextDeparture ??= segmentEnd.add(Duration(seconds: transferSeconds));

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
/// [staysOnRouteBranch]를 넘기면 행선지가 탑승 구간을 끝까지 태워주지 않는
/// 열차를 제외한다 (지선 분기 + 중간 종착). null이면 판정 없이 동작한다.
/// [isGhostTrain]을 넘기면 **탑승역에 오지 않는 유령 열차**를 제외한다 — 종착이
/// 노선 중간인 열차(회차·셔틀)를 API 가 종착 너머 역에도 도착 예정으로 이어 붙인
/// 행이다(`ghost_train.dart`). 행선지만 보는 [staysOnRouteBranch] 와 달리 열차의
/// **현재역**까지 보므로, 탑승역보다 앞에서 끝나는 열차(예: 남태령 하행의 "사당행")를
/// 잡는다. 이름이 안 읽히거나 경로가 구해지지 않으면 통과시킨다(fail-open).
DateTime? _getRealtimeDeparture({
  required AsyncValue<List<ArrivalInfo>> arrivalAsync,
  required String lineId,
  required bool isDown,
  required DateTime now,
  required List<String> routeStationIds,
  List<Station> stations = const [],
  int minArrivalSeconds = 0,
  bool expressOnly = false,
  bool Function(String destination)? staysOnRouteBranch,
  bool Function(ArrivalInfo arrival)? isGhostTrain,
}) {
  // 2호선 성수지선처럼 API 라벨 극성이 구간 단위로 앱 규칙과 반대인 구간에서는
  // 라벨을 뒤집어 읽는다. 안 뒤집으면 **반대 방향 열차의 남은시간**이 출발 시각이
  // 된다 — 시간표 폴백이 아니라 틀린 실시간 값이라 더 나쁘다.
  //
  // 판정 단위는 **열차별 접근 쌍**이다(`apiLabelReversedForTrain` 주석 참조). 경로
  // 단위로 하면 분기역 성수 출발 지선 경로에서 본선 열차가 후보에 섞여, 더 자주
  // 오는 본선 열차가 "가장 빠른 열차" 로 뽑힌다 — 고치려던 증상이 역으로 재현된다.
  // 지도 방향 게이트(`live_train_provider`)와 같은 규칙을 쓴다.
  final apiLabelReversed = isApiLabelReversedOnRoute(lineId, routeStationIds);
  final boardingId = routeStationIds.firstOrNull;

  /// 현재역명 → 이 노선의 역 ID. 못 찾으면 null(접근 쌍 판정 불가).
  String? currentIdOf(ArrivalInfo a) {
    if (a.currentStationName.isEmpty) return null;
    for (final s in stations) {
      if (s.lineId == lineId && s.name == a.currentStationName) return s.id;
    }
    return null;
  }

  return arrivalAsync.whenOrNull(
    data: (arrivals) {
      final matching = arrivals.where((a) {
        final mappedLineId = subwayIdToLineId[a.subwayId] ?? a.subwayId;
        if (mappedLineId != lineId) return false;
        final trainReversed = apiLabelReversedForTrain(
          lineId: lineId,
          currentStationId: currentIdOf(a),
          boardingStationId: boardingId,
        );
        // 접근 쌍의 반전 여부가 경로와 다르면 이 경로의 열차가 아니다.
        // 반전 구간이 아닌 노선에서는 양쪽 다 false 라 아무도 떨어지지 않는다.
        if (trainReversed != apiLabelReversed) return false;
        var labelIsDown = isDownDirectionString(a.direction);
        if (trainReversed) labelIsDown = !labelIsDown;
        if (labelIsDown != isDown) return false;
        if (a.arrivalSeconds == null) return false;
        if (a.arrivalSeconds! <= minArrivalSeconds) return false;
        if (expressOnly && a.trainType != '급행') return false;
        // 지선 판정은 그래프 탐색이 필요해 가장 비싸므로 맨 뒤에 둔다.
        if (staysOnRouteBranch != null &&
            !staysOnRouteBranch(a.destination)) {
          return false;
        }
        if (isGhostTrain != null && isGhostTrain(a)) return false;
        return true;
      }).toList();

      if (matching.isEmpty) return null;

      matching
          .sort((a, b) => a.arrivalSeconds!.compareTo(b.arrivalSeconds!));
      return now.add(Duration(seconds: matching.first.arrivalSeconds!));
    },
  );
}
