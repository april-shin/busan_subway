import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:seoul_subway/data/local/cache_manager.dart';

void main() {
  late CacheManager cacheManager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cacheManager = CacheManager();
  });

  group('CacheManager', () {
    test('cacheData stores data and timestamp', () async {
      await cacheManager.cacheData('test_key', '{"data": "value"}');

      final result = await cacheManager.getCachedData('test_key');
      expect(result, '{"data": "value"}');
    });

    test('getCachedData returns null for missing key', () async {
      final result = await cacheManager.getCachedData('nonexistent');
      expect(result, isNull);
    });

    test('getCachedData returns null when only data exists without timestamp',
        () async {
      SharedPreferences.setMockInitialValues({
        'cache_no_ts': 'some data',
      });
      cacheManager = CacheManager();

      final result = await cacheManager.getCachedData('no_ts');
      expect(result, isNull);
    });

    test('getCachedDataWithTimestamp returns entry with timestamp', () async {
      await cacheManager.cacheData('ts_key', 'test_data');

      final entry = await cacheManager.getCachedDataWithTimestamp('ts_key');
      expect(entry, isNotNull);
      expect(entry!.data, 'test_data');
      expect(entry.cachedAt.isBefore(DateTime.now()), true);
    });

    test('getCachedDataWithTimestamp returns null for missing key', () async {
      final entry =
          await cacheManager.getCachedDataWithTimestamp('nonexistent');
      expect(entry, isNull);
    });

    test('cacheRecentSearches stores and retrieves searches', () async {
      final searches = [
        {'from': '강남', 'to': '서울역'},
        {'from': '시청', 'to': '을지로입구'},
      ];

      await cacheManager.cacheRecentSearches(searches);
      final result = await cacheManager.getRecentSearches();

      expect(result.length, 2);
      expect(result[0]['from'], '강남');
      expect(result[1]['to'], '을지로입구');
    });

    test('getRecentSearches returns empty list when no data', () async {
      final result = await cacheManager.getRecentSearches();
      expect(result, isEmpty);
    });
  });

  group('CachedEntry', () {
    test('isExpired returns false for fresh entry', () {
      final entry = CachedEntry(
        data: 'test',
        cachedAt: DateTime.now(),
      );
      expect(entry.isExpired, false);
    });

    test('isExpired returns true for old entry', () {
      final entry = CachedEntry(
        data: 'test',
        cachedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(entry.isExpired, true);
    });
  });
}
