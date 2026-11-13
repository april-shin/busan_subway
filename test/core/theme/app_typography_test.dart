import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/theme/tokens/app_typography.dart';

void main() {
  group('appTextTheme — 13개 슬롯 존재 검증', () {
    test('displayLarge 가 정의되어 있어야 한다', () {
      expect(appTextTheme.displayLarge, isNotNull);
    });
    test('displayMedium 이 정의되어 있어야 한다', () {
      expect(appTextTheme.displayMedium, isNotNull);
    });
    test('displaySmall 이 정의되어 있어야 한다', () {
      expect(appTextTheme.displaySmall, isNotNull);
    });
    test('headlineLarge 가 정의되어 있어야 한다', () {
      expect(appTextTheme.headlineLarge, isNotNull);
    });
    test('headlineMedium 이 정의되어 있어야 한다', () {
      expect(appTextTheme.headlineMedium, isNotNull);
    });
    test('headlineSmall 이 정의되어 있어야 한다', () {
      expect(appTextTheme.headlineSmall, isNotNull);
    });
    test('titleLarge 가 정의되어 있어야 한다', () {
      expect(appTextTheme.titleLarge, isNotNull);
    });
    test('titleMedium 이 정의되어 있어야 한다', () {
      expect(appTextTheme.titleMedium, isNotNull);
    });
    test('titleSmall 이 정의되어 있어야 한다', () {
      expect(appTextTheme.titleSmall, isNotNull);
    });
    test('bodyLarge 가 정의되어 있어야 한다', () {
      expect(appTextTheme.bodyLarge, isNotNull);
    });
    test('bodyMedium 이 정의되어 있어야 한다', () {
      expect(appTextTheme.bodyMedium, isNotNull);
    });
    test('bodySmall 이 정의되어 있어야 한다', () {
      expect(appTextTheme.bodySmall, isNotNull);
    });
    test('labelLarge 가 정의되어 있어야 한다', () {
      expect(appTextTheme.labelLarge, isNotNull);
    });
    test('labelMedium 이 정의되어 있어야 한다', () {
      expect(appTextTheme.labelMedium, isNotNull);
    });
    test('labelSmall 이 정의되어 있어야 한다', () {
      expect(appTextTheme.labelSmall, isNotNull);
    });
  });

  group('appTextTheme — 설계 명세 fontSize/fontWeight 일치 검증', () {
    test('titleLarge: fontSize=22, fontWeight=w700', () {
      final style = appTextTheme.titleLarge!;
      expect(style.fontSize, 22.0);
      expect(style.fontWeight, FontWeight.w700);
    });

    test('titleMedium: fontSize=16, fontWeight=w600', () {
      final style = appTextTheme.titleMedium!;
      expect(style.fontSize, 16.0);
      expect(style.fontWeight, FontWeight.w600);
    });

    test('titleSmall: fontSize=14, fontWeight=w600', () {
      final style = appTextTheme.titleSmall!;
      expect(style.fontSize, 14.0);
      expect(style.fontWeight, FontWeight.w600);
    });

    test('bodyLarge: fontSize=16, fontWeight=w700', () {
      final style = appTextTheme.bodyLarge!;
      expect(style.fontSize, 16.0);
      expect(style.fontWeight, FontWeight.w700);
    });

    test('bodyMedium: fontSize=14, fontWeight=w400', () {
      final style = appTextTheme.bodyMedium!;
      expect(style.fontSize, 14.0);
      expect(style.fontWeight, FontWeight.w400);
    });

    test('bodySmall: fontSize=12, fontWeight=w400', () {
      final style = appTextTheme.bodySmall!;
      expect(style.fontSize, 12.0);
      expect(style.fontWeight, FontWeight.w400);
    });

    test('labelLarge: fontSize=14, fontWeight=w500', () {
      final style = appTextTheme.labelLarge!;
      expect(style.fontSize, 14.0);
      expect(style.fontWeight, FontWeight.w500);
    });

    test('labelMedium: fontSize=13, fontWeight=w500', () {
      final style = appTextTheme.labelMedium!;
      expect(style.fontSize, 13.0);
      expect(style.fontWeight, FontWeight.w500);
    });

    test('labelSmall: fontSize=11, fontWeight=w500', () {
      final style = appTextTheme.labelSmall!;
      expect(style.fontSize, 11.0);
      expect(style.fontWeight, FontWeight.w500);
    });
  });

  group('appTextTheme — height(line-height) 정의 검증 (한국어 가독성 보장)', () {
    // 모든 슬롯은 height 가 null 이 아니어야 한다 (명시적으로 설정).
    test('titleLarge 의 height 가 정의되어 있어야 한다', () {
      expect(appTextTheme.titleLarge!.height, isNotNull);
    });
    test('bodyLarge 의 height 가 정의되어 있어야 한다', () {
      expect(appTextTheme.bodyLarge!.height, isNotNull);
    });
    test('bodyMedium 의 height 가 정의되어 있어야 한다', () {
      expect(appTextTheme.bodyMedium!.height, isNotNull);
    });
    test('bodySmall 의 height 가 정의되어 있어야 한다', () {
      expect(appTextTheme.bodySmall!.height, isNotNull);
    });
    test('labelSmall 의 height 가 정의되어 있어야 한다', () {
      expect(appTextTheme.labelSmall!.height, isNotNull);
    });
    // 본문 계열(body*)은 한국어 가독성을 위해 1.33 이상이어야 한다.
    test('bodyLarge height >= 1.33 (한국어 가독성)', () {
      expect(appTextTheme.bodyLarge!.height!, greaterThanOrEqualTo(1.33));
    });
    test('bodyMedium height >= 1.33 (한국어 가독성)', () {
      expect(appTextTheme.bodyMedium!.height!, greaterThanOrEqualTo(1.33));
    });
    test('bodySmall height >= 1.33 (한국어 가독성)', () {
      expect(appTextTheme.bodySmall!.height!, greaterThanOrEqualTo(1.33));
    });
  });

  group('appTextTheme — fontFamily 미지정 검증 (한글 fallback 보호)', () {
    // fontFamily 가 null 이어야 시스템 폰트(Apple SD Gothic Neo / Noto Sans CJK)가 fallback 된다.
    test('titleLarge 의 fontFamily 는 null 이어야 한다', () {
      expect(appTextTheme.titleLarge!.fontFamily, isNull);
    });
    test('bodyLarge 의 fontFamily 는 null 이어야 한다', () {
      expect(appTextTheme.bodyLarge!.fontFamily, isNull);
    });
    test('labelSmall 의 fontFamily 는 null 이어야 한다', () {
      expect(appTextTheme.labelSmall!.fontFamily, isNull);
    });
    test('전체 슬롯에서 fontFamily 가 명시된 슬롯이 없어야 한다', () {
      final slots = [
        appTextTheme.displayLarge,
        appTextTheme.displayMedium,
        appTextTheme.displaySmall,
        appTextTheme.headlineLarge,
        appTextTheme.headlineMedium,
        appTextTheme.headlineSmall,
        appTextTheme.titleLarge,
        appTextTheme.titleMedium,
        appTextTheme.titleSmall,
        appTextTheme.bodyLarge,
        appTextTheme.bodyMedium,
        appTextTheme.bodySmall,
        appTextTheme.labelLarge,
        appTextTheme.labelMedium,
        appTextTheme.labelSmall,
      ];
      for (final style in slots) {
        expect(style?.fontFamily, isNull,
            reason: '$style 슬롯에 fontFamily 가 명시되어 있어 한글 fallback 이 차단될 수 있다');
      }
    });
  });
}
