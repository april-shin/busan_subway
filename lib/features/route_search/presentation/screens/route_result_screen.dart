import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/arrival_info.dart';
import '../../../../domain/entities/line_schedule.dart';
import '../../../../domain/entities/route_result.dart';
import '../../../ads/presentation/widgets/home_banner_ad.dart';
import '../../../arrival_info/presentation/providers/arrival_providers.dart';
import '../providers/timetable_providers.dart';
import '../../utils/departure_time_calculator.dart';
import '../widgets/transfer_row.dart';

/// 결과 화면 탭 구성 — 두 후보 경로의 차이가 무엇이냐에 따라 라벨이 달라진다.
///
/// - [transferTradeoff]: 환승 횟수가 다른 두 경로 비교 ("최단시간" / "최소환승")
/// - [modeTradeoff]: 환승 동일·시간 다름인 두 경로(완행 단독 vs 급행 단독) 비교 ("급행" / "완행")
/// - [single]: 단일 경로 — 탭 미표시
enum _TabConfig { transferTradeoff, modeTradeoff, single }

class RouteResultScreen extends ConsumerStatefulWidget {
  final RouteResult fastest;
  final RouteResult? leastTransfer;
  final RouteResult? fastestExpress;
  final RouteResult? fastestLocal;
  final String departureStationName;

  const RouteResultScreen({
    super.key,
    required this.fastest,
    this.leastTransfer,
    this.fastestExpress,
    this.fastestLocal,
    required this.departureStationName,
  });

  @override
  ConsumerState<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends ConsumerState<RouteResultScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  /// 두 후보의 차이를 보고 탭 라벨/구성을 결정한다.
  ///
  /// 우선순위:
  ///   1. 환승 트레이드오프(`leastTransfer != null`) — "최단시간/최소환승" 탭
  ///   2. 모드 트레이드오프(`fastestExpress`/`fastestLocal` 모두 존재 + 시간 다름) — "급행/완행" 탭
  ///   3. 그 외 — 단일 탭
  ///
  /// `widget` 또는 `oldWidget` 어느 쪽에서도 동일 규칙으로 판정해야 하므로
  /// 위젯을 인자로 받는 정적-스타일 함수로 단일화한다.
  static _TabConfig _resolveTabConfig(RouteResultScreen w) {
    if (w.leastTransfer != null) {
      return _TabConfig.transferTradeoff;
    }
    final express = w.fastestExpress;
    final local = w.fastestLocal;
    if (express != null &&
        local != null &&
        express.totalTimeSeconds != local.totalTimeSeconds) {
      return _TabConfig.modeTradeoff;
    }
    return _TabConfig.single;
  }

  _TabConfig get _tabConfig => _resolveTabConfig(widget);
  bool get _hasTabs => _tabConfig != _TabConfig.single;

  @override
  void initState() {
    super.initState();
    if (_hasTabs) {
      _tabController = TabController(length: 2, vsync: this);
    }
  }

