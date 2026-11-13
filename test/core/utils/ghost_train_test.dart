import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/ghost_train.dart';
import 'package:busan_subway/domain/entities/arrival_info.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';

/// 유령 열차(종착 너머 도착 예정) 위상 판정 검증.
///
/// 규칙: 열차의 탑승 방향 진행 경로 `현재역(arvlMsg3) → 행선지(bstatnNm)` 위에
/// 탑승역이 없으면 유령. 2026-10-20 야간 실측 사례를 실제 노선 데이터로 재현한다.
///  - 4호선 남태령 하행: "사당행"(현재역 총신대입구(이수)·이촌·사당) — 사당에서
///    끝나는 열차를 API 가 남태령에도 이어 붙인다.
///  - 3호선 지축 상행: "구파발행"(현재역 불광) — 구파발에서 끝난다.
///
/// 지켜야 할 반대편(오탐 방지):
///  - `passed`(탑승역이 이미 열차 뒤)는 유령이 아니다 — `arvlMsg3` 가 지연·불일치한
///    실제 열차가 숨겨지면 안 된다.
///  - 이름이 안 읽히거나 경로가 안 구해지면 통과(fail-open). route_branch.dart 와
///    같은 정책이며 이 규칙은 그것을 대체하지 않고 **추가 신호**일 뿐이다.
void main() {
  _parallelBranchGroup();
  TestWidgetsFlutterBinding.ensureInitialized();

  group('classifyTrainTopology (순수 판정)', () {
    // 직선 a→b→c→d→e (단방향). 도달성은 알파벳 순서.
    bool reach(String from, String to) => from.compareTo(to) <= 0;

    TrainTopology classify({
      required List<String> cur,
      required List<String> dest,
      required String boarding,
    }) =>
        classifyTrainTopology(
          currentIds: cur,
          destinationIds: dest,
          boardingId: boarding,
          reach: reach,
        );

    test('현재역 → 행선지 사이에 탑승역이 있으면 정상', () {
      expect(classify(cur: ['a'], dest: ['e'], boarding: 'c'),
          TrainTopology.onRoute);
    });

    test('탑승역이 행선지와 같아도 정상 (종착역에서 내리는 승객의 열차)', () {
      expect(classify(cur: ['a'], dest: ['c'], boarding: 'c'),
          TrainTopology.onRoute);
    });

    test('현재역이 곧 탑승역이면 정상', () {
      expect(classify(cur: ['c'], dest: ['e'], boarding: 'c'),
          TrainTopology.onRoute);
    });

    test('탑승역이 앞쪽에 있는데 행선지가 그 앞에서 끝나면 유령', () {
      expect(classify(cur: ['a'], dest: ['b'], boarding: 'd'),
          TrainTopology.beyondTerminus);
    });

    test('이미 종착역에 선 열차가 그 너머 탑승역에 잡히면 유령', () {
      expect(classify(cur: ['b'], dest: ['b'], boarding: 'd'),
          TrainTopology.beyondTerminus);
    });

    test('탑승역이 열차 뒤에 있으면 passed — 유령이 아니다', () {
      expect(classify(cur: ['d'], dest: ['e'], boarding: 'b'),
          TrainTopology.passed);
    });

    test('현재역 → 행선지 경로가 없으면(방향 모순) 판정 불가 — fail-open', () {
      expect(classify(cur: ['d'], dest: ['a'], boarding: 'e'),
          TrainTopology.undetermined);
    });

    test('이름이 읽히지 않으면(ID 후보 없음) 판정 불가 — fail-open', () {
      expect(classify(cur: [], dest: ['e'], boarding: 'c'),
          TrainTopology.undetermined);
      expect(classify(cur: ['a'], dest: [], boarding: 'c'),
          TrainTopology.undetermined);
    });

    test('동명 후보가 여럿이면 하나라도 정상일 때 정상 (가장 유리한 판정)', () {
      expect(classify(cur: ['a', 'd'], dest: ['b', 'e'], boarding: 'c'),
          TrainTopology.onRoute);
    });
  });

  group('실제 노선 데이터 — 부산 1호선·3호선', () {
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

    String idOf(String name, String lineId) => stations
        .firstWhere((s) => s.name == name && s.lineId == lineId)
        .id;

    ArrivalInfo row({
      required String destination,
      required String current,
      String direction = '하행',
      int arrivalSeconds = 100,
    }) =>
        ArrivalInfo(
          subwayId: '',
          stationName: '',
          trainLineNm: '$destination행',
          direction: direction,
          arrivalMessage: '',
          destination: destination,
          trainType: '일반',
          arrivalSeconds: arrivalSeconds,
          receivedAt: DateTime(2026, 11, 13, 21, 0),
          currentStationName: current,
        );

    TrainTopology Function(ArrivalInfo) classifier({
      required String boarding,
      required String lineId,
      required bool isDown,
      List<Station>? overrideStations,
      List<Connection>? overrideConnections,
    }) =>
        makeTrainTopologyClassifier(
          boardingStationId: idOf(boarding, lineId),
          lineId: lineId,
          isDown: isDown,
          stations: overrideStations ?? stations,
          connections: overrideConnections ?? connections,
        );

    group('1호선 동래 하행(ID 증가 = 노포 방향)', () {
      late TrainTopology Function(ArrivalInfo) classify;
      setUp(() {
        classify = classifier(boarding: '동래', lineId: '1', isDown: true);
      });

      test('부전행(동래 이전 종착)은 현재역이 어디든 유령', () {
        expect(classify(row(destination: '부전', current: '서면')),
            TrainTopology.beyondTerminus);
        expect(classify(row(destination: '부전', current: '범내골')),
            TrainTopology.beyondTerminus);
      });

      test('노포행은 정상', () {
        expect(classify(row(destination: '노포', current: '서면')),
            TrainTopology.onRoute);
      });

      test('동래행·온천장행처럼 탑승역 이후가 종착인 열차도 정상', () {
        expect(classify(row(destination: '동래', current: '교대')),
            TrainTopology.onRoute);
        expect(classify(row(destination: '온천장', current: '교대')),
            TrainTopology.onRoute);
      });

      test('passed — 현재역이 이미 동래를 지난 열차는 숨기지 않는다', () {
        final t = classify(row(destination: '노포', current: '명륜'));
        expect(t, TrainTopology.passed);
      });

      test('방향 모순(현재역이 행선지 뒤)은 판정 불가 — 통과', () {
        expect(classify(row(destination: '서면', current: '온천장')),
            isNot(TrainTopology.beyondTerminus));
      });

      test('이름이 노선에 없으면 통과', () {
        expect(classify(row(destination: '없는역', current: '서면')),
            TrainTopology.undetermined);
      });
    });

    group('3호선 상행(ID 감소 = 수영 방향)', () {
      test('거제 탑승 상행: 수영행은 정상, 거제 앞(종합운동장)에서 끝나는 열차는 유령', () {
        final classify = classifier(boarding: '거제', lineId: '3', isDown: false);
        // 상행 경로 사직(308) → 종합운동장(307) → 거제(306) → 연산(305) → 수영(301).
        expect(classify(row(destination: '수영', current: '사직', direction: '상행')),
            TrainTopology.onRoute);
        expect(classify(row(destination: '종합운동장', current: '사직', direction: '상행')),
            TrainTopology.beyondTerminus);
      });
    });

    group('fail-open 경계', () {
      test('2호선도 다른 노선과 같이 판정한다 (부산은 순환선 예외가 없다)', () {
        final classify = classifier(boarding: '서면', lineId: '2', isDown: true);
        // 하행 지게골(215) → 전포(218) 종착: 탑승역 서면(219)은 그 너머라 유령.
        expect(classify(row(destination: '전포', current: '지게골')),
            TrainTopology.beyondTerminus);
      });

      test('stations/connections 미로딩이면 판정하지 않는다', () {
        final classify = makeTrainTopologyClassifier(
          boardingStationId: idOf('동래', '1'),
          lineId: '1',
          isDown: true,
          stations: const [],
          connections: const [],
        );
        expect(classify(row(destination: '부전', current: '서면')),
            TrainTopology.undetermined);
      });

      test('makeGhostTrainDetector 는 beyondTerminus 만 true', () {
        final isGhost = makeGhostTrainDetector(
          boardingStationId: idOf('동래', '1'),
          lineId: '1',
          isDown: true,
          stations: stations,
          connections: connections,
        );
        expect(isGhost(row(destination: '부전', current: '서면')), isTrue);
        // passed / undetermined / onRoute 는 모두 false.
        expect(isGhost(row(destination: '노포', current: '명륜')), isFalse);
        expect(isGhost(row(destination: '노포', current: '서면')), isFalse);
        expect(isGhost(row(destination: '없는역', current: '서면')), isFalse);
      });
    });
  });
}

