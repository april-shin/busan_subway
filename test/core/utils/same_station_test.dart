import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/same_station.dart';
import 'package:busan_subway/domain/entities/station.dart';

/// 역 선택 화면의 중복 제거 계약 검증.
///
/// 핵심 회귀: 이름만으로 합치면 이름이 같고 위치는 다른 **동명이역**(부산 좌천 1호선/동해선, 동래 1·4호선/동해선)의 뒤쪽 레코드가 목록에서 사라져 검색으로 선택할 방법이
/// 없어진다. 동시에 진짜 환승역은 계속 한 항목으로 합쳐져야 한다.
void main() {
  Station station(
    String id,
    String name,
    String lineId, {
    required double lat,
    required double lng,
    bool isTransfer = false,
    List<String> transferLines = const [],
  }) =>
      Station(
        id: id,
        name: name,
        lineId: lineId,
        latitude: lat,
        longitude: lng,
        isTransfer: isTransfer,
        transferLines: transferLines,
      );

  group('uniqueStationsByLocation', () {
    test('빈 목록은 빈 목록', () {
      expect(uniqueStationsByLocation([]), isEmpty);
    });

    test('같은 좌표의 환승역 레코드는 하나로 합쳐지고 첫 레코드가 대표', () {
      final result = uniqueStationsByLocation([
        station('222', '왕십리', '2',
            lat: 37.5614, lng: 127.0378, isTransfer: true,
            transferLines: ['2', '5', '경의중앙', '수인분당']),
        station('540', '왕십리', '5',
            lat: 37.5614, lng: 127.0378, isTransfer: true,
            transferLines: ['2', '5', '경의중앙', '수인분당']),
      ]);

      expect(result, hasLength(1));
      expect(result.single.id, '222');
      expect(result.single.transferLines, contains('경의중앙'));
    });

    test('이름이 같고 멀리 떨어진 동명이역은 둘 다 남는다 (양평)', () {
      final result = uniqueStationsByLocation([
        station('513', '양평', '5', lat: 37.5273, lng: 126.8874),
        station('K50', '양평', '경의중앙', lat: 37.4895, lng: 127.4879),
      ]);

      expect(result.map((s) => s.id), ['513', 'K50']);
    });

    test('이름이 같고 출입구 차이만큼 떨어진 환승역은 합쳐진다 (보라매 304m)', () {
      final result = uniqueStationsByLocation([
        station('734', '보라매', '7', lat: 37.4948, lng: 126.9159),
        station('S04', '보라매', '신림', lat: 37.4960, lng: 126.9190),
      ]);

      expect(result, hasLength(1));
      expect(result.single.id, '734');
    });

    test('이름이 다르면 좌표가 같아도 합치지 않는다', () {
      final result = uniqueStationsByLocation([
        station('1', '가', '1', lat: 37.5, lng: 127.0),
        station('2', '나', '1', lat: 37.5, lng: 127.0),
      ]);

      expect(result, hasLength(2));
    });

    test('입력 순서를 보존한다', () {
      final result = uniqueStationsByLocation([
        station('c', '다', '1', lat: 37.50, lng: 127.00),
        station('a', '가', '1', lat: 37.60, lng: 127.10),
        station('c2', '다', '2', lat: 37.50, lng: 127.00),
        station('b', '나', '1', lat: 37.70, lng: 127.20),
      ]);

      expect(result.map((s) => s.id), ['c', 'a', 'b']);
    });

    test('경계: 반경보다 멀면 분리, 가까우면 통합', () {
      // 위도 1도 ≈ 111.32km → 반경 2km ≈ 0.01796도.
      const degPerKm = 1 / 111.32;
      final near = uniqueStationsByLocation([
        station('1', '역', '1', lat: 37.5, lng: 127.0),
        station('2', '역', '2', lat: 37.5 + degPerKm * 1.9, lng: 127.0),
      ]);
      final far = uniqueStationsByLocation([
        station('1', '역', '1', lat: 37.5, lng: 127.0),
        station('2', '역', '2', lat: 37.5 + degPerKm * 2.1, lng: 127.0),
      ]);

      expect(near, hasLength(1));
      expect(far, hasLength(2));
    });
  });

  group('distinctSameNameLineIds', () {
    final line5Yangpyeong =
        station('513', '양평', '5', lat: 37.5273, lng: 126.8874);
    final jungangYangpyeong =
        station('K50', '양평', '경의중앙', lat: 37.4895, lng: 127.4879);

    test('동명이역이면 그 역의 노선만 반환', () {
      final stations = [line5Yangpyeong, jungangYangpyeong];

      expect(
        distinctSameNameLineIds(target: line5Yangpyeong, stations: stations),
        {'5'},
      );
      expect(
        distinctSameNameLineIds(target: jungangYangpyeong, stations: stations),
        {'경의중앙'},
      );
    });

    test('동명 역이 없으면 null (필터 없음)', () {
      expect(
        distinctSameNameLineIds(
          target: line5Yangpyeong,
          stations: [line5Yangpyeong],
        ),
        isNull,
      );
    });

    test('같은 위치의 환승역뿐이면 null (필터 없음)', () {
      final line2 = station('222', '왕십리', '2',
          lat: 37.5614, lng: 127.0378, isTransfer: true,
          transferLines: ['2', '5']);
      final line5 = station('540', '왕십리', '5',
          lat: 37.5614, lng: 127.0378, isTransfer: true,
          transferLines: ['2', '5']);

      expect(
        distinctSameNameLineIds(target: line2, stations: [line2, line5]),
        isNull,
      );
    });

    test('동명이역이면서 환승역이면 자기 쪽 노선 전체를 반환', () {
      // 가상: A 역은 1·3호선 환승, 멀리 떨어진 동명 B 역은 7호선 단독.
      final a1 = station('101', '가상', '1',
          lat: 37.50, lng: 127.00, isTransfer: true, transferLines: ['1', '3']);
      final a3 = station('301', '가상', '3',
          lat: 37.50, lng: 127.00, isTransfer: true, transferLines: ['1', '3']);
      final b7 = station('701', '가상', '7', lat: 37.80, lng: 127.50);
      final stations = [a1, a3, b7];

      expect(
        distinctSameNameLineIds(target: a1, stations: stations),
        {'1', '3'},
      );
      expect(
        distinctSameNameLineIds(target: b7, stations: stations),
        {'7'},
      );
    });
  });

  group('실제 stations.json', () {
    late List<Station> stations;

    setUpAll(() {
      final file = File('assets/json/stations.json');
      if (!file.existsSync()) {
        fail('stations.json 이 없습니다: ${file.absolute.path}');
      }
      final raw = json.decode(file.readAsStringSync()) as List<dynamic>;
      stations = [
        for (final item in raw) Station.fromJson(item as Map<String, dynamic>),
      ];
    });

    test('동명이역(좌천 2건, 동래 2건)만 여러 건으로 남고 나머지 환승역은 1건으로 합쳐진다', () {
      final result = uniqueStationsByLocation(stations);
      final countByName = <String, int>{};
      for (final s in result) {
        countByName[s.name] = (countByName[s.name] ?? 0) + 1;
      }

      final multi = Map.fromEntries(
        countByName.entries.where((e) => e.value > 1),
      );
      expect(multi, {'좌천': 2, '동래': 2});
    });

    test('좌천은 1호선·동해선이 각각 별개 역으로 남는다', () {
      final jwacheon = uniqueStationsByLocation(stations)
          .where((s) => s.name == '좌천')
          .toList();
      expect(jwacheon.map((s) => s.lineId), unorderedEquals(['1', '동해']));
    });

    test('동래는 동해선이 분리되고 1·4호선은 한 항목으로 합쳐진다', () {
      final dongnae = uniqueStationsByLocation(stations)
          .where((s) => s.name == '동래')
          .toList();
      expect(dongnae, hasLength(2));
      final byLine = {for (final s in dongnae) s.lineId: s};
      expect(byLine.keys, containsAll(['1', '동해']));
      // 1호선 대표 항목이 1·4호선 환승을 모두 안고 있다.
      expect(byLine['1']!.transferLines, containsAll(['1', '4']));
    });

    test('전체 역 이름 종류는 모두 목록에 남는다', () {
      final result = uniqueStationsByLocation(stations);
      final allNames = stations.map((s) => s.name).toSet();
      expect(result.map((s) => s.name).toSet(), allNames);
    });

    test('노선 필터가 걸리는 역은 좌천·동래 동명이역 레코드뿐', () {
      final filtered = <String, Set<String>?>{};
      for (final s in stations) {
        final own = distinctSameNameLineIds(target: s, stations: stations);
        if (own != null) filtered['${s.name}_${s.id}'] = own;
      }

      expect(filtered, {
        '좌천_116': {'1'},
        '좌천_816': {'동해'},
        '동래_125': {'1', '4'},
        '동래_402': {'1', '4'},
        '동래_805': {'동해'},
      });
    });
  });
}
