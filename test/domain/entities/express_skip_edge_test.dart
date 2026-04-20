import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';

void main() {
  group('ExpressSkipEdge', () {
    test('기본 생성자 — 필수 필드만 지정하면 skippedStationIds=빈 리스트', () {
      const edge = ExpressSkipEdge(
        lineId: '9',
        fromStationId: '902',
        toStationId: '905',
        seconds: 180,
      );

      expect(edge.lineId, '9');
      expect(edge.fromStationId, '902');
      expect(edge.toStationId, '905');
      expect(edge.seconds, 180);
      expect(edge.skippedStationIds, isEmpty);
    });

    test('skippedStationIds 명시', () {
      const edge = ExpressSkipEdge(
        lineId: '9',
        fromStationId: '902',
        toStationId: '905',
        seconds: 180,
        skippedStationIds: ['903', '904'],
      );

      expect(edge.skippedStationIds, ['903', '904']);
    });

    test('fromJson — 필수 필드만 있어도 파싱 성공', () {
      final edge = ExpressSkipEdge.fromJson({
        'lineId': '9',
        'fromStationId': '902',
        'toStationId': '905',
        'seconds': 180,
      });

      expect(edge.skippedStationIds, isEmpty);
    });

    test('fromJson — skippedStationIds 포함', () {
      final edge = ExpressSkipEdge.fromJson({
        'lineId': '9',
        'fromStationId': '902',
        'toStationId': '905',
        'seconds': 180,
        'skippedStationIds': ['903', '904'],
      });

      expect(edge.skippedStationIds, ['903', '904']);
    });

    test('toJson/fromJson 라운드트립', () {
      const original = ExpressSkipEdge(
        lineId: '9',
        fromStationId: '902',
        toStationId: '905',
        seconds: 180,
        skippedStationIds: ['903', '904'],
      );

      final encoded = original.toJson();
      final decoded = ExpressSkipEdge.fromJson(encoded);

      expect(decoded, equals(original));
    });

    test('copyWith — seconds 변경', () {
      const edge = ExpressSkipEdge(
        lineId: '9',
        fromStationId: '902',
        toStationId: '905',
        seconds: 180,
      );

      final updated = edge.copyWith(seconds: 200);

      expect(updated.seconds, 200);
      expect(updated.lineId, '9');
      expect(edge.seconds, 180); // 원본 불변
    });
  });
}
