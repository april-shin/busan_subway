import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../domain/usecases/search_route.dart';
import '../../../ads/presentation/widgets/home_banner_ad.dart';
import '../../../route_search/presentation/providers/timetable_providers.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';
import '../../../subway_map/presentation/screens/subway_map_screen.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/settings_fab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // AppBar 없음. Scaffold 배경색(surface)이 상태바 영역을 채우고,
    // 지도는 SafeArea top 안쪽(상태바 아래)부터 시작한다 — 몰입형 아님.
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // 바닥 레이어: 지도 전체화면. SafeArea top 존중.
                // selectedStations 와 독립 — Consumer 밖에 두어 출발/도착
                // 선택 변경 시 리빌드되지 않도록 리빌드 경계를 유지한다.
                const Positioned.fill(
                  child: SafeArea(
                    bottom: false,
                    child: SubwayMapScreen(),
                  ),
                ),
                // floating 설정 버튼: 좌측 하단.
                // 자기 크기(48x48)만 차지하므로 지도 줌/팬/탭에 방해되지 않는다.
                const Positioned(
                  left: AppSpacing.space16,
                  bottom: AppSpacing.space16,
                  child: SettingsFab(),
                ),
                // floating 오버레이: 상단에 겹쳐 뜨는 검색바.
                // 자기 bounds(상단)만 차지하므로 나머지 지도 영역의
                // 줌/팬/탭 터치는 그대로 지도로 전달된다.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final selectedStations =
                            ref.watch(selectedStationsProvider);
                        return RouteSearchBar(
                          departure: selectedStations.departure,
                          arrival: selectedStations.arrival,
                          onDepartureTap: () =>
                              context.go('/pick-station/departure'),
                          onArrivalTap: () =>
                              context.go('/pick-station/arrival'),
                          onSwap: () {
                            ref.read(selectedStationsProvider.notifier).swap();
                          },
                          onSearchRoute: selectedStations.isComplete
                              ? () => _searchRoute(context, ref)
                              : null,
                          // 취소(X): 각 입력창 내부 우측에서 해당 역만 취소.
                          // 선택된 역이 있을 때만 콜백을 전달해 X 를 노출한다.
                          onClearDeparture: selectedStations.departure != null
                              ? () => ref
                                  .read(selectedStationsProvider.notifier)
                                  .setDeparture(null)
                              : null,
                          onClearArrival: selectedStations.arrival != null
                              ? () => ref
                                  .read(selectedStationsProvider.notifier)
                                  .setArrival(null)
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const HomeBannerAd(),
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
