import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/subway_map_providers.dart';
import '../widgets/subway_map_viewer.dart';

class SubwayMapScreen extends ConsumerWidget {
  const SubwayMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stationsAsync = ref.watch(allStationsProvider);
    final stationRepo = ref.watch(stationRepositoryProvider);

    return stationsAsync.when(
      data: (stations) => FutureBuilder(
        future: stationRepo.getAllConnections(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return SubwayMapViewer(
            stations: stations,
            connections: snapshot.data!,
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('데이터 로드 실패: $error'),
          ],
        ),
      ),
    );
  }
}
