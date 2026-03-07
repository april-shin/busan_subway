import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/connection.dart';
import '../providers/subway_map_providers.dart';
import '../widgets/subway_map_viewer.dart';

class SubwayMapScreen extends ConsumerStatefulWidget {
  const SubwayMapScreen({super.key});

  @override
  ConsumerState<SubwayMapScreen> createState() => _SubwayMapScreenState();
}

class _SubwayMapScreenState extends ConsumerState<SubwayMapScreen> {
  late final Future<List<Connection>> _connectionsFuture;

  @override
  void initState() {
    super.initState();
    _connectionsFuture =
        ref.read(stationRepositoryProvider).getAllConnections();
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(allStationsProvider);

    return stationsAsync.when(
      data: (stations) => FutureBuilder(
        future: _connectionsFuture,
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
