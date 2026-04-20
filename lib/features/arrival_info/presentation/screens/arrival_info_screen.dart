import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/line_colors.dart';
import '../../../../core/constants/subway_id_mapping.dart';
import '../../../../core/utils/enrich_arrival_info.dart';
import '../../../../domain/entities/arrival_info.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';
import '../providers/arrival_providers.dart';
import '../widgets/arrival_card.dart';

/// 환승역에서 노선별로 도착 정보를 분리해서 보여주기 위해
/// 외부(노선) 탭 + 내부(상행/하행) 탭의 2단 구조로 구성한다.
/// 비환승역은 노선 탭을 생략하고 상행/하행 탭만 표시한다.
class ArrivalInfoScreen extends ConsumerStatefulWidget {
  final String stationName;

  const ArrivalInfoScreen({super.key, required this.stationName});

  @override
  ConsumerState<ArrivalInfoScreen> createState() => _ArrivalInfoScreenState();
}

class _ArrivalInfoScreenState extends ConsumerState<ArrivalInfoScreen> {
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  List<ArrivalInfo> _previousEnriched = [];

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(
      ApiConstants.refreshInterval,
      (_) => _refresh(),
    );
  }

  void _refresh() {
    ref.invalidate(arrivalInfoProvider(widget.stationName));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool _isUp(ArrivalInfo a) =>
      a.direction == '상행' || a.direction == '내선';

  bool _isDown(ArrivalInfo a) =>
      a.direction == '하행' || a.direction == '외선';

  @override
  Widget build(BuildContext context) {
    final arrivalAsync = ref.watch(arrivalInfoProvider(widget.stationName));
    final stationsAsync = ref.watch(allStationsProvider);
    final connectionsAsync = ref.watch(allConnectionsProvider);

    return arrivalAsync.when(
      data: (rawArrivals) {
        final stations = stationsAsync.valueOrNull;
        final connections = connectionsAsync.valueOrNull;
        final arrivals = (stations != null && connections != null)
            ? enrichArrivalInfoList(
                arrivals: rawArrivals,
                targetStationName: widget.stationName,
                stations: stations,
                connections: connections,
                previousArrivals: _previousEnriched,
              )
            : rawArrivals;
        _previousEnriched = arrivals;

        // subwayId로 그룹화 → 노선 탭의 기준
        final groups = <String, List<ArrivalInfo>>{};
        for (final a in arrivals) {
          groups.putIfAbsent(a.subwayId, () => []).add(a);
        }
        final subwayIds = groups.keys.toList()
          ..sort((a, b) => _lineSortKey(a).compareTo(_lineSortKey(b)));

        return _buildContent(subwayIds, groups);
      },
      loading: () => Scaffold(
        appBar: _appBar(showRefresh: true),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: _appBar(showRefresh: true),
        body: _buildError(error),
      ),
    );
  }

  /// 노선 정렬 키: 숫자 노선(1~9)은 그 숫자, 그 외는 큰 값으로 뒤쪽 배치.
  int _lineSortKey(String subwayId) {
    final lineId = subwayIdToLineId[subwayId] ?? subwayId;
    final n = int.tryParse(lineId);
    return n ?? (1000 + subwayId.hashCode % 100);
  }

  AppBar _appBar({
    required bool showRefresh,
    PreferredSizeWidget? bottom,
  }) {
    return AppBar(
      title: Text('${widget.stationName} 실시간 도착'),
      bottom: bottom,
      actions: [
        if (showRefresh)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
      ],
    );
  }

  Widget _buildContent(
    List<String> subwayIds,
    Map<String, List<ArrivalInfo>> groups,
  ) {
    // 노선이 0개(완전 빈 응답) 또는 1개: 노선 탭 없이 상/하 탭만
    if (subwayIds.length <= 1) {
      final arrivals =
          subwayIds.isEmpty ? <ArrivalInfo>[] : groups[subwayIds.first]!;
      return _buildSingleLine(arrivals, includeAppBar: true);
    }

    // 환승역: 노선 탭(상단) + 각 탭 안에 상/하 탭
    return DefaultTabController(
      length: subwayIds.length,
      child: Scaffold(
        appBar: _appBar(
          showRefresh: true,
          bottom: TabBar(
            isScrollable: true,
            tabs: subwayIds.map(_buildLineTab).toList(),
          ),
        ),
        body: TabBarView(
          children: subwayIds
              .map((id) => _buildSingleLine(groups[id]!, includeAppBar: false))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildLineTab(String subwayId) {
    final lineId = subwayIdToLineId[subwayId] ?? subwayId;
    final name = lineNames[lineId] ?? lineId;
    final color = lineColorFor(lineId);

    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(name),
        ],
      ),
    );
  }

  /// 단일 노선의 상/하 탭 뷰. 비환승역에서는 그대로 Scaffold(`includeAppBar: true`),
  /// 환승역의 노선 탭 안쪽에서는 Scaffold 없이 Column만(`includeAppBar: false`).
  Widget _buildSingleLine(
    List<ArrivalInfo> arrivals, {
    required bool includeAppBar,
  }) {
    final isLine2 = arrivals.isNotEmpty &&
        arrivals.every((a) => a.subwayId == '1002');
    final upLabel = isLine2 ? '내선' : '상행';
    final downLabel = isLine2 ? '외선' : '하행';

    final upbound = arrivals.where(_isUp).toList();
    final downbound = arrivals.where(_isDown).toList();

    final tabBar = TabBar(
      tabs: [Tab(text: upLabel), Tab(text: downLabel)],
    );

    if (includeAppBar) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: _appBar(showRefresh: true, bottom: tabBar),
          body: TabBarView(
            children: [
              _buildArrivalList(upbound, upLabel),
              _buildArrivalList(downbound, downLabel),
            ],
          ),
        ),
      );
    }

    // 환승역의 노선 탭 안에서는 자체 TabBar를 Column 상단에 둠
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 1,
            child: tabBar,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildArrivalList(upbound, upLabel),
                _buildArrivalList(downbound, downLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              '도착 정보를 불러올 수 없습니다',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              _userFriendlyError(error),
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  String _userFriendlyError(Object error) {
    final message = error.toString();
    if (message.contains('네트워크') || message.contains('연결')) {
      return '인터넷 연결을 확인해 주세요.';
    }
    if (message.contains('API_KEY') || message.contains('api_key')) {
      return 'API 키가 설정되지 않았습니다. .env 파일을 확인해 주세요.';
    }
    if (message.contains('시간 초과') || message.contains('timeout')) {
      return '서버 응답이 느립니다. 잠시 후 다시 시도해 주세요.';
    }
    return '일시적인 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
  }

  Widget _buildArrivalList(
    List<ArrivalInfo> arrivals,
    String direction,
  ) {
    if (arrivals.isEmpty) {
      return Center(
        child: Text(
          '$direction 방면 도착 정보가 없습니다',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: arrivals.length,
        itemBuilder: (context, index) {
          return ArrivalCard(arrival: arrivals[index]);
        },
      ),
    );
  }
}
