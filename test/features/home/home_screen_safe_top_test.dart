// 배선 가드: 홈 화면이 검색 카드 높이를 mapSafeTopProvider 에 기록하고,
// SvgWebView 가 그 값을 JS(setSafeTop)로 전달한다. 한 줄을 지우면 깨진다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/home/presentation/screens/home_screen.dart';
import 'package:busan_subway/features/home/presentation/widgets/search_bar_widget.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

void main() {
  testWidgets('HomeScreen 이 검색 카드 높이를 mapSafeTopProvider 에 기록한다', (tester) async {
    // 지도(WebView) 로딩을 막으려 역 목록은 영원히 pending (favorite_tag_bar_test 와 같은 우회).
    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith(
          (ref) => Completer<List<Station>>().future,
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(mapSafeTopProvider), 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final cardHeight = tester.getSize(find.byType(RouteSearchBar)).height;
    expect(cardHeight, greaterThan(0));
    expect(container.read(mapSafeTopProvider), cardHeight);
  });

  test('SvgWebView 소스가 setSafeTop 을 listen 과 페이지 로드 재전달 두 곳에서 보낸다', () {
    final src = File(
      'lib/features/subway_map/presentation/widgets/svg_web_view.dart',
    ).readAsStringSync();

    // (1) 값 변경 listen: 준비된 경우에만 JS 호출.
    expect(src, contains('ref.listen(mapSafeTopProvider'));
    expect(src, contains(r"_runJs('window.setSafeTop($next)')"));
    // (2) 페이지 로드/복구 재로드 시 현재 값 재전달.
    final onLoaded = src.indexOf('void _onPageLoaded()');
    expect(onLoaded, greaterThan(0));
    final body = src.substring(onLoaded, src.indexOf('_injectStationData();', onLoaded));
    expect(body, contains('ref.read(mapSafeTopProvider)'));
    expect(body, contains(r"_runJs('window.setSafeTop($_safeTop)')"));
  });

  test('HomeScreen 소스가 RouteSearchBar 를 HeightReporter 로 감싼다', () {
    final src = File(
      'lib/features/home/presentation/screens/home_screen.dart',
    ).readAsStringSync();
    final reporter = src.indexOf('HeightReporter(');
    expect(reporter, greaterThan(0));
    expect(src.indexOf('RouteSearchBar(', reporter), greaterThan(reporter));
    expect(src, contains('mapSafeTopProvider'));
  });
}
