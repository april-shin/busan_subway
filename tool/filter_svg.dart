/// 서울 지하철 SVG에서 미지원 노선을 제거하고 flutter_svg 호환 변환을 수행하는 스크립트.
///
/// 입력: assets/svg/seoul_metro_map.svg
/// 출력: assets/svg/seoul_subway_map_filtered.svg
///
/// 변환 내용:
/// - 미지원 노선의 path/text/circle 제거
/// - SVG 루트: 퍼센트 치수 → 고정 치수, background 스타일 제거
/// - CSS `<style>` 블록 → 인라인 속성 변환 후 제거
/// - 모든 `<text>` 요소 제거 (Flutter Text 위젯으로 대체)
/// - data-*, class 속성 제거
///
/// 사용법: dart run tool/filter_svg.dart
library;

import 'dart:io';

import 'package:xml/xml.dart';

/// 앱에서 지원하는 노선의 data-line 값 목록.
const supportedDataLines = {
  '2-1', // 1호선
  '3-2', // 2호선
  '4-3', // 3호선
  '5-4', // 4호선
  '6-5', // 5호선
  '7-6', // 6호선
  '8-7', // 7호선
  '9-8', // 8호선
  '10-9', // 9호선
  'S', // 신분당선
  'K', // 경의중앙선
  'KK', // 경춘선
  'A', // 공항철도
  'B', // 수인분당선
  'SL', // 신림선
};

/// 지원 노선의 stroke/fill 색상 (circle/rect 필터링용).
const supportedColors = {
  '#052f93', // 1호선
  '#10a643', // 2호선
  '#de6d00', // 3호선
  '#0099d1', // 4호선
  '#a95094', // 5호선
  '#d08d1a', // 6호선
  '#657931', // 7호선
  '#e74e6d', // 8호선
  '#b58600', // 9호선
  '#cd2234', // 신분당선
  '#5f9c82', // 경의중앙선
  '#004ea7', // 경춘선
  '#038fa0', // 공항철도
  '#a69500', // 수인분당선
  '#0781fa', // 신림선
  '#333', // interchange stroke
  '#333333', // interchange stroke (alternative)
};

