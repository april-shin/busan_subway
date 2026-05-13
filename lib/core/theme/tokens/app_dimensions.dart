// lib/core/theme/tokens/app_dimensions.dart
//
// 4의 배수 그리드 기반 spacing/padding/iconSize 토큰.
// 인라인 매직 넘버(EdgeInsets.all(12), Icon size:14) 대신 사용한다.

abstract final class AppSpacing {
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6; // 비표준이지만 기존 코드에 6 다수
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;
}

/// 시맨틱 별칭 — 의미가 명확한 곳에서 사용.
abstract final class AppPadding {
  static const double screenHorizontal = AppSpacing.space16; // 화면 가장자리 좌우
  static const double screenVertical = AppSpacing.space12; // 화면 가장자리 상하
  static const double cardPadding = AppSpacing.space12; // Card 내부
  static const double cardOuterMargin = AppSpacing.space16; // Card 외곽 좌우
  static const double cardOuterMarginV = AppSpacing.space4; // Card 외곽 상하
  static const double listItemVertical = AppSpacing.space8;
  static const double summaryHeader = AppSpacing.space20; // 결과 요약 헤더 좌우
  static const double summaryHeaderV = AppSpacing.space16; // 결과 요약 헤더 상하
}

abstract final class AppIconSize {
  static const double xs = 12; // dot 표시
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  // 기존 14(InfoChip), 18(Tab icon) 은 가까운 sm/md 로 정규화.
}
