import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seoul_subway/app.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: SeoulSubwayApp()),
    );

    expect(find.text('서울 지하철'), findsOneWidget);
  });
}