  @override
  void didUpdateWidget(covariant RouteResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadTabs = _resolveTabConfig(oldWidget) != _TabConfig.single;
    if (hadTabs != _hasTabs) {
      _tabController?.dispose();
      _tabController = _hasTabs ? TabController(length: 2, vsync: this) : null;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _tabConfig;
    final tabs = _buildTabs(config);
    final routes = _buildRoutes(config);

    return Scaffold(
      appBar: AppBar(
        title: const Text('경로 검색 결과'),
        bottom: tabs == null
            ? null
            : TabBar(
                controller: _tabController,
                tabs: tabs,
              ),
      ),
      bottomNavigationBar: const HomeBannerAd(),
      body: routes.length == 1
          ? _RouteView(
              key: ValueKey(routes.first),
              routeResult: routes.first,
              departureStationName: widget.departureStationName,
            )
          : TabBarView(
              controller: _tabController,
              children: [
                for (final r in routes)
                  _RouteView(
                    key: ValueKey(r),
                    routeResult: r,
                    departureStationName: widget.departureStationName,
                  ),
              ],
            ),
    );
  }

  /// 탭 라벨 — 단일 탭이면 null.
  List<Widget>? _buildTabs(_TabConfig config) {
    switch (config) {
      case _TabConfig.transferTradeoff:
        return const [
          Tab(icon: Icon(Icons.access_time, size: 18), text: '최단시간'),
          Tab(icon: Icon(Icons.swap_horiz, size: 18), text: '최소환승'),
        ];
      case _TabConfig.modeTradeoff:
        return const [
          // 급행이 기본값이므로 왼쪽에 위치한다 (사용자 합의 사항).
          Tab(icon: Icon(Icons.flash_on, size: 18), text: '급행'),
          Tab(icon: Icon(Icons.directions_subway, size: 18), text: '완행'),
        ];
      case _TabConfig.single:
        return null;
    }
  }

  /// 각 탭에 대응하는 경로 리스트.
  List<RouteResult> _buildRoutes(_TabConfig config) {
    switch (config) {
      case _TabConfig.transferTradeoff:
        return [widget.fastest, widget.leastTransfer!];
      case _TabConfig.modeTradeoff:
        return [widget.fastestExpress!, widget.fastestLocal!];
      case _TabConfig.single:
        return [widget.fastest];
    }
  }
}

/// 단일 경로 뷰 — 탭이 모드/경로를 이미 결정하므로 내부 토글은 없다.
///
/// 급행 모드 사용 여부는 첫 세그먼트 lineId 패턴(`{base}E`)으로 자동 판정한다.
/// 단, 가상 급행 노선을 거치지 않더라도 세그먼트가 `expressDurationSeconds`를
/// 가질 수 있으므로(완행 모델에서 운영 구간만 별도 시간 노출), 시간 표시는
/// 첫 세그먼트의 lineId가 `E`로 끝날 때만 급행 시간을 사용한다.
///
/// **도착정보 freeze 정책** — 결과 화면은 "한번 로드되면 더 이상 refresh하지
/// 않는다". 출발역/환승역별 `arrivalInfoProvider`가 최초 1회 non-loading 값을
/// 확정하면 그 스냅샷을 State에 고정하고, 이후 지도 화면(`liveTrainsProvider`)
/// 등에서 동일 station name provider를 invalidate/refetch해도 표시값을 바꾸지
/// 않는다. 정적 데이터인 `lineSchedulesProvider`(keepAlive)는 재조회되지 않으므로
/// 예외적으로 `ref.watch`를 그대로 유지한다.
class _RouteView extends ConsumerStatefulWidget {
  final RouteResult routeResult;
  final String departureStationName;

  const _RouteView({
    super.key,
    required this.routeResult,
    required this.departureStationName,
  });

  bool get _useExpress {
    if (routeResult.segments.isEmpty) return false;
    // 첫 세그먼트가 가상 급행 노선(`{base}E`)이면 급행 모드로 동작한다.
    // 가상 급행 세그먼트의 시간/도착정보는 `expressOnly` 필터로 분리 매칭된다.
    return isExpressLineId(routeResult.segments.first.lineId);
  }

