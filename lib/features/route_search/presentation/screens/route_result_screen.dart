import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/route_result.dart';
import '../../../arrival_info/presentation/providers/arrival_providers.dart';
import '../../utils/departure_time_calculator.dart';

class RouteResultScreen extends ConsumerWidget {
  final RouteResult routeResult;
  final String departureStationName;

  const RouteResultScreen({
    super.key,
    required this.routeResult,
    required this.departureStationName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arrivalAsync = ref.watch(arrivalInfoProvider(departureStationName));
    final totalMinutes = routeResult.totalTimeSeconds ~/ 60;
    final isLoading = arrivalAsync is AsyncLoading;
    final departureTime = computeDepartureTime(
      arrivalAsync: arrivalAsync,
      routeResult: routeResult,
      now: DateTime.now(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('경로 검색 결과'),
      ),
      body: Column(
        children: [
          _RouteSummaryHeader(
            routeResult: routeResult,
            totalMinutes: totalMinutes,
            departureTime: departureTime,
            isLoading: isLoading,
          ),
          const Divider(height: 1),
          Expanded(
            child: _RouteTimeline(
              routeResult: routeResult,
              departureTime: departureTime,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class _RouteSummaryHeader extends StatelessWidget {
  final RouteResult routeResult;
  final int totalMinutes;
  final DateTime departureTime;
  final bool isLoading;

  const _RouteSummaryHeader({
    required this.routeResult,
    required this.totalMinutes,
    required this.departureTime,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final arrivalTime = departureTime.add(
      Duration(seconds: routeResult.totalTimeSeconds),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Theme.of(context).colorScheme.surface,
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
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                text: '환승 ${routeResult.transferCount}회',
              ),
              const _ChipDivider(),
              _InfoChip(
                icon: Icons.train,
                text: '${routeResult.stationCount}개역',
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

  const _RouteTimeline({
    required this.routeResult,
    required this.departureTime,
  });

  @override
  Widget build(BuildContext context) {
    final items = _buildTimelineItems(departureTime);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  List<Widget> _buildTimelineItems(DateTime departureTime) {
    final items = <Widget>[];
    var currentTime = departureTime;

    for (var i = 0; i < routeResult.segments.length; i++) {
      final isLast = i == routeResult.segments.length - 1;
      currentTime = _addSegmentItems(items, i, currentTime, isLast);
      if (!isLast) {
        currentTime = _addTransferItem(items, i, currentTime);
      }
    }

    return items;
  }

  DateTime _addSegmentItems(
    List<Widget> items,
    int segIndex,
    DateTime startTime,
    bool isLastSegment,
  ) {
    final segment = routeResult.segments[segIndex];
    final color = lineColors[segment.lineId] ?? Colors.grey;
    final stationCount = segment.stations.length;
    final intervalSeconds = stationCount > 1
        ? segment.durationSeconds / (stationCount - 1)
        : 0.0;

    items.add(_SegmentHeader(
      color: color,
      lineName: segment.lineName,
      direction: segment.direction,
      minutes: segment.durationSeconds ~/ 60,
      stationCount: stationCount,
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

    return startTime.add(Duration(seconds: segment.durationSeconds));
  }

  DateTime _addTransferItem(
    List<Widget> items,
    int transferIndex,
    DateTime startTime,
  ) {
    final transferSeconds =
        transferIndex < routeResult.transferDurations.length
            ? routeResult.transferDurations[transferIndex]
            : 0;
    items.add(_TransferRow(transferMinutes: (transferSeconds / 60).ceil()));
    return startTime.add(Duration(seconds: transferSeconds));
  }
}

class _SegmentHeader extends StatelessWidget {
  final Color color;
  final String lineName;
  final String direction;
  final int minutes;
  final int stationCount;

  const _SegmentHeader({
    required this.color,
    required this.lineName,
    required this.direction,
    required this.minutes,
    required this.stationCount,
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

class _TransferRow extends StatelessWidget {
  final int transferMinutes;

  const _TransferRow({required this.transferMinutes});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 54),
          SizedBox(
            width: 20,
            height: 36,
            child: CustomPaint(
              painter: _DashedLinePainter(color: Colors.orange.shade700),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.directions_walk, size: 14, color: Colors.orange[700]),
          const SizedBox(width: 4),
          Text(
            '환승 $transferMinutes분',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 4.0;
    const dashGap = 3.0;
    final centerX = size.width / 2;
    var startY = 0.0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(centerX, startY),
        Offset(centerX, (startY + dashHeight).clamp(0, size.height)),
        paint,
      );
      startY += dashHeight + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
