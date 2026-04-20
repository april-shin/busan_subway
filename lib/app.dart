import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'domain/entities/route_result.dart';
import 'features/arrival_info/presentation/screens/arrival_info_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/route_search/presentation/screens/route_result_screen.dart';
import 'features/route_search/presentation/screens/station_picker_screen.dart';
import 'features/station_detail/presentation/screens/station_detail_screen.dart';

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'pick-station/:purpose',
          builder: (context, state) => StationPickerScreen(
            purpose: state.pathParameters['purpose']!,
          ),
        ),
        GoRoute(
          path: 'route-result',
          builder: (context, state) {
            final extra = state.extra;
            // 4종 record: 환승 트레이드오프 + 모드 트레이드오프 판정용.
            // 모든 호출부(home_screen, subway_map_viewer)가 이 형태로 전달한다.
            if (extra
                is ({
                  RouteResult fastest,
                  RouteResult? leastTransfer,
                  RouteResult? fastestExpress,
                  RouteResult? fastestLocal,
                  String departureStationName,
                })) {
              return RouteResultScreen(
                fastest: extra.fastest,
                leastTransfer: extra.leastTransfer,
                fastestExpress: extra.fastestExpress,
                fastestLocal: extra.fastestLocal,
                departureStationName: extra.departureStationName,
              );
            }
            return const Scaffold(
              body: Center(child: Text('잘못된 경로입니다')),
            );
          },
        ),
        GoRoute(
          path: 'station/:stationId',
          builder: (context, state) => StationDetailScreen(
            stationId: state.pathParameters['stationId']!,
          ),
        ),
        GoRoute(
          path: 'arrivals/:stationName',
          builder: (context, state) => ArrivalInfoScreen(
            stationName: state.pathParameters['stationName']!,
          ),
        ),
      ],
    ),
  ],
);

class SeoulSubwayApp extends StatelessWidget {
  const SeoulSubwayApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Android 15(API 35)부터 edge-to-edge가 강제되어 시스템 네비게이션 바가
    // 앱 콘텐츠 위에 그려지면서 하단이 가려진다. 시스템 nav bar 색을 명시하고
    // 모든 화면을 SafeArea(top:false)로 감싸 bottom inset만큼 콘텐츠를 올린다.
    // top은 AppBar/Scaffold가 status bar 영역을 처리하므로 제외.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return MaterialApp.router(
      title: '서울 지하철',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: child,
        );
      },
    );
  }
}
