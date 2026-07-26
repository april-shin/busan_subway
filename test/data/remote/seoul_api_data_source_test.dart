import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/core/network/api_client.dart';
import 'package:seoul_subway/data/remote/seoul_api_data_source.dart';

class MockApiClient extends Mock implements ApiClient {}

Response<String> _emptyResponse() => Response<String>(
      requestOptions: RequestOptions(path: ''),
      data: '{"realtimeArrivalList":[]}',
    );

void main() {
  late MockApiClient mockApiClient;
  late SeoulApiDataSource dataSource;

  setUpAll(() {
    dotenv.testLoad(mergeWith: {'SEOUL_SUBWAY_API_KEY': 'testkey'});
  });

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = SeoulApiDataSource(apiClient: mockApiClient);
    when(() => mockApiClient.get<String>(any()))
        .thenAnswer((_) async => _emptyResponse());
  });

  String capturedUrl() =>
      verify(() => mockApiClient.get<String>(captureAny())).captured.single
          as String;

  group('SeoulApiDataSource 질의명 치환', () {
    test('부역명 필요 역은 API 등록명으로 질의한다 (남한산성입구)', () async {
      await dataSource.getRealtimeArrival('남한산성입구');

      final url = capturedUrl();
      expect(url, contains('남한산성입구(성남법원,검찰청)'));
      // 표시명 단독(괄호 없는 형태)으로 끝나지 않아야 한다.
      expect(url.endsWith('/남한산성입구'), isFalse);
    });

    test('축약 케이스도 API 등록명으로 질의한다 (평택지제 → 지제)', () async {
      await dataSource.getRealtimeArrival('평택지제');

      final url = capturedUrl();
      expect(url, endsWith('/지제'));
      expect(url, isNot(contains('평택지제')));
    });

    test('치환 대상이 아닌 역은 표시명 그대로 질의한다 (강남)', () async {
      await dataSource.getRealtimeArrival('강남');

      final url = capturedUrl();
      expect(url, endsWith('/강남'));
      expect(url, isNot(contains('(')));
    });
  });
}
