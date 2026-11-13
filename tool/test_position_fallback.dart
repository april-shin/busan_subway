// 열차위치 API 폴백 실측 프로브.
//
// 도착정보 API 가 제공하지 않는 (역, 노선) — 예: 5호선 천호 — 에서 위치 API 폴백이
// 실제로 열차를 만들어내는지 라이브 데이터로 확인한다.
//
// 실행: dart run tool/test_position_fallback.dart [역명] [노선]
//   기본값: 천호 5
//
// 앱 런타임과 같은 코드 경로(TrainPositionDto → fallbackArrivalsFromPositions)를
// 쓰므로, 이 스크립트가 열차를 뽑아내면 지도에도 나온다.
import 'dart:convert';
import 'dart:io';

import 'package:busan_subway/core/constants/subway_id_mapping.dart';
import 'package:busan_subway/core/utils/fallback_arrivals_from_positions.dart';
import 'package:busan_subway/data/remote/dto/train_position_dto.dart';
import 'package:busan_subway/domain/entities/connection.dart';
import 'package:busan_subway/domain/entities/station.dart';

Future<void> main(List<String> args) async {
  final targetStation = args.isNotEmpty ? args[0] : '천호';
  final lineId = args.length > 1 ? args[1] : '5';

  final apiKey = _readApiKey();
  final lineApiName = positionApiLineName(lineId);
  if (lineApiName == null) {
    stderr.writeln('위치 API 미지원 노선: $lineId');
    exit(1);
  }

  final stations = (jsonDecode(File('assets/json/stations.json').readAsStringSync())
          as List)
      .map((e) => Station.fromJson(e as Map<String, dynamic>))
      .toList();
  final connections =
      (jsonDecode(File('assets/json/connections.json').readAsStringSync())
              as List)
          .map((e) => Connection.fromJson(e as Map<String, dynamic>))
          .toList();

  final client = HttpClient();
  final uri = Uri.parse(
    'http://swopenapi.seoul.go.kr/api/subway/$apiKey/json/realtimePosition/0/100/'
    '${Uri.encodeComponent(lineApiName)}',
  );
  final response = await (await client.getUrl(uri)).close();
  final body = await response.transform(utf8.decoder).join();
  client.close();

  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final list = decoded['realtimePositionList'] as List<dynamic>?;
  if (list == null) {
    stderr.writeln('위치 응답 없음: ${decoded['errorMessage'] ?? decoded}');
    exit(1);
  }

  final dtos = list
      .map((e) => TrainPositionDto.fromJson(e as Map<String, dynamic>))
      .toList();
  stdout.writeln('$lineApiName 재차 열차: ${dtos.length}대');

  final fallback = fallbackArrivalsFromPositions(
    rawPositions: [for (final d in dtos) d.toArrivalInfo(targetStation)],
    targetStationName: targetStation,
    stations: stations,
    connections: connections,
  );

  stdout.writeln('\n$targetStation($lineId호선) 폴백 도착정보: ${fallback.length}건');
  for (final a in fallback) {
    stdout.writeln(
      '  ${a.direction} | ${a.destination}행 | 열차 ${a.trainNo} | '
      '현재역 ${a.currentStationName}(${a.positionStatus}) | '
      '${a.arrivalSeconds}초 후 | 기준시각 ${a.receivedAt}',
    );
  }
  if (fallback.isEmpty) {
    stdout.writeln('  (대상역을 향하는 열차가 범위 내에 없음)');
  }
}

String _readApiKey() {
  final env = File('.env').readAsLinesSync();
  for (final line in env) {
    if (line.startsWith('BUSAN_SUBWAY_API_KEY')) {
      return line.split('=')[1].trim();
    }
  }
  stderr.writeln('.env 에 BUSAN_SUBWAY_API_KEY 가 없습니다');
  exit(1);
}
