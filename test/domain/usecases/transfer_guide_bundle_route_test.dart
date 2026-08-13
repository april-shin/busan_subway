@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/data/repositories/station_repository_impl.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/transfer_guide.dart';
import 'package:seoul_subway/domain/usecases/search_route.dart';

/// 환승 가이드(빠른환승) 오안내 제보 2건의 **실 번들 데이터** end-to-end 회귀 가드.
///
/// `search_route_test.dart` 의 다른 환승 가이드 테스트는 전부 Mock 주입이라,
/// `data/transfer_guides.csv` → `assets/json/transfer_guides.json` 파이프라인이
/// 다시 오염돼도 통과한다. 이 파일은 실제 번들 JSON 을 `LocalDataSource` 로 읽어
/// 제보 경로 그대로 조회한다 — 데이터 회귀를 잡는 것이 유일한 목적이다.
///
/// 패턴은 `test/graph/seohae_route_test.dart` 를 따른다.
///
/// ⚠ 이 파일은 **제보된 두 경로의 값만** 단언한다. 다른 환승 값은 데이터 교정이
/// 진행 중일 수 있으므로 의존하지 않는다.
void main() {
  late SearchRoute searchRoute;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    searchRoute = SearchRoute(
      stationRepository:
          StationRepositoryImpl(localDataSource: LocalDataSource()),
    );
  });

  /// [result] 에서 [stationName] 에서 일어나는 환승의 가이드를 찾는다.
  ///
  /// 환승 i 의 환승역은 세그먼트 i 의 마지막 역이다(`_buildSegments` 불변식).
  TransferGuide? guideAt(RouteResult result, String stationName) {
    for (var i = 0; i < result.transferGuides.length; i++) {
      if (result.segments[i].stations.last.name == stationName) {
        return result.transferGuides[i];
      }
    }
    return null;
  }

  test('제보 1 — 총신대입구(이수) → 잠실새내: 사당 환승 가이드는 1-1', () async {
    // 424 총신대입구(이수, 4호선) → 217 잠실새내(2호선).
    //
    // 방향 근거:
    //   - 4호선 424 → 425(사당): ID 증가 & 둘 다 본선 → down = **오이도 방면**.
    //   - 2호선 226(사당) → 225(방배) → … → 217(잠실새내): ID 감소 → down = **외선**.
    // 나무위키 사당역 환승정보: 4호선 오이도 방면 → 2호선 외선 = 1-1.
    // 키: `사당_4_down_2_down` (5-tuple 구체 키).
    //
    // 이 환승이 4-tuple 로 뭉개지던 것이 제보의 원인이었다. 목적 방향(내선/외선)에
    // 따라 값이 갈리므로, 폴백 키로 강등되면 이 단언이 깨진다.
    final result = await searchRoute.execute('424', '217');

    expect(result, isNotNull, reason: '총신대입구(이수) → 잠실새내 경로 없음');
    final guide = guideAt(result!, '사당');
    expect(guide, isNotNull,
        reason: '사당 환승 가이드 미조회 — 경로: '
            '${result.segments.map((s) => "${s.lineId}:${s.stations.last.name}").toList()}');
    expect(guide!.car, 1, reason: '사당 4호선(오이도 방면) → 2호선 외선 = 1-1');
    expect(guide.door, 1, reason: '사당 4호선(오이도 방면) → 2호선 외선 = 1-1');
  });

  test('제보 2 — 여의도 → 총신대입구(이수): 동작 환승 가이드는 1-1', () async {
    // 915 여의도(9호선) → 424 총신대입구(이수, 4호선).
    //
    // 방향 근거:
    //   - 9호선 915(여의도) → 920(동작): ID 증가지만 9호선은 서울 API 라벨에 맞춰
    //     규칙이 반전(`isDownBetween` 의 `to < from`)되므로 up = **중앙보훈병원 방면**.
    //   - 4호선 423(동작) → 424(총신대입구): ID 증가 → down(오이도 방면).
    // 키: `동작_9_up_4` (목적 방향 무관 → 4-tuple 폴백 키).
    //
    // 값 1-1 은 **공식 데이터셋의 결손을 보정한 값**이다. 공식(공공데이터포털
    // 15098252)은 동작역 9호선 4행을 방면 구분 없이 전부 6-4 로 적었는데, 차량
    // 번호는 편성 방향과 함께 뒤집히므로(6칸 편성: 칸 6↔1, 문 4↔1) 양방향 동일은
    // 물리적으로 성립하지 않는다 — 같은 역 4호선 출발 행은 8-4/2-4 로 정상 분화돼
    // 있어 9호선 쪽만 한 방향 값을 복제한 결손으로 판단했다. 6-4 의 미러가 정확히
    // 1-1 이고 사용자 실측 제보·나무위키가 모두 1-1 로 일치한다.
    // 보정 근거와 미검증 의심 그룹 목록은
    // `tool/import_official_transfer_guides.dart` 의 `_officialDefectOverrides`.
    final result = await searchRoute.execute('915', '424');

    expect(result, isNotNull, reason: '여의도(9호선) → 총신대입구(이수) 경로 없음');
    final guide = guideAt(result!, '동작');
    expect(guide, isNotNull,
        reason: '동작 환승 가이드 미조회 — 경로: '
            '${result.segments.map((s) => "${s.lineId}:${s.stations.last.name}").toList()}');
    expect(guide!.car, 1,
        reason: '동작 9호선(중앙보훈병원 방면) → 4호선 하차위치 = 1-1');
    expect(guide.door, 1,
        reason: '동작 9호선(중앙보훈병원 방면) → 4호선 하차위치 = 1-1');
  });
}
