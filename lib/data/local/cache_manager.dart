import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/api_constants.dart';

class CacheManager {
  static const String _prefix = 'cache_';
  static const String _timestampSuffix = '_timestamp';

  Future<void> cacheData(String key, String data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', data);
    await prefs.setInt(
      '$_prefix$key$_timestampSuffix',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<String?> getCachedData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('$_prefix$key');
    if (data == null) return null;

    final timestamp = prefs.getInt('$_prefix$key$_timestampSuffix');
    if (timestamp == null) return null;

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final elapsed = DateTime.now().difference(cachedAt);

    if (elapsed > ApiConstants.cacheTtl) {
      await _removeCache(prefs, key);
      return null;
    }

    return data;
  }

  Future<CachedEntry?> getCachedDataWithTimestamp(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('$_prefix$key');
    if (data == null) return null;

    final timestamp = prefs.getInt('$_prefix$key$_timestampSuffix');
    if (timestamp == null) return null;

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return CachedEntry(data: data, cachedAt: cachedAt);
  }

  Future<void> cacheRecentSearches(List<Map<String, String>> searches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent_searches', json.encode(searches));
  }

  Future<List<Map<String, String>>> getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('recent_searches');
    if (data == null) return [];

    final List<dynamic> decoded = json.decode(data) as List<dynamic>;
    return decoded
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  Future<void> _removeCache(SharedPreferences prefs, String key) async {
    await prefs.remove('$_prefix$key');
    await prefs.remove('$_prefix$key$_timestampSuffix');
  }
}

class CachedEntry {
  final String data;
  final DateTime cachedAt;

  const CachedEntry({required this.data, required this.cachedAt});

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > ApiConstants.cacheTtl;
}
