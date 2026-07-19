// lib/core/constants/app_info.dart
//
// 앱 버전 정보. `pubspec.yaml` 의 `version:` 값이 유일한 소스이며,
// 빌드 시 iOS Info.plist / Android build.gradle 로 주입된 값을
// `package_info_plus` 로 읽어와 앱 시작 시 1회만 캐싱한다.
//
// 초기화: `main()` 에서 `runApp` 이전에 반드시 `AppInfo.init()` 를 호출.
// 이후 모든 접근은 동기 상수처럼 사용 가능.
//
// 사용처:
// - 설정 화면 앱 버전 표기 (settings_screen.dart)
// - 슬랙 피드백 메타데이터 (feedback_tile.dart)

import 'package:package_info_plus/package_info_plus.dart';

abstract final class AppInfo {
  static late final String version;

  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
  }

  /// `버전 1.0.1` 형식의 표시 문자열.
  static String get versionLabel => '버전 $version';
}
