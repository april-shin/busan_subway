import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/usecases/search_route.dart';
import '../../../route_search/presentation/providers/timetable_providers.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';
import '../../../subway_map/presentation/screens/subway_map_screen.dart';
import '../widgets/search_bar_widget.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final selectedStations = ref.watch(selectedStationsProvider);
              if (selectedStations.departure == null &&
                  selectedStations.arrival == null) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  ref.read(selectedStationsProvider.notifier).clear();
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Consumer(
            builder: (context, ref, _) {
              final selectedStations = ref.watch(selectedStationsProvider);
              return RouteSearchBar(
                departure: selectedStations.departure,
                arrival: selectedStations.arrival,
                onDepartureTap: () => context.go('/pick-station/departure'),
                onArrivalTap: () => context.go('/pick-station/arrival'),
                onSwap: () {
                  ref.read(selectedStationsProvider.notifier).swap();
                },
                onSearchRoute: selectedStations.isComplete
                    ? () => _searchRoute(context, ref)
                    : null,
              );
            },
          ),
          const Expanded(
            child: SubwayMapScreen(),
          ),
        ],
      ),
    );
  }

  Future<void> _searchRoute(BuildContext context, WidgetRef ref) async {
    final selected = ref.read(selectedStationsProvider);
    if (!selected.isComplete) return;

    final repo = ref.read(stationRepositoryProvider);
    final timetableSource = ref.read(timetableDataSourceProvider);
    final useCase = SearchRoute(
      stationRepository: repo,
      timetableDataSource: timetableSource,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final (
        :fastest,
        :leastTransfer,
        :fastestExpress,
        :fastestLocal,
      ) = await useCase.executeAll(
        selected.departure!.id,
        selected.arrival!.id,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop();

      if (fastest != null) {
        context.go('/route-result', extra: (
          fastest: fastest,
          leastTransfer: leastTransfer,
          fastestExpress: fastestExpress,
          fastestLocal: fastestLocal,
          departureStationName: selected.departure!.name,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('경로를 찾을 수 없습니다')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('경로 검색 실패: $e')),
      );
    }
  }
}
