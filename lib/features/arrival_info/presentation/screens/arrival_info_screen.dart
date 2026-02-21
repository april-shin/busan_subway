import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../providers/arrival_providers.dart';
import '../widgets/arrival_card.dart';

class ArrivalInfoScreen extends ConsumerStatefulWidget {
  final String stationName;

  const ArrivalInfoScreen({super.key, required this.stationName});

  @override
  ConsumerState<ArrivalInfoScreen> createState() => _ArrivalInfoScreenState();
}

class _ArrivalInfoScreenState extends ConsumerState<ArrivalInfoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _startAutoRefresh();
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
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arrivalAsync = ref.watch(arrivalInfoProvider(widget.stationName));

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stationName} 실시간 도착'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '상행/내선'),
            Tab(text: '하행/외선'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: arrivalAsync.when(
        data: (arrivals) {
          final upbound = arrivals
              .where((a) =>
                  a.direction == '상행' ||
                  a.direction == '내선')
              .toList();
          final downbound = arrivals
              .where((a) =>
                  a.direction == '하행' ||
                  a.direction == '외선')
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildArrivalList(upbound, '상행/내선'),
              _buildArrivalList(downbound, '하행/외선'),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
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
    List<dynamic> arrivals,
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
