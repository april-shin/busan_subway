// ⛔ 실시간 열차 애니메이션 4원칙 — 변경 금지 (CLAUDE.md 최상위 정책)
//   이 프로바이더는 JS 애니메이션에 전달되는 `LiveTrain` 을 생성한다. 아래 두
//   필드의 "기준 시각" 계약은 4원칙의 원칙 1 (열차는 뒤로 가지 않는다) 구현의
//   핵심이다. 숫자 자체는 재조회로 늘어날 수 있으나, 기준 시각이 틀리면 JS 가
//   위치를 잘못 역산해 단조 전진 가드가 엉뚱한 지점에 열차를 붙잡아 둔다.
//   - `arrivalSeconds`: API 원본 또는 추정값 (척도 정차 포함)
//   - `receivedAtEpochMs`: 해당 값의 기준 시각 (API 는 recptnDt, 추정은 추정 시각)
//   JS 가 `realRemaining = arrivalSeconds − (now − receivedAtEpochMs)/1000` 으로
//   매 frame 실시간 남은시간을 계산한다. Dart 에서 elapsed 를 선차감하면 JS 가
//   이중 차감하므로 **절대 금지**. 변경 전 CLAUDE.md 4원칙 섹션 확인.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart'; // StateProvider (riverpod 3 레거시)
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/subway_id_mapping.dart';
import '../../../../core/utils/enrich_arrival_info.dart';
import '../../../../core/utils/line_direction.dart';
import '../../../../core/utils/live_arrival_seconds.dart';
import '../../../../core/utils/expand_path_backward.dart';
import '../../../../core/utils/path_on_line.dart';
import '../../../../core/utils/route_branch.dart';
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

  /// 탑승 구간을 완주하지 못하는 열차인지 — 중간 종착
  /// ([RouteCoverage.earlyTerminus]) 과 지선 분기([RouteCoverage.diverged]) 둘 다.
  /// 화면에 그려지는 구간에서는 같은 선로를 달리므로 지도에는 남기되,
  /// JS 측이 투명도를 낮춰 "유령"처럼 그린다.
  final bool isGhost;

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
    this.isGhost = false,
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
        'isGhost': isGhost,
      };

  // 유령 여부는 행선지가 바뀌면 뒤집히는 **표시 속성**이라 동등성에 포함한다.
  // 빠지면 다른 필드가 같을 때 WebView 갱신이 스킵돼 투명도가 그대로 남는다.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveTrain &&
          trainNo == other.trainNo &&
          lineId == other.lineId &&
          arrivalSeconds == other.arrivalSeconds &&
          currentStation == other.currentStation &&
          isGhost == other.isGhost;

  @override
  int get hashCode =>
      Object.hash(trainNo, lineId, arrivalSeconds, currentStation, isGhost);
}

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

  // 도착정보 API 가 이 역의 **해당 노선**을 아예 제공하지 않으면 지도가 통째로 비어
  // 버리므로, 노선 단위로 전 열차를 주는 위치 API 에서 대상역을 향하는 열차만 추려
  // 쓴다. 잔여초는 추정값이다.
  //
  // 조건이 "도착정보 0건"이 아니라 "해당 노선 0건"인 이유: 한 노선만 빠진 환승역에서는
  // 전체 건수가 0 이 아니어서 그 조건으로는 폴백이 걸리지 않는다.
  //
  // 계기는 5호선 천호였다(등록명 `천호(풍납토성)` 조회 시 8호선만, 일괄 조회에도
  // 5호선 엔트리 없음 — 2026-07-31 실측). **2026-08-04 부터 5호선분도 제공되어 천호는
  // 이 조건에 걸리지 않는다.** 조건부라 제공이 시작되면 저절로 정상 경로로 돌아오며,
  // 폴백은 같은 공백의 재발에 대비해 유지한다.
  var arrivalsForMap = enrichedArrivals;
  // 위치 API 폴백을 썼는가. 두 API 는 지선에서 라벨 극성이 달라 구분이 필요하다.
  var usedPositionFallback = false;
  final hasLineArrival = enrichedArrivals.any(
    (a) => subwayIdToLineId[a.subwayId] == routeFilter.lineId,
  );
  if (!hasLineArrival) {
    try {
      arrivalsForMap = await ref
          .watch(arrivalRepositoryProvider)
          .getTrainPositionArrivals(
            lineId: routeFilter.lineId,
            targetStationName: departureStationName,
            stations: stations,
            connections: connections,
          );
      usedPositionFallback = true;
      if (kDebugMode && arrivalsForMap.isNotEmpty) {
        debugPrint(
          '위치 API 폴백: $departureStationName ${routeFilter.lineId}호선 '
          '${arrivalsForMap.length}대',
        );
      }
    } catch (e) {
      // 폴백 실패는 치명적이지 않다 — 열차 없이 지도만 그린다.
      if (kDebugMode) debugPrint('위치 API 폴백 실패: $e');
      arrivalsForMap = const [];
    }
  }

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

  // 구간 완주 판정은 "탑승 구간이 출발역에서 시작한다"는 전제 위에서만 유효하다.
  // 열차 경로는 출발역까지 계산되므로, 첫 유효 세그먼트가 다른 역에서 시작하면
  // (출발역이 환승역이라 앞 세그먼트가 1역뿐인 변형) 비교 기준이 어긋나 정상
  // 열차를 지워버릴 수 있다. 그 경우 필터를 끈다.
  final routeStartStation =
      stationsById[routeFilter.routeStationIds.firstOrNull ?? '']?.firstOrNull;
  //
  // 2호선은 유령 판정에서 **제외한다**(사용자 결정). 순환선이라 행선지
  // (`bstatnNm`)가 실제 운행 범위를 나타내지 않는다 — 한 바퀴를 계속 도는
  // 열차도 "성수행" 처럼 임의의 역을 행선지로 보고하므로, 행선지 기준 완주
  // 판정이 정상 열차를 유령으로 오분류한다.
  // API 라벨 극성이 이 탑승 구간에서 앱 규칙과 반대인가(2호선 성수지선). 경로가
  // 바뀌지 않는 한 상수라 루프 밖에서 한 번만 구한다.
  final apiLabelReversed = isApiLabelReversedOnRoute(
    routeFilter.lineId,
    routeFilter.routeStationIds,
  );

  final branchFilterEnabled = routeFilter.lineId != '2' &&
      routeStartStation?.name == departureStationName;

  // 완주 판정 메모 — 같은 행선지의 열차가 여러 대 오므로 행선지별 1회만 계산한다.
  final coverageCache = <String, RouteCoverage>{};
  RouteCoverage coverageOf(String destination) {
    return coverageCache.putIfAbsent(destination, () {
      final destIds = [
        for (final s in stationsByName[destination] ?? const <Station>[])
          if (s.lineId == routeFilter.lineId) s.id,
      ];
      return classifyDestinationCoverage(
        routeStationIds: routeFilter.routeStationIds,
        destinationStationIds: destIds,
        lineId: routeFilter.lineId,
        connections: connections,
        isDown: routeFilter.isDown,
      );
    });
  }

  final result = <LiveTrain>[];

  for (final arrival in arrivalsForMap) {
    // subwayId → lineId 변환
    final lineId = subwayIdToLineId[arrival.subwayId];
    if (lineId == null) continue;

    // 활성 경로의 노선만 필터링
    if (lineId != routeFilter.lineId) continue;

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

    // 라벨 반전은 **열차 자신의 접근 쌍**(현재역 → 탑승역)으로 판정한다. 경로 단위로
    // 적용하면 분기역 성수(211)에서 출발하는 지선 경로에서 본선 열차까지 뒤집혀
    // 통과한다 — 성수는 본선 순환에도 쓰여 `_line2SeongsuBranchIds` 에 넣을 수 없고
    // (넣으면 본선 간선이 오염된다), 2호선은 행선지 기반 지선 필터가 꺼져 있어
    // (`branchFilterEnabled`) 걸러 줄 장치가 방향 게이트뿐이다. 통과해 버리면
    // `findPathOnLine` 이 hop 상한 없는 BFS 라 순환을 한 바퀴 도는 42정거장 경로를
    // 찾아내 열차를 성수 반대편에 붙박아 그린다.
    //
    // 접근 쌍의 반전 여부가 경로의 그것과 다르면 그 열차는 이 경로의 열차가 아니다
    // (지선 경로에 본선 열차, 또는 그 반대) — 방향을 보기 전에 떨군다.
    // 현재역 == 탑승역인 열차는 접근 쌍이 성립하지 않아 분기역에서 본선/지선을
    // 가릴 수 없다. 틀린 열차를 그리느니 빼는 쪽을 택한다(반전 전에도 떨어지던 행).
    final trainReversed = apiLabelReversedForTrain(
      lineId: lineId,
      currentStationId: currentStation.id,
      boardingStationId: routeFilter.routeStationIds.firstOrNull,
    );
    if (trainReversed != apiLabelReversed) continue;

    // 방향 필터링: 활성 경로 방향과 일치하는 열차만.
    // ⚠ 반전은 **도착정보 API**(`realtimeStationArrival`) 라벨에만 적용한다. 위치 API
    // (`realtimePosition`) 폴백은 극성이 앱 규칙과 **이미 일치한다** — 2026-10-28 실측:
    // 1625 신설동행 `updnLine=1`(하행), 1628 성수지선행 `updnLine=0`(상행)으로 앱
    // 규칙(ID 증가 = 하행)과 같다. 여기서 뒤집으면 폴백이 작동하는 바로 그 상황에서
    // 지선 열차가 전부 사라진다.
    var trainIsDown = isDownDirectionString(arrival.direction);
    if (trainReversed && !usedPositionFallback) trainIsDown = !trainIsDown;
    if (trainIsDown != routeFilter.isDown) continue;

    // 잔여시간을 알 수 없는 열차는 **지도에서 뺀다.**
    //
    // 판정은 도착정보 화면과 같은 `liveArrivalSeconds` 를 쓴다. 규칙이 두 벌로
    // 갈라져 있던 탓에, 카드가 "정보 없음"으로 판정한 열차를 지도는 계속
    // 카운트다운했다(2026-08-13 총신대입구 제보). 지도에는 "정보 없음" 이라는
    // 표시 상태가 없어 `max(0, ...)` 로 바닥을 0 에 붙이므로, 만료된 데이터로도
    // "곧 도착" 을 단언하게 된다. 그리지 않는 쪽으로 통일한다.
    //
    // 함께 제거한 것: 지도 전용 추정 폴백(`_EstimateEntry` 캐시). 게이트 통과
    // 시점에 `arrivalSeconds` 가 non-null 이라 도달 불가가 됐다. (제보 케이스의
    // "1분 후 도착" 은 이 폴백이 만든 값이 **아니라** API 원본 60 이었다 —
    // 그쪽은 `arrival_info_dto.dart` 의 도착 우선 판정으로 따로 고쳤다.)
    // `barvlDt` 미제공 노선(8호선 등)은 `enrichArrivalInfoList` 가 추정값을 채우고
    // 그때 `receivedAt` 도 추정 시각으로 갱신하므로 여기서 걸러지지 않는다.
    //
    // 경로 탐색(findPathOnLine)보다 **앞에** 둔다 — 버릴 행에 그래프 탐색을
    // 태우지 않기 위함. 판정에 필요한 건 `arrival` 하나뿐이다.
    //
    // 알려진 상호작용: 이미 그려져 있던 열차가 이 게이트로 빠지면 JS 의 제거
    // 분류(`toRemove`)에서 "API 누락"으로 보여, 직전 원본이
    // `SILENT_REMOVE_THRESHOLD_S`(60초) 이하였다면 도착 이펙트가 발동한다.
    // 잔여초가 소진돼 걸러지는 경우가 대부분이라 대개는 실제 도착과 일치한다.
    if (liveArrivalSeconds(arrival) == null) continue;

    // 구간 완주 판정 — 태워주지 못하는 열차도 **지우지 않고** 유령으로 남긴다.
    //  - 중간 종착(`내방 → 장암` 경로의 7호선 상행 "도봉산행")
    //  - 지선 분기(`천호 → 굽은다리` 경로의 5호선 하행 "마천행")
    // 둘 다 열차 아이콘이 그려지는 구간(현재역 → 출발역)에서는 실제로 같은
    // 선로를 달린다 — 갈라지거나 멈추는 지점은 출발역 **이후**라 화면에 나오지
    // 않는다. 그래서 위치는 정확하고, 다만 이 경로를 완주하지 못한다는 뜻으로
    // 흐리게 그린다(`isGhost` → JS 가 투명도로 반영).
    // 경로 결과의 출발 시각 계산은 이와 별개로 `full` 만 후보로 쓴다.
    var isGhost = false;
    if (branchFilterEnabled && arrival.destination.isNotEmpty) {
      isGhost = coverageOf(arrival.destination) != RouteCoverage.full;
    }

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

    // 원칙 1: 매 frame 실시간 남은시간 계산은 JS 측에서 `receivedAtEpochMs`
    // 기준으로 수행한다. 따라서 Dart 는 elapsed 선차감을 하지 않고 값과
    // 기준 시각(recptnDt 또는 추정 시각) 한 쌍을 그대로 통과시킨다.
    // (위 게이트를 통과했으므로 `arrivalSeconds` 는 non-null 이 보장된다.)
    final arrivalSecs = arrival.arrivalSeconds!;
    final receivedAtEpochMs = arrival.receivedAt.millisecondsSinceEpoch;

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
      // 언제나 `arrival.receivedAt` 하나다 — API 제공 값이면 recptnDt 이고,
      // enrich 가 채운 추정값이면 enrich 가 추정 시각을 실어 보낸다.
      // (지도 전용 추정 캐시가 있던 시절의 3갈래 분기는 제거됐다.)
      // JS 는 `realRemaining = arrivalSeconds - (now - receivedAtEpochMs)/1000`
      // 으로 매 frame 실시간 계산. Dart 는 값만 통과.
      receivedAtEpochMs: receivedAtEpochMs,
      initialProgress: initialProgress,
      currentStationIndex: currentStationIndex,
      trainType: arrival.trainType,
      isGhost: isGhost,
    ));
  }

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
          isGhost: t.isGhost,
        );
      }(),
  ];
}
