// lib/core/utils/foldable_layout.dart
//
// 펼친 폴더블 iPhone(iPhone Duo) 레이아웃 판정.
//
// 펼친 Duo 에서는 배너 광고를 "오른쪽 페이지 하단"에만 띄운다(사용자 결정
// 2026-10-28). **다른 기기는 기존 배치 그대로**여야 하므로 판정을 좁게 잡는다.
//
// - Flutter 는 iOS 에서 접힘선(`MediaQuery.displayFeatures`)을 주지 않는다
//   (Duo 실측: `[]`). 그래서 접힘선은 화면 가로 중앙으로 가정한다.
// - 화면 폭만으로는 iPad·가로모드 iPhone 과 구분되지 않아, 네이티브 idiom
//   (`AppDelegate.swift` 의 `seoul_subway/device` 채널)이 phone 이면서 짧은 변이
//   [kUnfoldedMinShortestSide] 이상일 때만 펼친 Duo 로 본다.
//   일반 iPhone 은 가로로 돌려도 짧은 변이 440pt 이하, 접힌 Duo 는 466pt,
//   펼친 Duo 는 669pt(실측)다.
//
// 초기화: `main()` 에서 `runApp` 이전에 `FoldableLayout.init()` 호출.

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// 펼친 폴더블로 볼 짧은 변 하한(logical px).
const double kUnfoldedMinShortestSide = 600;

/// [isIosPhone] 기기에서 화면 [size] 가 펼친 폴더블인지.
///
/// 가로가 더 긴 경우로 한정한다 — 펼친 채 세로로 돌리면 접힘선이 가로선이
/// 되어 "가로 중앙 접힘선" 가정이 깨지므로 기존 배치로 둔다.
bool isUnfoldedFoldable({required Size size, required bool isIosPhone}) =>
    isIosPhone &&
    size.width > size.height &&
    size.shortestSide >= kUnfoldedMinShortestSide;

/// 오른쪽 페이지의 쓸 수 있는 폭.
///
/// 접힘선(화면 중앙)부터 오른쪽 safe area(Duo 는 세로 상태바 84pt) 앞까지.
/// [view] 는 SafeArea 로 padding 이 지워지기 전의 원본 값이어야 한다
/// (`MediaQueryData.fromView`).
double rightPageWidth(MediaQueryData view) =>
    view.size.width / 2 - view.padding.right;

abstract final class FoldableLayout {
  static const _channel = MethodChannel('seoul_subway/device');

  static bool _isIosPhone = false;

  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      _isIosPhone = await _channel.invokeMethod<bool>('isPhoneIdiom') ?? false;
    } on PlatformException {
      _isIosPhone = false;
    } on MissingPluginException {
      _isIosPhone = false;
    }
  }

  @visibleForTesting
  static set isIosPhoneForTesting(bool value) => _isIosPhone = value;

  /// 현재 화면이 펼친 폴더블인지. 다른 기기에서는 항상 false.
  static bool isUnfolded(BuildContext context) => isUnfoldedFoldable(
    size: MediaQuery.sizeOf(context),
    isIosPhone: _isIosPhone,
  );
}

/// 오른쪽 safe area 를 비우고 그 띠를 배경색으로 칠한다.
///
/// 펼친 Duo 에서는 앱 최상단 SafeArea 가 오른쪽을 비우지 않으므로(홈 지도를
/// 상태바 띠까지 깔기 위해), 홈 이외 화면을 이걸로 감싸 기존처럼 띠를 비운다.
/// 다른 기기는 padding.right 가 이미 0 이라 SafeArea 가 아무것도 하지 않고,
/// ColoredBox 는 불투명한 Scaffold 에 가려 보이지 않는다. 트리 모양을 늘
/// 같게 두어 접기/펼치기 때 화면 State 가 버려지지 않게 한다.
class RightSafeArea extends StatelessWidget {
  const RightSafeArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // 페이지 전환 중 아래 화면(홈 지도)이 띠로 비치지 않게 칠한다.
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(left: false, top: false, bottom: false, child: child),
    );
  }
}
