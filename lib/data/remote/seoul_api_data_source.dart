import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/station_api_name_overrides.dart';
import '../../core/network/api_client.dart';
import 'dto/arrival_info_dto.dart';

/// 도착정보 조회 결과.
///
/// [isPartial]은 등록명이 노선별로 갈린 역에서 **일부 질의만 실패해 결과가 불완전함**을
/// 뜻한다. 리포지토리는 이 경우 캐시를 덮어쓰지 않는다 — 부분 스냅샷을 저장해 두면
/// 이후 전체 실패 시 폴백 화면까지 노선이 빠진 상태가 되기 때문이다.
typedef ArrivalFetchResult = ({List<ArrivalInfoDto> arrivals, bool isPartial});

/// [_fetchMerged] 내부용: 질의 하나의 결과와 실패 사유.
typedef _SettledFetch = ({List<ArrivalInfoDto> rows, Object? error});

class SeoulApiDataSource {
  final ApiClient _apiClient;

  SeoulApiDataSource({required ApiClient apiClient}) : _apiClient = apiClient;

  /// 서울 열린데이터 실시간 지하철 도착정보 API를 호출한다.
  ///
  /// [stationName]은 앱 **표시명**이다. 질의명은 `resolveArrivalApiStationNames`가
  /// 정하며, 등록명이 노선별로 갈린 역(서울역·올림픽공원)은 여러 번 조회해 병합한다
  /// (`_fetchMerged`). 반환 DTO의 역명은 인바운드 치환으로 표시명에 되돌아온다.
  ///
  /// **엔드포인트:**
  /// `http://swopenapi.seoul.go.kr/api/subway/{apiKey}/json/realtimeStationArrival/0/{ApiConstants.arrivalRowLimit}/{stationName}`
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
  Future<ArrivalFetchResult> getRealtimeArrival(String stationName) async {
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
    //
    // 등록명이 노선별로 갈린 역(서울역·올림픽공원)은 이름이 여러 개 나온다 — 모두
    // 동시에 조회해 병합해야 모든 노선이 보인다.
    final apiStationNames = resolveArrivalApiStationNames(stationName);
    if (apiStationNames.length > 1) {
      return _fetchMerged(apiKey, stationName, apiStationNames);
    }
    return (
      arrivals: await _fetchOne(apiKey, stationName, apiStationNames.first),
      isPartial: false,
    );
  }

  /// 등록명이 노선별로 갈린 역의 모든 등록명을 **동시에** 조회해 병합한다.
  ///
  /// 질의들은 **대등하다** — 주/보조 구분이 없다. 서울역은 4:1이라 다수 쪽을 "주"로
  /// 볼 여지가 있지만 올림픽공원은 5호선 4건 : 9호선 4건이라 어느 쪽을 주로 둘 근거가
  /// 없다. 자의적 우선순위 대신 다음 규칙을 쓴다:
  /// - **하나라도 성공하면** 성공한 것들을 합쳐 반환하고 `isPartial` 로 불완전을 알린다.
  /// - **전부 실패해야** 예외를 던진다(→ 리포지토리가 캐시 폴백).
  ///
  /// 부분 결과는 [ArrivalFetchResult.isPartial] 때문에 캐시에 저장되지 않으므로,
  /// 일시적으로 노선이 빠져 보여도 다음 새로고침(15초)에 복구되고 폴백용 캐시는
  /// 마지막 온전한 스냅샷을 유지한다.
  ///
  /// 서로 다른 등록명은 서로 다른 `statnId` 라 응답이 겹치지 않으므로 중복 제거는 하지
  /// 않는다(2026-07-31 실측: 서울역·올림픽공원 모두 노선 집합이 서로소).
  Future<ArrivalFetchResult> _fetchMerged(
    String apiKey,
    String stationName,
    List<String> apiStationNames,
  ) async {
    // 전부 성공/실패를 알아야 isPartial 을 판정할 수 있으므로, 각 질의의 실패를
    // 그 자리에서 흡수해 결과 레코드로 만든다(= Future.wait 가 중도에 던지지 않음).
    final settled = await Future.wait(
      apiStationNames.map(
        (apiName) => _fetchOne(apiKey, stationName, apiName).then<_SettledFetch>(
          (rows) => (rows: rows, error: null),
          onError: (Object e, StackTrace st) {
            developer.log(
              '병합 조회 중 질의 실패: 역명=$stationName, API명=$apiName',
              name: 'SeoulApiDataSource',
              error: e,
              stackTrace: st,
              level: 900,
            );
            return (rows: <ArrivalInfoDto>[], error: e);
          },
        ),
      ),
    );

    final failures = settled.where((s) => s.error != null).toList();
    if (failures.length == settled.length) {
      // 전멸 — 캐시 폴백이 부분 화면보다 낫다.
      throw failures.first.error!;
    }

    final merged = settled.expand((s) => s.rows).toList();
    developer.log(
      '병합 조회 완료: 역명=$stationName, 질의명=$apiStationNames, '
      '열차 수=${merged.length}, 실패=${failures.length}/${settled.length}',
      name: 'SeoulApiDataSource',
    );
    return (arrivals: merged, isPartial: failures.isNotEmpty);
  }

  /// 등록명 하나로 도착정보를 조회한다. [stationName]은 로그용 표시명이다.
  Future<List<ArrivalInfoDto>> _fetchOne(
    String apiKey,
    String stationName,
    String apiStationName,
  ) async {
    final url = ApiConstants.realtimeArrivalUrl(apiKey, apiStationName);

    // 병합 조회 시 두 하위 질의를 로그에서 구분할 수 있도록 API명을 함께 붙인다.
    final label = apiStationName != stationName
        ? '$stationName (API명=$apiStationName)'
        : stationName;

    developer.log(
      '실시간 도착정보 요청: 역명=$label',
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
            'API 오류 응답: 역명=$label, 메시지=$message',
            name: 'SeoulApiDataSource',
            level: 1000,
          );
          throw Exception('API 오류: $message');
        }
      }

      final realtimeArrivalList = data['realtimeArrivalList'];
      if (realtimeArrivalList == null) {
        developer.log(
          '도착정보 없음: 역명=$label',
          name: 'SeoulApiDataSource',
        );
        return [];
      }

      final arrivalList = realtimeArrivalList as List<dynamic>;
      final result = arrivalList
          .map((e) => ArrivalInfoDto.fromJson(e as Map<String, dynamic>))
          .toList();

      developer.log(
        '실시간 도착정보 조회 성공: 역명=$label, 열차 수=${result.length}',
        name: 'SeoulApiDataSource',
      );

      return result;
    } catch (e) {
      developer.log(
        '실시간 도착정보 조회 실패: 역명=$label',
        name: 'SeoulApiDataSource',
        error: e,
      );
      rethrow;
    }
  }
}