  @override
  ConsumerState<_RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends ConsumerState<_RouteView> {
  /// 출발역 도착정보의 고정 스냅샷.
  ///
  /// - null: 아직 최초 `ref.read`조차 안 함(build 첫 진입 전).
  /// - `AsyncLoading`: 로딩 확정 전 — 다음 non-loading 값을 받으면 교체.
  /// - non-loading(`AsyncData`/`AsyncError`): 확정됨 — 이후 변경 무시.
  AsyncValue<List<ArrivalInfo>>? _departureArrival;

  /// 환승역별(역 이름 key) 도착정보의 고정 스냅샷. 값의 의미는 위와 동일.
  final Map<String, AsyncValue<List<ArrivalInfo>>> _transferArrivals = {};

  /// 환승역 이름 목록 — `initState`에서 1회 계산(세그먼트 경계마다 다음 세그먼트
  /// 첫 역). 기존 `build()` 루프의 로직을 위치만 이동한 것.
  late final List<String> _transferStationNames;

  @override
  void initState() {
    super.initState();
    final segments = widget.routeResult.segments;
    _transferStationNames = [
      for (var i = 0; i < segments.length - 1; i++)
        segments[i + 1].stations.first.name,
    ];
  }

  /// 도착정보 provider를 "최초 1회만 반영" 방식으로 구독한다.
  ///
  /// - 아직 확정 전(스냅샷이 null 또는 `isLoading`)이면 `ref.listen`으로 다음
  ///   변경을 감시하고 현재 값을 스냅샷에 반영한다. non-loading 값이 도착하면
  ///   1회 `setState`로 rebuild한다.
  /// - 이미 확정된 뒤에는 `ref.listen`을 재등록하지 않으므로(Riverpod가 이전
  ///   구독을 자동 해제), 외부 invalidate/refetch가 있어도 콜백이 호출되지 않아
  ///   표시값이 그대로 유지된다.
  ///
  /// [read]는 현재 스냅샷, [write]는 스냅샷 갱신 콜백이다.
  void _freezeSubscribe(
    ProviderListenable<AsyncValue<List<ArrivalInfo>>> provider,
    AsyncValue<List<ArrivalInfo>>? Function() read,
    void Function(AsyncValue<List<ArrivalInfo>>) write,
  ) {
    final current = read();
    if (current == null || current.isLoading) {
      ref.listen(provider, (prev, next) {
        if (!mounted) return;
        final snapshot = read();
        // 이미 non-loading으로 확정됐으면 이후 변경을 무시(freeze).
        if (snapshot != null && !snapshot.isLoading) return;
        setState(() => write(next));
      });
      write(ref.read(provider));
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeResult = widget.routeResult;

    // 출발역 도착정보 — 최초 1회 확정 후 freeze.
    final departureProvider =
        arrivalInfoProvider(widget.departureStationName);
    _freezeSubscribe(
      departureProvider,
      () => _departureArrival,
      (v) => _departureArrival = v,
    );
    final arrivalAsync =
        _departureArrival ?? const AsyncValue<List<ArrivalInfo>>.loading();

    // 정적 데이터(keepAlive) — 재조회되지 않으므로 그대로 watch.
    final schedulesAsync = ref.watch(lineSchedulesProvider);
    final isLoading =
        arrivalAsync is AsyncLoading && !schedulesAsync.hasValue;

    final schedules = schedulesAsync.valueOrNull ?? <String, LineSchedule>{};
    final firstLineId = routeResult.segments.isNotEmpty
        ? routeResult.segments.first.lineId
        : null;
    // 시간표는 base 노선 ID(`9`)로 인덱싱돼 있으므로 가상 급행(`9E`) → `9` 변환.
    final firstScheduleLineId =
        firstLineId == null ? null : baseLineId(firstLineId);
    final firstLineSchedule =
        firstScheduleLineId != null ? schedules[firstScheduleLineId] : null;

    // 환승역별 도착정보 — 각각 최초 1회 확정 후 freeze.
    final transferArrivals = <String, AsyncValue<List<ArrivalInfo>>>{};
    for (final transferName in _transferStationNames) {
      _freezeSubscribe(
        arrivalInfoProvider(transferName),
        () => _transferArrivals[transferName],
        (v) => _transferArrivals[transferName] = v,
      );
      transferArrivals[transferName] = _transferArrivals[transferName] ??
          const AsyncValue<List<ArrivalInfo>>.loading();
    }

    final useExpress = widget._useExpress;

    final now = DateTime.now();
    final departureTime = computeDepartureTime(
      arrivalAsync: arrivalAsync,
      routeResult: routeResult,
      now: now,
      lineSchedule: firstLineSchedule,
    );

    final segmentDepartures = computeSegmentDepartures(
      routeResult: routeResult,
      initialDeparture: departureTime,
      schedules: schedules,
      transferArrivals: transferArrivals,
      now: now,
      useExpress: useExpress,
    );

    // 실제 도착시간: 마지막 세그먼트 출발 + 마지막 세그먼트 소요시간(모드별)
    final DateTime arrivalTime;
    final int totalMinutes;
    if (routeResult.segments.isEmpty) {
      arrivalTime = departureTime;
      totalMinutes = 0;
    } else {
      final lastSegment = routeResult.segments.last;
      final lastDuration = useExpress
          ? (lastSegment.expressDurationSeconds ?? lastSegment.durationSeconds)
          : lastSegment.durationSeconds;
      arrivalTime =
          segmentDepartures.last.add(Duration(seconds: lastDuration));
      totalMinutes = arrivalTime.difference(departureTime).inMinutes;
    }

    return Column(
      children: [
        _RouteSummaryHeader(
          totalMinutes: totalMinutes,
          departureTime: departureTime,
          arrivalTime: arrivalTime,
          isLoading: isLoading,
          transferCount: routeResult.transferCount,
          stationCount: routeResult.stationCount,
        ),
        const Divider(height: 1),
        Expanded(
          child: _RouteTimeline(
            routeResult: routeResult,
            departureTime: departureTime,
            segmentDepartures: segmentDepartures,
            useExpress: useExpress,
          ),
        ),
      ],
    );
  }
}

String _formatTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class _RouteSummaryHeader extends StatelessWidget {
  final int totalMinutes;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final bool isLoading;
  final int transferCount;
  final int stationCount;

  const _RouteSummaryHeader({
    required this.totalMinutes,
    required this.departureTime,
    required this.arrivalTime,
    required this.isLoading,
    required this.transferCount,
    required this.stationCount,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        children: [
          if (isLoading)
            Text(
              '실시간 정보 조회중...',
              style: t.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatTime(departureTime),
                  style: t.titleLarge,
                ),
                Text(
                  ' 출발',
                  style: t.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward, size: 20),
                ),
                Text(
                  _formatTime(arrivalTime),
                  style: t.titleLarge,
                ),
                Text(
                  ' 도착',
                  style: t.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _InfoChip(
                icon: Icons.access_time,
                text: '소요 $totalMinutes분',
              ),
              const _ChipDivider(),
              _InfoChip(
                icon: Icons.swap_horiz,
                text: '환승 $transferCount회',
              ),
              const _ChipDivider(),
              _InfoChip(
                icon: Icons.train,
                text: '$stationCount개역',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: t.labelMedium?.copyWith(
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _ChipDivider extends StatelessWidget {
  const _ChipDivider();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: t.bodyMedium?.copyWith(
          color: Colors.grey[400],
        ),
      ),
    );
  }
}

class _RouteTimeline extends StatelessWidget {
  final RouteResult routeResult;
  final DateTime departureTime;
  final List<DateTime> segmentDepartures;
  final bool useExpress;

  const _RouteTimeline({
    required this.routeResult,
    required this.departureTime,
    required this.segmentDepartures,
    required this.useExpress,
  });

  /// 모드별 세그먼트 소요시간(초)을 반환한다.
  int _segmentDuration(RouteSegment segment) {
    if (useExpress) {
      return segment.expressDurationSeconds ?? segment.durationSeconds;
    }
    return segment.durationSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildTimelineItems();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  List<Widget> _buildTimelineItems() {
    final items = <Widget>[];

    for (var i = 0; i < routeResult.segments.length; i++) {
      final isLast = i == routeResult.segments.length - 1;
      final segStartTime =
          i < segmentDepartures.length ? segmentDepartures[i] : departureTime;
      _addSegmentItems(items, i, segStartTime, isLast);
      if (!isLast) {
        final segEndTime = segStartTime.add(
          Duration(seconds: _segmentDuration(routeResult.segments[i])),
        );
        _addTransferItem(items, i, segEndTime);
      }
    }

    return items;
  }

  void _addSegmentItems(
    List<Widget> items,
    int segIndex,
    DateTime startTime,
    bool isLastSegment,
  ) {
    final segment = routeResult.segments[segIndex];
    final color = lineColorFor(segment.lineId);
    final stationCount = segment.stations.length;
    final segmentDuration = _segmentDuration(segment);
    final intervalSeconds = stationCount > 1
        ? segmentDuration / (stationCount - 1)
        : 0.0;
    // 배지 표시 조건:
    //   - 새 모델: 세그먼트가 가상 급행 노선(`{base}E`)인 경우 → 항상 "급행" 배지.
    //   - 구 모델: useExpress + 세그먼트가 급행 운영 구간(expressDurationSeconds 존재).
    //     (가상 노선 구분이 없는 노선에서 후속 정리 후 제거 예정.)
    final showExpressBadge = isExpressLineId(segment.lineId) ||
        (useExpress && segment.expressDurationSeconds != null);

    items.add(_SegmentHeader(
      color: color,
      lineName: segment.lineName,
      direction: segment.direction,
      minutes: segmentDuration ~/ 60,
      stationCount: stationCount,
      showExpressBadge: showExpressBadge,
    ));

    for (var stIdx = 0; stIdx < stationCount; stIdx++) {
      final station = segment.stations[stIdx];
      final isFirst = stIdx == 0;
      final isLast = stIdx == stationCount - 1;
      final stationTime = startTime.add(
        Duration(seconds: (intervalSeconds * stIdx).round()),
      );

      items.add(_StationRow(
        color: color,
        stationName: station.name,
        time: _formatTime(stationTime),
        isFirstInSegment: isFirst,
        isLastInSegment: isLast,
        isLastOverall: isLast && isLastSegment,
        isTransferStation: station.isTransfer,
      ));
    }
  }

  void _addTransferItem(
    List<Widget> items,
    int transferIndex,
    DateTime startTime,
  ) {
    // SearchRoute가 보장하는 불변식: transferDurations, transferWalkDurations,
    // transferGuides는 항상 같은 길이(= transferCount)를 가진다. 디버그 빌드에서
    // 위반을 즉시 감지하되, 릴리스에서는 안전하게 빈 값으로 폴백한다.
    assert(
      transferIndex < routeResult.transferDurations.length,
      'transferIndex($transferIndex)가 transferDurations 범위를 벗어남. '
      'RouteResult 불변식 위반.',
    );
    assert(
      routeResult.transferGuides.length == routeResult.transferDurations.length,
      'transferGuides(${routeResult.transferGuides.length})와 '
      'transferDurations(${routeResult.transferDurations.length}) 길이 불일치. '
      'RouteResult 불변식 위반.',
    );
    assert(
      routeResult.transferWalkDurations.length ==
          routeResult.transferDurations.length,
      'transferWalkDurations(${routeResult.transferWalkDurations.length})와 '
      'transferDurations(${routeResult.transferDurations.length}) 길이 불일치. '
      'RouteResult 불변식 위반.',
    );

    // "환승 N분" 라벨은 **도보시간만** 표시한다(열차 대기 제외). 총소요시간과
    // 출발시각 계산은 여전히 transferDurations(도보+대기)를 사용하므로 불변.
    // transferWalkDurations가 비어 있는 경우(레거시/폴백)엔 0분으로 표시.
    final transferWalkSeconds =
        transferIndex < routeResult.transferWalkDurations.length
            ? routeResult.transferWalkDurations[transferIndex]
            : 0;
    final guide = transferIndex < routeResult.transferGuides.length
        ? routeResult.transferGuides[transferIndex]
        : null;
    items.add(TransferRow(
      transferMinutes: (transferWalkSeconds / 60).ceil(),
      guide: guide,
    ));
  }
}

class _SegmentHeader extends StatelessWidget {
  final Color color;
  final String lineName;
  final String direction;
  final int minutes;
  final int stationCount;
  final bool showExpressBadge;

  const _SegmentHeader({
    required this.color,
    required this.lineName,
    required this.direction,
    required this.minutes,
    required this.stationCount,
    this.showExpressBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 60, bottom: 4, top: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              lineName,
              style: t.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (showExpressBadge) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '급행',
                style: t.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Text(
            direction,
            style: t.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const Spacer(),
          Text(
            '$minutes분 (${stationCount > 1 ? stationCount - 1 : 0}개역)',
            style: t.bodySmall?.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

class _StationRow extends StatelessWidget {
  final Color color;
  final String stationName;
  final String time;
  final bool isFirstInSegment;
  final bool isLastInSegment;
  final bool isLastOverall;
  final bool isTransferStation;

  const _StationRow({
    required this.color,
    required this.stationName,
    required this.time,
    required this.isFirstInSegment,
    required this.isLastInSegment,
    required this.isLastOverall,
    required this.isTransferStation,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isEndpoint = isFirstInSegment || isLastInSegment;
    final dotSize = isEndpoint ? 12.0 : 6.0;

    return SizedBox(
      height: 28,
      child: Row(
        children: [
          // 시각 표시
          SizedBox(
            width: 50,
            child: isEndpoint
                ? Text(
                    time,
                    style: t.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 4),
          // 세로 바 + 원
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: isFirstInSegment ? 0 : 2,
                    color: color,
                  ),
                ),
                Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: isEndpoint ? Colors.white : color,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: isLastOverall ? 0 : 2,
                    color: isLastInSegment ? Colors.transparent : color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 역명
          Text(
            stationName,
            style: (isEndpoint ? t.titleSmall : t.bodySmall)?.copyWith(
              color: isEndpoint ? Colors.black : Colors.grey[600],
            ),
          ),
          if (isTransferStation && !isEndpoint) ...[
            const SizedBox(width: 4),
            Icon(Icons.swap_horiz, size: 14, color: Colors.grey[400]),
          ],
        ],
      ),
    );
  }
}
