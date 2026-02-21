class ApiConstants {
  ApiConstants._();

  static const String subwayBaseUrl =
      'http://swopenapi.seoul.go.kr/api/subway';

  static String realtimeArrivalUrl(String apiKey, String stationName) =>
      '$subwayBaseUrl/$apiKey/json/realtimeStationArrival/0/20/$stationName';

  static const Duration cacheTtl = Duration(seconds: 30);
  static const Duration refreshInterval = Duration(seconds: 15);
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
