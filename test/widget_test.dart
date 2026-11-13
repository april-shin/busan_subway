// 홈 화면(HomeScreen)이 floating 검색바 스타일로 개편된 이후의 스모크 테스트.
//
// 예전에는 `BusanSubwayApp` 전체를 pump 하여 `MaterialApp.title`("부산 지하철")
// 텍스트를 찾았지만, 그 title은 OS 작업전환 화면 등에만 쓰일 뿐 실제
// 위젯 트리에는 렌더되지 않는다 — AppBar가 있던 과거에도 사실상 잘못된
// 검증이었고, AppBar를 제거한 지금은 더더욱 통과할 수 없다.
//
// 이 테스트는 실제로 화면에 렌더되는 것(floating RouteSearchBar, AppBar
// 부재)을 검증한다. 전체 앱 대신 `HomeScreen`만 pump하여 아래 의존성을
// 결정론적으로 우회한다:
//   - allStationsProvider(Future) 를 영원히 pending 상태로 override.
//     SubwayMapScreen은 이 provider가 resolve되기 전까지
//     CircularProgressIndicator만 그리므로, WebView(SvgWebView)가 실제로
//     로드되지 않는다. WebView는 테스트 환경(flutter test)에서 플랫폼
//     채널이 없어 초기화가 불안정하므로 이렇게 우회한다.
//   - .env / BUSAN_SUBWAY_API_KEY 등 런타임 환경변수는 이 화면 트리에서 직접
//     쓰이지 않으므로 별도 처리가 필요 없다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/home/presentation/screens/home_screen.dart';
import 'package:busan_subway/features/home/presentation/widgets/search_bar_widget.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

void main() {
  /// `allStationsProvider`를 영원히 resolve되지 않는 Future로 고정해
  /// SubwayMapScreen 하위 트리(WebView 포함)의 실제 로딩을 막는다.
  /// 검색바는 selectedStationsProvider(동기 StateNotifierProvider)만
  /// 필요로 하므로 이 override와 무관하게 즉시 렌더된다.
  Widget buildHarness() {
    return ProviderScope(
      overrides: [
        allStationsProvider.overrideWith(
          (ref) => Completer<List<Station>>().future,
        ),
      ],
      child: const MaterialApp(
        home: HomeScreen(),
      ),
    );
  }

  testWidgets('홈 화면은 AppBar 없이 floating RouteSearchBar를 렌더한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildHarness());
    // pumpAndSettle 대신 pump: allStationsProvider가 영원히 pending이라
    // pumpAndSettle은 타임아웃으로 실패한다. 첫 프레임만 확인하면 충분하다.
    await tester.pump();

    expect(find.byType(RouteSearchBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('지도 데이터 로딩 중에도 검색바는 출발/도착 placeholder를 표시한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pump();

    expect(find.text('출발역을 선택하세요'), findsOneWidget);
    expect(find.text('도착역을 선택하세요'), findsOneWidget);
  });
}
