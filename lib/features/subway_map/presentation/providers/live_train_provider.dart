// ⛔ 실시간 열차 애니메이션 4원칙 — 변경 금지 (CLAUDE.md 최상위 정책)
//   이 프로바이더는 JS 애니메이션에 전달되는 `LiveTrain` 을 생성한다. 아래 두
//   필드의 "기준 시각" 계약은 4원칙의 원칙 1 (단조 감소 카운트다운) 구현의 핵심이다.
//   - `arrivalSeconds`: API 원본 또는 추정값 (척도 정차 포함)
//   - `receivedAtEpochMs`: 해당 값의 기준 시각 (API 는 recptnDt, 추정은 추정 시각)
//   JS 가 `realRemaining = arrivalSeconds − (now − receivedAtEpochMs)/1000` 으로
//   매 frame 실시간 남은시간을 계산한다. Dart 에서 elapsed 를 선차감하면 JS 가
//   이중 차감하므로 **절대 금지**. 변경 전 CLAUDE.md 4원칙 섹션 확인.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart'; // StateProvider (riverpod 3 레거시)
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/dwell_time.dart';
import '../../../../core/constants/subway_id_mapping.dart';
import '../../../../core/utils/enrich_arrival_info.dart';
import '../../../../core/utils/expand_path_backward.dart';
import '../../../../core/utils/path_on_line.dart';
import '../../../../domain/entities/arrival_info.dart';
import '../../../../domain/entities/station.dart';
import '../../../arrival_info/presentation/providers/arrival_providers.dart';
import '../../../route_search/utils/direction_resolver.dart';
import '../providers/subway_map_providers.dart';

part 'live_train_provider.g.dart';

/// JS로 전달할 개별 열차 데이터
class LiveTrain {
  final String trainNo;
  final String lineId;
  final String direction;
  final String destination;
  final String message;
  final int arrivalSeconds;
  final String currentStation;
  final int? arrivalCode;
  final String positionStatus;
  final double fromSvgX;
  final double fromSvgY;
  final List<({double x, double y})> pathToTarget;

  /// 세그먼트별 "주행시간만" (초). 중간역 정차시간(dwell)은 포함하지 않는다.
  /// JS 측은 매 frame 남은시간 역산 시 이 값과 [dwellSeconds]를 분리 사용한다.
  final List<int> segmentDurations;

  /// 중간역 정차시간 상수(초). 현재는 항상 0으로 전달한다 — 정차 시각화는
  /// JS 의 "segmentIndex > 0 ⇒ 첫 세그먼트 95% 고정" 클램프가 대신 표현한다.
  /// 필드 자체는 JS 계약(`estimateTrainPosition`)과의 호환을 위해 유지.
  final int dwellSeconds;

  /// [arrivalSeconds] 가 측정된 기준 시각(epoch ms).
  /// JS 측은 이 시각과 현재 시각의 차이로 실제 남은시간을 계산한다.
  final int receivedAtEpochMs;

  /// 호환성용 필드. 신규 JS 로직은 읽지 않음. 항상 0.0 권장.
  final double initialProgress;

  /// `pathToTarget` 상 arvlMsg3("현재역")의 index. 경로가 `expandPathBackward`로
  /// 확장된 경우 0이 아닐 수 있다. 예: path=[구반포, 신반포, 고속터미널, 사평,
  /// 신논현] 에서 arvlMsg3="신반포" 이면 `currentStationIndex = 1`.
  /// JS 는 이 값을 기준으로 3-way 클램프 분기에 사용한다.
  final int currentStationIndex;

  /// 열차 종류 (`'급행'`, `'일반'`, `'특급'` 등). 실시간 API의 `btrainSttus`에서 옴.
  /// JS 측은 `'급행'`이면 마커에 빨간 "급" 딱지를 그린다.
  final String trainType;

