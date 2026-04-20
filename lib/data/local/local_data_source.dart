import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/station.dart';
import '../../domain/entities/line.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/express_skip_edge.dart';
import '../../domain/entities/transfer_guide.dart';

class LocalDataSource {
  List<Station>? _stationsCache;
  List<Line>? _linesCache;
  List<Connection>? _connectionsCache;
  Map<String, int>? _transferTimesCache;
  Map<String, TransferGuide>? _transferGuidesCache;
  List<ExpressSkipEdge>? _expressSkipEdgesCache;

  Future<List<Station>> loadStations() async {
    if (_stationsCache != null) return _stationsCache!;

    final jsonString = await rootBundle.loadString('assets/json/stations.json');
    final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
    _stationsCache = jsonList
        .map((e) => Station.fromJson(e as Map<String, dynamic>))
        .toList();
    return _stationsCache!;
  }

  Future<List<Line>> loadLines() async {
    if (_linesCache != null) return _linesCache!;

    final jsonString = await rootBundle.loadString('assets/json/lines.json');
    final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
    _linesCache =
        jsonList.map((e) => Line.fromJson(e as Map<String, dynamic>)).toList();
    return _linesCache!;
  }

  Future<List<Connection>> loadConnections() async {
    if (_connectionsCache != null) return _connectionsCache!;

    final jsonString =
        await rootBundle.loadString('assets/json/connections.json');
    final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
    _connectionsCache = jsonList
        .map((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
    return _connectionsCache!;
  }

  Future<Map<String, int>> loadTransferTimes() async {
    if (_transferTimesCache != null) return _transferTimesCache!;

    final jsonString =
        await rootBundle.loadString('assets/json/transfer_times.json');
    final Map<String, dynamic> jsonMap =
        json.decode(jsonString) as Map<String, dynamic>;
    _transferTimesCache =
        jsonMap.map((key, value) => MapEntry(key, value as int));
    return _transferTimesCache!;
  }

  /// 환승 가이드(하차 문 방향/객차/문 번호)를 번들 JSON에서 로드한다.
  ///
  /// 키 포맷: `{환승역명}_{도착노선}_{도착방향(up|down)}_{목적노선}`
  ///
  /// 개별 엔트리의 파싱에 실패해도(예: enum 오타, 타입 불일치) 경로 검색 전체가
  /// 중단되지 않도록 해당 엔트리만 건너뛴다. JSON 전체 구조가 망가진 경우에만
  /// 최상위 `FormatException`을 던진다.
  Future<Map<String, TransferGuide>> loadTransferGuides() async {
    if (_transferGuidesCache != null) return _transferGuidesCache!;

    final jsonString =
        await rootBundle.loadString('assets/json/transfer_guides.json');
    final Map<String, dynamic> jsonMap =
        json.decode(jsonString) as Map<String, dynamic>;

    final parsed = <String, TransferGuide>{};
    for (final entry in jsonMap.entries) {
      try {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        parsed[entry.key] = TransferGuide.fromJson(value);
      } catch (_) {
        // 개별 항목 파싱 실패는 무시하고 다음 엔트리로 진행.
      }
    }
    _transferGuidesCache = parsed;
    return _transferGuidesCache!;
  }

  /// 급행 정차역 간 skip edge 목록을 로드한다.
  ///
  /// JSON 포맷: `{ lineId: [ {lineId, fromStationId, toStationId, seconds,
  /// skippedStationIds}, ... ], ... }`
  ///
  /// 모든 노선의 edge를 단일 List로 flatten하여 반환한다.
  /// 파일이 없거나 비어있어도 예외를 던지지 않고 빈 리스트를 반환한다.
  Future<List<ExpressSkipEdge>> loadExpressSkipEdges() async {
    if (_expressSkipEdgesCache != null) return _expressSkipEdgesCache!;

    try {
      final jsonString = await rootBundle
          .loadString('assets/json/express_skip_edges.json');
      final Map<String, dynamic> jsonMap =
          json.decode(jsonString) as Map<String, dynamic>;

      final all = <ExpressSkipEdge>[];
      for (final entry in jsonMap.entries) {
        final value = entry.value;
        if (value is! List) continue;
        for (final item in value) {
          if (item is! Map<String, dynamic>) continue;
          try {
            all.add(ExpressSkipEdge.fromJson(item));
          } catch (_) {
            // 개별 항목 파싱 실패는 무시.
          }
        }
      }
      _expressSkipEdgesCache = List.unmodifiable(all);
    } catch (_) {
      // 파일 자체가 없으면 빈 리스트 반환 (호환성).
      _expressSkipEdgesCache = const <ExpressSkipEdge>[];
    }
    return _expressSkipEdgesCache!;
  }

  void clearCache() {
    _stationsCache = null;
    _linesCache = null;
    _connectionsCache = null;
    _transferTimesCache = null;
    _transferGuidesCache = null;
    _expressSkipEdgesCache = null;
  }
}
