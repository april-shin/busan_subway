// lib/core/theme/tokens/app_radii.dart
//
// BorderRadius 토큰. Card/Container/Badge 등의 모서리 반경.

import 'package:flutter/widgets.dart';

abstract final class AppRadius {
  static const double xs = 4; // 배지(노선/급행), InputDecoration 내부
  static const double sm = 8; // 카운트다운 박스, StationField
  static const double md = 12; // Card, InputDecoration outer
  static const double lg = 16;
  static const double pill = 9999; // 캡슐
}

abstract final class AppBorderRadius {
  static const BorderRadius xs =
      BorderRadius.all(Radius.circular(AppRadius.xs));
  static const BorderRadius sm =
      BorderRadius.all(Radius.circular(AppRadius.sm));
  static const BorderRadius md =
      BorderRadius.all(Radius.circular(AppRadius.md));
  static const BorderRadius lg =
      BorderRadius.all(Radius.circular(AppRadius.lg));
  static const BorderRadius pill =
      BorderRadius.all(Radius.circular(AppRadius.pill));
}
