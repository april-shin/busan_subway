/// 모든 역에 대해 실시간 도착정보 API 호출 및 DTO 파싱을 검증하는 통합 테스트.
///
/// 실행 방법:
///   flutter test test/integration/realtime_arrival_all_stations_test.dart
///
/// 실행 방법 (기본 `flutter test` 에서는 dart_test.yaml 의 real-api skip 으로 제외됨):
///   flutter test --run-skipped --tags real-api
///
/// 주의사항:
///   - .env 파일에 유효한 SEOUL_SUBWAY_API_KEY가 필요 (없으면 graceful skip)
///   - 실제 API를 호출하므로 네트워크 연결 필요
///   - 574개 역 전체 테스트 시 약 5~10분 소요
///   - 서울 열린데이터 API 일일 호출 한도에 주의
@Tags(['integration', 'real-api'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/constants/api_constants.dart';
import 'package:seoul_subway/data/remote/dto/arrival_info_dto.dart';

/// API 호출 간 대기 시간 (서버 부하 방지)
const _requestDelay = Duration(milliseconds: 100);

/// 동시 요청 배치 크기
const _batchSize = 5;

/// API 호출 타임아웃
const _timeout = Duration(seconds: 15);

/// .env 에서 유효한 SEOUL_SUBWAY_API_KEY 를 읽는다. 없거나 플레이스홀더면 null.
/// (테스트 등록 시점에 평가하여 skip 여부를 결정하기 위해 main() 밖에서 수행)
String? _readApiKey() {
  final envFile = File('.env');
  if (!envFile.existsSync()) return null;
  final match =
      RegExp(r'SEOUL_SUBWAY_API_KEY=(.+)').firstMatch(envFile.readAsStringSync());
  final value = match?.group(1)?.trim();
  if (value == null || value.isEmpty || value == 'your_api_key_here') return null;
  return value;
}

void main() {
  // 키가 없으면 hard fail 대신 graceful skip. (기본 실행은 dart_test.yaml 의
  // integration 태그 skip 으로 이미 제외되며, --run-skipped 로 명시 실행 시에만 도달)
  final apiKey = _readApiKey();
  final skipReason = apiKey == null
      ? '.env 에 유효한 SEOUL_SUBWAY_API_KEY 가 없어 통합 테스트를 건너뜁니다.'
      : null;

  Dio? dio;
  late List<String> uniqueStationNames;

  setUpAll(() {
    // stations.json에서 고유 역명 추출
    final stationsJson = File('assets/json/stations.json');
    if (!stationsJson.existsSync()) {
      fail('assets/json/stations.json 파일이 없습니다.');
    }

    final data = json.decode(stationsJson.readAsStringSync()) as List;
    uniqueStationNames = data
        .map((e) => (e as Map<String, dynamic>)['name'] as String)
        .toSet()
        .toList()
      ..sort();

    // Dio 인스턴스 생성
    dio = Dio(BaseOptions(
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
    ));
  });

  tearDownAll(() {
    dio?.close();
  });

  test(
    '모든 역(${0})에 대해 실시간 도착정보 API 호출 및 DTO 파싱 검증',
    () async {
      final totalCount = uniqueStationNames.length;
      final successStations = <String>[];
      final noDataStations = <String>[];
      final apiErrorStations = <String, String>{};
      final parseErrorStations = <String, String>{};
      final networkErrorStations = <String, String>{};

      // 배치 단위로 처리
      for (var batchStart = 0;
          batchStart < totalCount;
          batchStart += _batchSize) {
        final batchEnd = (batchStart + _batchSize).clamp(0, totalCount);
        final batch = uniqueStationNames.sublist(batchStart, batchEnd);

        final futures = batch.map((stationName) async {
          // 앱과 동일한 URL 빌더를 쓴다 — 행 수 상한이 드리프트하지 않도록.
          // apiKey 는 skipReason 가드로 non-null 이 보장된다(아래 dio! 와 동일).
          final url = ApiConstants.realtimeArrivalUrl(apiKey!, stationName);

          try {
            final response = await dio!.get<String>(url);
            final data =
                json.decode(response.data!) as Map<String, dynamic>;

            // API 에러 응답 확인
            if (data.containsKey('errorMessage')) {
              final errorInfo =
                  data['errorMessage'] as Map<String, dynamic>;
              final status = errorInfo['status']?.toString();
              if (status == 'ERROR') {
                final message =
                    errorInfo['message']?.toString() ?? '알 수 없는 오류';
                apiErrorStations[stationName] = message;
                return;
              }
            }

            // 도착 데이터가 없는 경우
            final realtimeArrivalList = data['realtimeArrivalList'];
            if (realtimeArrivalList == null) {
              noDataStations.add(stationName);
              return;
            }

            // DTO 파싱 및 엔티티 변환 검증
            final arrivalList = realtimeArrivalList as List<dynamic>;
            for (final item in arrivalList) {
              final dto = ArrivalInfoDto.fromJson(
                item as Map<String, dynamic>,
              );
              // toEntity() 호출로 전체 변환 파이프라인 검증
              dto.toEntity();
            }

            successStations.add(stationName);
          } on FormatException catch (e) {
            parseErrorStations[stationName] = e.toString();
          } on TypeError catch (e) {
            parseErrorStations[stationName] = e.toString();
          } on DioException catch (e) {
            networkErrorStations[stationName] = e.message ?? '알 수 없는 네트워크 오류';
          } catch (e) {
            parseErrorStations[stationName] = e.toString();
          }
        });

        await Future.wait(futures);

        // 진행 상황 출력
        final processed = batchEnd;
        final percent = (processed / totalCount * 100).toStringAsFixed(1);
        // ignore: avoid_print
        print(
          '[$percent%] $processed/$totalCount 완료 '
          '(성공: ${successStations.length}, '
          '데이터없음: ${noDataStations.length}, '
          'API오류: ${apiErrorStations.length}, '
          '파싱오류: ${parseErrorStations.length}, '
          '네트워크오류: ${networkErrorStations.length})',
        );

        // 다음 배치 전 대기
        if (batchEnd < totalCount) {
          await Future<void>.delayed(_requestDelay);
        }
      }

      // 결과 리포트
      // ignore: avoid_print
      print('\n${'=' * 60}');
      // ignore: avoid_print
      print('실시간 도착정보 API 통합 테스트 결과');
      // ignore: avoid_print
      print('=' * 60);
      // ignore: avoid_print
      print('전체 역: $totalCount');
      // ignore: avoid_print
      print('성공 (도착정보 있음): ${successStations.length}');
      // ignore: avoid_print
      print('도착정보 없음 (운행 외): ${noDataStations.length}');
      // ignore: avoid_print
      print('API 오류 (해당 역 없음 등): ${apiErrorStations.length}');
      // ignore: avoid_print
      print('파싱/타입 오류: ${parseErrorStations.length}');
      // ignore: avoid_print
      print('네트워크 오류: ${networkErrorStations.length}');

      if (apiErrorStations.isNotEmpty) {
        // ignore: avoid_print
        print('\n--- API 오류 역 목록 ---');
        for (final entry in apiErrorStations.entries) {
          // ignore: avoid_print
          print('  ${entry.key}: ${entry.value}');
        }
      }

      if (parseErrorStations.isNotEmpty) {
        // ignore: avoid_print
        print('\n--- 파싱/타입 오류 역 목록 ---');
        for (final entry in parseErrorStations.entries) {
          // ignore: avoid_print
          print('  ${entry.key}: ${entry.value}');
        }
      }

      if (networkErrorStations.isNotEmpty) {
        // ignore: avoid_print
        print('\n--- 네트워크 오류 역 목록 ---');
        for (final entry in networkErrorStations.entries) {
          // ignore: avoid_print
          print('  ${entry.key}: ${entry.value}');
        }
      }

      // 파싱 오류가 하나라도 있으면 실패
      expect(
        parseErrorStations,
        isEmpty,
        reason: '${parseErrorStations.length}개 역에서 파싱/타입 오류 발생: '
            '${parseErrorStations.keys.join(", ")}',
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
