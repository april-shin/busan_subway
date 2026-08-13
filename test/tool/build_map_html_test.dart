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

    test(
        '[래스터 기아 v5] text[data-line] 는 opacity transition 셀렉터에서 제외된다',
        () {
      // [회귀 가드, 2026-08-13] CDP LayerTree+Tracing 실측(chrome://inspect
      // 대체 — WebView 원격 디버깅 소켓에 직접 CDP로 접속)으로 확인: 팬 중
      // #text-layer(SVG, 자식 655개)/#train-layer 의 .style.transform 쓰기가
      // 매 프레임 InvalidateLayout 을 유발해 SvgTextLayoutAlgorithm::Layout 이
      // 10초 팬에 13843회 호출됐다(정상 팬은 0회여야 함). 원인은
      // `text[data-line]` 가 `path[data-line], circle, rect:not(...)` 와
      // 같은 `transition: opacity 0.3s` 셀렉터에 묶여 있던 것 — text 노드가
      // 수백 개(655)라 이 transition 대상 스타일 재계산이 전체 라벨 레이아웃을
      // 매 프레임 강제했다. text[data-line] 를 이 셀렉터에서 빼면 동일 조건
      // 재측정에서 LayoutInvalidationTracking 67232→5304(-92%),
      // SvgTextLayoutAlgorithm::Layout 13843→5278(-62%) 로 감소한다
      // (_workspace/10_map-math-engineer_pan-flicker-report.md §13 참조).
      // ⚠ 잔여 원인 있음(같은 보고서 §13) — 이 테스트는 재발 방지용이지
      // "점멸 완전 해결" 을 의미하지 않는다.
      final transitionRuleMatch = RegExp(
              r'([a-zA-Z0-9_,:#()\[\]="\-\s]*?)\{\s*transition:\s*opacity 0\.3s;')
          .firstMatch(htmlContent);
      expect(transitionRuleMatch, isNotNull,
          reason: 'opacity 0.3s transition 규칙을 찾지 못했다');
      final selector = transitionRuleMatch!.group(1)!;
      expect(selector.contains('text[data-line]'), isFalse,
          reason: 'text[data-line] 가 opacity transition 셀렉터에 재유입되면 '
              '#text-layer 전체 라벨 레이아웃 강제 재계산(v5 점멸)이 재발한다');
      // path/circle/rect 는 여전히 부드러운 dim 전환을 유지해야 한다
      // (라벨만 즉시 전환 — 트레이드오프는 CLAUDE.md/보고서에 명시).
      expect(selector, contains('path[data-line]'));
      expect(selector, contains('circle'));
      expect(selector, contains('rect:not(#route-overlay-bg)'));
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

    test('buildWaypointIndex가 순환선 재방문 역을 인덱스 최소 거리로 짝짓는다', () {
      // 회귀 가드: 2호선 본선 SVG path 는 신도림을 두 번 지난다(순환선 진입점 =
      // 종료점). "가장 가까운 정점 하나"만 고르면 대림↔신도림 구간이 앞쪽 신도림과
      // 짝지어져 slice 가 순환선을 거꾸로 한 바퀴 감싸고, 하이라이트가 2호선
      // 전체에 칠해진다.
      final start = htmlContent.indexOf('function buildWaypointIndex()');
      expect(start, greaterThan(0),
          reason: 'buildWaypointIndex 함수가 존재해야 한다');
      final body = htmlContent.substring(start, start + 3000);

      // 후보를 배열로 수집(동률 정점 모두) 후 인덱스 거리 최소 조합 선택
      expect(body, contains('findNearestIdxs('),
          reason: '단일 최근접 정점이 아니라 동률 후보 배열을 받아야 한다');
      expect(body, contains('Math.abs(fIdxs[fj] - tIdxs[tj])'));
      expect(body, contains('bestSpan'));

      // slice 길이 sanity(직선거리 3배) 가드 — 분기/순환 오매칭 2차 방어선
      expect(body, contains('straightDist * 3'));

      // 동률 제한 없이 tolerance 내 전 정점을 후보로 삼으면 곡선 중간점이
      // 사라지므로(약 50개 구간) TIE_EPS 제한이 있어야 한다
      expect(htmlContent, contains('TIE_EPS'));
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
      // [L-1 정리, 2026-08 리뷰] applyTransform 자체의 본문만 검사하려면
      // 창을 다음 함수(updateTextCompensation)가 시작하기 전까지로 좁혀야
      // 한다. 예전엔 setInitialView() 까지를 창으로 잡아 그 사이에 낀
      // updateTextCompensation() 전체(폰트/스트로크 보정 로직)가 함께
      // 매칭되어, 테스트명("applyTransform 에서…")과 실제 매칭 위치가
      // 어긋났다 — 아래 폰트/스트로크 관련 단언은 별도 창(applyEnd 이후,
      // updateTextCompensationBody)으로 분리한다.
      final applyStart = htmlContent.indexOf('function applyTransform()');
      final applyEnd =
          htmlContent.indexOf('function updateTextCompensation()', applyStart);
      final applyBody = htmlContent.substring(applyStart, applyEnd);

      expect(applyBody, isNot(contains("textLayer.setAttribute('viewBox'")));
      expect(applyBody, isNot(contains("trainLayer.setAttribute('viewBox'")));
      expect(applyBody, contains('textLayer.style.transform = matrixStr'));
      expect(applyBody, contains('trainLayer.style.transform = matrixStr'));
      // [2026-08 핀치 점멸 수정 회귀 가드] 2-포인터 핀치 진행 중에는 매 프레임
      // scale 이 바뀌므로, 팬 전용 프레임만 스킵하는 캐시(updateTextCompensation
      // 내부)가 무력화된다. applyTransform 은 핀치 중엔 폰트 보정 호출 자체를
      // 건너뛰고, 핀치 종료 시(pointerup/pointercancel) 별도로 flush 해야
      // 한다 — 그렇지 않으면 핀치 내내 text-layer 전체가 매 프레임(최대
      // 60fps) 리페인트된다.
      expect(applyBody, contains('getPointerCount() !== 2'));
      expect(applyBody, contains('updateTextCompensation();'));

      // 폰트/스트로크 보정 로직 자체는 별도 함수로 분리되어 있어야
      // pointerup/pointercancel 에서도 재사용할 수 있다. 이 함수 자신의
      // 본문(updateTextCompensation ~ setInitialView 사이)에서 검사한다.
      final compEnd =
          htmlContent.indexOf('function setInitialView()', applyEnd);
      final compBody = htmlContent.substring(applyEnd, compEnd);
      expect(compBody, contains('textLayer.style.fontSize'));
      // [래스터 기아 실험 A, 2026-08-13] stroke 보정이 `--stroke-w` 커스텀
      // 프로퍼티에서 네이티브 `style.strokeWidth` 로 바뀌었다(CSS 쪽은
      // `stroke-width: inherit`). 커스텀 프로퍼티는 Blink 의 독립 상속
      // 프로퍼티 최적화 경로를 타지 못해, 조상 스타일이 매 프레임 바뀌는 팬
      // 중에 라벨 655개가 스타일 재계산 후보로 남는다는 가설에 따른 것이다.
      // 검사 대상은 "보정이 이 함수 안에서 일어난다"는 사실이므로 형태만 교체한다.
      expect(compBody, contains('textLayer.style.strokeWidth'));
      // 팬 전용 프레임(scale 불변)에서는 폰트/스트로크 보정을 건너뛰어야 한다.
      // [P2, 2026-08 리뷰] no-op 판정 키는 scale 이 아니라 실제로 화면에
      // 쓰일 보정계수(cs)다 — scale>1(확대) 구간·MIN_SCALE 축소 구간처럼
      // scale 은 계속 바뀌어도 cs 는 고정되는 구간에서 동일 값 재기록을
      // 추가로 막는다(scale 키였다면 이 구간에서 매번 다시 썼을 것).
      expect(compBody, contains('cs === lastCs'));
      // pointerup/pointercancel 모두 핀치 종료 시 보정을 flush 해야 한다
      // (그렇지 않으면 핀치가 포인터 0개로 끝났을 때 아무도 applyTransform 을
      // 다시 부르지 않아 최종 폰트 크기가 영영 반영되지 않는다).
      final pointerUpStart = htmlContent.indexOf("addEventListener('pointerup'");
      final pointerCancelStart =
          htmlContent.indexOf("addEventListener('pointercancel'");
      expect(pointerUpStart, greaterThan(0));
      expect(pointerCancelStart, greaterThan(pointerUpStart));
      final pointerUpBody =
          htmlContent.substring(pointerUpStart, pointerCancelStart);
      final pointerCancelEnd = htmlContent.indexOf(
          "addEventListener('wheel'", pointerCancelStart);
      final pointerCancelBody =
          htmlContent.substring(pointerCancelStart, pointerCancelEnd);
      expect(pointerUpBody, contains('updateTextCompensation()'));
      expect(pointerCancelBody, contains('updateTextCompensation()'));
    });

    test('[래스터 기아 v3] 열차 아이콘은 개별 컴포지터 레이어 + style.transform으로만 이동한다',
        () {
      // [회귀 가드, 2026-08-13] 열차 위치를 SVG transform attribute 로 쓰면
      // 매 rAF 마다 #train-layer 레이어 내용이 무효화되어, 팬(레이어 이동)과
      // 재래스터가 같은 프레임에 겹친다. 최대 줌아웃(노출 면적 최대)에서 이
      // 경쟁이 래스터 예산을 초과해 라벨/말풍선/툴바가 순간 소실됐다(v3 점멸).
      // 각 열차 <g> 를 will-change 로 개별 컴포지터 레이어로 승격하고 위치는
      // CSS style.transform 으로만 반영해야 내용 재래스터 없이 이동한다.
      expect(htmlContent, contains('#live-trains > g {'));
      expect(htmlContent, contains('will-change: transform'));
      // step() hot path 는 style.transform 을 쓴다.
      expect(htmlContent, contains('trainState.element.style.transform ='));
      // 열차/마커 등 어디서든 attribute transform 쓰기가 재유입되면 안 된다
      // (getAttribute 읽기 짝도 함께 제거된 상태를 유지해야 혼재 버그가 없다).
      expect(htmlContent.contains(".setAttribute('transform'"), isFalse,
          reason: "SVG transform attribute 쓰기 재유입 — v3 점멸이 재발한다");
      expect(htmlContent.contains(".getAttribute('transform'"), isFalse,
          reason: 'attribute 읽기 잔존 — style.transform 과 혼재하면 낡은 위치를 읽는다');
    });

    test(
        '[래스터 기아 v4] 경로 툴바는 top/left 가 아니라 style.transform 으로 팬을 따라간다',
        () {
      // [회귀 가드, 2026-08-13] v3(열차 아이콘 will-change+style.transform)
      // 적용 후 교정된 측정 하네스(고정 기준선+plateau 검출)로 재분석해도
      // 최대 줌아웃+팬+실시간 열차 시나리오에서 점멸이 그대로 재현됐다
      // (_workspace/10_map-math-engineer_pan-flicker-report.md §12).
      // 점멸 순간 SVG 밖 HTML 오버레이(경로 툴바)까지 함께 사라지는 관측은
      // "#train-layer 내부 attribute 쓰기"만으로는 설명되지 않는다.
      //
      // 재조사 결과 updateRouteToolbarPosition()/드래그 핸들러가 팬 중 매
      // rAF 마다 routeToolbar.style.left/top(레이아웃 유발)을 썼다 — 같은
      // 문서(WebView 렌더러)에서 팬 중 유일한 non-transform 프레임별 DOM
      // 쓰기였다. #map-container/#text-layer/#train-layer 와 동일하게
      // transform(translate)로 바꿔 컴포지터 전용 쓰기로 통일한다.
      expect(htmlContent, contains('.route-toolbar {'));
      final toolbarRuleMatch =
          RegExp(r'\.route-toolbar\s*\{([^}]*)\}').firstMatch(htmlContent);
      expect(toolbarRuleMatch, isNotNull, reason: '.route-toolbar CSS 규칙을 찾지 못했다');
      final toolbarRule = toolbarRuleMatch!.group(1)!;
      expect(RegExp(r'top\s*:\s*0').hasMatch(toolbarRule), isTrue,
          reason: '툴바는 top:0 고정 원점 위에서 transform 으로만 이동해야 한다');
      expect(RegExp(r'left\s*:\s*0').hasMatch(toolbarRule), isTrue,
          reason: '툴바는 left:0 고정 원점 위에서 transform 으로만 이동해야 한다');
      expect(RegExp(r'will-change\s*:\s*transform').hasMatch(toolbarRule),
          isTrue,
          reason: '툴바를 독립 컴포지터 레이어로 승격해야 한다');

      expect(htmlContent,
          contains("routeToolbar.style.transform = 'translate(' + left"),
          reason: 'updateRouteToolbarPosition 이 transform 으로 위치를 반영해야 한다');
      expect(
          htmlContent,
          contains(
              "routeToolbar.style.transform =\n          'translate(' + newLeft"),
          reason: '툴바 드래그(onDragMove)도 transform 으로 위치를 반영해야 한다');

      // 레이아웃을 유발하는 left/top 직접 쓰기가 재유입되면 v4 점멸이 재발한다.
      expect(htmlContent.contains('routeToolbar.style.left ='), isFalse,
          reason: 'routeToolbar.style.left 직접 쓰기 재유입 — v4 점멸이 재발한다');
      expect(htmlContent.contains('routeToolbar.style.top ='), isFalse,
          reason: 'routeToolbar.style.top 직접 쓰기 재유입 — v4 점멸이 재발한다');
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

      // [래스터 기아 실험 A, 2026-08-13] `setProperty('--stroke-w', …)` 에서
      // `style.strokeWidth = …` 로 바뀌었다. 이 테스트가 지키려는 것은 대입
      // **경로**가 아니라 우변 수식에 `/scale` 이 붙지 않는다는 불변식이므로,
      // 패턴만 새 형태로 옮기고 단언은 그대로 둔다.
      final strokeMatch = RegExp(
        r"textLayer\.style\.strokeWidth\s*=\s*\(([^)]+)\)\s*\+\s*'px'",
      ).firstMatch(applyBody);
      expect(strokeMatch, isNotNull,
          reason: 'textLayer.style.strokeWidth 대입식을 찾지 못했다');
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

    test('[원칙 1-a] 표시용 기준쌍은 API 원본이 바뀐 refresh 에서만 채택한다', () {
      // 회귀 가드: 같은 barvlDt 를 recptnDt 만 바꿔 반복 보고하는 구간(2호선
      // 사당 정차 등)에서 recptnDt 를 매번 채택하면 말풍선 카운트다운이
      // "감소 → 원위치" 톱니파를 그린다.
      final fnStart = htmlContent.indexOf('function adoptDisplayBase');
      expect(fnStart, greaterThan(0), reason: '표시용 기준쌍 헬퍼가 존재해야 한다');
      final fnBody = htmlContent.substring(fnStart, fnStart + 400);
      expect(fnBody, contains('trainState.lastDisplayRawArrival !== raw'));

      // showTrains 의 기존 열차 갱신 경로가 헬퍼를 우회해 직접 대입하면
      // 그 경로만 다시 톱니파가 된다.
      expect(
        htmlContent,
        isNot(contains('existing.baseReceivedAt = t.receivedAtEpochMs')),
      );

      // step() 의 말풍선 숫자는 trainData 원본이 아니라 기준쌍을 입력으로 쓴다.
      // (공백·줄바꿈 변화에 깨지지 않도록 공백을 정규화해 비교한다.)
      final flat = htmlContent.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        flat,
        contains('remainingFromReceivedAt( '
            'trainState.baseArrival, trainState.baseReceivedAt'),
      );

      // 호출부가 지워지면 기준쌍이 생성 시점에 영구 고정돼 원본이 바뀌어도
      // 갱신되지 않는다. 위 검사들만으로는 그 회귀를 못 잡으므로 호출 횟수를 본다.
      expect(
        'adoptDisplayBase(existing, t, nowMs)'.allMatches(htmlContent).length,
        2,
        reason: 'showTrains 의 두 갱신 경로가 모두 헬퍼를 거쳐야 한다',
      );
    });

    test('[원칙 1-a] 위치 기준쌍은 표시 기준쌍을 그대로 물려받는다', () {
      // 회귀 가드: 위치가 trainData 원본(매 refresh 갱신되는 recptnDt)을 물면
      // 표시 카운트다운보다 뒤처져, 말풍선이 "곧 도착"인데 아이콘은 아직 오는
      // 중인 그림이 된다. 두 도메인이 같은 시각에 0 이 되어야 한다.
      expect(
        htmlContent,
        contains('var receivedAt = (trainState.baseReceivedAt != null)'),
      );
      expect(
        htmlContent,
        contains('var baseArrival = (trainState.baseArrival != null)'),
      );
    });

    test('[원칙 1-a] 도착 이펙트는 표시 숫자만으로 발동한다 (게이트 없음)', () {
      // 사용자 요구: 남은시간이 줄어 0 이 되면 열차도 그때 도착해야 한다.
      // API 원본으로 발동을 막는 게이트를 두면 이 동기화가 깨진다.
      expect(
        htmlContent,
        contains(
            'if (realRemaining <= 0 && atFinalLeg && !trainState.catchingUp)'),
      );
      expect(htmlContent, isNot(contains('ARRIVAL_RAW_GATE_SEC')));
      // 위치 일관성 조건: 아이콘이 목표역까지 온 경우에만 도착시킨다.
      // (원칙 3 클램프가 중간역에 붙잡고 있는데 숫자만 0 이 되면 엉뚱한 역에서
      //  사라진다. API 원본 게이트가 아니므로 동기화 요구와 충돌하지 않는다.)
      expect(
        htmlContent,
        contains('var atFinalLeg = (nextIdx === path.length - 1);'),
      );
    });

    test('[원칙 1-a] 유령 도착은 원본값이 바뀌면 복구된다', () {
      // 기준쌍 고정으로 realRemaining 이 0 에 닿으므로, stall 이 잔여초보다 길면
      // 아직 전역에 있는 열차가 도착 처리될 수 있다. `true` 만 박아두면 API 가
      // 계속 보고하는 한 정리 루프(!trainNoSet[id])가 못 지워 영구 소실된다.
      expect(htmlContent, contains('delete arrivedTrains[t.trainNo];'));
      // 옛 무조건 skip 이 남아 있으면 복구 경로가 죽는다.
      expect(htmlContent, isNot(contains('if (arrivedTrains[t.trainNo]) continue;')));

      // 도착 시점의 API 원본으로 정상/유령을 가른다. 임계 이하면 영구 확정.
      final flat = htmlContent.replaceAll(RegExp(r'\s+'), ' ');
      expect(htmlContent, contains('var GHOST_ARRIVAL_MIN_SEC = 30;'));
      expect(
        flat,
        contains('arrivedTrains[trainNo] = '
            '(rawAtArrival > GHOST_ARRIVAL_MIN_SEC) '
            '? { raw: rawAtArrival } : { final: true };'),
      );
      expect(htmlContent, contains('if (arrivedRec.raw === t.arrivalSeconds) continue;'));
    });

    test('[요구사항] 정상 도착 열차는 절대 되살아나지 않는다', () {
      // 2026-08-04 방배 실측: 목표역 **진입** 중인 열차가 `barvlDt=10, arvlCd=0`
      // 으로, 즉 **양수**로 다시 보고된다. 따라서 "새 원본이 <=0 이면 숨김" 같은
      // 값 비교로는 부활을 막지 못한다 — 도착 시점에 확정해야 한다.
      expect(htmlContent, contains('if (arrivedRec.final) continue;'));
      expect(htmlContent, contains('? { raw: rawAtArrival }'));
      expect(htmlContent, contains(': { final: true };'));
      // 값 비교로 정상 도착을 막으려던 옛 방식이 남아 있으면 안 된다.
      expect(htmlContent, isNot(contains('|| t.arrivalSeconds <= 0) continue;')));

      // 페이드아웃(0.6초) 중 부활 시 조기 continue 분기가 페이드의 animationId 를
      // 주행으로 오인하면 열차가 소리 없이 사라진다.
      expect(htmlContent, contains('trainState.arrivalPlaying = true;'));
      expect(htmlContent, contains('&& !existing.arrivalPlaying'));
      expect(htmlContent, contains('existing.arrivalPlaying = false;'));
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
      final fnEnd = htmlContent.indexOf('window.showTrains', fnStart);
      final fnBody = htmlContent.substring(fnStart, fnEnd);

      expect(fnBody, contains('return b.rem - a.rem'));
      expect(fnBody, contains('liveTrainsGroup.appendChild(items[i].el)'));
      // [래스터 부하 절감, 2026-08] 이미 원하는 순서와 같으면 DOM 이동 자체를
      // 생략해 불필요한 #train-layer 재정렬(페인트 유발)을 피한다.
      expect(fnBody, contains('alreadyOrdered'));

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
      // [래스터 기아 수정 v3] 위치는 SVG attribute 대신 CSS style.transform 으로
      // 쓴다(px 단위) — build_map_html.dart 의 "래스터 기아 수정 v3" 주석 참조.
      expect(
        "'translate(' + path[0].x + 'px,' + path[0].y + 'px)'".allMatches(body).length,
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
          body.indexOf("'translate(' + path[0].x + 'px,' + path[0].y + 'px)'");
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

    test('[안드로이드 팬/핀치 점멸 v2 수정] 열차 transform 쓰기는 좌표가 바뀔 때만 일어난다', () {
      // 2026-08 재발 점멸(라벨 타일 산발적 순간 소실) 조사 결과, 매 rAF 마다
      // 좌표가 그대로여도 #train-layer 내부 <g> 의 transform 속성을 무조건
      // 다시 쓰고 있었다. 3-way 클램프(원칙 3)나 단조 전진 backstop(원칙 1)이
      // target 을 같은 지점에 붙잡아 두는 동안에도 매 프레임 DOM 을 건드려
      // 불필요한 레이어 무효화를 유발한다 — 위치 계산 자체(4원칙)는 그대로
      // 두고 최종 DOM 반영만 실제 변화가 있을 때로 제한해야 한다.
      final stepStart = htmlContent.indexOf('function step() {');
      expect(stepStart, greaterThan(0));
      final stepEnd = htmlContent.indexOf(
          'function playArrivalEffect', stepStart);
      final stepBody = htmlContent.substring(stepStart, stepEnd);

      expect(
        stepBody,
        contains(
            'trainState.lastRenderedX !== pos.x || trainState.lastRenderedY !== pos.y'),
      );
      expect(stepBody, contains('trainState.lastRenderedX = pos.x;'));
      expect(stepBody, contains('trainState.lastRenderedY = pos.y;'));
    });

    test('[안드로이드 핀치 점멸 v2 수정] 핀치 중엔 text-layer 폰트 보정을 미루고 종료 시 flush한다', () {
      // 2026-08 재연 영상 분석: 역명 라벨만 타일 단위로 순간 소실되는 점멸이
      // 12회 이상 산발적으로 발생했다(7월의 "노선 2.9초 연속 소실"과는 다른
      // 증상). 2-포인터 핀치 동안 pointermove 마다 scale 이 거의 매번 달라져
      // text-layer 의 font-size/--stroke-w(상속 속성, 수백 개 <text> 자식에
      // 영향)가 최대 60fps 로 반복 재기록됐다 — 팬 전용 프레임은 이미
      // scale 불변 캐시로 스킵되지만 핀치 프레임은 스킵되지 않았다. 같은
      // 프레임에 실시간 열차 갱신(#train-layer)까지 겹치면 두 대형 레이어가
      // 동시에 무효화되어 안드로이드 래스터 스레드가 타일 커밋을 따라가지
      // 못해 라벨 타일이 순간 노출(미래스터 상태)됐다. 핀치 중엔 보정을
      // 미루고(라벨이 매트릭스 스케일을 그대로 따라감) 제스처 종료 시 한 번만
      // 반영해 리페인트를 제스처당 1회로 줄인다.
      expect(htmlContent, contains('function updateTextCompensation()'));

      final applyStart = htmlContent.indexOf('function applyTransform()');
      final applyEnd =
          htmlContent.indexOf('function updateTextCompensation()', applyStart);
      final applyBody = htmlContent.substring(applyStart, applyEnd);
      expect(applyBody, contains('if (getPointerCount() !== 2) {'));
      expect(applyBody, contains('updateTextCompensation();'));

      // 핀치가 포인터 0개로 끝나는 경우 이후 아무도 applyTransform 을 다시
      // 부르지 않으므로, pointerup/pointercancel 이 직접 flush 해야 최종
      // 폰트 크기가 반영된다.
      final pointerUpStart =
          htmlContent.indexOf("addEventListener('pointerup'");
      final pointerCancelStart =
          htmlContent.indexOf("addEventListener('pointercancel'");
      final wheelStart =
          htmlContent.indexOf("addEventListener('wheel'", pointerCancelStart);
      final pointerUpBody =
          htmlContent.substring(pointerUpStart, pointerCancelStart);
      final pointerCancelBody =
          htmlContent.substring(pointerCancelStart, wheelStart);
      expect(pointerUpBody, contains('if (getPointerCount() !== 2) {'));
      expect(pointerUpBody, contains('updateTextCompensation();'));
      expect(pointerCancelBody, contains('if (getPointerCount() !== 2) {'));
      expect(pointerCancelBody, contains('updateTextCompensation();'));
    });

    test('[H-1, 2026-08 리뷰] 도착 이펙트 시작 시 렌더 캐시를 무효화한다', () {
      // playArrivalEffect.animate() 는 매 프레임 el.style.transform =
      // currentTransform + ' scale(...)' 로 transform 을 **직접** 덮어써
      // step() 의 lastRenderedX/Y 좌표 비교를 완전히 우회한다. 0.6초 페이드
      // 도중 유령 도착이 부활(startTrainAnimation 재시작)하면, stall 열차는
      // 원칙 1 가드가 target 을 최전진 지점(직전 렌더 좌표와 비트 동일)에
      // 붙잡아 두므로 부활 후 첫 step() 프레임이 "좌표 변화 없음"으로 오판해
      // DOM 쓰기를 스킵한다 — 페이드 마지막 프레임의 확대(scale) 잔재가 위치가
      // 실제로 바뀔 때까지 고착되는 회귀. playArrivalEffect 진입 시 캐시를
      // 비워 부활 시 첫 step() 프레임이 반드시 clean translate 를 다시 쓰도록
      // 강제해야 한다.
      final fnStart = htmlContent.indexOf('function playArrivalEffect');
      expect(fnStart, greaterThan(0));
      final fnEnd =
          htmlContent.indexOf('function cancelTrainAnimation', fnStart);
      final fnBody = htmlContent.substring(fnStart, fnEnd);

      expect(fnBody, contains('trainState.lastRenderedX = null;'));
      expect(fnBody, contains('trainState.lastRenderedY = null;'));

      // 무효화가 arrivedTrains 판정보다 먼저(진입부에) 있어야 한다 — 이
      // 함수의 어느 조기 return/분기를 타든 캐시가 항상 비워지도록.
      final invalidateIdx = fnBody.indexOf('trainState.lastRenderedX = null;');
      final rawAtArrivalIdx = fnBody.indexOf('var rawAtArrival');
      expect(rawAtArrivalIdx, greaterThan(0));
      expect(invalidateIdx, lessThan(rawAtArrivalIdx));
    });

    test('[M-1, 2026-08 리뷰] 휠 줌은 포인터 게이트와 무관하게 폰트 보정을 직접 flush한다', () {
      // applyTransform 의 폰트 보정은 getPointerCount() !== 2 로 게이트된다.
      // pointerup/pointercancel 유실로 pointers 에 유령 항목 2개가 남으면 이
      // 게이트가 영구히 닫혀 이후 모든 보정(휠 줌 포함)이 동결될 수 있다.
      // scale 을 바꾸는 경로는 2-포인터 핀치와 휠 줌 뿐이고(panTo/resize 는
      // scale 을 바꾸지 않아 영향 없음), 휠은 터치 포인터 상태와 완전히 무관한
      // 입력이므로 핸들러 안에서 게이트를 우회해 직접 flush해야 한다.
      final wheelStart = htmlContent.indexOf("addEventListener('wheel'");
      expect(wheelStart, greaterThan(0));
      final wheelEnd = htmlContent.indexOf('});', wheelStart);
      final wheelBody = htmlContent.substring(wheelStart, wheelEnd);

      expect(wheelBody, contains('scale = newScale;'));
      expect(wheelBody, contains('updateTextCompensation();'));
      // 게이트를 재도입하면 안 된다 — 이 호출은 조건문 없이 이루어져야 한다
      // (설명 주석에서 getPointerCount 를 언급하는 것 자체는 허용하되, 실제
      // 코드로 조건 분기하면 안 된다).
      expect(wheelBody, isNot(contains('if (getPointerCount()')));
    });

    test('[P2, 2026-08 리뷰] 폰트 보정 캐시 키가 scale 이 아니라 cs 다', () {
      // cs = clamp(scale, TEXT_COMP_FLOOR, 1) 이므로 scale > 1(확대) 구간
      // 전체와 scale < TEXT_COMP_FLOOR(최대 축소) 구간에서는 scale 이 계속
      // 바뀌어도 cs 는 고정된다. 캐시 키가 scale 이면 이 구간에서 매번
      // "값이 다르다"고 오판해 실제로는 동일한 fontSize/--stroke-w 를
      // 불필요하게 다시 쓴다.
      final compStart = htmlContent.indexOf('function updateTextCompensation()');
      expect(compStart, greaterThan(0));
      final compEnd = htmlContent.indexOf('function setInitialView()', compStart);
      final compBody = htmlContent.substring(compStart, compEnd);

      expect(compBody, contains('if (cs === lastCs) return;'));
      expect(compBody, contains('lastCs = cs;'));
      expect(compBody, isNot(contains('lastFontScale')));
      expect(htmlContent, contains('var lastCs = null;'));
    });

    test('[P1, 2026-08 리뷰] 팬/핀치 제스처 중엔 말풍선 카운트다운 DOM 쓰기를 미룬다', () {
      // 열차 대수가 늘고(20→30행 조회, 유령 열차 상주 등) train-layer 무효화
      // 총량이 증가했을 가능성에 대한 저위험 방어. realRemaining 계산(원칙
      // 1-a)은 매 프레임 그대로 수행하고, 결과를 말풍선 텍스트에 반영하는
      // DOM 쓰기만 제스처 동안 미룬다 — 도착 판정(realRemaining<=0 기준)은
      // 이 값을 참조하지 않으므로 4원칙에는 영향이 없다.
      final stepStart = htmlContent.indexOf('function step() {');
      final stepEnd = htmlContent.indexOf('function playArrivalEffect', stepStart);
      final stepBody = htmlContent.substring(stepStart, stepEnd);

      expect(
        stepBody,
        contains('if (!gestureActive && trainState.lastShownSec !== shownSec)'),
      );

      // 제스처 상태는 포인터 접촉 여부(pointerdown~pointerup/cancel 0개)로
      // 정의되며, 도착 판정(realRemaining<=0)과는 별개 변수여야 한다.
      expect(htmlContent, contains('var gestureActive = false;'));
      final pointerDownStart = htmlContent.indexOf("addEventListener('pointerdown'");
      final pointerUpStart2 = htmlContent.indexOf("addEventListener('pointerup'");
      final pointerDownBody =
          htmlContent.substring(pointerDownStart, pointerUpStart2);
      expect(pointerDownBody, contains('gestureActive = true;'));

      final arrivalGateIdx = stepBody.indexOf('realRemaining <= 0 && atFinalLeg');
      expect(arrivalGateIdx, greaterThan(0),
          reason: '도착 발동 조건은 gestureActive 와 무관하게 realRemaining 만 봐야 한다');

      // [L-4, 2026-08 2차 리뷰] gestureActive 가 도착 판정식 자체에 결합되는
      // 것을 명시적으로 부정한다 — 위 인덱스 비교만으로는 "같은 줄에
      // gestureActive 가 섞여 들어가는" 형태의 회귀(예: 실수로
      // `if (!gestureActive && realRemaining <= 0 && ...)` 처럼 게이트가
      // 번져 도착이 제스처 동안 미뤄지는 경우)를 못 잡는다.
      expect(
        stepBody,
        isNot(contains('gestureActive && realRemaining')),
      );
    });

    test('[M-2, 2026-08 2차 리뷰] 툴바 드래그의 포인터 전량 클리어가 gestureActive 도 초기화한다', () {
      // initRouteToolbarDrag 는 "맵 pan state 강제 초기화" 관용구로 pointers
      // 를 전량 비우며 isDragging 도 함께 false 로 되돌린다. 지도 쪽
      // pointerup/pointercancel 유실로 gestureActive 가 이미 true 로 걸려
      // 있었다면, 이 초기화 지점에 gestureActive 리셋이 빠질 경우 회복
      // 기회를 놓쳐 이후 세션 내내 열차 카운트다운 DOM 쓰기가 동결된다.
      final dragFnStart = htmlContent.indexOf('function initRouteToolbarDrag');
      expect(dragFnStart, greaterThan(0));
      final dragFnEnd = htmlContent.indexOf('routeToolbar.addEventListener(\'pointerdown\', onDragStart);', dragFnStart);
      final dragFnBody = htmlContent.substring(dragFnStart, dragFnEnd);

      // pointers 전량 클리어 지점이 정확히 2곳(onDragStart, onDragEnd)이고,
      // 각각 isDragging = false 옆에 gestureActive = false 가 있어야 한다.
      final clearPattern = RegExp(
        r'for \(var __k in pointers\)[^\n]*\n\s*isDragging = false;\s*\n(?:[^\n]*\n)*?\s*gestureActive = false;',
      );
      final matches = clearPattern.allMatches(dragFnBody).toList();
      expect(matches.length, equals(2),
          reason: 'onDragStart/onDragEnd 두 클리어 지점 모두 gestureActive 를 '
              '초기화해야 한다');
    });
  });
}
