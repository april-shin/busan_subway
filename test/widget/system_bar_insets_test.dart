import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/app.dart' show appRootBuilder;
import 'package:seoul_subway/core/theme/app_theme.dart';

/// Android 15(API 35)+ edge-to-edge 회귀 가드.
///
/// 시스템 nav bar 가 앱 콘텐츠 위에 그려지는 환경에서 루트 builder 가
/// 세 가지를 보장해야 한다:
///   (1) bottom inset 만큼 콘텐츠를 올리고, 자손에게는 그 inset 을 소비된
///       것으로 보여준다 (이중 패딩 방지).
///   (2) 비워진 하단 띠를 Flutter 가 surface 색으로 직접 칠한다
///       (안 칠하면 Android window background 노출 → 다크모드 기기에서 검은 띠).
///   (3) nav bar/status bar 아이콘을 dark 로 지정한다. MaterialApp 이 테마
///       brightness 기준으로 호출하는 SystemUiOverlayStyle.dark 프리셋은
///       nav bar 아이콘을 흰색으로 두는데, 이 앱은 light 전용이라
///       흰 배경 위 흰 아이콘이 되어 보이지 않는다.
void main() {
  const bottomInset = 48.0;
  const topInset = 24.0;

  /// appRootBuilder 를 Theme + MediaQuery 아래에서 직접 호출한다.
  /// (실제 앱에서도 MaterialApp.builder 는 AnimatedTheme 안쪽에서 호출되므로
  ///  Theme.of / MediaQuery.of 가 동일하게 해석된다.)
  Widget buildHarness({required Widget child}) {
    return MediaQuery(
      data: const MediaQueryData(
        padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
        viewPadding: EdgeInsets.only(top: topInset, bottom: bottomInset),
      ),
      child: Theme(
        data: AppTheme.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) => appRootBuilder(context, child),
          ),
        ),
      ),
    );
  }

  testWidgets('bottom inset 만큼 콘텐츠를 올리고 자손에게는 소비된 상태로 전달한다',
      (tester) async {
    EdgeInsets? innerPadding;

    await tester.pumpWidget(
      buildHarness(
        child: Builder(
          builder: (context) {
            innerPadding = MediaQuery.of(context).padding;
            return const SizedBox.expand(key: Key('content'));
          },
        ),
      ),
    );

    // (1) bottom 은 SafeArea 가 소비 → 자손은 0 으로 본다. 이중 패딩 방지.
    expect(innerPadding!.bottom, 0);
    // top 은 SafeArea(top:false) 로 통과 → AppBar/Scaffold 가 직접 처리.
    expect(innerPadding!.top, topInset);

    // 콘텐츠 실제 높이가 bottom inset 만큼 줄었는지 확인.
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final contentHeight = tester.getSize(find.byKey(const Key('content'))).height;
    expect(contentHeight, screenHeight - bottomInset);
  });

  testWidgets('비워진 하단 띠를 surface 색 ColoredBox 로 칠한다', (tester) async {
    await tester.pumpWidget(
      buildHarness(child: const SizedBox.expand()),
    );

    // (2) SafeArea 를 감싸는 ColoredBox 가 전체 화면을 덮고, 색은 surface.
    final coloredBox = tester.widget<ColoredBox>(
      find.ancestor(
        of: find.byType(SafeArea),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(coloredBox.color, AppTheme.light.colorScheme.surface);

    final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    final boxSize = tester.getSize(
      find.ancestor(
        of: find.byType(SafeArea),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(boxSize.height, screenSize.height);
  });

  testWidgets('시스템 바 아이콘을 dark 로 지정한다 (MaterialApp 기본값 덮어쓰기)',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(child: const SizedBox.expand()),
    );

    // (3) 루트 AnnotatedRegion 이 nav bar/status bar 아이콘을 dark 로 고정.
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
    expect(region.value.statusBarIconBrightness, Brightness.dark);
    // iOS: light = 밝은 배경 → 어두운 글자.
    expect(region.value.statusBarBrightness, Brightness.light);
    // nav bar 색은 하단 띠와 동일해야 한다 (API 35 미만 경로).
    expect(
      region.value.systemNavigationBarColor,
      AppTheme.light.colorScheme.surface,
    );
    expect(region.value.statusBarColor, Colors.transparent);
  });

  testWidgets('AnnotatedRegion 이 ColoredBox 보다 바깥이어야 한다 (전체화면 샘플링)',
      (tester) async {
    await tester.pumpWidget(
      buildHarness(child: const SizedBox.expand()),
    );

    // RenderView 는 화면 최하단 픽셀(nav bar 중앙)에서 annotation 을 찾는다.
    // 리전이 SafeArea 안쪽에 있으면 그 지점을 덮지 못해 무시된다.
    expect(
      find.ancestor(
        of: find.byType(ColoredBox),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
      findsOneWidget,
    );
  });
}
