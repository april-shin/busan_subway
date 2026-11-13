/// 앱 기능 on/off 스위치. 컴파일 타임 상수라 꺼진 분기는 tree-shaking 된다.
class FeatureFlags {
  FeatureFlags._();

  /// 실시간 기능(도착정보 화면 + 지도 위 실시간 열차) 사용 여부.
  ///
  /// **꺼져 있다(false).** 현재 연동된 실시간 API(서울 열린데이터)는 부산 노선을
  /// 제공하지 않는다. 부산 실시간 API 를 연동하면 true 로 바꾼다 — 코드는 모두
  /// 남겨 두었다(데이터소스·리포지토리·`liveTrainsProvider`·지도 JS 애니메이션).
  ///
  /// false 일 때:
  /// - `arrivalInfoProvider` 가 API 를 부르지 않고 빈 목록을 돌려준다. 경로 결과의
  ///   출발 시각은 그대로 시간표(배차간격) 폴백으로 계산된다.
  /// - `liveTrainsProvider` 가 API 를 부르지 않고 빈 목록을 돌려준다(새로고침
  ///   타이머도 만들지 않는다) → 지도에 실시간 열차가 그려지지 않는다.
  /// - 진입점을 숨긴다: 역 상세의 "실시간 도착 정보 보기" 버튼, 지도 툴팁의
  ///   "도착정보" 버튼. `/arrivals/...` 딥링크는 홈(`/`)으로 돌려보낸다.
  static const bool realtimeEnabled = false;
}
