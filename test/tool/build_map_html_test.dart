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

    test('경유역 액션이 툴팁과 마커에 배선되어 있다', () {
      // 툴팁 "경유" 버튼 → Flutter 로 addWaypoint 액션 전송
      // (svg_web_view.dart 의 _onJsMessage case 'addWaypoint' 와 짝)
      expect(htmlContent, contains('window._addWaypoint'));
      expect(htmlContent, contains("action: 'addWaypoint'"));
      expect(htmlContent, contains("'경유'"));
      // 경유 마커 색: 출발(파랑)/도착(빨강)이 아닌 3순위 분기(주황).
      // search_bar_widget.dart 의 waypointColor(0xFFFF9800) 와 같아야 한다.
      expect(htmlContent, contains('#FF9800'));
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

    test(
        'applyTransform에서 텍스트/열차 레이어를 CSS transform(컴포지터 전용)으로 동기화한다',
        () {
      // [래스터 기아 수정] text-layer/train-layer는 더 이상 매 프레임 viewBox를
      // 재계산하지 않는다 — viewBox 변경은 SVG 뷰포트 좌표 매핑을 바꿔 내부 콘텐츠
      // (역명 라벨 수백 개) 전체를 메인스레드에서 강제 리페인트시키고, 팬 제스처
      // 동안 이 리페인트가 map-container의 신규 타일 래스터를 기아시켜 안드로이드
      // 에서 노선이 순간 소실되는 점멸을 유발했다. 이제 map-container와 동일한
      // CSS transform matrix를 text-layer/train-layer에도 그대로 적용해 팬 중
      // 재페인트 자체를 제거한다(회귀 가드).
      final applyStart = htmlContent.indexOf('function applyTransform()');
      final applyEnd =
          htmlContent.indexOf('function setInitialView()', applyStart);
      final applyBody = htmlContent.substring(applyStart, applyEnd);

      expect(applyBody, isNot(contains("textLayer.setAttribute('viewBox'")));
      expect(applyBody, isNot(contains("trainLayer.setAttribute('viewBox'")));
      expect(applyBody, contains('textLayer.style.transform = matrixStr'));
      expect(applyBody, contains('trainLayer.style.transform = matrixStr'));
      expect(applyBody, contains('textLayer.style.fontSize'));
      expect(applyBody, contains("'--stroke-w'"));
      // 팬 전용 프레임(scale 불변)에서는 폰트/스트로크 보정을 건너뛰어야 한다.
      expect(applyBody, contains('scale !== lastFontScale'));
    });

    test('text-layer/train-layer가 map-container와 동일한 고정 viewBox(1:1)를 갖는다',
        () {
      // viewBox는 최초 렌더링 시 "0 0 2416 1560"으로 고정되고 이후 JS에서 다시
      // 바뀌지 않는다 (팬/줌은 오직 CSS transform으로만 표현).
      // 생성기 템플릿의 줄바꿈/공백 변화에 깨지지 않도록 개행 포함 원문 대신
      // 정규식(공백류는 \s+로 흡수)으로 매칭한다.
      final textLayerTagPattern = RegExp(
        r'id="text-layer"\s+xmlns="http://www\.w3\.org/2000/svg"\s+'
        r'viewBox="0 0 2416 1560"\s+width="2416"\s+height="1560"',
      );
      final trainLayerTagPattern = RegExp(
        r'id="train-layer"\s+xmlns="http://www\.w3\.org/2000/svg"\s+'
        r'viewBox="0 0 2416 1560"\s+width="2416"\s+height="1560"',
      );
      expect(textLayerTagPattern.hasMatch(htmlContent), isTrue,
          reason: 'text-layer의 viewBox/width/height 고정 마크업을 찾지 못했다');
      expect(trainLayerTagPattern.hasMatch(htmlContent), isTrue,
          reason: 'train-layer의 viewBox/width/height 고정 마크업을 찾지 못했다');
    });

    test('텍스트 폰트/스트로크 보정 수식이 scale 이중 나눗셈 없이 TEXT_BASE/cs 형태를 유지한다', () {
      // [회귀 가드, 2026-07-29] CSS transform 전환 당시 "text-layer 전체가
      // scale배로 확대되니 로컬 값에서 미리 나눠 상쇄해야 한다"고 잘못 판단해
      // `/ scale`을 추가로 나눈 적이 있다. 그러나 구 viewBox 구현도 이미 동일한
      // scale 배율로 확대되고 있었으므로(뷰포트:viewBox 비율 = scale) 이는 이중
      // 보정이었다 — 브라우저 A/B 실측으로 scale=0.5에서 라벨 2배, scale=2에서
      // 라벨 1/2배가 되는 회귀가 확정됐다. `contains('textLayer.style.fontSize')`
      // 같은 문자열 존재 검사만으로는 이 회귀를 잡지 못하므로, 대입 우변 수식을
      // 정규식으로 추출해 정확한 값 형태(scale 없음)를 고정한다.
      final applyStart = htmlContent.indexOf('function applyTransform()');
      final applyEnd =
          htmlContent.indexOf('function setInitialView()', applyStart);
      final applyBody = htmlContent.substring(applyStart, applyEnd);

      final fontSizeMatch =
          RegExp(r"textLayer\.style\.fontSize\s*=\s*\(([^)]+)\)\s*\+\s*'px'")
              .firstMatch(applyBody);
      expect(fontSizeMatch, isNotNull,
          reason: 'textLayer.style.fontSize 대입식을 찾지 못했다');
      expect(
        fontSizeMatch!.group(1)!.replaceAll(RegExp(r'\s+'), ''),
        equals('TEXT_BASE_FONT_SIZE/cs'),
        reason: '/scale 이 붙으면 CSS transform의 scale 배율과 이중으로 곱해져 '
            '화면 폰트 크기가 scale=0.5에서 2배, scale=2에서 1/2배로 어긋난다',
      );

      final strokeMatch =
          RegExp(r"'--stroke-w',\s*\(([^)]+)\)\s*\+\s*'px'")
              .firstMatch(applyBody);
      expect(strokeMatch, isNotNull, reason: '--stroke-w 대입식을 찾지 못했다');
      expect(
        strokeMatch!.group(1)!.replaceAll(RegExp(r'\s+'), ''),
        equals('TEXT_BASE_STROKE_W/cs'),
        reason: '/scale 이 붙으면 화면 stroke 두께도 동일하게 이중 보정된다',
      );

      // 설계 불변식 검증: 최대 줌아웃(MIN_SCALE)에서 화면 폰트 =
      // TEXT_BASE_FONT_SIZE * MIN_SCALE / TEXT_COMP_FLOOR = 12 * 0.5 / (2/3) = 9px
      // (소스 상단 주석에 문서화된 값). 상수들이 실제로 이 값을 만들어내는지
      // 재계산해 문서-코드 드리프트까지 함께 감지한다.
      final baseFontMatch = RegExp(r'TEXT_BASE_FONT_SIZE\s*=\s*([\d.]+)')
          .firstMatch(htmlContent);
      final minScaleMatch =
          RegExp(r'MIN_SCALE\s*=\s*([\d.]+)').firstMatch(htmlContent);
      final compFloorMatch =
          RegExp(r'TEXT_COMP_FLOOR\s*=\s*(\d+)\s*/\s*(\d+)')
              .firstMatch(htmlContent);
      expect(baseFontMatch, isNotNull, reason: 'TEXT_BASE_FONT_SIZE 상수를 찾지 못했다');
      expect(minScaleMatch, isNotNull, reason: 'MIN_SCALE 상수를 찾지 못했다');
      expect(compFloorMatch, isNotNull, reason: 'TEXT_COMP_FLOOR 상수를 찾지 못했다');

      final baseFont = double.parse(baseFontMatch!.group(1)!);
      final minScale = double.parse(minScaleMatch!.group(1)!);
      final compFloor = double.parse(compFloorMatch!.group(1)!) /
          double.parse(compFloorMatch.group(2)!);

      final screenFontAtMinScale = baseFont * minScale / compFloor;
      expect(
        screenFontAtMinScale,
        closeTo(9.0, 0.001),
        reason: '최대 줌아웃 화면 폰트 불변식(TEXT_BASE_FONT_SIZE*MIN_SCALE/TEXT_COMP_FLOOR'
            ' = 9px)이 깨졌다',
      );
    });

    test('text-layer/train-layer CSS가 overflow: visible로 캔버스 밖 클리핑을 막는다', () {
      // [회귀 가드, 2026-07-29] 두 레이어가 지도 캔버스(2416x1560)로 고정
      // 치수화되면서 UA 기본값(hidden)이 말단역 도착 말풍선·화면 끝 라벨을
      // 실제로 잘라냈다. overflow: visible 이 빠지면(hidden 원복 포함) 같은
      // 클리핑이 재발하므로 각 레이어의 CSS 규칙 블록에서 값을 직접 고정한다.
      for (final layer in ['#text-layer', '#train-layer']) {
        final ruleMatch = RegExp(
          RegExp.escape(layer) + r'\s*\{([^}]*)\}',
        ).firstMatch(htmlContent);
        expect(ruleMatch, isNotNull, reason: '$layer CSS 규칙 블록을 찾지 못했다');
        expect(
          RegExp(r'overflow\s*:\s*visible').hasMatch(ruleMatch!.group(1)!),
          isTrue,
          reason: '$layer 에 overflow: visible 이 없으면 고정 치수(2416x1560) '
              '경계 밖 말풍선·라벨이 잘린다',
        );
      }
    });

    test('텍스트 레이어 CSS에 font-size inherit !important가 설정되어 있다', () {
      expect(htmlContent, contains('font-size: inherit !important'));
    });

    test('highlightLines 흐림 처리가 열차 레이어를 건드리지 않는다', () {
      // 회귀 가드: document 전역 조회는 #train-layer 안의 도착 말풍선 배경(rect)·
      // 급행 배지·디버그 박스까지 .dimmed 처리해, 경로 모드(최단경로↔최소환승)
      // 전환 시 흰색 말풍선 글씨만 남아 남은시간이 안 보이게 된다.
      final hlStart = htmlContent.indexOf('window.highlightLines');
      final hlEnd = htmlContent.indexOf('window.clearLineHighlight');
      expect(hlStart, greaterThan(0));
      expect(hlEnd, greaterThan(hlStart));
      final hlBody = htmlContent.substring(hlStart, hlEnd);

      // 원본 지도(container) / 라벨 레이어(textLayer) 로 스코프가 제한돼야 한다.
      expect(hlBody, contains("container.querySelectorAll('path[data-line]')"));
      expect(hlBody,
          contains("container.querySelectorAll('circle:not([data-overlay])')"));
      expect(
        hlBody,
        contains("container.querySelectorAll('rect:not(#route-overlay-bg)')"),
      );
      expect(hlBody, contains("textLayer.querySelectorAll('text[data-line]')"));

      // 전역 조회가 남아 있으면 열차 요소가 다시 흐려진다.
      expect(hlBody, isNot(contains('document.querySelectorAll')));
    });

    test('showTrains가 경로 스코프 키를 두 번째 인자로 받는다', () {
      // Flutter 가 activeRouteFilter 를 스코프 키로 넘기고, JS 가 이를 열차
      // 상태에 기록해야 경로 변경으로 무효해진 열차를 즉시 제거할 수 있다.
      expect(
        htmlContent,
        contains('window.showTrains = function(trainsJson, routeScopeKey)'),
      );
      expect(htmlContent, contains('scopeKey: scopeKey'));
      expect(htmlContent, contains('existing.scopeKey = scopeKey'));
    });

    test('앞선 열차가 위에 오도록 열차 DOM 순서를 재정렬한다', () {
      // SVG 는 문서 순서대로 페인트 → 마지막 자식이 최상위.
      // 남은시간 내림차순으로 재삽입해야 남은시간이 가장 적은(앞선) 열차가
      // 마지막 = 최상위가 되어 말풍선 겹침에서 가려지지 않는다.
      final fnStart = htmlContent.indexOf('function reorderTrainsByRemaining');
      expect(fnStart, greaterThan(0), reason: '재정렬 함수가 존재해야 한다');
      final fnBody = htmlContent.substring(fnStart, fnStart + 1200);

      expect(fnBody, contains('return b.rem - a.rem'));
      expect(fnBody, contains('liveTrainsGroup.appendChild(items[i].el)'));

      // showTrains 가 신규 추가·제거를 끝낸 뒤 호출해야 한다.
      final showStart = htmlContent.indexOf('window.showTrains');
      final showEnd = htmlContent.indexOf('window.clearTrains');
      final showBody = htmlContent.substring(showStart, showEnd);
      expect(showBody, contains('reorderTrainsByRemaining()'));
      expect(
        showBody.indexOf('reorderTrainsByRemaining()'),
        greaterThan(showBody.indexOf('toRemove.length')),
        reason: '제거 처리 이후에 재정렬해야 한다',
      );
    });

    test('경로 스코프가 바뀐 열차는 grace 없이 즉시 제거된다', () {
      // 회귀 가드: 도착역만 바꿔 경로 노선이 달라졌을 때 이전 노선 열차가
      // jitter grace(MAX_MISS_CYCLES)로 최대 2분간 지도에 남던 문제.
      final showStart = htmlContent.indexOf('window.showTrains');
      final showEnd = htmlContent.indexOf('window.clearTrains');
      expect(showStart, greaterThan(0));
      expect(showEnd, greaterThan(showStart));
      final body = htmlContent.substring(showStart, showEnd);

      // 스코프 불일치 분기가 jitter grace(missedCycles) 판정보다 앞에 있어야 한다.
      final scopeGuardIdx =
          body.indexOf("trainState.scopeKey !== scopeKey");
      final graceIdx = body.indexOf('if (eta > JITTER_GRACE_S)');
      expect(scopeGuardIdx, greaterThan(0),
          reason: '스코프 불일치 즉시 제거 분기가 있어야 한다');
      expect(scopeGuardIdx, lessThan(graceIdx),
          reason: '스코프 판정이 jitter grace 판정보다 먼저 실행돼야 한다');
      expect(body, contains('removeTrainSilently(trainState, id)'));

      // 도착 이펙트(playArrivalEffect)로 빠지지 않아야 한다 — 도착이 아니므로
      // 스낵바가 뜨면 오탐. 즉시 제거 분기는 continue 로 끊는다.
      final afterGuard = body.substring(scopeGuardIdx);
      final continueIdx = afterGuard.indexOf('continue;');
      final arrivalIdx = afterGuard.indexOf('playArrivalEffect');
      expect(continueIdx, greaterThan(0));
      expect(continueIdx, lessThan(arrivalIdx));
    });
  });
}
