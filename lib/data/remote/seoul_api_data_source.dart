import 'dart:convert';

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
      throw Exception('SEOUL_API_KEY가 설정되지 않았습니다');
    }

    final url = ApiConstants.realtimeArrivalUrl(apiKey, stationName);
    final response = await _apiClient.get<String>(url);

    final data = json.decode(response.data!) as Map<String, dynamic>;

    if (data.containsKey('errorMessage')) {
      final errorInfo = data['errorMessage'] as Map<String, dynamic>;
      final status = errorInfo['status'] as String?;
      if (status == 'ERROR') {
        final message = errorInfo['message'] as String? ?? '알 수 없는 오류';
        throw Exception('API 오류: $message');
      }
    }

    final realtimeArrivalList = data['realtimeArrivalList'];
    if (realtimeArrivalList == null) return [];

    final arrivalList = realtimeArrivalList as List<dynamic>;
    return arrivalList
        .map((e) => ArrivalInfoDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
