import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import 'dto/arrival_info_dto.dart';

class SeoulApiDataSource {
  final ApiClient _apiClient;

  SeoulApiDataSource({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<ArrivalInfoDto>> getRealtimeArrival(String stationName) async {
    final apiKey = dotenv.env['SEOUL_API_KEY'];
    if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
      developer.log(
        'API 키 오류: SEOUL_API_KEY가 설정되지 않았습니다',
        name: 'SeoulApiDataSource',
        level: 1000,
      );
      throw Exception('SEOUL_API_KEY가 설정되지 않았습니다');
    }

    final url = ApiConstants.realtimeArrivalUrl(apiKey, stationName);

    developer.log(
      '실시간 도착정보 요청: 역명=$stationName',
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
