class ApiConstants {
  ApiConstants._();

  static const String subwayBaseUrl =
      'http://swopenapi.seoul.go.kr/api/subway';

  static String realtimeArrivalUrl(String apiKey, String stationName) =>
      '$subwayBaseUrl/$apiKey/json/realtimeStationArrival/0/20/$stationName';

  // 캐시 TTL 은 refreshInterval 이하로 유지해야 한다.
  // 초과하면 refresh 때 캐시 응답만 재사용되어 실제 API 호출이 일어나지 않는다.
  // 서울 열린데이터 일일 호출 한도(1,000건/일) 절약을 위해 15초 주기로 운영한다.
  static const Duration cacheTtl = Duration(seconds: 15);
  static const Duration refreshInterval = Duration(seconds: 15);
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);

  /// "도착(0초)" 상태를 신뢰할 수 있는 최대 데이터 경과시간.
  ///
  /// 도착 정보의 시간 값은 모두 `recptnDt`(API 등록시각) 기준이다. 도착 상태
  /// (`arvlCd=1`, `barvlDt=0`)는 잔여초가 아니라 "그 시각에 역에 있었다"는
  /// **상태**이므로, 데이터가 오래되면 이미 떠난 열차를 "0초"로 보여주게 된다.
  /// 이 시간을 넘긴 도착 상태는 0초가 아니라 **알 수 없음**으로 처리한다.
  ///
  /// 값 근거(2026-07-30 실측): 1~9호선 등 정상 갱신 노선의 `recptnDt` 지연은
  /// 28~59초. GTX-A 는 73~817초, 서해선은 444~777초까지 지연된다. 120초로 두면
  /// 정상 노선의 표시는 그대로 유지하면서 갱신이 멈춘 노선만 걸러진다.
  static const Duration arrivalStateGrace = Duration(seconds: 120);
}