void main() {
  final inputPath = 'assets/svg/seoul_metro_map.svg';
  final outputPath = 'assets/svg/seoul_subway_map_filtered.svg';

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('입력 파일 없음: $inputPath');
    exit(1);
  }

  final svgContent = inputFile.readAsStringSync();
  final document = XmlDocument.parse(svgContent);
  final svg = document.rootElement;

  var removedPaths = 0;
  var removedTexts = 0;
  var removedCircles = 0;
  var removedRects = 0;

  // 1단계: 지원 노선의 텍스트 좌표를 수집 (circle/rect 매칭용)
  final supportedTextPositions = <String>{};

  for (final text in svg.findAllElements('text').toList()) {
    final dataLine = text.getAttribute('data-line');
    if (dataLine != null && supportedDataLines.contains(dataLine)) {
      final x = text.getAttribute('x');
      final y = text.getAttribute('y');
      if (x != null && y != null) {
        supportedTextPositions.add('$x,$y');
      }
    }
  }

  // 2단계: 미지원 path 요소 제거
  for (final path in svg.findAllElements('path').toList()) {
    final dataLine = path.getAttribute('data-line');
    if (dataLine != null && !supportedDataLines.contains(dataLine)) {
      path.parent?.children.remove(path);
      removedPaths++;
    }
  }

  // 3단계: 모든 text 요소 제거 (flutter_svg가 한국어 텍스트 렌더링 불가)
  for (final text in svg.findAllElements('text').toList()) {
    text.parent?.children.remove(text);
    removedTexts++;
  }

  // 4단계: 미지원 circle 요소 제거 (색상으로 판별)
  for (final circle in svg.findAllElements('circle').toList()) {
    final fill = circle.getAttribute('fill');
    final className = circle.getAttribute('class') ?? '';

    // interchange 클래스는 유지 (환승역은 여러 노선 공유)
    if (className.contains('interchange')) continue;

    // station-dot은 fill 색상으로 노선 판별
    if (className.contains('station-dot')) {
      if (fill != null && !supportedColors.contains(fill)) {
        circle.parent?.children.remove(circle);
        removedCircles++;
        continue;
      }
    }

    // stroke 또는 fill이 미지원 색상인 경우 제거
    if (fill != null &&
        !supportedColors.contains(fill) &&
        fill != 'white' &&
        fill != '#ffffff' &&
        fill != 'none') {
      circle.parent?.children.remove(circle);
      removedCircles++;
    }
  }

  // 5단계: interchange rect 중 미지원 역 제거
  // rect는 위치 기반으로 판별 — 가장 가까운 text와 비교
  // interchange는 여러 노선을 공유하므로 기본적으로 유지
  // (지원 노선이 하나라도 있으면 환승역 유지)

  // ============================================================
  // flutter_svg 호환 변환
  // ============================================================

  // 6단계: SVG 루트 속성 수정
  // width="100%" height="100%" → 고정 치수
  svg.setAttribute('width', '2416');
  svg.setAttribute('height', '1560');
  // style="background: white;" 제거
  svg.removeAttribute('style');

  // 7단계: CSS → 인라인 속성 변환
  // station-dot circle: stroke="white" stroke-width="1"
  for (final circle in svg.findAllElements('circle').toList()) {
    final className = circle.getAttribute('class') ?? '';
    if (className.contains('station-dot')) {
      if (circle.getAttribute('stroke') == null) {
        circle.setAttribute('stroke', 'white');
      }
      if (circle.getAttribute('stroke-width') == null) {
        circle.setAttribute('stroke-width', '1');
      }
    }
  }

  // interchange rect/circle: stroke="#333" stroke-width="1.5" fill="white"
  for (final element in [
    ...svg.findAllElements('rect'),
    ...svg.findAllElements('circle'),
  ]) {
    final className = element.getAttribute('class') ?? '';
    if (className.contains('interchange')) {
      if (element.getAttribute('stroke') == null) {
        element.setAttribute('stroke', '#333');
      }
      if (element.getAttribute('stroke-width') == null) {
        element.setAttribute('stroke-width', '1.5');
      }
      if (element.getAttribute('fill') == null) {
        element.setAttribute('fill', 'white');
      }
    }
  }

  // 8단계: <style> 블록 제거
  for (final style in svg.findAllElements('style').toList()) {
    style.parent?.children.remove(style);
  }

  // 9단계: data-*, class 속성 제거
  _removeAttributes(svg);

  // 10단계: 출력
  final outputFile = File(outputPath);
  outputFile.writeAsStringSync(document.toXmlString(pretty: false));

  final inputSize = inputFile.lengthSync();
  final outputSize = outputFile.lengthSync();

  stdout.writeln('SVG 필터링 완료');
  stdout.writeln('  제거된 path: $removedPaths');
  stdout.writeln('  제거된 text: $removedTexts');
  stdout.writeln('  제거된 circle: $removedCircles');
  stdout.writeln('  제거된 rect: $removedRects');
  stdout.writeln(
    '  크기: ${(inputSize / 1024).toStringAsFixed(1)}KB → '
    '${(outputSize / 1024).toStringAsFixed(1)}KB',
  );
}

/// 모든 요소에서 data-*, class 속성을 재귀적으로 제거한다.
void _removeAttributes(XmlElement element) {
  final attrsToRemove = element.attributes
      .where(
        (attr) =>
            attr.localName.startsWith('data-') ||
            attr.localName == 'class',
      )
      .toList();

  for (final attr in attrsToRemove) {
    element.removeAttribute(attr.localName);
  }

  for (final child in element.children.whereType<XmlElement>()) {
    _removeAttributes(child);
  }
}
