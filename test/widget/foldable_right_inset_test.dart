import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/app.dart' show appRootBuilder;
import 'package:busan_subway/core/theme/app_theme.dart';
import 'package:busan_subway/core/utils/foldable_layout.dart';

/// 펼친 iPhone Duo 오른쪽 상태바 띠 회귀 가드.
///
/// 펼친 Duo 에서만 루트 SafeArea 가 오른쪽을 비우지 않아 홈 지도가 띠까지
/// 깔린다. 다른 화면은 [RightSafeArea] 로 기존처럼 띠를 비운다.
/// 다른 기기에서는 루트가 오른쪽을 비워 기존과 동일해야 한다.
void main() {
  const rightInset = 84.0;

  tearDown(() => FoldableLayout.isIosPhoneForTesting = false);

  Future<EdgeInsets> pumpRoot(
    WidgetTester tester, {
    required Size size,
    Widget Function(Widget probe)? wrap,
  }) async {
    late EdgeInsets inner;
    final probe = Builder(
      builder: (context) {
        inner = MediaQuery.paddingOf(context);
        return const SizedBox.expand();
      },
    );
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(right: rightInset),
          viewPadding: const EdgeInsets.only(right: rightInset),
        ),
        child: Theme(
          data: AppTheme.light,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) =>
                  appRootBuilder(context, wrap?.call(probe) ?? probe),
            ),
          ),
        ),
      ),
    );
    return inner;
  }

  testWidgets('다른 기기: 루트가 오른쪽 inset 을 소비한다(기존 동작)', (tester) async {
    FoldableLayout.isIosPhoneForTesting = false;
    final inner = await pumpRoot(tester, size: const Size(951, 669));
    expect(inner.right, 0);
  });

  testWidgets('펼친 Duo: 루트가 오른쪽을 비우지 않아 홈이 띠까지 쓴다', (tester) async {
    FoldableLayout.isIosPhoneForTesting = true;
    final inner = await pumpRoot(tester, size: const Size(951, 669));
    expect(inner.right, rightInset);
  });

  testWidgets('펼친 Duo: RightSafeArea 로 감싼 화면은 띠를 비운다', (tester) async {
    FoldableLayout.isIosPhoneForTesting = true;
    final inner = await pumpRoot(
      tester,
      size: const Size(951, 669),
      wrap: (probe) => RightSafeArea(child: probe),
    );
    expect(inner.right, 0);
  });
}
