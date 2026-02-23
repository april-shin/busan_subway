/// SVG 파일에서 역 좌표(cx, cy)와 역명(data-station)을 추출하는 스크립트.
///
/// 출력: assets/json/svg_station_coords.json
/// 형식: { "역명": { "svgX": ..., "svgY": ..., "dataLine": "..." }, ... }
///
/// 모든 data-line의 text 라벨을 추출하여 역명 → SVG 좌표 매핑을 생성한다.
/// 앱의 lineId 매핑은 generate_station_data.dart에서 처리한다.
///
/// 사용법: dart run tool/extract_svg_stations.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:xml/xml.dart';

/// text 라벨과 circle 사이의 최대 매칭 거리 (SVG 좌표계 단위).
/// SVG에서 역명 라벨은 일반적으로 역 원(circle)에서 30~40px 이내에 위치한다.
const _maxMatchingDistance = 50.0;

void main() {
  final inputPath = 'assets/svg/seoul_metro_map.svg';
  final outputPath = 'assets/json/svg_station_coords.json';

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('입력 파일 없음: $inputPath');
    exit(1);
  }

  final svgContent = inputFile.readAsStringSync();
  final document = XmlDocument.parse(svgContent);
  final svg = document.rootElement;

  // 1. 모든 circle (station-dot) 추출
  final stationDots = <_Circle>[];
  for (final circle in svg.findAllElements('circle')) {
    final cx = double.tryParse(circle.getAttribute('cx') ?? '');
    final cy = double.tryParse(circle.getAttribute('cy') ?? '');
    final fill = circle.getAttribute('fill') ?? '';
    final className = circle.getAttribute('class') ?? '';
    if (cx == null || cy == null) continue;

    stationDots.add(_Circle(cx, cy, fill, className));
  }

  // 2. 모든 캡슐형 rect 추출 (환승역 마커, rx 속성으로 식별)
  for (final rect in svg.findAllElements('rect')) {
    final rx = rect.getAttribute('rx');
    if (rx == null) continue;

    final x = double.tryParse(rect.getAttribute('x') ?? '');
    final y = double.tryParse(rect.getAttribute('y') ?? '');
    final w = double.tryParse(rect.getAttribute('width') ?? '');
    final h = double.tryParse(rect.getAttribute('height') ?? '');
    if (x == null || y == null || w == null || h == null) continue;

    stationDots.add(_Circle(x + w / 2, y + h / 2, '', 'capsule'));
  }

  // 3. 모든 text (역명 라벨) 추출 — data-line 필터 없이 전부
  final textLabels = <_TextLabel>[];
  for (final text in svg.findAllElements('text')) {
    final rawName = text.getAttribute('data-station');
    final dataLine = text.getAttribute('data-line');
    final x = double.tryParse(text.getAttribute('x') ?? '');
    final y = double.tryParse(text.getAttribute('y') ?? '');
    if (rawName == null || dataLine == null || x == null || y == null) {
      continue;
    }

    // 줄바꿈 문자 제거 (SVG에서 <tspan>으로 분할된 역명)
    final cleanName = rawName.replaceAll('\n', '').replaceAll('\r', '').trim();

    textLabels.add(_TextLabel(cleanName, dataLine, x, y));
  }

  // 4. 각 text 라벨에 대해 가장 가까운 circle 찾기
  // 역명 기준으로 중복 제거 (첫 번째 매칭만 사용)
  final stationCoords = <String, Map<String, dynamic>>{};
  var matched = 0;
  var unmatched = 0;

  final usedCircles = <int>{};
  for (final label in textLabels) {
    // 키: 역명 (동일 역은 하나의 좌표만 저장)
    final key = label.name;
    if (stationCoords.containsKey(key)) continue;

    // text 좌표 근처에서 가장 가까운 미사용 circle 찾기
    var bestCircleIdx = -1;
    var bestDist = double.infinity;

    for (var i = 0; i < stationDots.length; i++) {
      if (usedCircles.contains(i)) continue;
      final dot = stationDots[i];
      final dx = dot.cx - label.x;
      final dy = dot.cy - label.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < bestDist) {
        bestDist = dist;
        bestCircleIdx = i;
      }
    }

    if (bestCircleIdx >= 0 && bestDist < _maxMatchingDistance) {
      final bestCircle = stationDots[bestCircleIdx];
      usedCircles.add(bestCircleIdx);
      stationCoords[key] = {
        'name': label.name,
        'dataLine': label.dataLine,
        'svgX': bestCircle.cx,
        'svgY': bestCircle.cy,
        'distance': bestDist.round(),
      };
      matched++;
    } else {
      // text 좌표를 폴백으로 사용 (baseline 보정)
      const textBaselineOffset = 10.0;
      stationCoords[key] = {
        'name': label.name,
        'dataLine': label.dataLine,
        'svgX': label.x,
        'svgY': label.y - textBaselineOffset,
        'distance': -1,
      };
      unmatched++;
    }
  }

  // 수동 좌표 오버라이드 (텍스트-circle 거리가 임계값 초과하는 경우)
  const manualOverrides = {
    '장자호수공원': {'svgX': 2072.0, 'svgY': 576.0},
  };
  for (final entry in manualOverrides.entries) {
    if (stationCoords.containsKey(entry.key)) {
      stationCoords[entry.key]!['svgX'] = entry.value['svgX'];
      stationCoords[entry.key]!['svgY'] = entry.value['svgY'];
      stationCoords[entry.key]!['distance'] = 0;
    }
  }

  // 출력
  final encoder = const JsonEncoder.withIndent('  ');
  File(outputPath).writeAsStringSync(encoder.convert(stationCoords));

  stdout.writeln('SVG 역 좌표 추출 완료');
  stdout.writeln('  총 text 라벨: ${textLabels.length}');
  stdout.writeln('  총 circle/rect: ${stationDots.length}');
  stdout.writeln('  매칭 성공: $matched');
  stdout.writeln('  매칭 실패 (폴백): $unmatched');
  stdout.writeln('  고유 역: ${stationCoords.length}');
  stdout.writeln('  출력: $outputPath');
}

class _Circle {
  final double cx;
  final double cy;
  final String fill;
  final String className;

  _Circle(this.cx, this.cy, this.fill, this.className);
}

class _TextLabel {
  final String name;
  final String dataLine;
  final double x;
  final double y;

  _TextLabel(this.name, this.dataLine, this.x, this.y);
}
