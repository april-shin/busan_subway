class ApiConstants {
  ApiConstants._();

  static const String subwayBaseUrl =
      'http://swopenapi.seoul.go.kr/api/subway';

  /// 도착정보 1회 질의로 받아올 최대 행 수.
  ///
  /// 종전 20 은 4개 노선 환승역에서 실제로 절단됐다 — 2026-07-31 금요일 18:45 실측
  /// `total`: 서울역 22, 왕십리 21, 공덕 20, 청량리 20 (그 외 주요 환승역은 4~17).
  /// 한 질의에 5개 노선이 걸리는 역은 없으므로 관측 최대 22 에 여유를 둔 30 으로 잡았다.
  /// 상한이라 20행 미만인 대다수 역의 응답 크기·캐시 용량에는 영향이 없다.
  static const int arrivalRowLimit = 30;

  static String realtimeArrivalUrl(String apiKey, String stationName) =>
      '$subwayBaseUrl/$apiKey/json/realtimeStationArrival'
      '/0/$arrivalRowLimit/$stationName';

  /// 노선별 실시간 열차 위치 API.
  ///
  /// 도착정보 API 가 특정 (역, 노선) 을 아예 제공하지 않는 경우의 폴백 경로다.
  /// 이 API 는 역이 아니라 **노선** 단위로 전 열차를 돌려주므로 그 공백을 우회한다.
  ///
  /// 계기가 된 5호선 천호(`1005000547`)는 **2026-08-04 부터 정상 제공된다** — 등록명
  /// `천호(풍납토성)` 질의 하나로 5호선 4건 + 8호선 4건이 온다(2026-08-04 실측).
  /// 2026-07-31 조사 시점에는 일괄 조회(`.../ALL`)에도 없어 미제공이었다. 폴백은
  /// 조건부("해당 노선 0건")라 지금 천호에서는 걸리지 않으며, 같은 공백이 다른
  /// (역, 노선) 에서 재발할 때를 위한 안전망으로 남긴다.
  ///
  /// 한 노선의 재차 열차는 60대 이하라 100건이면 전량을 덮는다(5호선 실측 53대).
  static String realtimePositionUrl(String apiKey, String lineApiName) =>
      '$subwayBaseUrl/$apiKey/json/realtimePosition/0/100/$lineApiName';

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
