import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/station.dart';
import '../../domain/entities/line.dart';
import '../../domain/entities/connection.dart';

class LocalDataSource {
  List<Station>? _stationsCache;
  List<Line>? _linesCache;
  List<Connection>? _connectionsCache;
  Map<String, int>? _transferTimesCache;

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

  void clearCache() {
    _stationsCache = null;
    _linesCache = null;
    _connectionsCache = null;
    _transferTimesCache = null;
  }
}
