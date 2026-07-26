import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/station_api_name_overrides.dart';
import '../../core/network/api_client.dart';
import 'dto/arrival_info_dto.dart';

class SeoulApiDataSource {
  final ApiClient _apiClient;

  SeoulApiDataSource({required ApiClient apiClient}) : _apiClient = apiClient;

  /// 서울 열린데이터 실시간 지하철 도착정보 API를 호출한다.
  ///
  /// **엔드포인트:**
  /// `http://swopenapi.seoul.go.kr/api/subway/{apiKey}/json/realtimeStationArrival/0/20/{stationName}`
  ///
  /// **응답 필드 (`realtimeArrivalList[]`):**
  ///
  /// | 필드 | 타입 | 설명 |
  /// |------|------|------|
  /// | `subwayId` | String | 노선 ID (예: `"1002"` = 2호선) |
  /// | `updnLine` | String | 방향 (`"상행"` / `"하행"`) |
  /// | `trainLineNm` | String | 열차 행선지명 (예: `"성수행"`) |
  /// | `statnNm` | String | 도착 역명 |
  /// | `bstatnNm` | String | 종점역명 |
  /// | `barvlDt` | String | 도착 예상 시간 (초) |
  /// | `btrainSttus` | String | 열차 타입 (`"일반"` / `"급행"` 등) |
  /// | `arvlMsg2` | String | 도착 메시지 (예: `"전역 도착"`) |
  /// | `arvlMsg3` | String | 현재 위치 + 상태 (예: `"역삼 출발"`) |
  /// | `arvlCd` | String | 도착코드 — `0`: 진입, `1`: 도착, `2`: 출발, `3`: 전역 출발, `4`: 전역 진입, `5`: 전역 도착, `99`: 운행중 |
  /// | `recptnDt` | String | 데이터 수신 시간 (예: `"2024-01-01 12:00:00"`) |
  /// | `btrainNo` | String | 열차 번호 |
  /// | `ordkey` | String | 정렬 키 (열차 고유 식별) |
  /// | `lstcarAt` | String | 막차 여부 (`"0"`: 일반, `"1"`: 막차) |
  Future<List<ArrivalInfoDto>> getRealtimeArrival(String stationName) async {
    final apiKey = dotenv.env['SEOUL_SUBWAY_API_KEY'];
    if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
      developer.log(
        'API 키 오류: SEOUL_SUBWAY_API_KEY가 설정되지 않았습니다',
        name: 'SeoulApiDataSource',
        level: 1000,
      );
      throw Exception('SEOUL_SUBWAY_API_KEY가 설정되지 않았습니다');
    }

    // 일부 역은 부역명이 포함된 정식 등록명으로만 조회된다(예: "남한산성입구" →
    // "남한산성입구(성남법원,검찰청)"). 질의명만 API 등록명으로 치환하고, 캐시 키·
    // 화면 표시 등 앱 내부는 계속 표시용 역명(stationName)을 사용한다.
    final apiStationName = resolveArrivalApiStationName(stationName);
    final url = ApiConstants.realtimeArrivalUrl(apiKey, apiStationName);

    developer.log(
      '실시간 도착정보 요청: 역명=$stationName'
      '${apiStationName != stationName ? ' (API명=$apiStationName)' : ''}',
      name: 'SeoulApiDataSource',
    );

    try {
      final response = await _apiClient.get<String>(url);

      final data = json.decode(response.data!) as Map<String, dynamic>;

      if (data.containsKey('errorMessage')) {
        final errorInfo = data['errorMessage'] as Map<String, dynamic>;
        final status = errorInfo['status']?.toString();
        if (status == 'ERROR') {
          final message = errorInfo['message']?.toString() ?? '알 수 없는 오류';
          developer.log(
            'API 오류 응답: 역명=$stationName, 메시지=$message',
            name: 'SeoulApiDataSource',
            level: 1000,
          );
          throw Exception('API 오류: $message');
        }
      }

      final realtimeArrivalList = data['realtimeArrivalList'];
      if (realtimeArrivalList == null) {
        developer.log(
          '도착정보 없음: 역명=$stationName',
          name: 'SeoulApiDataSource',
        );
        return [];
      }

      final arrivalList = realtimeArrivalList as List<dynamic>;
      final result = arrivalList
          .map((e) => ArrivalInfoDto.fromJson(e as Map<String, dynamic>))
          .toList();

      developer.log(
        '실시간 도착정보 조회 성공: 역명=$stationName, 열차 수=${result.length}',
        name: 'SeoulApiDataSource',
      );

      return result;
    } catch (e) {
      developer.log(
        '실시간 도착정보 조회 실패: 역명=$stationName',
        name: 'SeoulApiDataSource',
        error: e,
      );
      rethrow;
    }
  }
}
