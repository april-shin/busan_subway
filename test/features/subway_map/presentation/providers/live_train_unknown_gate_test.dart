// 지도의 "모름 판정" 게이트 회귀 가드.
//
// 2026-08-13 제보: 총신대입구(이수) 7호선 도봉산행이 도착정보 화면에서는
// "정보 없음"인데 지도에는 "1분 후 도착"으로 그려졌다. 두 화면이 각자의 판정
// 규칙을 갖고 있었고, 지도는 값을 모르는 행에 자체 추정값을 발급했다.
//
// 사용자 결정: **모름으로 판정된 열차는 지도에서 뺀다.**
// 판정은 `liveArrivalSeconds` 한 곳에 있고, `liveTrainsProvider` 가 그 결과가
// null 인 열차를 결과에서 제외한다.
//
// 이 테스트는 그 `continue` 한 줄을 지키기 위한 것이다 — 순수함수 테스트
// (live_arrival_seconds_test.dart)만으로는 게이트가 실제로 배선됐는지 알 수 없다.
@Skip('부산 전환: FeatureFlags.realtimeEnabled 가 const false 라 liveTrainsProvider 가 항상 빈 목록 — 플래그를 켤 때 부산 픽스처로 복원(로직 자체는 유지)')
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/constants/api_constants.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';
import 'package:busan_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/live_train_provider.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Station> stations;
  late List<Connection> connections;

  setUpAll(() async {
    final stationsJson =
        await rootBundle.loadString('assets/json/stations.json');
    stations = (jsonDecode(stationsJson) as List)
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();

    final connectionsJson =
        await rootBundle.loadString('assets/json/connections.json');
    connections = (jsonDecode(connectionsJson) as List)
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  Station stationOf(String name, String lineId) =>
      stations.firstWhere((s) => s.name == name && s.lineId == lineId);

  /// 천호로 접근 중인 5호선 하행 열차(광나루 위치 — 경로 탐색이 성공하는 배치).
  ArrivalInfo arrivalOf({
    required String trainNo,
    required int? arrivalSeconds,
    Duration receivedAgo = Duration.zero,
  }) {
    return ArrivalInfo(
      subwayId: '1005',
      stationName: '천호',
      trainLineNm: '하남검단산행',
      direction: '하행',
      arrivalMessage: '광나루 출발',
      destination: '하남검단산',
      trainType: '일반',
      arrivalSeconds: arrivalSeconds,
      receivedAt: DateTime.now().subtract(receivedAgo),
      trainNo: trainNo,
      currentStationName: '광나루',
    );
  }

  ProviderContainer containerWith(List<ArrivalInfo> arrivals) {
    final container = ProviderContainer(
      overrides: [
        allStationsProvider.overrideWith((ref) async => stations),
        allConnectionsProvider.overrideWith((ref) async => connections),
        arrivalInfoProvider('천호').overrideWith((ref) async => arrivals),
      ],
    );
    addTearDown(container.dispose);

    container.read(selectedStationsProvider.notifier).setBoth(
          stationOf('천호', '5'),
          stationOf('굽은다리', '5'),
        );
    container.read(activeRouteFilterProvider.notifier).state = ActiveRouteFilter(
      lineId: '5',
      isDown: true,
      routeStationIds: [
        for (final n in ['천호', '강동', '길동', '굽은다리']) stationOf(n, '5').id,
      ],
    );
    return container;
  }

  test('대조군: 잔여시간을 아는 열차는 그대로 그린다', () async {
    final container = containerWith([
      arrivalOf(trainNo: '5100', arrivalSeconds: 180),
    ]);
    final trains = await container.read(liveTrainsProvider.future);
    expect(trains.map((t) => t.trainNo), ['5100']);
  });

  test('대조군: null 이어도 enrich 가 값을 채우면 그린다 (8호선 등)', () async {
    // `barvlDt` 미제공 노선 대응. enrich 가 구간 기반 추정값과 **추정 시각**을
    // 실어 보내므로 경과 ≈ 0 이라 게이트를 통과한다. 이 경로가 죽으면 8호선
    // 열차가 지도에서 통째로 사라진다.
    final container = containerWith([
      arrivalOf(trainNo: '5200', arrivalSeconds: null),
    ]);
    final trains = await container.read(liveTrainsProvider.future);
    expect(trains.map((t) => t.trainNo), ['5200']);
  });

  test('enrich 가 포기한 행은 지도에서 뺀다', () async {
    // recptnDt 지연이 구간 추정값을 넘겨 enrich 가 `corrected <= 0` 으로
    // 포기(null 유지)하는 경로. 예전에는 지도 전용 추정 폴백이 이 행에
    // **기준 시각을 now 로 리베이스한** 새 숫자를 발급해 그렸다.
    final container = containerWith([
      arrivalOf(trainNo: '5100', arrivalSeconds: 180),
      arrivalOf(
        trainNo: '5200',
        arrivalSeconds: null,
        receivedAgo: const Duration(minutes: 10),
      ),
    ]);
    final trains = await container.read(liveTrainsProvider.future);
    expect(trains.map((t) => t.trainNo), ['5100'],
        reason: '모르는 열차만 빠지고 아는 열차는 남아야 한다');
  });

  test('잔여초가 소진된 열차는 0 초로 그리지 않고 뺀다 (제보 분류)', () async {
    // 제보 케이스가 속한 분류. 2026-08-13 15:04 실측:
    //   barvlDt='60' arvlCd='0'(진입) msg3='남성' recptnDt 경과=62초
    // 지도는 refresh 직후 경과 ≈ 0 인 쌍을 받아 "1분 후 도착"을 표시했고,
    // 도착정보 화면은 렌더 시점에 경과가 60 을 넘겨 "정보 없음"이었다.
    // (스크린샷의 arvlCd=1 행은 이제 DTO 가 0 으로 읽어 이 경로에 오지 않는다.)
    // 0 으로 클램프하면 recptnDt 지연이 큰 노선에서 전 열차가 "곧 도착"이 된다.
    final container = containerWith([
      arrivalOf(
        trainNo: '5300',
        arrivalSeconds: 60,
        receivedAgo: const Duration(seconds: 120),
      ),
    ]);
    final trains = await container.read(liveTrainsProvider.future);
    expect(trains, isEmpty);
  });

  test('"역에 있음"(0) 은 grace 이내만 그리고, 넘기면 뺀다', () async {
    final grace = ApiConstants.arrivalStateGrace;

    final fresh = containerWith([
      arrivalOf(trainNo: '5400', arrivalSeconds: 0, receivedAgo: grace),
    ]);
    expect((await fresh.read(liveTrainsProvider.future)).map((t) => t.trainNo),
        ['5400'], reason: 'grace 경계까지는 유효한 "역에 있음" 상태');

    final stale = containerWith([
      arrivalOf(
        trainNo: '5400',
        arrivalSeconds: 0,
        receivedAgo: grace + const Duration(seconds: 1),
      ),
    ]);
    expect(await stale.read(liveTrainsProvider.future), isEmpty,
        reason: '이미 떠난 열차 — 도착정보 화면도 "정보 없음"으로 판정한다');
  });
}
