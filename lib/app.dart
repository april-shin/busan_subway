import 'package:flutter/material.dart';
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
            if (extra
                is ({
                  RouteResult fastest,
                  RouteResult? leastTransfer,
                  String departureStationName,
                })) {
              return RouteResultScreen(
                fastest: extra.fastest,
                leastTransfer: extra.leastTransfer,
                departureStationName: extra.departureStationName,
              );
            }
            // 하위 호환: 기존 단일 경로 전달 방식 지원
            if (extra
                is ({
                  RouteResult routeResult,
                  String departureStationName,
                })) {
              return RouteResultScreen(
                fastest: extra.routeResult,
                leastTransfer: null,
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
    return MaterialApp.router(
      title: '서울 지하철',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
