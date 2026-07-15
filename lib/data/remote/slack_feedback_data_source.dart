import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 슬랙 Incoming Webhook 으로 사용자 피드백을 전송한다.
///
/// `.env` 의 `SLACK_FEEDBACK_WEBHOOK_URL` 을 사용하며, 값이 없으면 예외를
/// 던진다. 응답 상태 코드가 200 아니면 예외로 실패를 알린다.
///
/// 슬랙 웹훅은 인증 토큰 없이 URL 자체가 시크릿이므로, 이 클래스는 리포지토리
/// 계층 없이 UI 프로바이더에서 직접 사용된다.
class SlackFeedbackDataSource {
  final Dio _dio;

  SlackFeedbackDataSource({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {'Content-Type': 'application/json'},
            ));

  Future<void> sendFeedback({
    required String message,
    required String appVersion,
    required String platform,
    required String osVersion,
  }) async {
    final url = dotenv.env['SLACK_FEEDBACK_WEBHOOK_URL'];
    if (url == null || url.isEmpty || url.startsWith('YOUR_')) {
      throw Exception('피드백 채널이 설정되지 않았습니다.');
    }

    // 슬랙은 mrkdwn 텍스트 렌더링. 사용자 본문은 트리플 백틱으로 감싸
    // 마크다운 이스케이핑 없이 그대로 전달한다.
    final text = '*[Seoul Subway] 사용자 의견*\n'
        '```\n'
        '$message\n'
        '```\n'
        '\n'
        '• 앱 버전: $appVersion\n'
        '• 플랫폼: $platform\n'
        '• OS: $osVersion';

    final response = await _dio.post<dynamic>(
      url,
      data: {'text': text},
    );

    if (response.statusCode != 200) {
      throw Exception('슬랙 응답 오류: ${response.statusCode}');
    }
  }
}
