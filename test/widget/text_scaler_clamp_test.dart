import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/app.dart' show appRootBuilder;

/// lib/app.dart 의 builder 에서 수행하는 textScaler clamp 로직을 직접 추출해
/// 단위 테스트로 검증한다.
///
/// 클램프 명세: minScaleFactor=0.9, maxScaleFactor=1.15
/// (lib/app.dart appRootBuilder 의 clamped 계산부 참고)
TextScaler _applyClamp(TextScaler input) {
  return input.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);
}

void main() {
  group('textScaler clamp — 0.9~1.15 범위 클램프 검증', () {
    test('입력 0.5 → 출력 0.9 (하한 클램프)', () {
      final result = _applyClamp(TextScaler.linear(0.5));
      // TextScaler.linear 는 textScaleFactor 와 동일한 배수.
      expect(result.scale(1.0), closeTo(0.9, 1e-9));
    });

    test('입력 1.0 → 출력 1.0 (범위 안, 변화 없음)', () {
      final result = _applyClamp(TextScaler.linear(1.0));
      expect(result.scale(1.0), closeTo(1.0, 1e-9));
    });

    test('입력 2.0 → 출력 1.15 (상한 클램프)', () {
      final result = _applyClamp(TextScaler.linear(2.0));
      expect(result.scale(1.0), closeTo(1.15, 1e-9));
    });

    test('입력 1.1 → 출력 1.1 (범위 안, 변화 없음)', () {
      final result = _applyClamp(TextScaler.linear(1.1));
      expect(result.scale(1.0), closeTo(1.1, 1e-9));
    });

    test('입력 0.9 (하한 경계) → 출력 0.9 (변화 없음)', () {
      final result = _applyClamp(TextScaler.linear(0.9));
      expect(result.scale(1.0), closeTo(0.9, 1e-9));
    });

    test('입력 1.15 (상한 경계) → 출력 1.15 (변화 없음)', () {
      final result = _applyClamp(TextScaler.linear(1.15));
      expect(result.scale(1.0), closeTo(1.15, 1e-9));
    });

    test('입력 0.85 → 출력 0.9 (설계 문서 예시: 0.85→0.9)', () {
      final result = _applyClamp(TextScaler.linear(0.85));
      expect(result.scale(1.0), closeTo(0.9, 1e-9));
    });

    test('입력 1.3 → 출력 1.15 (설계 문서 예시: 1.3→1.15)', () {
      final result = _applyClamp(TextScaler.linear(1.3));
      expect(result.scale(1.0), closeTo(1.15, 1e-9));
    });
  });

  group('textScaler clamp — appRootBuilder 위젯 통합 검증', () {
    // lib/app.dart 의 appRootBuilder 를 직접 import 해 MaterialApp.builder 로 주입.
    // 외부 MediaQuery(textScaler: input) 를 씌우고, 내부 위젯이 받는 textScaler 를 캡처.
    // 이렇게 하면 실제 앱과 동일한 builder 함수 경로를 검증한다.
    TextScaler? captured;

    Widget buildTestApp({required TextScaler inputScaler}) {
      captured = null;
      return MediaQuery(
        data: MediaQueryData(textScaler: inputScaler),
        child: MaterialApp(
          // @visibleForTesting 으로 노출된 실제 lib/app.dart builder 사용.
          builder: appRootBuilder,
          home: Builder(
            builder: (innerCtx) {
              // appRootBuilder 가 MediaQuery 를 clamp 한 뒤 child 로 내려주므로
              // 여기서 읽으면 클램프된 값을 얻는다.
              captured = MediaQuery.of(innerCtx).textScaler;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }

    testWidgets('appRootBuilder: 0.5 → 0.9 하한 클램프', (tester) async {
      await tester.pumpWidget(buildTestApp(inputScaler: TextScaler.linear(0.5)));
      expect(captured, isNotNull);
      expect(captured!.scale(1.0), closeTo(0.9, 1e-9));
    });

    testWidgets('appRootBuilder: 1.0 → 1.0 변화 없음', (tester) async {
      await tester.pumpWidget(buildTestApp(inputScaler: TextScaler.linear(1.0)));
      expect(captured, isNotNull);
      expect(captured!.scale(1.0), closeTo(1.0, 1e-9));
    });

    testWidgets('appRootBuilder: 2.0 → 1.15 상한 클램프', (tester) async {
      await tester.pumpWidget(buildTestApp(inputScaler: TextScaler.linear(2.0)));
      expect(captured, isNotNull);
      expect(captured!.scale(1.0), closeTo(1.15, 1e-9));
    });

    testWidgets('appRootBuilder: 1.1 → 1.1 범위 안 변화 없음', (tester) async {
      await tester.pumpWidget(buildTestApp(inputScaler: TextScaler.linear(1.1)));
      expect(captured, isNotNull);
      expect(captured!.scale(1.0), closeTo(1.1, 1e-9));
    });

    testWidgets('appRootBuilder: child == null 이면 SizedBox.shrink 반환', (tester) async {
      // builder 에 child=null 을 직접 호출해 방어 코드 검증.
      // pumpWidget 으로 직접 렌더링하여 null child 케이스를 검증.
      await tester.pumpWidget(
        Builder(
          builder: (ctx) => appRootBuilder(ctx, null),
        ),
      );
      // SizedBox.shrink 가 렌더링되면 예외 없이 완료.
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });
}