  const LiveTrain({
    required this.trainNo,
    required this.lineId,
    required this.direction,
    required this.destination,
    required this.message,
    required this.arrivalSeconds,
    required this.currentStation,
    this.arrivalCode,
    this.positionStatus = '',
    required this.fromSvgX,
    required this.fromSvgY,
    required this.pathToTarget,
    this.segmentDurations = const [],
    required this.dwellSeconds,
    required this.receivedAtEpochMs,
    this.initialProgress = 0.0,
    this.currentStationIndex = 0,
    this.trainType = '일반',
  });

  Map<String, dynamic> toJson() => {
        'trainNo': trainNo,
        'lineId': lineId,
        'direction': direction,
        'destination': destination,
        'message': message,
        'arrivalSeconds': arrivalSeconds,
        'currentStation': currentStation,
        'arrivalCode': arrivalCode,
        'positionStatus': positionStatus,
        'fromSvgX': fromSvgX,
        'fromSvgY': fromSvgY,
        'pathToTarget': [
          for (final p in pathToTarget) {'x': p.x, 'y': p.y},
        ],
        'segmentDurations': segmentDurations,
        'dwellSeconds': dwellSeconds,
        'receivedAtEpochMs': receivedAtEpochMs,
        'initialProgress': initialProgress,
        'currentStationIndex': currentStationIndex,
        'trainType': trainType,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveTrain &&
          trainNo == other.trainNo &&
          lineId == other.lineId &&
          arrivalSeconds == other.arrivalSeconds &&
          currentStation == other.currentStation;

  @override
  int get hashCode =>
      Object.hash(trainNo, lineId, arrivalSeconds, currentStation);
}

/// 추정값 캐시 엔트리: 초단위 도착시간 없는 열차의 최초 추정값과 시점을 보존
class _EstimateEntry {
  final int estimate;
  final DateTime estimatedAt;
  final String currentStation;
  final String positionStatus;

  const _EstimateEntry({
    required this.estimate,
    required this.estimatedAt,
    required this.currentStation,
    required this.positionStatus,
  });
}

/// 추정값 캐시: 역 정보 변경 시에만 재추정하여 카운트다운 리셋 방지
final _estimateCacheProvider =
    StateProvider<Map<String, _EstimateEntry>>((ref) => {});

/// 네트워크 오류 시 마지막 성공 데이터를 유지하기 위한 캐시.
///
/// 계산에 쓰인 `ActiveRouteFilter` 를 함께 보관한다. 필터(노선+방향)가 바뀐 뒤의
/// API 실패에서 이전 필터의 열차를 그대로 돌려주면, 새 경로와 무관한 노선의
/// 열차가 지도에 남는다(도착역만 바꿨을 때의 잔류 열차와 같은 증상).
final _lastSuccessfulTrainsProvider = StateProvider<
    ({ActiveRouteFilter filter, List<LiveTrain> trains})?>((ref) => null);

/// enrichment 추정값 캐시: 동일 열차·동일 위치에서 추정값 재사용으로 카운트다운 안정화
final _lastEnrichedArrivalsProvider =
    StateProvider<List<ArrivalInfo>>((ref) => []);

/// API 가 보고하는 currentStationName 에서 부역명 괄호를 제거한다.
/// 예: "오목교(목동운동장앞)" → "오목교", "신정(은행정)" → "신정".
/// stations.json 내부 이름과 매칭이 가능하도록 정규화. 괄호가 없으면 그대로 반환.
final _stationAliasPattern = RegExp(r'\s*\([^)]*\)\s*');
String _stripStationAlias(String name) =>
    name.replaceAll(_stationAliasPattern, '').trim();

/// 실시간 열차 데이터를 가공하여 반환하는 프로바이더.
///
/// 출발역이 선택되어 있을 때만 활성화되며, `ApiConstants.refreshInterval`
/// 타이머로 자동 새로고침한다.
@riverpod
Future<List<LiveTrain>> liveTrains(Ref ref) async {
  final selected = ref.watch(selectedStationsProvider);
  if (!selected.isComplete) return [];

  // 활성 경로 필터 (노선 + 방향)
  final routeFilter = ref.watch(activeRouteFilterProvider);
  if (routeFilter == null) return [];

  final departureStation = selected.departure!;
  final departureStationName = departureStation.name;

  // `ApiConstants.refreshInterval` 주기로 자동 새로고침.
  // arrivalInfoProvider 를 watch 하고 있으므로 invalidate 만 하면 자동 재계산됨.
  final timer = Timer(ApiConstants.refreshInterval, () {
    ref.invalidate(arrivalInfoProvider(departureStationName));
  });
  ref.onDispose(timer.cancel);

  // 도착 정보 API 호출
  final List<ArrivalInfo> arrivals;
  try {
    arrivals =
        await ref.watch(arrivalInfoProvider(departureStationName).future);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('실시간 열차 데이터 로드 실패: $e\n$st');
    }
    // 네트워크 오류 시 마지막 성공 데이터 반환 (기존 애니메이션 유지).
    // 단, 그 데이터가 현재 활성 경로 필터에서 계산된 것일 때만 — 필터가 바뀐
    // 뒤라면 이전 노선·방향의 열차이므로 재사용하지 않고 비운다.
    final cached = ref.read(_lastSuccessfulTrainsProvider);
    if (cached != null && cached.filter == routeFilter) return cached.trains;
    return const [];
  }

