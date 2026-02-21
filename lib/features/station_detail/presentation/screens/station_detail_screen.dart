import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/station.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';

class StationDetailScreen extends ConsumerWidget {
  final String stationId;

  const StationDetailScreen({super.key, required this.stationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stationsAsync = ref.watch(allStationsProvider);

    return stationsAsync.when(
      data: (stations) {
        final station = stations
            .where((s) => s.id == stationId)
            .firstOrNull;

        if (station == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('역 정보')),
            body: const Center(child: Text('역 정보를 찾을 수 없습니다')),
          );
        }

        return _StationDetailBody(station: station);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('역 정보')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('역 정보')),
        body: Center(child: Text('오류: $e')),
      ),
    );
  }
}

class _StationDetailBody extends StatelessWidget {
  final Station station;

  const _StationDetailBody({required this.station});

  @override
  Widget build(BuildContext context) {
    final color = lineColors[station.lineId] ?? Colors.grey;
    final lineName = lineNames[station.lineId] ?? station.lineId;

    return Scaffold(
      appBar: AppBar(
        title: Text(station.name),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          lineName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '역 번호: ${station.id}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          if (station.isTransfer && station.transferLines.length > 1) ...[
            const SizedBox(height: 16),
            const Text(
              '환승 노선',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: station.transferLines.map((lineId) {
                final transferColor = lineColors[lineId] ?? Colors.grey;
                final transferName = lineNames[lineId] ?? lineId;
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: transferColor,
                    radius: 10,
                  ),
                  label: Text(transferName),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              context.go('/arrivals/${station.name}');
            },
            icon: const Icon(Icons.access_time),
            label: const Text('실시간 도착 정보 보기'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
