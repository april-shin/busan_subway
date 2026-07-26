import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/constants/station_api_name_overrides.dart';

void main() {
  group('resolveArrivalApiStationName (아웃바운드)', () {
    test('부역명이 필요한 역은 API 등록명으로 치환한다', () {
      // 사용자 제보 케이스: 8호선 남한산성입구
      expect(
        resolveArrivalApiStationName('남한산성입구'),
        '남한산성입구(성남법원,검찰청)',
      );
      expect(resolveArrivalApiStationName('몽촌토성'), '몽촌토성(평화의문)');
      expect(resolveArrivalApiStationName('천호'), '천호(풍납토성)');
    });

    test('축약/치환형(부역명 아님)도 API 등록명으로 치환한다', () {
      // 앱 표시명이 API 등록명보다 긴 경우 — 개명 전 이름으로 조회됨
      expect(resolveArrivalApiStationName('평택지제'), '지제');
    });

    test('1~8호선 외 노선도 치환한다 (우이신설·신림·경강)', () {
      // 우이신설: 가운뎃점(·)+공백없음 → 마침표+공백
      expect(resolveArrivalApiStationName('4·19민주묘지'), '4.19 민주묘지');
      // 신림: 앱은 부역명 병기, API는 본역명만
      expect(resolveArrivalApiStationName('관악산(서울대)'), '관악산');
      // 경강: API는 "대"를 뺀 축약명(2026-07-26 이웃역 arvlMsg3 교차 확인)
      expect(resolveArrivalApiStationName('세종대왕릉'), '세종왕릉');
      // 7호선: 현행명 "자양"(앱 표기) ↔ API 개명 전 이름 "뚝섬유원지"
      expect(resolveArrivalApiStationName('자양'), '뚝섬유원지');
      // 6호선 응암순환 종착역: API 등록명은 "응암순환(상선)"
      expect(resolveArrivalApiStationName('응암'), '응암순환(상선)');
    });

    test('치환 대상이 아닌 역은 표시명을 그대로 반환한다', () {
      expect(resolveArrivalApiStationName('강남'), '강남');
      expect(resolveArrivalApiStationName('서울역'), '서울역');
      expect(resolveArrivalApiStationName('잠실'), '잠실');
    });

    test('빈 문자열은 그대로 반환한다', () {
      expect(resolveArrivalApiStationName(''), '');
    });
  });

  group('resolveDisplayStationName (인바운드 역치환)', () {
    test('API 등록명을 표시용 역명으로 되돌린다', () {
      // 축약·치환형: _stripStationAlias 로는 복원 불가 → 역맵이 유일 수단
      expect(resolveDisplayStationName('지제'), '평택지제');
      expect(resolveDisplayStationName('관악산'), '관악산(서울대)');
      expect(resolveDisplayStationName('4.19 민주묘지'), '4·19민주묘지');
      expect(resolveDisplayStationName('세종왕릉'), '세종대왕릉');
      expect(resolveDisplayStationName('뚝섬유원지'), '자양');
      expect(resolveDisplayStationName('응암순환(상선)'), '응암');
      // 부역명 덧붙임형도 역맵으로 복원 가능
      expect(resolveDisplayStationName('오목교(목동운동장앞)'), '오목교');
    });

    test('등록되지 않은 API명은 그대로 반환한다', () {
      expect(resolveDisplayStationName('강남'), '강남');
      expect(resolveDisplayStationName(''), '');
    });

    test('아웃바운드 → 인바운드 왕복은 항등이다', () {
      arrivalApiStationNameOverrides.forEach((display, api) {
        expect(
          resolveDisplayStationName(resolveArrivalApiStationName(display)),
          display,
          reason: '$display 왕복 치환이 원복되지 않음',
        );
      });
    });
  });

  group('resolveDisplayInText (자유텍스트 인바운드)', () {
    test('방면 라벨의 응암순환(상선)을 응암으로 정리한다', () {
      expect(
        resolveDisplayInText('응암순환(상선)행 - 응암순환(상선)방면'),
        '응암행 - 응암방면',
      );
    });

    test('도착 메시지의 부역명형 API명을 표시명으로 정리한다', () {
      expect(resolveDisplayInText('4분 후 (증산(명지대앞))'), '4분 후 (증산)');
      expect(resolveDisplayInText('응암순환(상선) 도착'), '응암 도착');
    });

    test('인바운드 전용 표기 응암(하선-종착)도 응암으로 정리한다', () {
      expect(resolveDisplayInText('1분 후 (응암(하선-종착))'), '1분 후 (응암)');
    });

    test('치환 대상이 없는 텍스트/빈 문자열은 그대로 둔다', () {
      expect(resolveDisplayInText('성수행 - 을지로입구방면'), '성수행 - 을지로입구방면');
      expect(resolveDisplayInText('전역 도착'), '전역 도착');
      expect(resolveDisplayInText(''), '');
    });
  });

  group('맵 무결성 (드리프트/충돌 가드)', () {
    test('모든 항목은 표시명과 다른 API명으로 매핑된다', () {
      // 자기 자신으로 매핑하는(=불필요한) 항목이 섞이지 않도록 방어
      arrivalApiStationNameOverrides.forEach((displayName, apiName) {
        expect(
          apiName,
          isNot(displayName),
          reason: '$displayName 은 표시명과 동일한 API명으로 매핑되어 있어 치환이 무의미함',
        );
        expect(apiName.trim(), isNotEmpty, reason: '$displayName 의 API명이 비어 있음');
      });
    });

    test('치환 후 값을 다시 치환해도 변하지 않는다 (이중 치환 방지)', () {
      arrivalApiStationNameOverrides.forEach((_, apiName) {
        expect(
          resolveArrivalApiStationName(apiName),
          apiName,
          reason: 'API명 "$apiName" 이 또 다른 키로 잡혀 이중 치환됨',
        );
      });
    });

    test('API 등록명(값)은 서로 유일하다 (역맵 무결성)', () {
      // 값이 겹치면 resolveDisplayStationName 역맵이 한쪽을 삼킨다.
      final values = arrivalApiStationNameOverrides.values.toList();
      expect(values.toSet().length, values.length, reason: 'API 등록명 중복 존재');
    });

    // 아래 두 테스트는 stations.json 실데이터와 대조한다.
    // "역 데이터 파이프라인 드리프트"(assets/json 재생성 시 표시명 변동) 조기 감지용.
    group('stations.json 대조', () {
      late Set<String> displayNames;

      setUpAll(() {
        final raw = File('assets/json/stations.json').readAsStringSync();
        displayNames = (json.decode(raw) as List)
            .map((s) => (s as Map<String, dynamic>)['name'] as String)
            .toSet();
      });

      test('모든 키는 stations.json 에 실존하는 표시명이다', () {
        for (final key in arrivalApiStationNameOverrides.keys) {
          expect(
            displayNames,
            contains(key),
            reason: '"$key" 가 stations.json 에 없음 — 데이터 드리프트 의심',
          );
        }
      });

      test('API 등록명(값)은 다른 역의 표시명과 충돌하지 않는다', () {
        // 값이 실제 표시명이면 인바운드 역치환이 그 역의 정상 이름을 오염시킨다.
        // (예: "신둔도예촌" 이 별개 역으로 실존 → 세종대왕릉 항목을 뺀 이유)
        for (final apiName in arrivalApiStationNameOverrides.values) {
          expect(
            displayNames,
            isNot(contains(apiName)),
            reason: 'API 등록명 "$apiName" 이 실제 역 표시명과 충돌 — 역치환 오염 위험',
          );
        }
      });
    });
  });
}
