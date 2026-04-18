class ApiConstants {
  ApiConstants._();

  static const String subwayBaseUrl =
      'http://swopenapi.seoul.go.kr/api/subway';

  static String realtimeArrivalUrl(String apiKey, String stationName) =>
      '$subwayBaseUrl/$apiKey/json/realtimeStationArrival/0/20/$stationName';

  // 캐시 TTL 은 refreshInterval 이하로 유지해야 한다.
  // 초과하면 refresh 때 캐시 응답만 재사용되어 실제 API 호출이 일어나지 않는다.
  static const Duration cacheTtl = Duration(seconds: 10);
  static const Duration refreshInterval = Duration(seconds: 10);
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