// [2026-10-20 코드 리뷰 MEDIUM-1] 병행 지선은 `passed` 가 아니라 `undetermined` 다.
// 둘 다 "통과"라 필터 결과는 같지만, `passed` 를 "실제 열차"의 근거로 쓰는 소비자가
// 생기면 오판한다 — 지나친 열차가 아니라 **오지 않는** 열차이기 때문이다.
void _parallelBranchGroup() {
  group('병행 지선 (코드 리뷰 MEDIUM-1)', () {
    // 5호선 하행: 강동에서 마천 지선과 하남검단산 본선이 갈린다.
    // 탑승역 상일동(본선) · 현재역 둔촌동(마천 지선) · 행선지 마천.
    bool reach(String from, String to) {
      const down = {
        '강동': ['둔촌동', '길동'],
        '둔촌동': ['올림픽공원'],
        '올림픽공원': ['마천'],
        '길동': ['상일동'],
        '상일동': ['하남검단산'],
      };
      final seen = <String>{};
      final stack = [from];
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        if (cur == to) return true;
        if (!seen.add(cur)) continue;
        stack.addAll(down[cur] ?? const []);
      }
      return false;
    }

    test('상호 도달 불가 → undetermined (passed 아님)', () {
      expect(
        classifyTrainTopology(
          currentIds: ['둔촌동'],
          destinationIds: ['마천'],
          boardingId: '상일동',
          reach: reach,
        ),
        TrainTopology.undetermined,
      );
    });

    test('역방향으로 닿으면 passed 유지 — 지나친 열차', () {
      expect(
        classifyTrainTopology(
          currentIds: ['상일동'],
          destinationIds: ['하남검단산'],
          boardingId: '길동',
          reach: reach,
        ),
        TrainTopology.passed,
      );
    });
  });
}
