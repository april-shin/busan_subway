import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'domain/entities/route_result.dart';
import 'features/arrival_info/presentation/screens/arrival_info_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/route_search/presentation/screens/route_result_screen.dart';
import 'features/route_search/presentation/screens/station_picker_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
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
        GoRoute(
          path: 'settings',
          builder: (context, state) => const SettingsScreen(),
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
      builder: appRootBuilder,
    );
  }
}

/// `MaterialApp.router` 의 `builder` 콜백.
///
/// 두 가지 변환을 한 번에 적용한다:
///   (1) 시스템 폰트 배율(textScaler)을 0.9~1.15 로 클램프.
///       너무 작으면 가독성 저하, 너무 크면 레이아웃 깨짐.
///       4원칙 코드(map.html WebView) 는 textScaler 영향 없음 (자체 CSS).
///   (2) Android 15 edge-to-edge 처리: bottom inset 만큼 콘텐츠 올림.
///       MediaQuery 가 바깥, SafeArea 가 안쪽이어야 SafeArea 가
///       `MediaQuery.of(context).padding` 을 정상적으로 읽어들인다.
///
/// `@visibleForTesting` 으로 노출해 위젯 테스트가 동일 builder 패턴을
/// 그대로 검증할 수 있게 한다.
@visibleForTesting
Widget appRootBuilder(BuildContext context, Widget? child) {
  if (child == null) return const SizedBox.shrink();

  final mq = MediaQuery.of(context);
  final clamped = mq.textScaler.clamp(
    minScaleFactor: 0.9,
    maxScaleFactor: 1.15,
  );

  return MediaQuery(
    data: mq.copyWith(textScaler: clamped),
    child: SafeArea(
      top: false,
      child: child,
    ),
  );
}
