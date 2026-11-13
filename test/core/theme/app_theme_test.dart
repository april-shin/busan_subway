import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/theme/app_theme.dart';

void main() {
  // AppTheme.light 는 getter 이므로 매 테스트에서 fresh 하게 얻는다.
  ThemeData theme() => AppTheme.light;

  group('AppTheme.light — Material 3 설정 검증', () {
    test('useMaterial3 == true', () {
      expect(theme().useMaterial3, isTrue);
    });

    test('typography 가 TargetPlatform.android 기반으로 설정되어 있어야 한다', () {
      // Typography.material2021(platform: TargetPlatform.android) 와 동등한지 확인한다.
      // 직접 비교는 Typography 가 == 연산자를 지원하지 않으므로 black/white TextTheme 의
      // displayLarge fontSize 로 대조한다 (M2021 android 표준 값: 57).
      final expected = Typography.material2021(platform: TargetPlatform.android);
      expect(
        theme().typography.black.displayLarge?.fontSize,
        expected.black.displayLarge?.fontSize,
        reason: 'typography 가 material2021(android) 기준이 아닌 것으로 보인다',
      );
    });
  });

  group('AppTheme.light — TextTheme 슬롯 값 검증', () {
    test('textTheme.titleLarge?.fontSize == 22', () {
      expect(theme().textTheme.titleLarge?.fontSize, 22.0);
    });

    test('textTheme.bodyLarge?.fontWeight == w700', () {
      expect(theme().textTheme.bodyLarge?.fontWeight, FontWeight.w700);
    });

    test('textTheme.labelSmall?.fontSize == 11', () {
      expect(theme().textTheme.labelSmall?.fontSize, 11.0);
    });
  });

  group('AppTheme.light — ColorScheme 시드값 보존 검증', () {
    // 시드 색상 0xFF0052A4 기반임을 primary 색상 대역으로 검증한다.
    // ColorScheme.fromSeed 는 시드와 "동일"하지 않을 수 있지만 hue 계열이 일치해야 한다.
    test('colorScheme.primary 가 파란 계열 (hue ~220°) 이어야 한다', () {
      final primary = theme().colorScheme.primary;
      // HSLColor 로 변환해 hue 가 180~260 사이인지 확인 (파란 계열).
      final hsl = HSLColor.fromColor(primary);
      expect(
        hsl.hue,
        inInclusiveRange(180.0, 260.0),
        reason: 'ColorScheme 시드(0xFF0052A4 = 파란색)가 변경된 것으로 의심된다',
      );
    });

    test('colorScheme.brightness == Brightness.light', () {
      expect(theme().colorScheme.brightness, Brightness.light);
    });
  });

  group('AppTheme.light — AppBarTheme 보존 검증', () {
    test('appBarTheme.centerTitle == true', () {
      expect(theme().appBarTheme.centerTitle, isTrue);
    });

    test('appBarTheme.elevation == 0', () {
      expect(theme().appBarTheme.elevation, 0.0);
    });
  });

  group('AppTheme.light — BackButton 기본 동작 위임 검증', () {
    // `actionIconTheme.backButtonIconBuilder` 명시 등록 시 iOS 26 + Material 3
    // 환경에서 leading 영역이 빈 회색 박스로 깨지는 회귀가 있어 등록을 제거.
    // Flutter 의 기본 `BackButtonIcon` 이 `Theme.of(context).platform` 을
    // 보고 iOS chevron / Android arrow_back 을 자동 선택하므로 명시 등록
    // 없이도 platform-aware 동작이 유지된다.
    test('actionIconTheme 미등록 (Flutter 기본 BackButton 동작 위임)', () {
      expect(theme().actionIconTheme?.backButtonIconBuilder, isNull);
    });
  });

  group('AppTheme.light — CardTheme / InputDecorationTheme 보존 검증', () {
    test('cardTheme.elevation == 1', () {
      expect(theme().cardTheme.elevation, 1.0);
    });

    test('inputDecorationTheme.filled == true', () {
      expect(theme().inputDecorationTheme.filled, isTrue);
    });
  });
}