  // stations와 connections 로드
  final stations = await ref.watch(allStationsProvider.future);
  final connections = await ref.watch(allConnectionsProvider.future);

  // 8호선 등 barvlDt를 제공하지 않는 노선 대응: arrivalSeconds가 null이면
  // 경로/역 수 기반으로 추정값을 채워 넣는다.
  // previousArrivals를 전달하여 동일 열차·동일 위치에서 추정값을 재사용,
  // 15초마다 카운트다운이 리셋되는 현상을 방지한다.
  final enrichedArrivals = enrichArrivalInfoList(
    arrivals: arrivals,
    targetStationName: departureStationName,
    stations: stations,
    connections: connections,
    previousArrivals: ref.read(_lastEnrichedArrivalsProvider),
  );
  ref.read(_lastEnrichedArrivalsProvider.notifier).state = enrichedArrivals;

  // 역명 → Station 매핑 (SVG 좌표 조회용)
  final stationsByName = <String, List<Station>>{};
  for (final s in stations) {
    stationsByName.putIfAbsent(s.name, () => []).add(s);
  }

  // ID → Station 매핑 (경로 확장 시 이전 역 Station 조회용).
  final stationsById = <String, List<Station>>{};
  for (final s in stations) {
    stationsById.putIfAbsent(s.id, () => []).add(s);
  }

  final estimateCache = Map<String, _EstimateEntry>.from(
    ref.read(_estimateCacheProvider),
  );

  final result = <LiveTrain>[];

