import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../core/theme/tokens/app_dimensions.dart';
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
        padding: const EdgeInsets.all(AppSpacing.space16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space12,
                            vertical: AppSpacing.space4),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          lineName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space12),
                      Text(
                        station.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space12),
                  Text(
                    '역 번호: ${station.id}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
            ),
          ),
          if (station.isTransfer && station.transferLines.length > 1) ...[
            const SizedBox(height: AppSpacing.space16),
            Text(
              '환승 노선',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.space8),
            Wrap(
              spacing: AppSpacing.space8,
              runSpacing: AppSpacing.space8,
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
          const SizedBox(height: AppSpacing.space24),
          ElevatedButton.icon(
            onPressed: () {
              // stationId 를 함께 넘겨 동명이역(양평 등)의 도착 정보가
              // 섞이지 않게 한다.
              context.go('/arrivals/${station.name}?stationId=${station.id}');
            },
            icon: const Icon(Icons.access_time),
            label: const Text('실시간 도착 정보 보기'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.space12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
