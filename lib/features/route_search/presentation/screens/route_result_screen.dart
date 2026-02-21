import 'package:flutter/material.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/route_result.dart';

class RouteResultScreen extends StatelessWidget {
  final RouteResult routeResult;

  const RouteResultScreen({super.key, required this.routeResult});

  @override
  Widget build(BuildContext context) {
    final totalMinutes = routeResult.totalTimeSeconds ~/ 60;

    return Scaffold(
      appBar: AppBar(
        title: const Text('경로 검색 결과'),
      ),
      body: Column(
        children: [
          _RouteSummary(
            totalMinutes: totalMinutes,
            transferCount: routeResult.transferCount,
            stationCount: routeResult.stationCount,
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: routeResult.segments.length,
              itemBuilder: (context, index) {
                final segment = routeResult.segments[index];
                final isLast = index == routeResult.segments.length - 1;

                return _SegmentWidget(
                  segment: segment,
                  isLast: isLast,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  final int totalMinutes;
  final int transferCount;
  final int stationCount;

  const _RouteSummary({
    required this.totalMinutes,
    required this.transferCount,
    required this.stationCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _SummaryItem(
            icon: Icons.access_time,
            label: '소요시간',
            value: '$totalMinutes분',
          ),
          _SummaryItem(
            icon: Icons.swap_horiz,
            label: '환승',
            value: '$transferCount회',
          ),
          _SummaryItem(
            icon: Icons.train,
            label: '정거장',
            value: '$stationCount개',
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _SegmentWidget extends StatelessWidget {
  final RouteSegment segment;
  final bool isLast;

  const _SegmentWidget({
    required this.segment,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = lineColors[segment.lineId] ?? Colors.grey;
    final minutes = segment.durationSeconds ~/ 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                segment.lineName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${segment.direction} 방면',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const Spacer(),
            Text(
              '$minutes분',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...segment.stations.asMap().entries.map((entry) {
          final index = entry.key;
          final station = entry.value;
          final isFirst = index == 0;
          final isStationLast = index == segment.stations.length - 1;

          return Row(
            children: [
              SizedBox(
                width: 30,
                child: Column(
                  children: [
                    Container(
                      width: 2,
                      height: isFirst ? 0 : 12,
                      color: color,
                    ),
                    Container(
                      width: (isFirst || isStationLast) ? 10 : 6,
                      height: (isFirst || isStationLast) ? 10 : 6,
                      decoration: BoxDecoration(
                        color: (isFirst || isStationLast)
                            ? Colors.white
                            : color,
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                      ),
                    ),
                    Container(
                      width: 2,
                      height: (isStationLast && isLast) ? 0 : 12,
                      color: color,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                station.name,
                style: TextStyle(
                  fontSize: (isFirst || isStationLast) ? 14 : 12,
                  fontWeight: (isFirst || isStationLast)
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: (isFirst || isStationLast)
                      ? Colors.black
                      : Colors.grey[600],
                ),
              ),
              if (station.isTransfer) ...[
                const SizedBox(width: 4),
                const Icon(Icons.swap_horiz, size: 14, color: Colors.orange),
              ],
            ],
          );
        }),
        if (!isLast) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.swap_vert, size: 16, color: Colors.orange[700]),
              const SizedBox(width: 8),
              Text(
                '환승',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