  for (final arrival in enrichedArrivals) {
    // subwayId → lineId 변환
    final lineId = subwayIdToLineId[arrival.subwayId];
    if (lineId == null) continue;

    // 활성 경로의 노선만 필터링
    if (lineId != routeFilter.lineId) continue;

    // 방향 필터링: 활성 경로 방향과 일치하는 열차만
    final trainIsDown = isDownDirectionString(arrival.direction);
    if (trainIsDown != routeFilter.isDown) continue;

    // 현재 위치 역명 → stations.json 매칭.
    // 두 방향의 괄호 표기를 모두 처리하기 위해 "정확 매칭 우선, strip 은 폴백"으로 둔다.
    //  - 정식명에 괄호가 있는 역(예: "관악산(서울대)", "총신대입구(이수)"): 그대로 매칭.
    //    (DTO 인바운드 복원이 arvlMsg3 를 정식명으로 되돌려 놓음)
    //  - API 가 부역명을 덧붙인 경우(예: "오목교(목동운동장앞)" → stations.json "오목교",
    //    "신정(은행정)" → "신정"): 정확 매칭 실패 후 strip 으로 복원.
    // strip 을 무조건 적용하면 전자의 괄호를 벗겨 lookup 이 실패하므로 순서가 중요하다.
    final rawName = arrival.currentStationName;
    final currentName =
        stationsByName.containsKey(rawName) ? rawName : _stripStationAlias(rawName);
    if (currentName.isEmpty) continue;

    // 현재역의 SVG 좌표 조회 (같은 노선의 역 우선). 경로 확장 시작점으로 필요.
    final candidates = stationsByName[currentName];
    if (candidates == null || candidates.isEmpty) continue;
    final currentStation = candidates.firstWhere(
      (s) => s.lineId == lineId,
      orElse: () => candidates.first,
    );

    // 현재역 → 출발역 경유 좌표 및 세그먼트 소요시간 계산
    final pathResult = findPathOnLine(
      fromStationName: currentName,
      toStationName: departureStationName,
      lineId: lineId,
      stations: stations,
      connections: connections,
      isDown: routeFilter.isDown,
    );

    // 경로를 찾을 수 없으면 건너뜀
    if (pathResult == null || pathResult.points.isEmpty) continue;

    // trainNo가 비어있으면 고유 식별 불가 → 건너뜀
    if (arrival.trainNo.isEmpty) continue;

    final initialProgress = calculateInitialProgress(
      arrival.arrivalCode,
      arrival.positionStatus,
    );

    // 도착 예상 초: API 값이 있으면 원본 그대로, 없으면 구간 합산으로 추정.
    // 원칙 1: 매 frame 실시간 남은시간 계산은 JS 측에서 `receivedAtEpochMs`
    // 기준으로 수행한다. 따라서 Dart 는 elapsed 선차감을 하지 않고 값과
    // 기준 시각(recptnDt 또는 추정 시각) 한 쌍을 그대로 통과시킨다.
    final cacheKey = '${arrival.trainNo}_$lineId';
    final int arrivalSecs;
    final int receivedAtEpochMs;
    if (arrival.arrivalSeconds != null) {
      // API 제공값 → 캐시 불필요. 기준 시각 = arrival.receivedAt (API recptnDt).
      estimateCache.remove(cacheKey);
      arrivalSecs = arrival.arrivalSeconds!;
      receivedAtEpochMs = arrival.receivedAt.millisecondsSinceEpoch;
    } else {
      final cached = estimateCache[cacheKey];
      if (cached != null &&
          cached.currentStation == currentName &&
          cached.positionStatus == arrival.positionStatus) {
        // 역 정보 동일 → 최초 추정값 재사용. 기준 시각 = 추정 시점.
        arrivalSecs = cached.estimate;
        receivedAtEpochMs = cached.estimatedAt.millisecondsSinceEpoch;
      } else {
        // 새 열차 또는 역 변경 → 새로 추정.
        // durations 는 주행시간만. 중간역(durations.length - 1 개)마다
        // dwellTimeSeconds 를 더해 enrich/API 값과 같은 척도를 유지한다.
        final durations = pathResult.durations;
        final int newEstimate;
        if (durations.isEmpty) {
          newEstimate = 0;
        } else {
          final firstAdj =
              (durations.first * (1.0 - initialProgress)).round();
          final travelSecs =
              firstAdj + durations.skip(1).fold<int>(0, (a, b) => a + b);
          final dwellStops = math.max(0, durations.length - 1);
          newEstimate = travelSecs + dwellStops * dwellTimeSeconds;
        }
        final now = DateTime.now();
        estimateCache[cacheKey] = _EstimateEntry(
          estimate: newEstimate,
          estimatedAt: now,
          currentStation: currentName,
          positionStatus: arrival.positionStatus,
        );
        arrivalSecs = newEstimate;
        receivedAtEpochMs = now.millisecondsSinceEpoch;
      }
    }

    // 남은시간이 현재 pathToTarget 총시간보다 크면 이전 역을 prepend 해 경로 확장.
    // (순환선 방어 + 30칸 상한은 expandPathBackward 내부에서 처리)
    final expanded = expandPathBackward(
      basePoints: pathResult.points,
      baseDurations: pathResult.durations,
      currentStationId: currentStation.id,
      lineId: lineId,
      isDown: routeFilter.isDown,
      connections: connections,
      stationsById: stationsById,
      targetRemainingSeconds: arrivalSecs < 0 ? 0 : arrivalSecs,
    );

    // arvlMsg3("현재역") 의 확장된 path 상 새 index = prepend 된 역 수.
    final currentStationIndex =
        expanded.points.length - pathResult.points.length;
    final safeArrivalSecs = arrivalSecs < 0 ? 0 : arrivalSecs;

    result.add(LiveTrain(
      trainNo: arrival.trainNo,
      lineId: lineId,
      direction: arrival.direction,
      destination: arrival.destination,
      message: arrival.arrivalMessage,
      arrivalSeconds: safeArrivalSecs,
      currentStation: currentName,
      arrivalCode: arrival.arrivalCode,
      positionStatus: arrival.positionStatus,
      fromSvgX: expanded.points.first.x,
      fromSvgY: expanded.points.first.y,
      pathToTarget: expanded.points,
      segmentDurations: expanded.durations,
      dwellSeconds: 0,
      // 원칙 1: arrivalSeconds 와 쌍으로 "기준 시각" 을 통과시킨다.
      //   - API 제공 값: arrival.receivedAt (API recptnDt)
      //   - 캐시 추정 재사용: 최초 추정 시각
      //   - 새 추정: 지금 시각
      // JS 는 `realRemaining = arrivalSeconds - (now - receivedAtEpochMs)/1000`
      // 으로 매 frame 실시간 계산. Dart 는 값만 통과.
      receivedAtEpochMs: receivedAtEpochMs,
      initialProgress: initialProgress,
      currentStationIndex: currentStationIndex,
      trainType: arrival.trainType,
    ));
  }

