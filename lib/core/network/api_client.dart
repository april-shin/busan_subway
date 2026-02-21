import 'package:dio/dio.dart';

import '../constants/api_constants.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
    ));
  }

  Future<Response<T>> get<T>(String url) async {
    try {
      return await _dio.get<T>(url);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Exception _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('네트워크 연결 시간이 초과되었습니다');
      case DioExceptionType.connectionError:
        return Exception('네트워크에 연결할 수 없습니다');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode ?? 0;
        return Exception('서버 오류가 발생했습니다 (코드: $statusCode)');
      default:
        return Exception('알 수 없는 오류가 발생했습니다');
    }
  }
}
