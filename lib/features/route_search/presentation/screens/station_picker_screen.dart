import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../core/utils/chosung_search.dart';
import '../../../../core/utils/same_station.dart';
import '../../../../domain/entities/station.dart';
import '../../../settings/presentation/providers/home_station_provider.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';
import '../providers/recent_search_provider.dart';
import '../utils/route_result_navigator.dart';

class StationPickerScreen extends ConsumerStatefulWidget {
  final String purpose;

  /// `purpose == 'waypoint'` 일 때 채울 경유지 칸 index.
  ///
  /// 칸은 검색바의 + 가 미리 만들어 두고, 이 화면은 그 칸을 채우기만 한다.
  /// null 이면 빈 칸을 찾아 채우고 없으면 맨 뒤에 추가한다(방어적 폴백).
  final int? waypointIndex;

  const StationPickerScreen({
    super.key,
    required this.purpose,
    this.waypointIndex,
  });

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
      'waypoint' => '경유역 선택',
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
                hintText: '역 이름 또는 초성 검색',
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
          // 최근 검색 이력(마지막 1건): 출발/도착 선택 화면에서 검색어 입력 전에만
          // 노출한다. 'home'(지도 시작점) purpose 에는 표시하지 않는다.
          if (_query.isEmpty &&
              (widget.purpose == 'departure' || widget.purpose == 'arrival'))
            const _RecentSearchSection(),
          Expanded(
            child: stationsAsync.when(
              data: (stations) {
                // 초성 검색 지원: 'ㄱㄴ' → 강남. 초성이 섞이지 않은 검색어는
                // 기존 부분일치와 동작이 같다 — [matchesStationQuery].
                //
                // 엄격 매칭이 비면 조합 중인 종성을 떼어 한 번 더 거른다
                // ('사당' 입력 중 '삳' 한 타에 목록이 비는 것 방지). 결과가
                // 있을 때는 켜지 않아 평소 매칭 범위는 넓어지지 않는다.
                var filtered = _query.isEmpty
                    ? stations
                    : stations
                        .where((s) => matchesStationQuery(s.name, _query))
                        .toList();
                if (filtered.isEmpty && _query.isNotEmpty) {
                  filtered = stations
                      .where((s) => matchesStationQuery(s.name, _query,
                          splitTrailingJamo: true))
                      .toList();
                }

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

                // 같은 물리 역(환승역)의 노선별 레코드를 하나의 항목으로 통합한다.
                // 이름이 같아도 위치가 먼 동명이역(5호선 양평 vs 경의중앙선 양평)은
                // 별개 항목으로 남는다 — 자세한 규칙은 [uniqueStationsByLocation].
                final unique = uniqueStationsByLocation(filtered);

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

  void _selectStation(Station station) {
    switch (widget.purpose) {
      case 'departure':
        ref.read(selectedStationsProvider.notifier).setDeparture(station);
      case 'arrival':
        ref.read(selectedStationsProvider.notifier).setArrival(station);
      case 'waypoint':
        final notifier = ref.read(selectedStationsProvider.notifier);
        final index = widget.waypointIndex;
        if (index == null) {
          // index 누락 방어 — 빈 칸을 채우거나 맨 뒤에 추가.
          notifier.addWaypoint(station);
        } else {
          notifier.setWaypoint(index, station);
        }
      case 'home':
        // fire-and-forget: SharedPreferences 저장 후 상태 반영. 실패 시
        // provider 가 이전 값을 유지하므로 UI 는 안전하게 되돌아간다.
        ref.read(homeStationIdProvider.notifier).setHomeStation(station.id);
    }
    Navigator.of(context).pop();
  }
}

/// 최근 검색(마지막 1건) 이력 섹션.
///
/// [recentSearchStationsProvider]를 watch 하여 유효한 출발→도착 쌍이 있을 때만
/// 카드를 렌더한다(이력 없음/삭제된 역/로딩/에러 → 숨김). 탭하면 두 역을 원자적
/// 으로 선택한 뒤 곧바로 경로 결과 화면으로 이동한다.
class _RecentSearchSection extends ConsumerWidget {
  const _RecentSearchSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(recentSearchStationsProvider).asData?.value;
    if (pair == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space16,
            AppSpacing.space4,
            AppSpacing.space16,
            AppSpacing.space8,
          ),
          child: Text(
            '최근 검색',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        InkWell(
          onTap: () => _onTap(context, ref, pair.departure, pair.arrival),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space16,
              vertical: AppSpacing.space12,
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 20, color: Colors.grey[600]),
                const SizedBox(width: AppSpacing.space12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: _StationLabel(station: pair.departure)),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.space8,
                        ),
                        child: Icon(Icons.arrow_forward, size: 16),
                      ),
                      Flexible(child: _StationLabel(station: pair.arrival)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    Station departure,
    Station arrival,
  ) async {
    // 두 역을 원자적으로 설정(중간 stale isComplete 방지) 후 결과 화면으로.
    ref.read(selectedStationsProvider.notifier).setBoth(departure, arrival);
    await searchAndNavigateToResult(context, ref);
  }
}

/// 최근 검색 카드 내 역 이름 + 노선 색상 점.
class _StationLabel extends StatelessWidget {
  final Station station;

  const _StationLabel({required this.station});

  @override
  Widget build(BuildContext context) {
    final lineId =
        station.isTransfer && station.transferLines.isNotEmpty
            ? station.transferLines.first
            : station.lineId;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: lineColorFor(lineId)),
        const SizedBox(width: AppSpacing.space6),
        Flexible(
          child: Text(
            station.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
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
