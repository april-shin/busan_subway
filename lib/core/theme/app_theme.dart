import 'package:flutter/material.dart';

import 'tokens/app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      // ColorScheme 시드 보존 — 색상 팔레트 변경 X.
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0052A4),
        brightness: Brightness.light,
      ),
      // iOS 도 Android Roboto 메트릭 적용 → 글자 폭/줄간격 통일.
      typography: Typography.material2021(platform: TargetPlatform.android),
      // 시맨틱 슬롯 13 정의.
      textTheme: appTextTheme,
      // BackButton 은 Flutter 기본 동작에 위임 — `BackButtonIcon` 이 이미
      // `Theme.of(context).platform` 을 보고 iOS chevron / Android arrow_back
      // 을 자동 선택한다. `actionIconTheme.backButtonIconBuilder` 를 명시
      // 등록하면 iOS 26 + Material 3 조합에서 leading 영역이 빈 회색 박스로
      // 깨지는 회귀가 있어 등록을 제거한다.
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }
}