  // 사라진 열차의 캐시 제거
  final activeKeys = result.map((t) => '${t.trainNo}_${t.lineId}').toSet();
  estimateCache.removeWhere((k, _) => !activeKeys.contains(k));
  ref.read(_estimateCacheProvider.notifier).state = estimateCache;

  // 같은 역에 여러 열차가 있는 경우 Y축 오프셋 적용
  final adjusted = _applyOverlapOffset(result);

  // 성공 시 캐시 업데이트 (계산에 쓰인 필터와 함께)
  ref.read(_lastSuccessfulTrainsProvider.notifier).state =
      (filter: routeFilter, trains: adjusted);

  return adjusted;
}

/// 같은 현재역에 위치한 열차들에 Y축 오프셋을 적용하여 겹침을 방지한다.
List<LiveTrain> _applyOverlapOffset(List<LiveTrain> trains) {
  // 현재역별 열차 수 카운팅
  final countByStation = <String, int>{};
  for (final t in trains) {
    countByStation[t.currentStation] =
        (countByStation[t.currentStation] ?? 0) + 1;
  }

  final indexByStation = <String, int>{};
  return [
    for (final t in trains)
      () {
        final count = countByStation[t.currentStation] ?? 1;
        if (count <= 1) return t;

        final index = indexByStation[t.currentStation] ?? 0;
        indexByStation[t.currentStation] = index + 1;

        final offset = (index - (count - 1) / 2) * 12.0;
        return LiveTrain(
          trainNo: t.trainNo,
          lineId: t.lineId,
          direction: t.direction,
          destination: t.destination,
          message: t.message,
          arrivalSeconds: t.arrivalSeconds,
          currentStation: t.currentStation,
          arrivalCode: t.arrivalCode,
          positionStatus: t.positionStatus,
          fromSvgX: t.fromSvgX,
          fromSvgY: t.fromSvgY + offset,
          pathToTarget: t.pathToTarget,
          segmentDurations: t.segmentDurations,
          dwellSeconds: t.dwellSeconds,
          receivedAtEpochMs: t.receivedAtEpochMs,
          initialProgress: t.initialProgress,
          currentStationIndex: t.currentStationIndex,
          trainType: t.trainType,
        );
      }(),
  ];
}
