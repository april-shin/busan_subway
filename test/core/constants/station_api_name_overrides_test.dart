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

    test('노선별로 등록명이 갈린 역은 주 질의명을 반환한다', () {
      // 서울역: 1·4·경의중앙·공항철도="서울", GTX-A="서울역"
      expect(resolveArrivalApiStationName('서울역'), '서울');
      // 올림픽공원: 5호선="올림픽공원(한국체대)", 9호선="올림픽공원"
      expect(resolveArrivalApiStationName('올림픽공원'), '올림픽공원(한국체대)');
    });

    test('치환 대상이 아닌 역은 표시명을 그대로 반환한다', () {
      expect(resolveArrivalApiStationName('강남'), '강남');
      expect(resolveArrivalApiStationName('시청'), '시청');
      expect(resolveArrivalApiStationName('잠실'), '잠실');
    });

    test('빈 문자열은 그대로 반환한다', () {
      expect(resolveArrivalApiStationName(''), '');
    });
  });

  group('resolveArrivalApiStationNames (복수 질의명)', () {
    test('노선별로 갈린 역은 등록명 전체를 반환한다', () {
      expect(resolveArrivalApiStationNames('서울역'), ['서울', '서울역']);
      expect(
        resolveArrivalApiStationNames('올림픽공원'),
        ['올림픽공원(한국체대)', '올림픽공원'],
      );
    });

    test('갈리지 않은 역은 주 질의명 한 개만 반환한다', () {
      expect(resolveArrivalApiStationNames('강남'), ['강남']);
      expect(resolveArrivalApiStationNames('오목교'), ['오목교(목동운동장앞)']);
      expect(resolveArrivalApiStationNames(''), ['']);
    });

    test('첫 원소는 항상 주 질의명이다', () {
      // 주 질의는 실패 시 예외를 던져 캐시 폴백을 태우므로, 단일 질의명 경로와
      // 반드시 일치해야 한다.
      for (final display in arrivalApiSplitRegistrationNames.keys) {
        expect(
          resolveArrivalApiStationNames(display).first,
          resolveArrivalApiStationName(display),
          reason: '$display 의 주 질의명이 단일 질의명과 다름',
        );
      }
    });

    test('갈린 등록명은 모두 인바운드로 표시명에 되돌아온다', () {
      // 하나라도 복원되지 않으면 그 노선 열차의 stations.json 매칭이 깨져
      // 라이브맵 좌표 조회·도착시간 추정이 실패한다.
      arrivalApiSplitRegistrationNames.forEach((display, apiNames) {
        for (final apiName in apiNames) {
          expect(
            resolveDisplayStationName(apiName),
            display,
            reason: '"$apiName" 이 표시명 "$display" 로 복원되지 않음',
          );
        }
      });
    });

    test('갈린 등록명 목록은 2개 이상이고 중복이 없다', () {
      arrivalApiSplitRegistrationNames.forEach((display, apiNames) {
        expect(apiNames.length, greaterThanOrEqualTo(2),
            reason: '$display 는 갈린 역이 아니므로 등록 불필요');
        expect(apiNames.toSet().length, apiNames.length,
            reason: '$display 의 등록명에 중복 있음 — 같은 질의를 두 번 보냄');
      });
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
      // 서울역: statnNm·arvlMsg3 이 "서울"로 오므로 표시명으로 복원해야
      // stations.json 매칭(라이브맵 좌표·도착시간 추정)이 성립한다.
      expect(resolveDisplayStationName('서울'), '서울역');
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

    test('다른 역명의 접두사인 "서울"은 자유텍스트에서 치환하지 않는다', () {
      // "서울" 을 부분 치환하면 서울대입구·서울숲 등이 "서울역대입구"로 오염된다.
      // 전체 문자열이 역명인 필드는 resolveDisplayStationName 이 정확히 복원하므로,
      // 자유텍스트에서는 API 표기("서울")가 그대로 남는 편을 택했다.
      expect(resolveDisplayInText('성수행 - 서울대입구방면'), '성수행 - 서울대입구방면');
      expect(resolveDisplayInText('왕십리행 - 서울숲방면'), '왕십리행 - 서울숲방면');
      expect(resolveDisplayInText('서울 도착'), '서울 도착');
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

      test('갈린 역 키도 stations.json 에 실존하는 표시명이다', () {
        for (final key in arrivalApiSplitRegistrationNames.keys) {
          expect(
            displayNames,
            contains(key),
            reason: '"$key" 가 stations.json 에 없음 — 데이터 드리프트 의심',
          );
        }
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

      test('다른 역 표시명의 부분 문자열인 API 표기는 자유텍스트를 오염시키지 않는다', () {
        // 치환 후보가 다른 역 이름의 일부이면(예: "서울" ⊂ "서울대입구")
        // resolveDisplayInText 가 없는 역명을 만들어낸다. 그런 후보는
        // _textReplacementExclusions 로 제외해야 한다.
        //
        // 후보는 아웃바운드 맵의 값 + 인바운드 전용 표기를 모두 포함한다
        // (textReplacementCandidates) — 인바운드 전용 표기도 같은 치환 경로를 타므로
        // 함께 검사하지 않으면 가드를 조용히 우회한다.
        //
        // 단, 치환 맵의 **키(표시명)** 는 피해자 후보에서 뺀다 — 키는 API 가 보내지
        // 않는 이름이고("관악산(서울대)" 는 API 상 늘 "관악산"), 왕복 항등 테스트가
        // 이미 지키고 있다. 이 전제가 깨지는 노선이 나오면 여기부터 재검토할 것.
        for (final apiName in textReplacementCandidates) {
          final victims = displayNames.where(
            (n) =>
                n != apiName &&
                n.contains(apiName) &&
                !arrivalApiStationNameOverrides.containsKey(n),
          );
          for (final victim in victims) {
            expect(
              resolveDisplayInText('$victim행 - $victim방면'),
              '$victim행 - $victim방면',
              reason:
                  'API 표기 "$apiName" 이 다른 역 "$victim" 안에서 부분 치환됨 — '
                  '_textReplacementExclusions 에 추가 필요',
            );
          }
        }
      });
    });
  });
}
