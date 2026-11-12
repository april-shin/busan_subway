import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../core/utils/foldable_layout.dart';
import '../../../ads/presentation/widgets/home_banner_ad.dart';
import '../../../favorites/presentation/widgets/favorite_tag_bar.dart';
import '../../../route_search/presentation/utils/route_result_navigator.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';
import '../../../subway_map/presentation/screens/subway_map_screen.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/height_reporter.dart';
import '../widgets/settings_fab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // AppBar 없음. Scaffold 배경색(surface)이 상태바 영역을 채우고,
    // 지도는 SafeArea top 안쪽(상태바 아래)부터 시작한다 — 몰입형 아님.
    //
    // 배너: 기본은 지도 아래 별도 줄. 펼친 iPhone Duo 에서만 지도를 바닥까지
    // 깔고 배너를 오른쪽 페이지 하단에 겹쳐 띄운다(왼쪽 페이지 하단은 지도).
    //
    // 펼친 iPhone Duo 에서는 오른쪽 세로 상태바 띠까지 지도를 깐다(사용자 결정
    // 2026-10-28). 그때만 앱 최상단 SafeArea(app.dart)가 오른쪽을 비우지 않아
    // MediaQuery.padding.right(84pt)가 여기까지 내려온다. 지도만 right 를
    // 무시하고, 검색바(SafeArea)·배너(rightInset)는 띠 안쪽에 둔다.
    // 다른 기기에서는 padding.right 가 이미 0 이라 기존과 동일하다.
    final unfolded = FoldableLayout.isUnfolded(context);
    final rightInset = MediaQuery.paddingOf(context).right;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // 바닥 레이어: 지도 전체화면. SafeArea top 존중.
                // selectedStations 와 독립 — Consumer 밖에 두어 출발/도착
                // 선택 변경 시 리빌드되지 않도록 리빌드 경계를 유지한다.
                Positioned.fill(
                  child: SafeArea(
                    bottom: false,
                    right: !unfolded,
                    child: const SubwayMapScreen(),
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
                        final selectedStations = ref.watch(
                          selectedStationsProvider,
                        );
                        final notifier = ref.read(
                          selectedStationsProvider.notifier,
                        );
                        // 카드 높이를 지도에 알린다(경로 툴바가 카드 밑으로
                        // 들어가지 않게). SafeArea 안쪽 높이 = 지도 WebView(같은
                        // SafeArea top 안쪽에서 시작) 원점 기준 아래쪽 경계 y.
                        return HeightReporter(
                          onHeight: (h) =>
                              ref.read(mapSafeTopProvider.notifier).state = h,
                          child: RouteSearchBar(
                            departure: selectedStations.departure,
                            arrival: selectedStations.arrival,
                            waypoints: selectedStations.waypoints,
                            onDepartureTap: () =>
                                context.go('/pick-station/departure'),
                            onArrivalTap: () =>
                                context.go('/pick-station/arrival'),
                            // 경유지 칸 탭 = 역 선택 화면으로. 빈 칸은 "고르기",
                            // 채워진 칸은 "바꾸기" — 둘 다 그 index 를 채운다.
                            onWaypointTap: (index) => context.go(
                              '/pick-station/waypoint?index=$index',
                            ),
                            onWaypointClear: notifier.removeWaypointAt,
                            // + 버튼 = 화면 이동 없이 빈 칸만 추가.
                            // 상한 도달 시 null 을 넘겨 모든 + 를 숨긴다.
                            onAddSlotAt: selectedStations.canAddWaypoint
                                ? notifier.insertWaypointSlot
                                : null,
                            onSwap: () {
                              ref
                                  .read(selectedStationsProvider.notifier)
                                  .swap();
                            },
                            onSearchRoute: selectedStations.isComplete
                                ? () => searchAndNavigateToResult(context, ref)
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
                            // 즐겨찾기 태그 줄: 도착역 칸 아래. 자체 Consumer 라
                            // 즐겨찾기 변경이 검색바·지도를 다시 그리지 않는다.
                            footer: const FavoriteTagBar(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (unfolded)
                  Positioned(
                    right: rightInset,
                    bottom: 0,
                    child: const HomeBannerAd(),
                  ),
              ],
            ),
          ),
          if (!unfolded) const HomeBannerAd(),
        ],
      ),
    );
  }
}
