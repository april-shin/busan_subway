import 'package:flutter/material.dart';

/// 부산 지하철 앱 전역 TextTheme.
///
/// 정책:
///   - fontFamily 명시 X — Typography.material2021(android) 가 Roboto 메트릭을
///     적용하고, 한글은 시스템 fallback 으로 자연 처리됨.
///   - height(line-height) 한국어 가독성을 위해 본문 계열 1.45 로 통일.
///   - 인라인 TextStyle() 사용 금지. 모든 Text 는 Theme.of(context).textTheme.* 사용.
const TextTheme appTextTheme = TextTheme(
  // ───── Display: 거의 사용 안 함. 매우 큰 헤더용 ─────
  displayLarge: TextStyle(
    fontSize: 57,
    fontWeight: FontWeight.w400,
    height: 1.12,
    letterSpacing: -0.25,
  ),
  displayMedium: TextStyle(
    fontSize: 45,
    fontWeight: FontWeight.w400,
    height: 1.16,
    letterSpacing: 0,
  ),
  displaySmall: TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w400,
    height: 1.22,
    letterSpacing: 0,
  ),

  // ───── Headline: 화면 최상단 큰 제목 (현재 미사용, 향후 확장 여지) ─────
  headlineLarge: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w400,
    height: 1.25,
    letterSpacing: 0,
  ),
  headlineMedium: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w400,
    height: 1.29,
    letterSpacing: 0,
  ),
  headlineSmall: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0,
  ),

  // ───── Title: AppBar/카드 제목/요약 헤더 (메인 사용처) ─────
  // titleLarge: 22px bold — 출발/도착 시각 헤더
  titleLarge: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.27,
    letterSpacing: 0,
  ),
  // titleMedium: 16px semi-bold — 카드 1차 제목 (도착 노선명 등)
  titleMedium: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.50,
    letterSpacing: 0.15,
  ),
  // titleSmall: 14px semi-bold — 강조 본문 (역명 endpoint)
  titleSmall: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.43,
    letterSpacing: 0.1,
  ),

  // ───── Body: 일반 본문 ─────
  // bodyLarge: 16px bold — 카운트다운 분 표시 (실측 18 → 16 으로 다운)
  bodyLarge: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.50,
    letterSpacing: 0.5,
  ),
  // bodyMedium: 14px regular — 일반 본문, 에러 메시지
  bodyMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: 0.25,
  ),
  // bodySmall: 12px regular — 보조 본문, 직선 표시, 가이드 노트
  bodySmall: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0.4,
  ),

  // ───── Label: 라벨/배지/칩 ─────
  // labelLarge: 14px medium — 칩 텍스트, 출발/도착 라벨
  labelLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.43,
    letterSpacing: 0.1,
  ),
  // labelMedium: 13px medium — 환승 가이드, InfoChip
  labelMedium: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.38,
    letterSpacing: 0.5,
  ),
  // labelSmall: 11px medium — 카운트다운 초 단위 보조
  labelSmall: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.45,
    letterSpacing: 0.5,
  ),
);
