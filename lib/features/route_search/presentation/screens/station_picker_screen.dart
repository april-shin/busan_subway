import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../domain/entities/station.dart';
import '../../../settings/presentation/providers/home_station_provider.dart';
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
    final title = switch (widget.purpose) {
      'departure' => '출발역 선택',
      'arrival' => '도착역 선택',
      'home' => '지도 시작점 선택',
      _ => '역 선택',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space16),
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
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[500],
                              ),
                    ),
                  );
                }

                // 같은 이름 역(환승역)을 하나의 항목으로 통합한다. 환승역 Station
                // 레코드는 이미 `transferLines`에 모든 소속 노선(`['2','9']` 등)을
                // 포함하므로 어느 레코드를 대표로 저장하든 환승 정보는 동일하다.
                // 입력이 lineId 오름차순 기준 정렬이라 가정하고, 첫 레코드를
                // 결정적으로 대표로 선택한다 (동일 역 이름이 다른 화면에서도
                // 동일한 Station ID로 표시되도록 보장).
                final unique = _uniqueByName(filtered);

                return ListView.builder(
                  itemCount: unique.length,
                  itemBuilder: (context, index) {
                    final station = unique[index];
                    return _StationTile(
                      station: station,
                      onTap: () => _selectStation(station),
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

  /// 역 이름 기준 고유 목록 반환. 첫 등장 Station 레코드를 대표로 사용한다.
  List<Station> _uniqueByName(List<Station> stations) {
    final seen = <String>{};
    final result = <Station>[];
    for (final s in stations) {
      if (seen.add(s.name)) result.add(s);
    }
    return result;
  }

  void _selectStation(Station station) {
    switch (widget.purpose) {
      case 'departure':
        ref.read(selectedStationsProvider.notifier).setDeparture(station);
      case 'arrival':
        ref.read(selectedStationsProvider.notifier).setArrival(station);
      case 'home':
        // fire-and-forget: SharedPreferences 저장 후 상태 반영. 실패 시
        // provider 가 이전 값을 유지하므로 UI 는 안전하게 되돌아간다.
        ref.read(homeStationIdProvider.notifier).setHomeStation(station.id);
    }
    Navigator.of(context).pop();
  }
}

/// 검색 결과의 개별 역 항목.
///
/// 환승역이면 `transferLines`의 모든 노선을 색상 뱃지로 나열하여
/// 사용자가 한 항목만 탭하면 모든 노선을 포함한 환승역으로 선택되도록 한다.
/// 일반역이면 `lineId` 하나만 뱃지로 표시한다.
class _StationTile extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;

  const _StationTile({
    required this.station,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 환승역은 transferLines 전체, 일반역은 단일 lineId만 뱃지로 그린다.
    final lineIds = station.isTransfer && station.transferLines.isNotEmpty
        ? station.transferLines
        : [station.lineId];

    return ListTile(
      leading: Icon(
        station.isTransfer ? Icons.swap_horiz : Icons.circle,
        size: station.isTransfer ? 22 : 10,
        color: lineColorFor(lineIds.first),
      ),
      title: Text(
        station.name,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.space4),
        child: Wrap(
          spacing: AppSpacing.space6,
          runSpacing: AppSpacing.space4,
          children: [
            for (final id in lineIds) _LineBadge(lineId: id),
          ],
        ),
      ),
      dense: false,
      onTap: onTap,
    );
  }
}

/// 노선 색상 + 이름을 보여주는 뱃지.
class _LineBadge extends StatelessWidget {
  final String lineId;

  const _LineBadge({required this.lineId});

  @override
  Widget build(BuildContext context) {
    final color = lineColorFor(lineId);
    final name = lineNames[lineId] ?? lineId;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space8,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        name,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
