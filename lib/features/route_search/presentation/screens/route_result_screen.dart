import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/arrival_info.dart';
import '../../../../domain/entities/line_schedule.dart';
import '../../../../domain/entities/route_result.dart';
import '../../../arrival_info/presentation/providers/arrival_providers.dart';
import '../providers/timetable_providers.dart';
import '../../utils/departure_time_calculator.dart';
import '../widgets/transfer_row.dart';

/// 열차 모드 — 완행/급행 토글 상태.
enum TrainMode { local, express }

class RouteResultScreen extends ConsumerStatefulWidget {
  final RouteResult fastest;
  final RouteResult? leastTransfer;
  final String departureStationName;

  const RouteResultScreen({
    super.key,
    required this.fastest,
    this.leastTransfer,
    required this.departureStationName,
  });

  @override
  ConsumerState<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends ConsumerState<RouteResultScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  bool get _hasTwoRoutes => widget.leastTransfer != null;

  @override
  void initState() {
    super.initState();
    if (_hasTwoRoutes) {
      _tabController = TabController(length: 2, vsync: this);
    }
  }

  @override
  void didUpdateWidget(covariant RouteResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadTwo = oldWidget.leastTransfer != null;
    if (hadTwo != _hasTwoRoutes) {
      _tabController?.dispose();
      _tabController =
          _hasTwoRoutes ? TabController(length: 2, vsync: this) : null;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('경로 검색 결과'),
        bottom: _hasTwoRoutes
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.access_time, size: 18), text: '최단시간'),
                  Tab(icon: Icon(Icons.swap_horiz, size: 18), text: '최소환승'),
                ],
              )
            : null,
      ),
      body: _hasTwoRoutes
          ? TabBarView(
              controller: _tabController,
              children: [
                _RouteView(
                  routeResult: widget.fastest,
                  departureStationName: widget.departureStationName,
                ),
                _RouteView(
                  routeResult: widget.leastTransfer!,
                  departureStationName: widget.departureStationName,
                ),
              ],
            )
          : _RouteView(
              routeResult: widget.fastest,
              departureStationName: widget.departureStationName,
            ),
    );
  }
}

class _RouteView extends ConsumerStatefulWidget {
  final RouteResult routeResult;
  final String departureStationName;

  const _RouteView({
    required this.routeResult,
    required this.departureStationName,
  });

