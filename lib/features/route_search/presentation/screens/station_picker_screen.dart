import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../domain/entities/station.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';

class StationPickerScreen extends ConsumerStatefulWidget {
  final String purpose;

  const StationPickerScreen({super.key, required this.purpose});

  @override
  ConsumerState<StationPickerScreen> createState() =>
      _StationPickerScreenState();
}

class _StationPickerScreenState extends ConsumerState<StationPickerScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(allStationsProvider);
    final isDeparture = widget.purpose == 'departure';

    return Scaffold(
      appBar: AppBar(
        title: Text(isDeparture ? '출발역 선택' : '도착역 선택'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '역 이름을 입력하세요',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: stationsAsync.when(
              data: (stations) {
                final filtered = _query.isEmpty
                    ? stations
                    : stations
                        .where((s) => s.name.contains(_query))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      '검색 결과가 없습니다',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  );
                }

                final grouped = _groupByLine(filtered);

                return ListView.builder(
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final entry = grouped.entries.elementAt(index);
                    return _LineGroup(
                      lineId: entry.key,
                      stations: entry.value,
                      onStationSelected: (station) {
                        _selectStation(station, isDeparture);
                      },
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('오류: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<Station>> _groupByLine(List<Station> stations) {
    final grouped = <String, List<Station>>{};
    for (final station in stations) {
      grouped.putIfAbsent(station.lineId, () => []).add(station);
    }
    return grouped;
  }

  void _selectStation(Station station, bool isDeparture) {
    if (isDeparture) {
      ref.read(selectedStationsProvider.notifier).setDeparture(station);
    } else {
      ref.read(selectedStationsProvider.notifier).setArrival(station);
    }
    Navigator.of(context).pop();
  }
}

class _LineGroup extends StatelessWidget {
  final String lineId;
  final List<Station> stations;
  final ValueChanged<Station> onStationSelected;

  const _LineGroup({
    required this.lineId,
    required this.stations,
    required this.onStationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final color = lineColors[lineId] ?? Colors.grey;
    final lineName = lineNames[lineId] ?? lineId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            ],
          ),
        ),
        ...stations.map((station) => ListTile(
              leading: Icon(
                station.isTransfer ? Icons.swap_horiz : Icons.circle,
                size: station.isTransfer ? 20 : 8,
                color: color,
              ),
              title: Text(station.name),
              subtitle: station.isTransfer
                  ? Text(
                      station.transferLines
                          .map((l) => lineNames[l] ?? l)
                          .join(', '),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    )
                  : null,
              dense: true,
              onTap: () => onStationSelected(station),
            )),
        const Divider(),
      ],
    );
  }
}
