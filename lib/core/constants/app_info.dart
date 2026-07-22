// lib/core/constants/app_info.dart
//
// 앱 버전 정보 상수. `pubspec.yaml` 의 `version: 1.0.1+2` 값과 수동으로
// 맞춰 관리한다. `package_info_plus` 를 도입하지 않고 정적 상수로 유지해
// 부팅 지연·의존성 증가를 피한다.
//
// 사용처:
// - 설정 화면 앱 버전 표기 (settings_screen.dart)
// - 슬랙 피드백 메타데이터 (feedback_tile.dart)

abstract final class AppInfo {
  static const String version = '1.0.1';
  static const String build = '2';

  /// `버전 1.0.1 (build 2)` 형식의 표시 문자열.
  static const String versionLabel = '버전 $version (build $build)';
}
