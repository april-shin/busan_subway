import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../data/remote/slack_feedback_data_source.dart';

part 'feedback_provider.g.dart';

/// 슬랙 피드백 전송용 데이터 소스 주입 통로.
///
/// 액션 상태(전송 중/성공/실패)는 `FeedbackTile` 위젯 로컬에서 관리하므로,
/// 이 프로바이더는 데이터 소스 인스턴스만 제공한다.
@riverpod
SlackFeedbackDataSource slackFeedbackDataSource(Ref ref) {
  return SlackFeedbackDataSource();
}
