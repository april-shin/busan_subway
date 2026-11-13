import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/core/utils/parse_arrival_message.dart';

void main() {
  group('parseTimeFromMessage', () {
    test('"3분 30초" → 210', () {
      expect(parseTimeFromMessage('3분 30초'), 210);
    });

    test('"2분" → 120', () {
      expect(parseTimeFromMessage('2분'), 120);
    });

    test('"1분 후" → 60', () {
      expect(parseTimeFromMessage('1분 후'), 60);
    });

    test('"전역 출발" → null (시간 정보 없음)', () {
      expect(parseTimeFromMessage('전역 출발'), isNull);
    });

    test('"" → null (빈 문자열)', () {
      expect(parseTimeFromMessage(''), isNull);
    });

    test('"10분 5초" → 605', () {
      expect(parseTimeFromMessage('10분 5초'), 605);
    });

    test('"곧 도착" → null', () {
      expect(parseTimeFromMessage('곧 도착'), isNull);
    });
  });

  group('parseStationCount', () {
    test('"전역 출발" → (count: 1, status: "출발")', () {
      final result = parseStationCount('전역 출발');
      expect(result, isNotNull);
      expect(result!.count, 1);
      expect(result.status, '출발');
    });

    test('"3번째 전역 도착" → (count: 3, status: "도착")', () {
      final result = parseStationCount('3번째 전역 도착');
      expect(result, isNotNull);
      expect(result!.count, 3);
      expect(result.status, '도착');
    });

    test('"3번째 전역" → (count: 3, status: "")', () {
      final result = parseStationCount('3번째 전역');
      expect(result, isNotNull);
      expect(result!.count, 3);
      expect(result.status, '');
    });

    test('"전역 진입" → (count: 1, status: "진입")', () {
      final result = parseStationCount('전역 진입');
      expect(result, isNotNull);
      expect(result!.count, 1);
      expect(result.status, '진입');
    });

    test('"전역" → (count: 1, status: "")', () {
      final result = parseStationCount('전역');
      expect(result, isNotNull);
      expect(result!.count, 1);
      expect(result.status, '');
    });

    test('"2번째 전역 출발" → (count: 2, status: "출발")', () {
      final result = parseStationCount('2번째 전역 출발');
      expect(result, isNotNull);
      expect(result!.count, 2);
      expect(result.status, '출발');
    });

    test('"[4]번째 전역 (판교)" → (count: 4, status: "")', () {
      final result = parseStationCount('[4]번째 전역 (판교)');
      expect(result, isNotNull);
      expect(result!.count, 4);
      expect(result.status, '');
    });

    test('"[2]번째 전역" → (count: 2, status: "")', () {
      final result = parseStationCount('[2]번째 전역');
      expect(result, isNotNull);
      expect(result!.count, 2);
      expect(result.status, '');
    });

    test('"[1]번째 전역 (양재) 출발" → (count: 1, status: "출발")', () {
      final result = parseStationCount('[1]번째 전역 (양재) 출발');
      expect(result, isNotNull);
      expect(result!.count, 1);
      expect(result.status, '출발');
    });

    test('"곧 도착" → null', () {
      expect(parseStationCount('곧 도착'), isNull);
    });

    test('"" → null (빈 문자열)', () {
      expect(parseStationCount(''), isNull);
    });
  });
}
