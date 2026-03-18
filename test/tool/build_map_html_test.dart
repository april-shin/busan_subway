import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('build_map_html.dart 생성 결과', () {
    late String htmlContent;

    setUpAll(() {
      final htmlFile = File('assets/html/map.html');
      if (!htmlFile.existsSync()) {
        fail('map.html이 존재하지 않습니다. '
            'dart run tool/build_map_html.dart를 먼저 실행하세요.');
      }
      htmlContent = htmlFile.readAsStringSync();
    });

    test('HTML 파일이 유효한 구조를 가진다', () {
      expect(htmlContent, contains('<!DOCTYPE html>'));
      expect(htmlContent, contains('<html'));
      expect(htmlContent, contains('</html>'));
      expect(htmlContent, contains('<body>'));
      expect(htmlContent, contains('</body>'));
    });

    test('SVG가 인라인으로 삽입되어 있다', () {
      expect(htmlContent, contains('<svg'));
      expect(htmlContent, contains('viewBox="0 0 2416.0 1560.0"'));
      expect(htmlContent, contains('width="2416" height="1560"'));
    });

    test('SVG에 한국어 텍스트가 보존되어 있다', () {
      // 원본 SVG의 역명이 제거되지 않고 남아있어야 한다
      expect(htmlContent, contains('data-station'));
    });

    test('배경 스타일이 제거되었다', () {
      // style="background: white;" 가 제거되어야 한다
      expect(htmlContent, isNot(contains('style="background: white;"')));
      expect(htmlContent, isNot(contains("style='background: white;'")));
    });

    test('width="100%" height="100%"가 고정 치수로 변환되었다', () {
      expect(htmlContent, isNot(contains('width="100%"')));
      expect(htmlContent, isNot(contains('height="100%"')));
    });

    test('오버레이 SVG가 존재한다', () {
      expect(htmlContent, contains('id="overlay"'));
      expect(htmlContent, contains('id="route-overlay-bg"'));
      expect(htmlContent, contains('id="route-lines"'));
      expect(htmlContent, contains('id="route-markers"'));
      expect(htmlContent, contains('id="selection-markers"'));
    });

    test('탭 레이어가 존재한다', () {
      expect(htmlContent, contains('id="tap-layer"'));
    });

    test('툴팁 컨테이너가 존재한다', () {
      expect(htmlContent, contains('id="tooltip"'));
    });

    test('JS API 함수가 정의되어 있다', () {
      expect(htmlContent, contains('window.initStations'));
      expect(htmlContent, contains('window.highlightRoute'));
      expect(htmlContent, contains('window.clearRoute'));
      expect(htmlContent, contains('window.setMarker'));
      expect(htmlContent, contains('window.clearMarkers'));
      expect(htmlContent, contains('window.showTooltip'));
      expect(htmlContent, contains('window.hideTooltip'));
    });

    test('Flutter 통신 채널이 설정되어 있다', () {
      expect(htmlContent, contains('StationChannel'));
      expect(htmlContent, contains('postMessage'));
    });

    test('줌/팬 상수가 올바르게 설정되어 있다', () {
      expect(htmlContent, contains('MIN_SCALE = 0.5'));
      expect(htmlContent, contains('MAX_SCALE = 5.0'));
      expect(htmlContent, contains('INITIAL_SCALE = 1.0'));
      expect(htmlContent, contains('INITIAL_CENTER_X = 1040'));
      expect(htmlContent, contains('INITIAL_CENTER_Y = 618'));
    });

    test('탭 감지 반경이 설정되어 있다', () {
      expect(htmlContent, contains('TAP_RADIUS = 12'));
    });

    test('DOM API를 사용하여 툴팁을 생성한다 (XSS 방지)', () {
      // innerHTML 대신 textContent/createElement 사용 확인
      expect(htmlContent, contains('document.createElement'));
      expect(htmlContent, contains('textContent'));
    });

    test('툴팁 내 innerHTML을 사용하지 않는다 (XSS 방지)', () {
      // showTooltip 함수 내에서 innerHTML 사용 금지
      // (clearMarkers 등에서 innerHTML = "" 은 허용)
      final showTooltipStart = htmlContent.indexOf('window.showTooltip');
      final showTooltipEnd = htmlContent.indexOf('window.hideTooltip');
      if (showTooltipStart > 0 && showTooltipEnd > showTooltipStart) {
        final showTooltipBody =
            htmlContent.substring(showTooltipStart, showTooltipEnd);
        expect(showTooltipBody, isNot(contains('innerHTML')));
      }
    });

    test('CSS 트랜지션 셀렉터에 rect 요소가 포함되어 있다', () {
      // rect:not(#route-overlay-bg) 가 transition 셀렉터에 포함되어야
      // 환승역 연결선도 노선 강조 시 부드러운 opacity 전환이 적용된다
      expect(
        htmlContent,
        contains('rect:not(#route-overlay-bg)'),
      );
    });

    test('highlightLines 함수에 rect 흐림 처리 로직이 포함되어 있다', () {
      // highlightLines 함수 본문 추출
      final hlStart = htmlContent.indexOf('window.highlightLines');
      final hlEnd = htmlContent.indexOf('window.clearLineHighlight');
      expect(hlStart, greaterThan(0), reason: 'highlightLines 함수가 존재해야 한다');
      expect(hlEnd, greaterThan(hlStart),
          reason: 'clearLineHighlight가 highlightLines 뒤에 존재해야 한다');

      final hlBody = htmlContent.substring(hlStart, hlEnd);

      // rect 요소를 querySelectorAll로 조회하고 dimmed 클래스로 처리하는 로직 확인
      expect(hlBody, contains("querySelectorAll('rect:not(#route-overlay-bg)')"));
      expect(hlBody, contains("classList.add('dimmed')"));
      expect(hlBody, contains("classList.remove('dimmed')"));
    });

    test('HTML 파일 크기가 합리적이다 (100KB~500KB)', () {
      final size = htmlContent.length;
      expect(size, greaterThan(100 * 1024)); // 최소 100KB
      expect(size, lessThan(500 * 1024)); // 최대 500KB
    });

    test('텍스트 레이어가 map-container 밖에 존재한다', () {
      expect(htmlContent, contains('id="text-layer"'));

      // text-layer는 map-container 닫힘 태그 이후에 위치해야 한다
      final mapContainerCloseIdx =
          htmlContent.indexOf('</div>', htmlContent.indexOf('id="tap-layer"'));
      final textLayerIdx = htmlContent.indexOf('id="text-layer"');
      expect(textLayerIdx, greaterThan(mapContainerCloseIdx),
          reason: 'text-layer는 map-container 밖에 위치해야 한다');
    });

    test('text 요소가 text-layer에 분리되어 있다', () {
      // text-layer 내에 data-station 텍스트가 있어야 한다
      final textLayerStart = htmlContent.indexOf('id="text-layer"');
      final textLayerEnd = htmlContent.indexOf('</svg>', textLayerStart);
      final textLayerBody =
          htmlContent.substring(textLayerStart, textLayerEnd);
      expect(textLayerBody, contains('data-station'));

      // 원본 SVG(map-container 내)에는 text 요소가 없어야 한다
      final mapContainerStart = htmlContent.indexOf('id="map-container"');
      final mapContainerEnd =
          htmlContent.indexOf('</div>', htmlContent.indexOf('id="tap-layer"'));
      final mapBody =
          htmlContent.substring(mapContainerStart, mapContainerEnd);
      expect(mapBody, isNot(contains('<text ')));
    });

    test('텍스트 레이어에 pointer-events:none이 설정되어 있다', () {
      expect(htmlContent, contains('#text-layer'));
      expect(htmlContent, contains('pointer-events: none'));
    });

    test('applyTransform에서 텍스트 레이어 viewBox를 동기화한다', () {
      final applyStart = htmlContent.indexOf('function applyTransform()');
      final applyEnd =
          htmlContent.indexOf('function setInitialView()', applyStart);
      final applyBody = htmlContent.substring(applyStart, applyEnd);

      expect(applyBody, contains("textLayer.setAttribute('viewBox'"));
      expect(applyBody, contains('textLayer.style.fontSize'));
      expect(applyBody, contains("'--stroke-w'"));
    });

    test('텍스트 레이어 CSS에 font-size inherit !important가 설정되어 있다', () {
      expect(htmlContent, contains('font-size: inherit !important'));
    });
  });
}
