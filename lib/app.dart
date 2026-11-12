import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/foldable_layout.dart';
import 'features/arrival_info/presentation/screens/arrival_info_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/route_search/presentation/screens/route_result_screen.dart';
import 'features/route_search/presentation/utils/route_result_navigator.dart';
import 'features/route_search/presentation/screens/station_picker_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/station_detail/presentation/screens/station_detail_screen.dart';

/// 홈 이외 화면: 펼친 Duo 에서 오른쪽 상태바 띠를 기존처럼 비운다
/// ([RightSafeArea]). 다른 기기에서는 아무 효과 없음.
GoRouterWidgetBuilder _withRightSafeArea(GoRouterWidgetBuilder builder) =>
    (context, state) => RightSafeArea(child: builder(context, state));

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'pick-station/:purpose',
          // purpose == 'favorite-departure' / 'favorite-arrival' 은 설정의
          // 즐겨찾기 편집용 — `context.push<Station>` 으로 열면 고른 역을 pop
          // 결과로 돌려주고 전역 출발/도착 선택은 바꾸지 않는다.
          //
          // purpose == 'waypoint' 일 때 `?index=N` 으로 어느 경유지 칸을 채울지
          // 지정한다. 칸은 검색바의 + 가 미리 만들어 두므로 이 화면은 채우기만
          // 한다. 파싱 실패/누락이면 null → picker 가 빈 칸/맨 뒤로 폴백.
          builder: _withRightSafeArea(
            (context, state) => StationPickerScreen(
              purpose: state.pathParameters['purpose']!,
              waypointIndex: int.tryParse(
                state.uri.queryParameters['index'] ?? '',
              ),
            ),
          ),
        ),
        GoRoute(
          path: 'route-result',
          builder: _withRightSafeArea((context, state) {
            final extra = state.extra;
            // 4종 record: 환승 트레이드오프 + 모드 트레이드오프 판정용.
            // 모든 호출부(home_screen, subway_map_viewer)가 이 형태로 전달한다.
            if (extra is RouteResultExtra) {
              return RouteResultScreen(
                fastest: extra.fastest,
                leastTransfer: extra.leastTransfer,
                fastestExpress: extra.fastestExpress,
                fastestLocal: extra.fastestLocal,
                departureStationName: extra.departureStationName,
                searchedStations: extra.searchedStations,
              );
            }
            return const Scaffold(body: Center(child: Text('잘못된 경로입니다')));
          }),
        ),
        GoRoute(
          path: 'station/:stationId',
          builder: _withRightSafeArea(
            (context, state) => StationDetailScreen(
              stationId: state.pathParameters['stationId']!,
            ),
          ),
        ),
        GoRoute(
          // `?stationId=` 는 동명이역(5호선 양평 vs 경의중앙선 양평) 구분용 —
          // 없으면 역명만으로 조회한다(노선 필터 없음).
          path: 'arrivals/:stationName',
          builder: _withRightSafeArea(
            (context, state) => ArrivalInfoScreen(
              stationName: state.pathParameters['stationName']!,
              stationId: state.uri.queryParameters['stationId'],
            ),
          ),
        ),
        GoRoute(
          path: 'settings',
          builder: _withRightSafeArea(
            (context, state) => const SettingsScreen(),
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
    // 시스템 바 스타일은 여기서 명령형으로 설정하지 않는다.
    // MaterialApp 이 자기 build 안에서 테마 brightness 를 보고
    // `SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark)` 를
    // 매번 호출하므로(flutter/src/material/app.dart), build 전에 설정한 값은
    // 즉시 덮어써진다. 대신 appRootBuilder 의 AnnotatedRegion 에서 선언적으로
    // 지정한다 — RenderView 가 매 프레임 화면 최상/최하단에서 샘플링해
    // 적용하므로 MaterialApp 의 호출보다 나중에 반영된다.
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
/// 세 가지 변환을 한 번에 적용한다:
///   (1) 시스템 폰트 배율(textScaler)을 0.9~1.15 로 클램프.
///       너무 작으면 가독성 저하, 너무 크면 레이아웃 깨짐.
///       4원칙 코드(map.html WebView) 는 textScaler 영향 없음 (자체 CSS).
///   (2) Android 15 edge-to-edge 처리: bottom inset 만큼 콘텐츠 올림.
///       MediaQuery 가 바깥, SafeArea 가 안쪽이어야 SafeArea 가
///       `MediaQuery.of(context).padding` 을 정상적으로 읽어들인다.
///   (3) 시스템 바 영역 마감: SafeArea 로 비워진 하단 띠를 Flutter 가 직접
///       칠하고, 시스템 바 아이콘 밝기를 앱(light 전용)에 맞춘다.
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

  // Scaffold 기본 배경과 동일한 색 — 하단 띠가 본문과 이어져 보이게 한다.
  final surface = Theme.of(context).colorScheme.surface;

  return MediaQuery(
    data: mq.copyWith(textScaler: clamped),
    // AnnotatedRegion 은 RenderView 가 매 프레임 화면 최상단/최하단 픽셀에서
    // 샘플링해 반영하므로(rendering/view.dart), MaterialApp 이 테마 brightness
    // 기준으로 호출하는 SystemUiOverlayStyle.dark 를 덮어쓸 수 있다.
    // 그 프리셋은 nav bar 아이콘을 Brightness.light(흰색)로 두는데, 이 앱은
    // light 전용이라 흰 배경 위 흰 아이콘이 되어 보이지 않는다.
    // AppBar 가 있는 화면은 AppBar 의 AnnotatedRegion 이 상단(status bar)
    // 속성을 제공하고, 이 루트 리전이 하단(nav bar) 속성을 제공한다.
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Android
        statusBarBrightness: Brightness.light, // iOS
        // Android 15(API 35)+ 는 이 값을 무시한다(Window.setNavigationBarColor
        // deprecated·no-op). API 35 미만 대비로 남겨두고, 35+ 에서는 아래
        // ColoredBox 가 같은 색으로 그 영역을 칠해 결과를 동일하게 맞춘다.
        systemNavigationBarColor: surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      // SafeArea 가 만든 하단 여백은 Flutter 가 아무것도 그리지 않는 영역이라
      // 그대로 두면 Android window background 가 노출된다
      // (values-night 다크모드 기기에서는 검정 띠). 직접 칠해 막는다.
      child: ColoredBox(
        color: surface,
        child: SafeArea(
          top: false,
          // 펼친 iPhone Duo 에서만 오른쪽(세로 상태바 띠)을 비우지 않는다 —
          // 홈 지도가 그 띠까지 깔리도록(HomeScreen). Navigator Overlay·페이지
          // 전환이 자기 경계에서 클립하므로 지도만 밖으로 내밀 수 없다.
          // 다른 화면은 [RightSafeArea] 로 기존처럼 띠를 비운다.
          right: !FoldableLayout.isUnfolded(context),
          child: child,
        ),
      ),
    ),
  );
}