  @override
  ConsumerState<_RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends ConsumerState<_RouteView> {
  // 초기값은 급행 가용성에 따라 결정된다 (급행 가능한 경로는 급행이 기본).
  late TrainMode _trainMode;

  bool get _isExpressAvailable =>
      widget.routeResult.totalExpressTimeSeconds != null;

  @override
  void initState() {
    super.initState();
    _trainMode = _isExpressAvailable ? TrainMode.express : TrainMode.local;
  }

  @override
  void didUpdateWidget(covariant _RouteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 탭/경로가 바뀌어 급행 가용성이 변하면 기본값을 재설정한다.
    final oldHasExpress = oldWidget.routeResult.totalExpressTimeSeconds != null;
    if (oldHasExpress != _isExpressAvailable) {
      _trainMode = _isExpressAvailable ? TrainMode.express : TrainMode.local;
    }
  }

  @override
  Widget build(BuildContext context) {
    final arrivalAsync =
        ref.watch(arrivalInfoProvider(widget.departureStationName));
    final schedulesAsync = ref.watch(lineSchedulesProvider);
    final isLoading =
        arrivalAsync is AsyncLoading && !schedulesAsync.hasValue;

    final schedules = schedulesAsync.valueOrNull ?? <String, LineSchedule>{};
    final firstLineId = widget.routeResult.segments.isNotEmpty
        ? widget.routeResult.segments.first.lineId
        : null;
    final firstLineSchedule =
        firstLineId != null ? schedules[firstLineId] : null;

    final transferArrivals = <String, AsyncValue<List<ArrivalInfo>>>{};
    for (var i = 0; i < widget.routeResult.segments.length - 1; i++) {
      final transferName =
          widget.routeResult.segments[i + 1].stations.first.name;
      transferArrivals[transferName] =
          ref.watch(arrivalInfoProvider(transferName));
    }

    // 급행이 비활성된 경로에서는 항상 완행을 사용한다.
    final effectiveMode =
        _isExpressAvailable ? _trainMode : TrainMode.local;
    final useExpress = effectiveMode == TrainMode.express;

    final now = DateTime.now();
    final departureTime = computeDepartureTime(
      arrivalAsync: arrivalAsync,
      routeResult: widget.routeResult,
      now: now,
      lineSchedule: firstLineSchedule,
    );

    final segmentDepartures = computeSegmentDepartures(
      routeResult: widget.routeResult,
      initialDeparture: departureTime,
      schedules: schedules,
      transferArrivals: transferArrivals,
      now: now,
      useExpress: useExpress,
    );

    // 실제 도착시간: 마지막 세그먼트 출발 + 마지막 세그먼트 소요시간(모드별)
    final DateTime arrivalTime;
    final int totalMinutes;
    if (widget.routeResult.segments.isEmpty) {
      arrivalTime = departureTime;
      totalMinutes = 0;
    } else {
      final lastSegment = widget.routeResult.segments.last;
      final lastDuration = useExpress
          ? (lastSegment.expressDurationSeconds ?? lastSegment.durationSeconds)
          : lastSegment.durationSeconds;
      arrivalTime = segmentDepartures.last.add(Duration(seconds: lastDuration));
      totalMinutes = arrivalTime.difference(departureTime).inMinutes;
    }

    return Column(
      children: [
        _RouteSummaryHeader(
          totalMinutes: totalMinutes,
          departureTime: departureTime,
          arrivalTime: arrivalTime,
          isLoading: isLoading,
          transferCount: widget.routeResult.transferCount,
          stationCount: widget.routeResult.stationCount,
          trainMode: effectiveMode,
          isExpressAvailable: _isExpressAvailable,
          onTrainModeChanged: (mode) {
            setState(() {
              _trainMode = mode;
            });
          },
        ),
        // 탭이 있으면 탭 내부 회색선이 구분선 역할을 하므로 Divider는 생략.
        // 탭이 없을 때만(급행 비활성 경로) 외부 Divider로 헤더/타임라인을 구분한다.
        if (!_isExpressAvailable) const Divider(height: 1),
        Expanded(
          child: _RouteTimeline(
            routeResult: widget.routeResult,
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
  final TrainMode trainMode;
  final bool isExpressAvailable;
  final ValueChanged<TrainMode> onTrainModeChanged;

  const _RouteSummaryHeader({
    required this.totalMinutes,
    required this.departureTime,
    required this.arrivalTime,
    required this.isLoading,
    required this.transferCount,
    required this.stationCount,
    required this.trainMode,
    required this.isExpressAvailable,
    required this.onTrainModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // 시간·칩 영역만 가로/세로 패딩. 탭은 전체 너비로 확장되고
          // 주황 언더라인이 바로 아래 Divider에 공백 없이 붙도록 한다.
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              isExpressAvailable ? 12 : 16,
            ),
            child: Column(
              children: [
                if (isLoading)
                  const Text(
                    '실시간 정보 조회중...',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatTime(departureTime),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ' 출발',
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.arrow_forward, size: 20),
                      ),
                      Text(
                        _formatTime(arrivalTime),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ' 도착',
                        style:
                            TextStyle(fontSize: 14, color: Colors.grey[600]),
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
          ),
          // 탭은 컨테이너 전체 너비로 확장. 주황 언더라인이 바로 아래
          // `_RouteView`의 `Divider`에 공백 없이 붙는다.
          if (isExpressAvailable)
            _TrainModeToggle(
              trainMode: trainMode,
              onChanged: onTrainModeChanged,
            ),
        ],
      ),
    );
  }
}

/// 완행/급행 토글 — 탭 스타일.
///
/// 호출부(`_RouteSummaryHeader`)가 급행 가용성을 판단하여 렌더 여부를 결정한다.
/// 이 위젯은 급행이 반드시 가능한 상태에서만 표시된다.
///
/// 급행이 기본값이므로 왼쪽에, 완행이 오른쪽에 위치한다.
class _TrainModeToggle extends StatelessWidget {
  final TrainMode trainMode;
  final ValueChanged<TrainMode> onChanged;

  const _TrainModeToggle({
    required this.trainMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _TrainModeTab(
              label: '급행',
              selected: trainMode == TrainMode.express,
              onTap: () => onChanged(TrainMode.express),
            ),
            _TrainModeTab(
              label: '완행',
              selected: trainMode == TrainMode.local,
              onTap: () => onChanged(TrainMode.local),
            ),
          ],
        ),
        // 주황 언더라인 바로 아래 회색 1px 구분선을 Column으로 직접 쌓아
        // 공백 없이 딱 붙게 한다. (외부 Divider로 쓰면 Container 경계/테마 색상
        // 차이로 인해 미세한 시각적 공백이 발생한다)
        Container(height: 1, color: Colors.grey.shade300),
      ],
    );
  }
}

/// 단일 탭 버튼. 선택 시 하단에 주황색 언더라인이 표시된다.
class _TrainModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TrainModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Colors.orange.shade700;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: selected ? accent : Colors.grey[600],
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _ChipDivider extends StatelessWidget {
  const _ChipDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text('|', style: TextStyle(color: Colors.grey[400])),
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
    final color = lineColors[segment.lineId] ?? Colors.grey;
    final stationCount = segment.stations.length;
    final segmentDuration = _segmentDuration(segment);
    final intervalSeconds = stationCount > 1
        ? segmentDuration / (stationCount - 1)
        : 0.0;
    // 급행 모드 + 이 세그먼트가 급행 운영 구간이면 배지 표시.
    final showExpressBadge =
        useExpress && segment.expressDurationSeconds != null;

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
    // SearchRoute가 보장하는 불변식: transferDurations와 transferGuides는
    // 항상 같은 길이(= transferCount)를 가진다. 디버그 빌드에서 위반을 즉시
    // 감지하되, 릴리스에서는 안전하게 빈 값으로 폴백한다.
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

    final transferSeconds =
        transferIndex < routeResult.transferDurations.length
            ? routeResult.transferDurations[transferIndex]
            : 0;
    final guide = transferIndex < routeResult.transferGuides.length
        ? routeResult.transferGuides[transferIndex]
        : null;
    items.add(TransferRow(
      transferMinutes: (transferSeconds / 60).ceil(),
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
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
              child: const Text(
                '급행',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Text(
            direction,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const Spacer(),
          Text(
            '$minutes분 (${stationCount > 1 ? stationCount - 1 : 0}개역)',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
                    style: TextStyle(
                      fontSize: 12,
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
            style: TextStyle(
              fontSize: isEndpoint ? 14 : 12,
              fontWeight: isEndpoint ? FontWeight.bold : FontWeight.normal,
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

