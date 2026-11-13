import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/constants/station_api_name_overrides.dart';

/// 부산 전환으로 치환 맵은 비어 있다(실시간 API 미연동). 이 테스트는
/// (1) 비어 있을 때 모든 변환이 항등으로 동작하는지, (2) 나중에 맵을 채울 때
/// 무결성 규칙(표시명 실존·충돌·이중 치환)이 지켜지는지를 잠근다.
void main() {
  group('빈 맵 — 항등 동작 (부산 전환 상태)', () {
    const names = ['서면', '동래', '벡스코(시립미술관)', '좌천', ''];

    test('아웃바운드는 표시명을 그대로 돌려준다', () {
      for (final n in names) {
        expect(resolveArrivalApiStationName(n), n);
        expect(resolveArrivalApiStationNames(n), [n]);
      }
    });

    test('인바운드(역명·자유텍스트)는 입력을 그대로 돌려준다', () {
      for (final n in names) {
        expect(resolveDisplayStationName(n), n);
      }
      expect(resolveDisplayInText('노포행 - 서면방면'), '노포행 - 서면방면');
      expect(resolveDisplayInText('전역 도착'), '전역 도착');
      expect(resolveDisplayInText(''), '');
    });

    test('복수 질의명 첫 원소는 항상 주 질의명이다', () {
      for (final e in arrivalApiSplitRegistrationNames.entries) {
        expect(e.value.first, resolveArrivalApiStationName(e.key));
        expect(e.value.toSet().length, e.value.length);
      }
    });
  });

  group('맵 무결성 (채워질 때를 대비한 드리프트/충돌 가드)', () {
    late Set<String> displayNames;

    setUpAll(() {
      final raw = File('assets/json/stations.json').readAsStringSync();
      displayNames = (json.decode(raw) as List)
          .map((s) => (s as Map<String, dynamic>)['name'] as String)
          .toSet();
    });

    test('모든 항목은 표시명과 다른 API명으로 매핑된다', () {
      arrivalApiStationNameOverrides.forEach((displayName, apiName) {
        expect(apiName, isNot(displayName));
        expect(apiName.trim(), isNotEmpty);
      });
    });

    test('치환 후 값을 다시 치환해도 변하지 않는다', () {
      for (final apiName in arrivalApiStationNameOverrides.values) {
        expect(resolveArrivalApiStationName(apiName), apiName);
      }
    });

    test('API 등록명(값)은 서로 유일하다', () {
      final values = arrivalApiStationNameOverrides.values.toList();
      expect(values.toSet().length, values.length);
    });

    test('키는 stations.json 에 실존하고 값은 다른 역 표시명과 충돌하지 않는다', () {
      for (final key in [
        ...arrivalApiStationNameOverrides.keys,
        ...arrivalApiSplitRegistrationNames.keys,
      ]) {
        expect(displayNames, contains(key));
      }
      for (final apiName in arrivalApiStationNameOverrides.values) {
        expect(displayNames, isNot(contains(apiName)));
      }
    });

    test('동명이역(좌천·동래)은 치환 맵에 등록되지 않는다', () {
      for (final n in ['좌천', '동래']) {
        expect(arrivalApiStationNameOverrides.containsKey(n), isFalse);
      }
    });
  });
}
