import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/foldable_layout.dart';

void main() {
  group('isUnfoldedFoldable', () {
    test('펼친 iPhone Duo(951x669, phone) → true', () {
      expect(
        isUnfoldedFoldable(size: const Size(951, 669), isIosPhone: true),
        isTrue,
      );
    });

    test('펼친 iPhone Duo 를 세로로 돌림(669x951) → false — 접힘선 가정이 깨진다', () {
      expect(
        isUnfoldedFoldable(size: const Size(669, 951), isIosPhone: true),
        isFalse,
      );
    });

    test('접힌 iPhone Duo(466x678) → false', () {
      expect(
        isUnfoldedFoldable(size: const Size(466, 678), isIosPhone: true),
        isFalse,
      );
    });

    test('가로모드 iPhone Pro Max(956x440) → false — 기존 배치 유지', () {
      expect(
        isUnfoldedFoldable(size: const Size(956, 440), isIosPhone: true),
        isFalse,
      );
    });

    test('iPad(1194x834) → false — idiom 이 phone 이 아니다', () {
      expect(
        isUnfoldedFoldable(size: const Size(1194, 834), isIosPhone: false),
        isFalse,
      );
    });

    test('Android 폴더블(673x841) → false — iOS phone 만 대상', () {
      expect(
        isUnfoldedFoldable(size: const Size(673, 841), isIosPhone: false),
        isFalse,
      );
    });
  });

  test('rightPageWidth: 중앙 접힘선부터 오른쪽 safe area 앞까지', () {
    const view = MediaQueryData(
      size: Size(951, 669),
      padding: EdgeInsets.only(right: 84, bottom: 34),
    );
    expect(rightPageWidth(view), 951 / 2 - 84);
  });
}
