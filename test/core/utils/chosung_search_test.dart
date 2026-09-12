import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/chosung_search.dart';

void main() {
  group('matchesStationQuery — 기존 부분일치 동작 보존', () {
    test('빈 검색어는 모두 통과', () {
      expect(matchesStationQuery('강남', ''), isTrue);
    });

    test('완성형 한글 부분일치', () {
      expect(matchesStationQuery('강남', '강남'), isTrue);
      expect(matchesStationQuery('강남구청', '남구'), isTrue);
      expect(matchesStationQuery('강남', '역삼'), isFalse);
    });

    test('검색어가 이름보다 길면 불일치', () {
      expect(matchesStationQuery('강남', '강남역'), isFalse);
    });

    test('괄호 부역명·숫자도 그대로 비교', () {
      expect(matchesStationQuery('총신대입구(이수)', '(이수)'), isTrue);
      expect(matchesStationQuery('4·19민주묘지', '19'), isTrue);
    });

    test('초성이 섞이지 않은 검색어는 contains 와 결과가 같다 (기본 모드)', () {
      const names = ['강남', '강남구청', '역삼', '사우 (김포시청)', '총신대입구(이수)'];
      const queries = ['강', '남구', '삼', '김포', '(이수)', '없는역'];
      for (final name in names) {
        for (final query in queries) {
          expect(
            matchesStationQuery(name, query),
            name.contains(query),
            reason: '$name / $query',
          );
        }
      }
    });
  });

  group('matchesStationQuery — 초성 검색', () {
    test('초성만으로 매칭', () {
      expect(matchesStationQuery('강남', 'ㄱㄴ'), isTrue);
      expect(matchesStationQuery('역삼', 'ㅇㅅ'), isTrue);
      expect(matchesStationQuery('강남', 'ㄱ'), isTrue);
    });

    test('초성이 다르면 불일치', () {
      expect(matchesStationQuery('강남', 'ㄴㄱ'), isFalse);
      expect(matchesStationQuery('강남', 'ㄱㄷ'), isFalse);
    });

    test('쌍자음 초성은 단자음과 구분된다', () {
      expect(matchesStationQuery('까치산', 'ㄲㅊㅅ'), isTrue);
      expect(matchesStationQuery('까치산', 'ㄱㅊㅅ'), isFalse);
    });

    test('이름 중간에서 시작하는 초성 매칭도 부분일치로 잡는다', () {
      expect(matchesStationQuery('강남구청', 'ㄱㅊ'), isTrue);
    });

    test('완성형과 초성을 섞은 검색어', () {
      expect(matchesStationQuery('강남', '강ㄴ'), isTrue);
      expect(matchesStationQuery('강남', 'ㄱ남'), isTrue);
      expect(matchesStationQuery('강남', '강ㄷ'), isFalse);
    });

    test('중성·겹받침 자모는 초성이 아니므로 매칭되지 않는다', () {
      expect(matchesStationQuery('강남', 'ㅏ'), isFalse);
      expect(matchesStationQuery('닭섬', 'ㄺ'), isFalse);
    });

    test('한글이 아닌 글자는 초성 비교 대상이 아니다', () {
      expect(matchesStationQuery('4·19민주묘지', 'ㅁㅈㅁㅈ'), isTrue);
      expect(matchesStationQuery('4·19민주묘지', 'ㄱ'), isFalse);
    });
  });

  group('matchesStationQuery — 초성 표·유니코드 경계', () {
    test('초성 19자 전부 index 가 맞는다', () {
      const chosung = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
      for (var i = 0; i < chosung.length; i++) {
        // 각 초성의 첫 음절: 가, 까, 나, 다, …
        final syllable = String.fromCharCode(0xAC00 + i * 588);
        expect(matchesStationQuery(syllable, chosung[i]), isTrue,
            reason: chosung[i]);
        if (i > 0) {
          expect(matchesStationQuery(syllable, chosung[i - 1]), isFalse,
              reason: '${chosung[i]} != ${chosung[i - 1]}');
        }
      }
    });

    test('한글 음절 영역 경계', () {
      expect(matchesStationQuery('가', 'ㄱ'), isTrue); // 0xAC00
      expect(matchesStationQuery('힣', 'ㅎ'), isTrue); // 0xD7A3
      expect(matchesStationQuery(String.fromCharCode(0xABFF), 'ㄱ'), isFalse);
      expect(matchesStationQuery(String.fromCharCode(0xD7A4), 'ㅎ'), isFalse);
    });

    test('조합용 초성 자모(U+1100~)도 초성으로 인식', () {
      expect(matchesStationQuery('강남', 'ᄀᄂ'), isTrue); // ᄀᄂ
      expect(matchesStationQuery('강남', 'ᄂᄀ'), isFalse);
    });

    test('서로게이트·이모지는 예외 없이 불일치', () {
      expect(matchesStationQuery('강남', '😀'), isFalse);
      expect(matchesStationQuery('강남', '\uD83D'), isFalse);
    });
  });

  group('matchesStationQuery — 조합 중 종성 분해(splitTrailingJamo)', () {
    test('기본 모드에서는 분해하지 않는다', () {
      expect(matchesStationQuery('사당', '삳'), isFalse);
    });

    test('열린음절 뒤 자음이 종성으로 흡수된 조합 중 상태를 복구', () {
      expect(matchesStationQuery('사당', '삳', splitTrailingJamo: true), isTrue);
      expect(matchesStationQuery('서울', '성', splitTrailingJamo: true), isTrue);
      expect(matchesStationQuery('노원', '농', splitTrailingJamo: true), isTrue);
      expect(matchesStationQuery('도곡', '독', splitTrailingJamo: true), isTrue);
    });

    test('겹받침은 앞 자음을 종성으로 남기고 뒤 자음만 뗀다', () {
      // '역삼' 입력 중 ㅅ 이 '역' 의 종성에 붙어 '엯'(ㄱ+ㅅ) 이 된 상태.
      expect(matchesStationQuery('역삼', '엯', splitTrailingJamo: true), isTrue);
      expect(matchesStationQuery('역삼', '엯'), isFalse);
    });

    test('분해해도 초성이 다르면 불일치', () {
      expect(matchesStationQuery('사당', '삭', splitTrailingJamo: true), isFalse);
    });

    test('뗄 종성이 없으면 기본 모드와 결과가 같다', () {
      expect(matchesStationQuery('사당', '사', splitTrailingJamo: true), isTrue);
      expect(matchesStationQuery('사당', 'ㅅ', splitTrailingJamo: true), isTrue);
      expect(matchesStationQuery('사당', '수', splitTrailingJamo: true), isFalse);
    });
  });
}
