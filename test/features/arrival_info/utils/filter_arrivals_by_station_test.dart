import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/arrival_info.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/arrival_info/utils/filter_arrivals_by_station.dart';

/// 역명 기반 API 응답에서 동명이역의 열차를 걸러내는 계약 검증.
///
/// 서울 API 는 `realtimeStationArrival/양평` 처럼 역명으로 조회하므로 5호선 양평
/// 조회 응답에 53km 떨어진 경의중앙선 양평의 열차가 섞여 온다. 필터는 그 경우만
/// 좁게 개입하고, 나머지 상황에서는 응답을 건드리지 않아야 한다(fail-open).
void main() {
  // 5호선 양평(서울 영등포구) ↔ 경의중앙선 양평(경기 양평군), 약 53km.
  const line5Yangpyeong = Station(
    id: '513',
    name: '양평',
    lineId: '5',
    latitude: 37.5273,
    longitude: 126.8874,
  );
  const jungangYangpyeong = Station(
    id: 'K50',
    name: '양평',
    lineId: '경의중앙',
    latitude: 37.4895,
    longitude: 127.4879,
  );
  // 같은 자리의 진짜 환승역.
  const wangsimni2 = Station(
    id: '222',
    name: '왕십리',
    lineId: '2',
    latitude: 37.5614,
    longitude: 127.0378,
    isTransfer: true,
    transferLines: ['2', '5'],
  );
  const wangsimni5 = Station(
    id: '540',
    name: '왕십리',
    lineId: '5',
    latitude: 37.5614,
    longitude: 127.0378,
    isTransfer: true,
    transferLines: ['2', '5'],
  );

  final stations = [line5Yangpyeong, jungangYangpyeong, wangsimni2, wangsimni5];

  ArrivalInfo arrival(String subwayId, String trainNo) => ArrivalInfo(
        subwayId: subwayId,
        stationName: '양평',
        trainLineNm: '테스트행',
        direction: '상행',
        arrivalMessage: '전역 출발',
        destination: '테스트',
        trainType: '일반',
        arrivalSeconds: 120,
        receivedAt: DateTime(2026, 7, 30, 9),
        currentStationName: '테스트역',
        trainNo: trainNo,
        positionStatus: '0',
      );

  // 1005 = 5호선, 1063 = 경의중앙, 1002 = 2호선.
  final line5Train = arrival('1005', 'A1');
  final jungangTrain = arrival('1063', 'B1');

  test('동명이역: 5호선 양평 조회 시 경의중앙 열차가 제거된다', () {
    final result = filterArrivalsToOwnLines(
      arrivals: [line5Train, jungangTrain],
      stationId: '513',
      stations: stations,
    );

    expect(result.map((a) => a.trainNo), ['A1']);
  });

  test('동명이역: 경의중앙 양평 조회 시 5호선 열차가 제거된다', () {
    final result = filterArrivalsToOwnLines(
      arrivals: [line5Train, jungangTrain],
      stationId: 'K50',
      stations: stations,
    );

    expect(result.map((a) => a.trainNo), ['B1']);
  });

  test('환승역은 소속 노선 전체가 유지된다', () {
    final arrivals = [arrival('1002', 'C1'), arrival('1005', 'C2')];

    final result = filterArrivalsToOwnLines(
      arrivals: arrivals,
      stationId: '222',
      stations: stations,
    );

    expect(result, arrivals);
  });

  group('fail-open — 판단 근거가 없으면 응답을 건드리지 않는다', () {
    final arrivals = [line5Train, jungangTrain];

    test('stationId 미전달', () {
      expect(
        filterArrivalsToOwnLines(
          arrivals: arrivals,
          stationId: null,
          stations: stations,
        ),
        arrivals,
      );
    });

    test('stations 미로딩', () {
      expect(
        filterArrivalsToOwnLines(
          arrivals: arrivals,
          stationId: '513',
          stations: null,
        ),
        arrivals,
      );
    });

    test('목록에 없는 stationId', () {
      expect(
        filterArrivalsToOwnLines(
          arrivals: arrivals,
          stationId: '없는ID',
          stations: stations,
        ),
        arrivals,
      );
    });

    test('매핑에 없는 호선 코드는 동명이역이어도 남긴다', () {
      final unknown = arrival('9999', 'X1');

      final result = filterArrivalsToOwnLines(
        arrivals: [line5Train, jungangTrain, unknown],
        stationId: '513',
        stations: stations,
      );

      expect(result.map((a) => a.trainNo), ['A1', 'X1']);
    });
  });

  test('빈 응답은 빈 응답', () {
    expect(
      filterArrivalsToOwnLines(
        arrivals: const [],
        stationId: '513',
        stations: stations,
      ),
      isEmpty,
    );
  });
}
