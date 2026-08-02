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

    test('남은시간 계산은 경과시간에 0 하한을 둔다 (미래 recptnDt 방어)', () {
      // 회귀 가드: 일부 노선(신분당선 등)은 recptnDt 가 실제보다 수 분 앞선다.
      // 경과가 음수로 들어가면 남은시간이 부풀어, arrivalSeconds=0("그 역에 있음")
      // 열차가 도착역에 붙박이로 선 채 "N초 후 도착" 말풍선을 달게 된다.
      final fnStart = htmlContent.indexOf('function remainingFromReceivedAt');
      expect(fnStart, greaterThan(0), reason: '남은시간 헬퍼가 존재해야 한다');
      final fnBody = htmlContent.substring(fnStart, fnStart + 300);
      expect(fnBody, contains('Math.max(0, (nowMs - receivedAtMs) / 1000)'));

      // 카운트다운·정렬·위치 기준쌍 등 남은시간을 쓰는 모든 경로가 이 헬퍼를
      // 거쳐야 한다. (직접 뺄셈이 남아 있으면 그 경로만 다시 부풀어 오른다.)
      expect(htmlContent, isNot(contains('(Date.now() - receivedAt) / 1000')));
      expect(
        htmlContent,
        isNot(contains('(nowMs - existing.baseReceivedAt) / 1000')),
      );
      expect(
        htmlContent,
        isNot(contains('(nowMs - st.baseReceivedAt) / 1000')),
      );
      expect(
        htmlContent,
        isNot(contains('(_nowSetup - trainState.posBaseReceivedAt) / 1000')),
      );
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

    test('중간 종착(isGhost) 열차는 흐린 투명도로 그려진다', () {
      // 유령 투명도는 inline opacity 속성이어야 한다 — CSS 클래스로 처리하면
      // 도착 이펙트의 inline opacity 를 CSS 가 이겨 페이드아웃이 먹지 않는다.
      expect(htmlContent, contains('var GHOST_OPACITY'));
      expect(htmlContent, contains('train.isGhost ? GHOST_OPACITY : 1'));
      expect(htmlContent, isNot(contains('.train-ghost')));

      // 신규 생성 경로: createTrainIcon 이 기본 투명도를 세팅한다.
      expect(htmlContent,
          contains("g.setAttribute('opacity', String(trainBaseOpacity(train)))"));

      // 갱신 경로: refresh 로 행선지가 바뀌면 유령 여부도 뒤집히므로
      // showTrains 의 기존 열차 분기 양쪽에서 재적용해야 한다.
      final showStart = htmlContent.indexOf('window.showTrains');
      final showEnd = htmlContent.indexOf('window.clearTrains');
      final showBody = htmlContent.substring(showStart, showEnd);
      expect(
        'applyTrainGhostState(existing, t)'.allMatches(showBody).length,
        2,
        reason: '도착 임박 조기 continue 분기와 일반 갱신 분기 모두에서 재적용해야 한다',
      );

      // 도착 페이드아웃은 유령의 흐린 투명도에서 시작해야 한다(곱셈).
      expect(htmlContent, contains('var opacity = (1 - eased) * base;'));
    });

    // ── 원칙 1 회귀 가드 (CLAUDE.md 최상위 정책) ────────────────────────────
    // "열차는 절대 뒤로 가지 않는다" — 숫자(realRemaining)는 API 원본 그대로라
    // 재조회 시 늘어날 수 있고, 보장 대상은 아이콘의 경로상 위치다.
    //
    // 아래는 생성 JS 의 **형태**만 지킨다. 실제 동작 검증은 Dart 미러
    // `test/core/utils/train_forward_guard_test.dart` 가 담당한다.

    test('[원칙 1] 위치 역산 입력은 표시용 숫자와 분리된 기준쌍을 쓴다', () {
      // 표시용은 API 원본(realRemaining), 위치용은 기준쌍(posBase*).
      // 기준쌍은 **API 원본 값이 바뀐 refresh 에서만** 보정한다 — 값이 그대로인데
      // (recptnDt 만 갱신) 보정하면 남은시간이 매 cycle 원복해 열차가 정지한다.
      expect(
        htmlContent,
        contains("if (trainState.posBaseArrival == null\n"
            "        || trainState.lastRawArrival !== baseArrival) {"),
      );
      expect(htmlContent, contains('trainState.lastRawArrival = baseArrival;'));
      expect(htmlContent, contains('trainState.posBaseArrival = baseArrival;'));
      expect(htmlContent, contains('trainState.posBaseReceivedAt = receivedAt;'));

      // 매 frame 위치 입력은 반드시 기준쌍에서 나와야 한다.
      expect(
        htmlContent,
        contains('var res = estimateTrainPosition(posRemaining, segDurations);'),
      );
      // 말풍선은 여전히 API 원본 기반.
      expect(htmlContent, contains('formatArrivalBubbleText(realRemaining)'));

      // 끝점이 바뀌면 기준쌍·직전 원본값이 함께 리셋되어야 하고, 그 리셋이
      // 기준쌍 선택보다 먼저 와야 한다(순서가 바뀌면 posBase 가 null 인 채
      // step 이 돌거나, stale 판정이 이전 경로의 값을 본다).
      final resetIdx = htmlContent.indexOf('trainState.posBaseArrival = null;');
      final selectIdx =
          htmlContent.indexOf('trainState.posBaseArrival = baseArrival;');
      expect(resetIdx, greaterThan(0));
      expect(selectIdx, greaterThan(resetIdx));
      expect(htmlContent, contains('trainState.lastRawArrival = null;'));
    });

    test('[원칙 1] rAF 를 타지 않는 분기가 열차를 뒤로 보내지 않는다', () {
      final fnStart = htmlContent.indexOf('function startTrainAnimation');
      final fnEnd = htmlContent.indexOf('function playArrivalEffect');
      expect(fnStart, greaterThan(0));
      final body = htmlContent.substring(fnStart, fnEnd);

      // (a) segDurations 불일치 분기: path[0](경로 맨 뒤)로 순간이동 금지.
      expect(
        body,
        isNot(contains("// 데이터 불일치 — path[0] 에 고정")),
        reason: 'path[0] 고정은 경로 뒤쪽으로의 후퇴다',
      );
      // 단일 점 분기 1곳에서만 path[0] 으로 이동해야 한다(그건 목표역 = 최전진).
      expect(
        "'translate(' + path[0].x + ',' + path[0].y + ')'".allMatches(body).length,
        1,
      );

      // (b) 단일 점 분기: rAF 를 타지 않으므로 전진 상태를 직접 동기화하되,
      //     **실제 도착일 때만** 최전진으로 고정한다. 양수에도 고정하면 '진입'
      //     오보고 한 번으로 열차가 목표역에 영구 고정된다(끝점이 같아
      //     pathEndKey 리셋도 안 탄다).
      expect(body,
          contains('var singlePointArrived = (trainData.arrivalSeconds || 0) <= 0;'));
      expect(body, contains('if (singlePointArrived) {'));
      expect(body, contains('trainState.currentPos = { x: path[0].x, y: path[0].y };'));
      expect(body, contains('trainState.minDistToEnd = 0;'));
      // posBase 쌍과 lastRawArrival 은 같은 값(0)에서 유도돼야 한다.
      expect(body, contains('trainState.posBaseArrival = 0;'));
      expect(body, contains('trainState.lastRawArrival = 0;'));
      expect(body,
          isNot(contains('trainState.lastRawArrival = trainData.arrivalSeconds')));

      // 좌표 이동·도착 이펙트 모두 도착 판정 안에서만 일어나야 한다.
      final arrivedIdx = body.indexOf('if (singlePointArrived) {');
      final moveIdx =
          body.indexOf("'translate(' + path[0].x + ',' + path[0].y + ')'");
      expect(moveIdx, greaterThan(arrivedIdx));
    });

    test('[원칙 1] 단조 전진 가드가 존재한다 (경로 끝까지 남은 거리 기준)', () {
      // 경로 앞부분은 refresh 마다 늘고 줄지만 끝점(목표역)은 고정이므로,
      // refresh 간 비교 가능한 전진 척도는 "끝에서부터 잰 거리" 뿐이다.
      expect(htmlContent, contains('var pathTotalLen = cumLen[cumLen.length - 1];'));
      expect(htmlContent, contains('function pointAtLength(len)'));
      expect(htmlContent, contains('var distToEnd = pathTotalLen - targetLen;'));

      // 뒤로 가는 target 은 폐기하고 최전진 지점 유지, 전진했을 때만 기억 갱신.
      expect(
        htmlContent,
        contains('if (trainState.minDistToEnd != null && '
            'distToEnd > trainState.minDistToEnd) {'),
      );
      expect(
        htmlContent,
        contains('target = pointAtLength(pathTotalLen - trainState.minDistToEnd);'),
      );
      expect(htmlContent, contains('trainState.minDistToEnd = distToEnd;'));

      // 경로 끝점이 바뀌면(= 다른 경로) 전진 기억을 리셋해야 한다.
      expect(htmlContent, contains('if (trainState.pathEndKey !== pathEndKey) {'));
      expect(htmlContent, contains('trainState.minDistToEnd = null;'));
    });

    test('[원칙 1] 가드는 3-way 클램프 뒤, catch-up 앞에 놓인다', () {
      // 적용 순서: 원칙 2(역산) → 원칙 3(클램프) → 원칙 1(가드) → 원칙 4(catch-up).
      // 순서가 어긋나면 원칙끼리 서로를 무력화한다.
      final clampIdx = htmlContent.indexOf('var res = estimateTrainPosition(');
      final guardIdx = htmlContent.indexOf('var distToEnd = pathTotalLen - targetLen;');
      final catchUpIdx = htmlContent.indexOf('if (!trainState.currentPos) {');

      expect(clampIdx, greaterThan(0));
      expect(guardIdx, greaterThan(clampIdx));
      expect(catchUpIdx, greaterThan(guardIdx));

      // 3-way 클램프 분기가 가드보다 먼저 target/targetLen 을 확정해야 한다.
      final clampBody = htmlContent.substring(clampIdx, guardIdx);
      expect(clampBody, contains('res.segmentIndex >= nextIdx'));
      expect(clampBody, contains('targetLen = cumLen[nextIdx];'));
    });

    test('[원칙 1] 옛 단조 감소 clamp·슬롯 메모리가 재도입되지 않았다', () {
      // 숫자를 붙잡아 위치를 간접 보장하던 구조는 2026-07-31 제거됐다.
      // 다시 들어오면 말풍선이 API 와 어긋난 값을 표시하게 된다.
      expect(htmlContent, isNot(contains('trainSlotMemory')));
      expect(htmlContent, isNot(contains('makeSlotKey')));
      expect(htmlContent, isNot(contains('rememberSlot')));
      expect(htmlContent, isNot(contains('slotOccupancy')));
      expect(htmlContent, isNot(contains('prevReal')));

      // 말풍선은 API 원본 기반 realRemaining 을 그대로 포맷해야 한다.
      expect(
        htmlContent,
        contains('formatArrivalBubbleText(realRemaining)'),
      );
    });
  });
}
