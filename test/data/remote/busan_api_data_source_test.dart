import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busan_subway/core/network/api_client.dart';
import 'package:busan_subway/data/remote/busan_api_data_source.dart';

class MockApiClient extends Mock implements ApiClient {}

Response<String> _emptyResponse() => Response<String>(
  requestOptions: RequestOptions(path: ''),
  data: '{"realtimeArrivalList":[]}',
);

/// 지정한 노선(subwayId) 열차만 담은 응답. 병합 결과를 노선으로 식별하기 위한 최소 행.
Response<String> _responseWithLines(List<String> subwayIds) => Response<String>(
  requestOptions: RequestOptions(path: ''),
  data: json.encode({
    'realtimeArrivalList': [
      for (final id in subwayIds) {'subwayId': id},
    ],
  }),
);

void main() {
  late MockApiClient mockApiClient;
  late BusanApiDataSource dataSource;

  setUpAll(() {
    dotenv.testLoad(mergeWith: {'BUSAN_SUBWAY_API_KEY': 'testkey'});
  });

  setUp(() {
    mockApiClient = MockApiClient();
    dataSource = BusanApiDataSource(apiClient: mockApiClient);
    when(
      () => mockApiClient.get<String>(any()),
    ).thenAnswer((_) async => _emptyResponse());
  });

  String capturedUrl() =>
      verify(() => mockApiClient.get<String>(captureAny())).captured.single
          as String;

  group('BusanApiDataSource 질의명 치환', () {
    test(
      '부역명 필요 역은 API 등록명으로 질의한다 (남한산성입구)',
      () async {
        await dataSource.getRealtimeArrival('남한산성입구');

        final url = capturedUrl();
        expect(url, contains('남한산성입구(성남법원,검찰청)'));
        // 표시명 단독(괄호 없는 형태)으로 끝나지 않아야 한다.
        expect(url.endsWith('/남한산성입구'), isFalse);
      },
      skip:
          '부산 전환: 역명 치환 맵(arrivalApiStationNameOverrides 등)이 const 빈 맵이라 서울 치환 사례를 검증할 수 없음 — 부산 API 등록명을 채울 때 부산 사례로 교체',
    );

    test(
      '축약 케이스도 API 등록명으로 질의한다 (평택지제 → 지제)',
      () async {
        await dataSource.getRealtimeArrival('평택지제');

        final url = capturedUrl();
        expect(url, endsWith('/지제'));
        expect(url, isNot(contains('평택지제')));
      },
      skip:
          '부산 전환: 역명 치환 맵(arrivalApiStationNameOverrides 등)이 const 빈 맵이라 서울 치환 사례를 검증할 수 없음 — 부산 API 등록명을 채울 때 부산 사례로 교체',
    );

    test('치환 대상이 아닌 역은 표시명 그대로 질의한다 (강남)', () async {
      await dataSource.getRealtimeArrival('강남');

      final url = capturedUrl();
      expect(url, endsWith('/강남'));
      expect(url, isNot(contains('(')));
    });
  });

  group(
    'BusanApiDataSource 복수 질의명 병합',
    () {
      // 등록명이 노선별로 갈린 역(서울역·올림픽공원)만 여러 번 조회한다.
      // capturedUrl() 은 .captured.single 이라 2회 호출에는 쓸 수 없어 별도 헬퍼를 둔다.
      List<String> capturedUrls() => verify(
        () => mockApiClient.get<String>(captureAny()),
      ).captured.cast<String>();

      test('서울역은 "서울"·"서울역" 두 이름으로 조회한다', () async {
        await dataSource.getRealtimeArrival('서울역');

        final urls = capturedUrls();
        expect(urls, hasLength(2));
        expect(urls.any((u) => u.endsWith('/서울')), isTrue, reason: '주 질의 누락');
        expect(urls.any((u) => u.endsWith('/서울역')), isTrue, reason: '보조 질의 누락');
      });

      test('올림픽공원은 부역명·본역명 두 이름으로 조회한다', () async {
        await dataSource.getRealtimeArrival('올림픽공원');

        final urls = capturedUrls();
        expect(urls, hasLength(2));
        expect(urls.any((u) => u.endsWith('/올림픽공원(한국체대)')), isTrue);
        expect(urls.any((u) => u.endsWith('/올림픽공원')), isTrue);
      });

      test('두 질의 결과를 병합해 모든 노선을 반환한다', () async {
        when(
          () => mockApiClient.get<String>(any(that: endsWith('/서울'))),
        ).thenAnswer((_) async => _responseWithLines(['1001', '1004']));
        when(
          () => mockApiClient.get<String>(any(that: endsWith('/서울역'))),
        ).thenAnswer((_) async => _responseWithLines(['1032']));

        final result = await dataSource.getRealtimeArrival('서울역');

        expect(result.arrivals, hasLength(3));
        expect(
          result.arrivals.map((d) => d.subwayId),
          containsAll(<String>['1001', '1004', '1032']),
        );
        expect(result.isPartial, isFalse, reason: '둘 다 성공했으므로 온전한 결과');
      });

      group('질의들은 대등하다 (주/보조 구분 없음)', () {
        test('다수 노선 쪽이 실패해도 성공한 쪽을 부분 결과로 반환한다', () async {
          when(
            () => mockApiClient.get<String>(any(that: endsWith('/서울'))),
          ).thenThrow(Exception('서울 질의 실패'));
          when(
            () => mockApiClient.get<String>(any(that: endsWith('/서울역'))),
          ).thenAnswer((_) async => _responseWithLines(['1032']));

          final result = await dataSource.getRealtimeArrival('서울역');

          expect(result.arrivals.map((d) => d.subwayId), <String>['1032']);
          expect(result.isPartial, isTrue, reason: '캐시를 덮어쓰지 않도록 알려야 함');
        });

        test('소수 노선 쪽이 실패해도 성공한 쪽을 부분 결과로 반환한다', () async {
          when(
            () => mockApiClient.get<String>(any(that: endsWith('/서울'))),
          ).thenAnswer((_) async => _responseWithLines(['1001']));
          when(
            () => mockApiClient.get<String>(any(that: endsWith('/서울역'))),
          ).thenThrow(Exception('서울역 질의 실패'));

          final result = await dataSource.getRealtimeArrival('서울역');

          expect(result.arrivals.map((d) => d.subwayId), <String>['1001']);
          expect(result.isPartial, isTrue);
        });
      });

      test('전부 실패해야 예외를 던진다 (캐시 폴백 조건)', () async {
        when(
          () => mockApiClient.get<String>(any(that: endsWith('/서울'))),
        ).thenThrow(Exception('서울 질의 실패'));
        when(
          () => mockApiClient.get<String>(any(that: endsWith('/서울역'))),
        ).thenThrow(Exception('서울역 질의 실패'));

        await expectLater(
          dataSource.getRealtimeArrival('서울역'),
          throwsA(isA<Exception>()),
        );
      });

      test('단일 질의명 역은 항상 isPartial=false 다', () async {
        final result = await dataSource.getRealtimeArrival('강남');
        expect(result.isPartial, isFalse);
      });
    },
    skip:
        '부산 전환: 역명 치환 맵(arrivalApiStationNameOverrides 등)이 const 빈 맵이라 서울 치환 사례를 검증할 수 없음 — 부산 API 등록명을 채울 때 부산 사례로 교체',
  );
}
