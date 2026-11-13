// 열차위치 API 폴백의 잔여초 추정·범위 제한 검증.
//
// 배경: 도착정보 API 에 5호선 천호(`1005000547`) 엔트리가 없다 — 등록명
// `천호(풍납토성)` 로 조회하면 8호선만 응답하고 전체역 일괄 조회에도 없다
// (2026-07-31 실측). 그래서 노선 단위로 전 열차를 주는 위치 API 로 폴백하는데,
// 이 API 는 잔여초를 주지 않고 노선의 **모든** 열차를 주므로 두 가지가 필요하다:
// 구간 소요시간 기반 잔여초 추정과, 대상역과 무관한 열차의 제거.
@Skip('부산 전환: subwayIdToLineId 가 const 빈 맵(실시간 API 미연동)이라 lineId 해석 불가 — 부산 API 코드를 채울 때 부산 픽스처로 복원')
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/fallback_arrivals_from_positions.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
    stations = (jsonDecode(
      await rootBundle.loadString('assets/json/stations.json'),
    ) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    connections = (jsonDecode(
      await rootBundle.loadString('assets/json/connections.json'),
    ) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  final receivedAt = DateTime(2026, 7, 31, 6, 10, 30);

  /// 위치 API 에서 온 5호선 열차 1대 (`TrainPositionDto.toArrivalInfo` 결과 형태).
  ArrivalInfo position({
    required String trainNo,
    required String currentStation,
    String destination = '하남검단산',
    String direction = '하행',
    int arrivalCode = 1,
    String positionStatus = '도착',
  }) {
    return ArrivalInfo(
      subwayId: '1005',
      stationName: '천호',
      trainLineNm: '$destination행',
      direction: direction,
      arrivalMessage: '',
      destination: destination,
      trainType: '일반',
      arrivalSeconds: null,
      receivedAt: receivedAt,
      currentStationName: currentStation,
      trainNo: trainNo,
      positionStatus: positionStatus,
      arrivalCode: arrivalCode,
    );
  }

  List<ArrivalInfo> run(
    List<ArrivalInfo> positions, {
    int maxSecondsAway = fallbackMaxSecondsAway,
    int maxPerDirection = fallbackMaxTrainsPerDirection,
  }) {
    return fallbackArrivalsFromPositions(
      rawPositions: positions,
      targetStationName: '천호',
      stations: stations,
      connections: connections,
      maxSecondsAway: maxSecondsAway,
      maxPerDirection: maxPerDirection,
    );
  }

  test('구간 소요시간으로 잔여초를 추정하고 추정값으로 표시한다', () {
    // 광나루는 천호 직전 역이다.
    final result = run([position(trainNo: '5133', currentStation: '광나루')]);

    expect(result, hasLength(1));
    expect(result.single.arrivalSeconds, isNotNull);
    expect(result.single.arrivalSeconds, greaterThan(0));
    expect(result.single.isEstimated, isTrue);
    // 기준 시각은 recptnDt 그대로 — 실시간 역산은 JS 가 수행한다(4원칙 1).
    expect(result.single.receivedAt, receivedAt);
  });

  test('대상역에 있는 열차는 0초("그 역에 있음")로 남는다', () {
    final result = run([position(trainNo: '5133', currentStation: '천호')]);
    expect(result.single.arrivalSeconds, 0);
  });

  test('대상역을 향하지 않는 열차(다른 지선)는 버린다', () {
    // 마천 지선의 둔촌동에서는 천호로 가는 5호선 경로가 없다(강동에서 갈라짐).
    final result = run([position(trainNo: '5901', currentStation: '둔촌동')]);
    expect(result, isEmpty);
  });

  test('trainNo 가 없으면 버린다 — 카운트다운 매칭 키이자 지도 식별자', () {
    final result = run([position(trainNo: '', currentStation: '광나루')]);
    expect(result, isEmpty);
  });

  test('먼 열차는 시간 상한으로 잘라낸다', () {
    // 여의도는 천호에서 20정거장 이상 떨어져 있다.
    final far = run([position(trainNo: '5500', currentStation: '여의도')]);
    expect(far, isEmpty, reason: '기본 상한 10분을 넘는다');

    // 상한을 크게 열면 남는다 — 버려진 이유가 "경로 없음"이 아니라 "거리"임을 확인.
    final loose = run(
      [position(trainNo: '5500', currentStation: '여의도')],
      maxSecondsAway: 100000,
    );
    expect(loose, hasLength(1));
  });

  test('방향별로 가까운 열차만 남긴다', () {
    final result = run([
      position(trainNo: 'D1', currentStation: '광나루'), // 하행, 가장 가까움
      position(trainNo: 'D2', currentStation: '아차산'),
      position(trainNo: 'D3', currentStation: '군자'), // 하행 3번째 → 제외
      position(
        trainNo: 'U1',
        currentStation: '강동',
        destination: '방화',
        direction: '상행',
      ),
    ], maxPerDirection: 2);

    final down = result.where((a) => a.direction == '하행').map((a) => a.trainNo);
    expect(down, ['D1', 'D2'], reason: '가까운 순으로 2대');
    expect(
      result.where((a) => a.direction == '상행').map((a) => a.trainNo),
      ['U1'],
      reason: '반대 방향은 따로 세어 남긴다',
    );
  });
}
