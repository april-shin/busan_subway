import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/line_badges.dart';
import '../../tool/map_constants.dart';

/// build_map_html.dart 의 빌드 타임 정규화와 같은 규칙 — 아직 XML 엔티티인
/// `&#10;`/`&#13;` 와 리터럴 개행을 제거하고 앞뒤 공백만 trim 한다. 내부 공백은
/// 실제 역명의 일부("사우 (김포시청)")라 보존해야 stations.json 과 맞는다.
String _normalizeStationName(String raw) => raw
    .replaceAll('&#10;', '')
    .replaceAll('&#13;', '')
    .replaceAll('\n', '')
    .replaceAll('\r', '')
    .trim();

/// [라벨 2단(tier) 정책, 2026-09-22] tl-major 부착의 기대값을 stations.json
/// (isTransfer)과 원본 SVG(`<text>` 의 data-station)에서 직접 계산한다.
///
/// [2026-09-22 2차 리뷰] 이 계산은 build_map_html.dart 의 매칭 로직을 복제한
/// 것이라, 그것만으로는 tautological 하다 — 양쪽이 **같은** 정규화 버그를
/// 가지면 교집합이 똑같이 줄어들어 개수가 일치해 버린다. 그래서 아래
/// `svgLabelNames`/`allStationNames`/`transferNames` 를 함께 돌려주고,
/// 테스트에서 "SVG 라벨 이름은 전부 stations.json 에 있다", "isTransfer 역은
/// 전부 SVG 라벨을 갖는다" 는 **데이터 계약**을 독립적으로 단언한다. 정규화가
/// 양쪽에서 같이 틀어지면 이 두 계약이 먼저 깨지므로 조용한 통과가 불가능하다.
({
  Set<String> transferNames,
  Set<String> allStationNames,
  Set<String> svgLabelNames,
  int svgLabelCount,
  int expectedMajorCount,
}) _labelTierExpectation() {
  final stationsData = jsonDecode(
    File('assets/json/stations.json').readAsStringSync(),
  ) as List<dynamic>;
  final transferNames = <String>{};
  final allStationNames = <String>{};
  for (final entry in stationsData) {
    final station = entry as Map<String, dynamic>;
    final name = station['name'] as String;
    allStationNames.add(name);
    if (station['isTransfer'] == true) {
      transferNames.add(name);
    }
  }

  // 스코프를 `<text>` 여는 태그로 한정한다 — 빌드 스크립트도 텍스트 요소만
  // 처리하므로, SVG 에 `<circle data-station=...>` 같은 것이 생겨도 기대값이
  // 어긋나지 않는다.
  final svgContent = File('assets/svg/seoul_metro_map.svg').readAsStringSync();
  final labelPattern = RegExp(r'<text[^>]*data-station="([^"]*)"');
  final svgLabelNames = <String>{};
  var svgLabelCount = 0;
  var expectedMajorCount = 0;
  for (final m in labelPattern.allMatches(svgContent)) {
    final name = _normalizeStationName(m.group(1)!);
    svgLabelNames.add(name);
    svgLabelCount++;
    if (transferNames.contains(name)) expectedMajorCount++;
  }

  return (
    transferNames: transferNames,
    allStationNames: allStationNames,
    svgLabelNames: svgLabelNames,
    svgLabelCount: svgLabelCount,
    expectedMajorCount: expectedMajorCount,
  );
}

/// 여는 태그의 class 속성을 파싱해 tl-major 부착 여부를 판정한다. 문자열
/// `class="tl-major"` 포함 검사로는 병합형(`class="foo tl-major"`)을 놓치고,
/// `<tspan>` 에 잘못 붙은 클래스도 걸러내지 못한다.
bool _hasMajorClass(String openTag) {
  final classMatch = RegExp(r'\sclass="([^"]*)"').firstMatch(openTag);
  if (classMatch == null) return false;
  return classMatch.group(1)!.split(RegExp(r'\s+')).contains('tl-major');
}

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

    test(
        '[래스터 기아 v8] dimmed 토글에는 opacity transition 이 없다',
        () {
      // [회귀 가드, 2026-08 v8] v4는 text[data-line] 만 opacity transition
      // 셀렉터에서 뺐고(팬 중 점멸 완화 우회책), v7은 v6(<svg> 루트를 <div>
      // 래퍼로 감싼 구조 변경)로 그 우회책의 전제가 소멸했다며 되돌렸다.
      // 그러나 v7 재검증은 팬/핀치 시나리오만 CDP로 재측정했고, "출발/도착
      // 선택·해제 순간"(팬과 무관)은 확인하지 않았다.
      //
      // 사용자 제보(선택/해제 순간 점멸) 후 화면 녹화(30fps) 프레임을 직접
      // 확인한 결과: 회현→이태원 선택 완료 순간(v7 빌드), 전환 시작 후 약
      // 0.13~0.20초 구간에서 지도 전체(노선·라벨·마커)가 완전히 사라지고
      // 흰 배경만 남는 프레임이 실측됐다(검색바·툴바 팝업·광고 배너는 생존).
      // 0.3초 트랜지션이 ~1,200개 요소(텍스트 639+원 528~600+선 32+사각형
      // 38)에 동시에 걸릴 때 안드로이드 WebView 래스터 스레드가 중간 프레임
      // 커밋을 완전히 놓치는 것으로 판단된다. 트랜지션을 완전히 제거한
      // 빌드로 재녹화하면 이 블랭크 프레임이 사라짐을 확인했다. 팬은 v6
      // 구조 변경 이후 이 트랜지션 유무와 무관하게 안전하므로 회귀 없음.
      // 상세: _workspace/10_map-math-engineer_pan-flicker-report.md §38.
      expect(
        htmlContent,
        isNot(contains('transition: opacity 0.3s')),
        reason: 'path[data-line]/text[data-line]/circle/rect 의 dimmed 토글에 '
            'opacity transition 이 재도입되면 출발/도착 선택·해제 순간 '
            '~1200개 요소가 동시에 트랜지션을 시작해 지도 전체가 0.1~0.2초간 '
            '완전히 사라지는 블랭크 점멸이 재발한다(30fps 녹화 프레임으로 실측).',
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
      // [v6, 2026-08-13] transform 은 <svg> 루트(textLayer/trainLayer)가 아니라
      // 그 바깥 <div> 래퍼(textLayerWrap/trainLayerWrap)에 대입한다 — 아래
      // '[래스터 기아 v6]' 테스트가 이 계약을 전담 가드한다.
      expect(applyBody, contains('textLayerWrap.style.transform = matrixStr'));
      expect(applyBody, contains('trainLayerWrap.style.transform = matrixStr'));
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
      // [라벨 2단(tier) 정책, 2026-09-22] 역보정은 더 이상 textLayer.style.
      // fontSize(전체 655개 라벨이 상속) 를 직접 쓰지 않는다 — 환승역
      // (text.tl-major) 만 읽는 --label-fs-major/--stroke-w-major 커스텀
      // 프로퍼티 두 개만 갱신해 일반역은 리페인트 대상에서 제외한다.
      expect(compBody, isNot(contains('textLayer.style.fontSize =')));
      expect(compBody, contains("textLayer.style.setProperty("));
      expect(compBody, contains("'--label-fs-major'"));
      // [래스터 기아 실험 A, 2026-08-13 — 기각·원복] stroke 보정을 `--stroke-w`
      // 커스텀 프로퍼티에서 네이티브 `style.strokeWidth` 로 바꿔 CDP Tracing 으로
      // 검증했으나 개선이 없었다(§10 보고서 §20~§22 — InvalidateLayout 이 자식의
      // 상속 프로퍼티 메커니즘과 무관하게 SVG 루트 자신에 직접 걸림이 확정됨).
      // 커스텀 프로퍼티 방식 자체는 유지하되, 2단 정책으로 이름만
      // `--stroke-w-major` 로 바뀌었다.
      expect(compBody, contains("'--stroke-w-major'"));
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

    test(
        '[래스터 기아 v6] text-layer/train-layer 는 <div> 래퍼에 감싸이고, 매 프레임 '
        'transform 은 <svg> 루트가 아니라 래퍼에만 대입된다',
        () {
      // [회귀 가드, 2026-08-13] CDP 실측(§10_map-math-engineer_pan-flicker-
      // report.md §22.2)으로 확정: <svg> 루트가 자기 자신의 인라인
      // style.transform 대입에 반응해 스스로 InvalidateLayout 을 거는 것이
      // 근본 원인이었다 — 동일 조건의 <div>(#map-container)는 0건. v3(개별
      // will-change 열차 레이어)·v4(툴바 transform 전환)로도 잔여 점멸이
      // 남았던 이유가 이것이다. 해결책은 pan/zoom transform 을 <svg> 루트가
      // 아니라 그 바깥의 <div> 래퍼(#text-layer-wrap/#train-layer-wrap)에만
      // 대입하는 것 — #map-container 가 이미 증명한 안전 패턴과 동일하게
      // 맞춘다.

      // 1) 래퍼 div 가 마크업에 존재하고, <svg> 루트를 감싼다.
      final textWrapStart = htmlContent.indexOf('<div id="text-layer-wrap">');
      final trainWrapStart =
          htmlContent.indexOf('<div id="train-layer-wrap">');
      expect(textWrapStart, greaterThan(0),
          reason: '#text-layer-wrap 래퍼 div 를 찾지 못했다');
      expect(trainWrapStart, greaterThan(0),
          reason: '#train-layer-wrap 래퍼 div 를 찾지 못했다');

      final textSvgIdx = htmlContent.indexOf('id="text-layer"', textWrapStart);
      final textWrapCloseIdx = htmlContent.indexOf('</div>', textSvgIdx);
      expect(textSvgIdx, greaterThan(textWrapStart),
          reason: '<svg id="text-layer"> 가 #text-layer-wrap 내부에 있어야 한다');
      expect(textWrapCloseIdx, greaterThan(textSvgIdx),
          reason: '#text-layer-wrap 닫힘 태그가 <svg id="text-layer"> 뒤에 있어야 한다');
      // [코드 리뷰 LOW-1 보강, v6] 위 두 단언만으로는 `<div id="text-layer-
      // wrap"></div><svg id="text-layer">…` 처럼 래퍼가 이미 비어서 닫히고
      // svg 가 그 뒤에(래퍼 밖에) 놓인 회귀도 통과시킬 수 있다 — 그 경우
      // textSvgIdx 이후의 아무 `</div>`(예: #train-layer-wrap 것)에 우연히
      // 매치되기 때문이다. wrapStart~svgIdx 구간에 `</div>` 가 없어야
      // "래퍼가 svg 를 감싸는 중" 이라는 전제가 성립한다.
      final textWrapClosedEarly =
          htmlContent.indexOf('</div>', textWrapStart);
      expect(
          textWrapClosedEarly == -1 || textWrapClosedEarly > textSvgIdx,
          isTrue,
          reason: '#text-layer-wrap 이 <svg id="text-layer"> 보다 먼저 닫히면 '
              '안 된다 (래퍼가 비어 있는 회귀)');

      final trainSvgIdx =
          htmlContent.indexOf('id="train-layer"', trainWrapStart);
      final trainWrapCloseIdx = htmlContent.indexOf('</div>', trainSvgIdx);
      expect(trainSvgIdx, greaterThan(trainWrapStart),
          reason: '<svg id="train-layer"> 가 #train-layer-wrap 내부에 있어야 한다');
      expect(trainWrapCloseIdx, greaterThan(trainSvgIdx),
          reason: '#train-layer-wrap 닫힘 태그가 <svg id="train-layer"> 뒤에 있어야 한다');
      final trainWrapClosedEarly =
          htmlContent.indexOf('</div>', trainWrapStart);
      expect(
          trainWrapClosedEarly == -1 || trainWrapClosedEarly > trainSvgIdx,
          isTrue,
          reason: '#train-layer-wrap 이 <svg id="train-layer"> 보다 먼저 닫히면 '
              '안 된다 (래퍼가 비어 있는 회귀)');

      // 2) 래퍼 CSS가 #map-container와 동일한 "고정 원점 + transform" 관용구를
      // 갖는다 (position:absolute, transform-origin:0 0, will-change:transform).
      final wrapRuleMatch = RegExp(
        r'#text-layer-wrap,\s*#train-layer-wrap\s*\{([^}]*)\}',
      ).firstMatch(htmlContent);
      expect(wrapRuleMatch, isNotNull,
          reason: '#text-layer-wrap, #train-layer-wrap CSS 규칙을 찾지 못했다');
      final wrapRule = wrapRuleMatch!.group(1)!;
      expect(RegExp(r'position\s*:\s*absolute').hasMatch(wrapRule), isTrue,
          reason: '래퍼는 #map-container 와 동일하게 position:absolute 여야 한다');
      expect(
          RegExp(r'transform-origin\s*:\s*0\s+0').hasMatch(wrapRule), isTrue,
          reason: '래퍼는 transform-origin:0 0 이어야 스케일 기준점이 맞는다');
      expect(RegExp(r'will-change\s*:\s*transform').hasMatch(wrapRule), isTrue,
          reason: '래퍼가 독립 컴포지터 레이어로 승격돼야 한다');

      // 3) applyTransform()은 래퍼에만 transform 을 쓰고, <svg> 루트에는
      // 절대 인라인 transform 을 쓰지 않는다.
      final applyStart = htmlContent.indexOf('function applyTransform()');
      final applyEnd =
          htmlContent.indexOf('function updateTextCompensation()', applyStart);
      final applyBody = htmlContent.substring(applyStart, applyEnd);
      expect(applyBody, contains('textLayerWrap.style.transform = matrixStr'));
      expect(applyBody, contains('trainLayerWrap.style.transform = matrixStr'));

      // 4) <svg> 루트 자신에 대한 style.transform 쓰기가 문서 전체에 재유입되지
      // 않았는지 확인한다 — "textLayer.style.transform"/"trainLayer.style.
      // transform" 은 "textLayerWrap.style.transform" 의 부분 문자열이
      // 아니므로(중간에 'Wrap' 이 끼어 있다) 오탐 없이 정확히 구별된다.
      expect(htmlContent.contains('textLayer.style.transform'), isFalse,
          reason: '<svg id="text-layer"> 루트에 직접 transform 을 쓰면 자기-'
              'InvalidateLayout 이 재발한다(v6 회귀)');
      expect(htmlContent.contains('trainLayer.style.transform'), isFalse,
          reason: '<svg id="train-layer"> 루트에 직접 transform 을 쓰면 자기-'
              'InvalidateLayout 이 재발한다(v6 회귀)');

      // 5) 내부 <svg> 는 여전히 고정 뷰포트(viewBox 1:1, width/height 고정)를
      // 유지해야 좌표 수학이 그대로 성립한다 — 아래 다른 테스트가 이미
      // 검증하지만, v6 계약의 핵심 전제이므로 여기서도 명시적으로 재확인한다.
      expect(htmlContent, contains('id="text-layer" xmlns='));
      expect(htmlContent, contains('id="train-layer" xmlns='));
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
      // 라벨 1/2배가 되는 회귀가 확정됐다. 문자열 존재 검사만으로는 이 회귀를
      // 잡지 못하므로, 대입 우변 수식을 정규식으로 추출해 정확한 값 형태
      // (scale 없음)를 고정한다.
      // [라벨 2단(tier) 정책, 2026-09-22] 이 보정은 환승역(--label-fs-major/
      // --stroke-w-major)에만 적용된다 — 일반역은 CSS 기본값(12px 상수)뿐이라
      // 이 수식 자체를 거치지 않는다.
      final applyStart = htmlContent.indexOf('function applyTransform()');
      final applyEnd =
          htmlContent.indexOf('function setInitialView()', applyStart);
      final applyBody = htmlContent.substring(applyStart, applyEnd);

      final fontSizeMatch = RegExp(
        r"setProperty\(\s*'--label-fs-major',\s*\(([^)]+)\)\s*\+\s*'px'",
      ).firstMatch(applyBody);
      expect(fontSizeMatch, isNotNull,
          reason: "setProperty('--label-fs-major', ...) 대입식을 찾지 못했다");
      expect(
        fontSizeMatch!.group(1)!.replaceAll(RegExp(r'\s+'), ''),
        equals('TEXT_BASE_FONT_SIZE/cs'),
        reason: '/scale 이 붙으면 CSS transform의 scale 배율과 이중으로 곱해져 '
            '화면 폰트 크기가 scale=0.5에서 2배, scale=2에서 1/2배로 어긋난다',
      );

      final strokeMatch = RegExp(
        r"setProperty\(\s*'--stroke-w-major',\s*\(([^)]+)\)\s*\+\s*'px'",
      ).firstMatch(applyBody);
      expect(strokeMatch, isNotNull,
          reason: "setProperty('--stroke-w-major', ...) 대입식을 찾지 못했다");
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
      // 클리핑이 재발하므로 CSS 규칙 블록에서 값을 직접 고정한다.
      // [v6, 2026-08-13] overflow 는 SVG 자신의 클리핑 특성이라 <div> 래퍼가
      // 아니라 내부 <svg id="text-layer">/<svg id="train-layer"> 자신의 규칙에
      // 있어야 한다 — 두 selector 가 하나의 규칙(`#text-layer, #train-layer`)
      // 으로 합쳐졌다.
      final ruleMatch = RegExp(
        r'#text-layer,\s*#train-layer\s*\{([^}]*)\}',
      ).firstMatch(htmlContent);
      expect(ruleMatch, isNotNull,
          reason: '#text-layer, #train-layer CSS 규칙 블록을 찾지 못했다');
      expect(
        RegExp(r'overflow\s*:\s*visible').hasMatch(ruleMatch!.group(1)!),
        isTrue,
        reason: '#text-layer/#train-layer 에 overflow: visible 이 없으면 고정 '
            '치수(2416x1560) 경계 밖 말풍선·라벨이 잘린다',
      );
    });

    test('텍스트 레이어 CSS가 라벨 2단(tier) font-size 정책을 갖는다', () {
      // [라벨 2단(tier) 정책, 2026-09-22] _workspace/16_requirements_label_zoom.md
      // 일반역은 상수 기본값(12px)만 쓰고(인라인 style="font-size:12px"를
      // 이겨야 하므로 !important 는 유지), 환승역(text.tl-major)만 scale<1
      // 에서 역보정된 --label-fs-major 를 읽는다.
      expect(htmlContent, contains('font-size: var(--label-fs, 12px) !important'));
      expect(htmlContent,
          contains('font-size: var(--label-fs-major, 12px) !important'));
      final majorRuleMatch =
          RegExp(r'#text-layer text\.tl-major\s*\{([^}]*)\}')
              .firstMatch(htmlContent);
      expect(majorRuleMatch, isNotNull,
          reason: '#text-layer text.tl-major CSS 규칙을 찾지 못했다');
      expect(majorRuleMatch!.group(1)!,
          contains('stroke-width: var(--stroke-w-major, 2px)'));
    });

    test('환승역 라벨에는 tl-major 클래스가 붙고, 일반역에는 붙지 않는다', () {
      // [라벨 2단(tier) 정책, 2026-09-22] stations.json 의 isTransfer 역
      // 이름과 매칭해 빌드 타임에 부여된다.
      // [2026-09-22 리뷰 수정] 기대값을 119로 하드코딩하면 환승역 추가/제거
      // 같은 정상적인 데이터 변경에도 테스트가 깨지고, 실패 메시지가 "매칭
      // 로직 회귀"라는 오진을 유도한다. stations.json의 isTransfer 이름
      // 집합과 원본 SVG의 data-station 이름 집합에서 기대값을 계산하되,
      // 그 계산이 빌드 스크립트의 복제라 tautology 가 되지 않도록 (1) 데이터
      // 계약 2건과 (2) 라벨 단위 1:1 대조를 함께 단언한다(_labelTierExpectation
      // 주석 참조).
      final expectation = _labelTierExpectation();

      // (1) 데이터 계약 — 이 두 단언이 있어야 위 기대값 계산이 tautology 가
      // 되지 않는다. 정규화가 빌드 스크립트와 테스트 양쪽에서 똑같이 틀어지면
      // 교집합이 조용히 줄어드는 대신 여기서 먼저 깨진다.
      expect(
        expectation.svgLabelNames.difference(expectation.allStationNames),
        isEmpty,
        reason: 'SVG data-station 이름이 stations.json 에 없다 — 역명 정규화가 '
            '틀렸거나 두 데이터가 드리프트했다',
      );
      expect(
        expectation.transferNames.difference(expectation.svgLabelNames),
        isEmpty,
        reason: 'isTransfer 역인데 대응하는 SVG 라벨이 없다 — 교집합이 조용히 '
            '줄어든 상태라 tl-major 개수 비교를 믿을 수 없다',
      );

      // (2) 라벨 단위 판정 — 개수 비교만으로는 클래스가 <tspan> 에 잘못 붙어도
      // 총합이 맞아 통과한다. 여는 태그마다 isTransfer 여부와 tl-major 부착을
      // 1:1로 대조한다.
      final labelPattern = RegExp(r'<text[^>]*data-station="([^"]*)"[^>]*>');
      var majorCount = 0;
      var labelCount = 0;
      for (final m in labelPattern.allMatches(htmlContent)) {
        labelCount++;
        final name = _normalizeStationName(m.group(1)!);
        final hasMajor = _hasMajorClass(m.group(0)!);
        if (hasMajor) majorCount++;
        expect(
          hasMajor,
          expectation.transferNames.contains(name),
          reason: '$name 라벨의 tl-major 부착 여부가 stations.json isTransfer 와 '
              '다르다',
        );
      }
      expect(labelCount, equals(expectation.svgLabelCount),
          reason: '생성물의 역명 라벨 수가 원본 SVG 의 <text> 라벨 수와 다르다 — '
              '<text> 추출/재삽입 경로 회귀를 의심할 것');
      expect(majorCount, equals(expectation.expectedMajorCount));
      expect(majorCount, greaterThan(0),
          reason: 'tl-major 클래스가 하나도 없다 — 라벨 2단(tier) 정책 자체가 '
              '증발했을 수 있다');

      // 실제 환승역(사당: 2·4호선 환승) 라벨에는 클래스가 붙어야 한다.
      final sadangMatch =
          RegExp(r'<text[^>]*data-station="사당"[^>]*>').firstMatch(htmlContent);
      expect(sadangMatch, isNotNull, reason: '사당 라벨을 찾지 못했다');
      expect(_hasMajorClass(sadangMatch!.group(0)!), isTrue);

      // 일반역(환승 없음, 예: 1호선 "연천")에는 클래스가 붙지 않아야 한다.
      final yeoncheonMatch = RegExp(r'<text[^>]*data-station="연천"[^>]*>')
          .firstMatch(htmlContent);
      expect(yeoncheonMatch, isNotNull, reason: '연천 라벨을 찾지 못했다');
      expect(_hasMajorClass(yeoncheonMatch!.group(0)!), isFalse);
    });

    test('textTargetRect가 라벨 tier 별로 다른 확대 배율(f)을 쓴다', () {
      // [라벨 2단(tier) 정책, 2026-09-22] 일반역은 역보정이 없으므로 f=1(기준
      // bbox 그대로), 환승역만 TEXT_COMP_FLOOR 하한을 반영한 f=1/cs 를 쓴다.
      // 이전 코드(f = 1/Math.min(scale,1))는 TEXT_COMP_FLOOR 하한을 반영하지
      // 않아 최대 줌아웃에서 탭 박스가 실제 렌더 배율보다 컸다(2026-09-22
      // 리뷰에서 지적된 부수 결함, 이번 변경으로 함께 수정).
      final fnStart = htmlContent.indexOf('function textTargetRect(t)');
      expect(fnStart, greaterThan(0), reason: 'textTargetRect 함수를 찾지 못했다');
      final fnEnd = htmlContent.indexOf('\n  }', fnStart);
      final fnBody = htmlContent.substring(fnStart, fnEnd);

      expect(fnBody, contains('t.major'));
      expect(fnBody, contains('TEXT_COMP_FLOOR'));
      expect(fnBody, isNot(contains('1 / Math.min(scale, 1)')),
          reason: 'TEXT_COMP_FLOOR 하한을 반영하지 않는 옛 공식이 재도입되면 '
              '탭 박스가 실제 렌더 배율과 다시 어긋난다');

      // [HIGH, 2026-09-22 2차 리뷰 수정] 터치 슬롭(pad)은 bbox 확대 배율(f,
      // tier 별로 다름)과 분리되어야 한다. pad = TAP_TEXT_PAD * f 로 f 를
      // 그대로 곱하면 화면 px 기준 슬롭이 tier 마다 달라지고, 변경 전
      // 6px 상수보다 scale=0.5 에서 일반역 3px/환승역 4.5px 로 줄어드는
      // 회귀가 생긴다. TAP_TEXT_PAD / Math.min(scale, 1) 은 tier 와 무관하게
      // 옛 코드(TAP_TEXT_PAD * (1/Math.min(scale,1)))와 scale 전 구간에서
      // 동일한 값을 내 슬롭 회귀를 0으로 만든다(화면 px 로는 scale<1 에서
      // 6px 상수, scale>=1 에서 6*scale px — 둘 다 변경 전과 같다).
      final padMatch =
          RegExp(r'var pad = ([^;]+);').firstMatch(fnBody);
      expect(padMatch, isNotNull, reason: 'pad 대입식을 찾지 못했다');
      expect(
        padMatch!.group(1)!.replaceAll(RegExp(r'\s+'), ''),
        equals('TAP_TEXT_PAD/Math.min(scale,1)'),
        reason: 'pad 가 f(tier 별 bbox 확대 배율)에 다시 묶이면 터치 슬롭이 '
            'tier·scale 에 따라 화면 px 기준으로 들쭉날쭉해진다',
      );
      expect(fnBody, isNot(contains('TAP_TEXT_PAD * f')),
          reason: '슬롭이 다시 f 에 묶이는 옛 공식이 재도입되면 안 된다');
    });

    test('buildTextTargets가 각 타깃에 major(tl-major 여부)를 저장한다', () {
      final fnStart = htmlContent.indexOf('function buildTextTargets()');
      expect(fnStart, greaterThan(0));
      final fnEnd = htmlContent.indexOf('\n  }', fnStart);
      final fnBody = htmlContent.substring(fnStart, fnEnd);

      expect(fnBody, contains("major: el.classList.contains('tl-major')"));
      // 측정 기준값(12px)은 이제 환승역 전용 프로퍼티만 명시 고정하면 된다.
      expect(fnBody,
          contains("textLayer.style.setProperty('--label-fs-major', TEXT_BASE_FONT_SIZE + 'px')"));
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

    group('[P2-4, 2026-10-06] 노선 이름 pill 배지', () {
      // 배지 <g class="lb" ...> 한 개를 파싱한 결과.
      List<Map<String, dynamic>> parseBadges() {
        final out = <Map<String, dynamic>>[];
        final re = RegExp(
          r'<g class="lb" data-badge-line="([^"]*)" data-code="([^"]*)" '
          r'transform="translate\(([\d.]+),([\d.]+)\)">'
          r'<rect x="(-?[\d.]+)" y="(-?[\d.]+)" width="([\d.]+)" height="([\d.]+)" '
          r'rx="[\d.]+" fill="(#[0-9a-fA-F]{6})"/>'
          r'<text [^>]*fill="(#[0-9a-fA-F]{6})">([^<]*)</text></g>',
        );
        for (final m in re.allMatches(htmlContent)) {
          out.add({
            'lineId': m.group(1)!,
            'code': m.group(2)!,
            'ax': double.parse(m.group(3)!),
            'ay': double.parse(m.group(4)!),
            'x': double.parse(m.group(5)!),
            'y': double.parse(m.group(6)!),
            'w': double.parse(m.group(7)!),
            'h': double.parse(m.group(8)!),
            'fill': m.group(9)!.toLowerCase(),
            'textFill': m.group(10)!.toLowerCase(),
            'text': m.group(11)!,
          });
        }
        return out;
      }

      List<Map<String, dynamic>> readJsonList(String path) =>
          (jsonDecode(File(path).readAsStringSync()) as List<dynamic>)
              .cast<Map<String, dynamic>>();

      // 입력 데이터를 한 번 읽어 두고, 조작한 사본으로 buildLineBadges 를 다시 돌린다.
      final svg = File('assets/svg/seoul_metro_map.svg').readAsStringSync();
      final stations = readJsonList('assets/json/stations.json');
      final lines = readJsonList('assets/json/lines.json');
      final conns = readJsonList('assets/json/connections.json');
      final transfer = {
        for (final s in stations)
          if (s['isTransfer'] == true) s['name'] as String,
      };
      LineBadgeResult run({
        List<Map<String, dynamic>>? st,
        List<Map<String, dynamic>>? ln,
        List<Map<String, dynamic>>? cn,
        Map<String, String>? codes,
        Map<String, List<String>>? overrides,
        Map<String, String>? names,
      }) =>
          buildLineBadges(
            svgContent: svg,
            stationsJson: st ?? stations,
            linesJson: ln ?? lines,
            connectionsJson: cn ?? conns,
            transferStationNames: transfer,
            lineCodes: codes ?? kLineIdToDataLine,
            terminalOverrides: overrides ?? kBadgeTerminalOverrides,
            badgeNames: names ?? kLineBadgeNames,
          );
      // 수동 위치 보정(data/badge_offsets.json)이 있으면 그 배지는 "자동 배치 품질 규칙"(앵커 24px·겹침 0)의
      // 적용 대상이 아니다 — 사람이 일부러 고른 자리라 빌드도 경고만 낸다. 그래서 자동 배치 품질을 재는
      // 테스트는 [autoBadges] 로 수동 배지를 빼고, 빌드 통계와 대조하는 테스트는 같은 보정으로 돌린 [runWithFile] 을 쓴다.
      // 보정 파일이 없거나 비어 있으면(현재 기본) 이 둘은 [parseBadges]/[run] 과 같다.
      BadgeOffsets fileOffsets() {
        final f = File(kBadgeOffsetsPath);
        return BadgeOffsets.parse(f.existsSync() ? f.readAsStringSync() : null);
      }

      LineBadgeResult runWithFile() => buildLineBadges(
            svgContent: svg,
            stationsJson: stations,
            linesJson: lines,
            connectionsJson: conns,
            transferStationNames: transfer,
            offsets: fileOffsets(),
          );
      String anchorKey(String lineId, num ax, num ay) =>
          '$lineId@${(ax * 10).round()},${(ay * 10).round()}';

      Set<String>? manualAnchorsCache;
      Set<String> manualAnchors() => manualAnchorsCache ??= fileOffsets().byKey.isEmpty
          ? <String>{}
          : {
              for (final p in runWithFile().placements)
                if (p.manual) anchorKey(p.lineId, p.anchorX, p.anchorY),
            };

      List<Map<String, dynamic>> autoBadges() => [
            for (final b in parseBadges())
              if (!manualAnchors().contains(anchorKey(b['lineId'] as String, b['ax'] as double, b['ay'] as double)))
                b,
          ];

      // 역명+노선으로 역 ID 를 찾는다 — ID 재배정에 견디도록 테스트에 ID 를 하드코딩하지 않는다.
      String idOf(String name, String lineId) => stations
          .firstWhere((s) => s['name'] == name && s['lineId'] == lineId)['id'] as String;
      Matcher stateErrorWith(String fragment) =>
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains(fragment)));

      test('전 노선(lines.json)의 양 종점에 배지가 정확히 2개씩 있다', () {
        final badges = parseBadges();
        expect(lines.length, equals(24),
            reason: '노선 수가 바뀌었다 — 요구사항(24개 노선)과 배지 정책을 재확인할 것');
        expect(badges.length, equals(lines.length * 2),
            reason: '정규식이 배지 마크업 형태를 못 읽었거나 배지 수가 다르다');
        for (final line in lines) {
          final mine =
              badges.where((b) => b['lineId'] == line['id']).toList();
          expect(mine.length, equals(2), reason: '${line['id']} 배지 수');
          for (final b in mine) {
            expect(b['text'], equals(kLineBadgeNames[line['id']] ?? line['name']),
                reason: '${line['id']} 배지 문구는 축약표(kLineBadgeNames) 우선, 없으면 lines.json name');
          }
        }
      });

      test('긴 노선명 축약표는 사용자 승인 2건뿐이다 — 김포골드·우이신설', () {
        // ⛔ 축약은 **사용자 승인 사안**이다. 배치가 빡빡하다는 이유로 임의로 늘리지 말 것.
        // 한때 '2'→"2호", '수인분당'→"수인분당", '우이신설'→"우이" 까지 줄여 앵커 상한을 16px 로
        // 맞춘 적이 있는데(2026-10-06 fix5), "2호" 는 다른 노선이 전부 "N호선" 인 가운데 혼자
        // 표기가 깨지고 아무도 그렇게 부르지 않아 **철회**했다. 대신 앵커 상한을 24px 로 두면
        // 공식 명칭 그대로도 미해결 0 이고, 겹침 수치는 오히려 더 좋다(타 노선 선 스침 53.5px→3.5px).
        // 의정부경전철은 "의정부" 가 실제 역명이라 축약 자체가 불가능하다 — 게이트가 막는다.
        const expected = {
          '김포골드': ('김포골드', 60.0), // 배치: lines.json "김포골드라인" 84px → 60px
          '우이신설': ('우이신설', 60.0), // 가독성: "우이신설경전철" 7자 → 4자 (전 배지 최장이었다)
        };
        expect(kLineBadgeNames,
            equals({for (final e in expected.entries) e.key: e.value.$1}));
        for (final entry in expected.entries) {
          final got =
              parseBadges().where((b) => b['lineId'] == entry.key).toList();
          expect(got.length, equals(2), reason: '${entry.key} 양 종점');
          for (final b in got) {
            expect(b['text'], equals(entry.value.$1));
            expect(b['w'], equals(entry.value.$2), reason: '글자 폭 합 + 좌우 패딩 12');
          }
        }
        for (final b in parseBadges()
            .where((b) => !kLineBadgeNames.containsKey(b['lineId']))) {
          final line = lines.firstWhere((l) => l['id'] == b['lineId']);
          expect(b['text'], equals(line['name']), reason: '${b['lineId']} 는 축약하지 않는다');
        }
      });

      test('배지 문구는 어떤 실제 역명과도 같지 않다 (역명 라벨로 오독 방지)', () {
        final stationNames = {
          for (final s in stations) (s['name'] as String).replaceAll(RegExp(r'\s+'), ''),
        };
        for (final b in parseBadges()) {
          expect(stationNames.contains((b['text'] as String).replaceAll(RegExp(r'\s+'), '')),
              isFalse, reason: '${b['lineId']} 배지 "${b['text']}" 가 역명과 같다');
        }
      });

      test('배지↔종점 연결선(줄기)은 하나도 없다 — 생성물에 배지 <line> 0개', () {
        // 사용자 결정(2026-10-06): 줄기는 노선 선과 굵기·색이 같아 "존재하지 않는 지선"으로 읽힌다.
        // 점선·짧은 선·화살표 등 어떤 형태로도 되살리지 않는다 — 배지 그룹 안에 <line> 이 없어야 한다.
        final start = htmlContent.indexOf('<g id="line-badges">');
        expect(start, greaterThan(0), reason: '배지 그룹을 못 찾았다');
        final end = htmlContent.indexOf('</g>\n</g>', start);
        final group = htmlContent.substring(start, end > 0 ? end : htmlContent.length);
        expect(group, isNot(contains('<line')), reason: '배지 그룹 안에 <line> 줄기');
        expect(group, isNot(contains('<path')), reason: '배지 그룹 안에 <path> 연결선');
        expect(group, isNot(contains('stroke-dasharray')), reason: '점선 연결선');
        expect(RegExp(r'<g class="lb"[^>]*>').allMatches(group).length, equals(48));
        // 배지 한 개는 <rect> 1 + <text> 1 로만 이뤄진다.
        expect(RegExp(r'<rect ').allMatches(group).length, equals(48));
        expect(RegExp(r'<text ').allMatches(group).length, equals(48));
      });

      test('줄기가 없으므로 pill 은 앵커(노선 선 끝점)에 붙어 있다 — 앵커↔pill 실제 최단 거리 24px 이하', () {
        // 귀속 단서가 "인접성"(+색)뿐이다. 기준 16 = 줄기 제거 직전 줄기 없이 놓이던 32개 배지의 최대(15.3px) 바로 위.
        final dists = <double>[];
        final manual = manualAnchors();
        for (final b in parseBadges()) {
          // 앵커가 원점인 좌표계에서 사각형까지의 거리.
          final x = b['x'] as double, y = b['y'] as double;
          final w = b['w'] as double, h = b['h'] as double;
          final dx = math.max(math.max(x, -(x + w)), 0.0);
          final dy = math.max(math.max(y, -(y + h)), 0.0);
          final d = math.sqrt(dx * dx + dy * dy);
          dists.add(d);
          // 수동 보정 배지는 상한 적용 대상이 아니다(빌드도 경고만 낸다).
          if (manual.contains(anchorKey(b['lineId'] as String, b['ax'] as double, b['ay'] as double))) continue;
          expect(d, lessThanOrEqualTo(24.0),
              reason: '${b['lineId']} 배지가 앵커에서 ${d.toStringAsFixed(1)}px — 연결선 없이 멀리 띄우면 귀속이 모호하다');
        }
        expect(dists.length, equals(48));
        final r = run(); // 보정 없는 자동 배치 알고리즘 자체의 상한
        expect(r.maxAnchorDistPx, lessThanOrEqualTo(24.0));
        expect(r.anchorDistsPx.length, equals(48));
        // 생성물(= 커밋된 보정으로 빌드된 map.html) 독립 계측과 같은 보정으로 돌린 빌드 로그 통계가 일치한다.
        expect(runWithFile().maxAnchorDistPx, closeTo(dists.reduce(math.max), 0.1));
        expect(r.summary.any((l) => l.contains('줄기(배지↔종점 연결선): 없음')), isTrue);
      });

      test('종점 선정 결과를 고정한다 — 알려진 함정 케이스(지선·순환·분리 노선)', () {
        // 이 단언이 이 기능의 핵심 알고리즘(hop 지름 양 끝)을 지킨다. 앵커-근접 테스트는
        // "마천 vs 하남검단산" 같은 오판도 통과시키므로 역명으로 직접 못 박는다.
        final names = run().terminalNames;
        expect(names['1']!.toSet(), equals({'연천', '신창'}),
            reason: 'stationIds 첫/끝(연천/광명)이 아니라 본선 양 끝');
        expect(names['2']!.toSet(), equals({'까치산', '신설동'}),
            reason: '순환선: 그래프의 차수 1 노드 = 두 지선 끝');
        expect(names['5']!.toSet(), equals({'방화', '하남검단산'}),
            reason: '유클리드 최원점이면 마천(지선)이 이긴다');
        expect(names['6']!.toSet(), equals({'신내', '독바위'}),
            reason: '차수 1 후보가 신내 하나뿐 → 전 노드 폴백(응암루프 반대 끝)');
        expect(names['GTX-A']!.toSet(), equals({'운정중앙', '동탄'}),
            reason: '분리 노선 오버라이드(서울역·수서 허브 회피)');
        expect(names['경의중앙']!.toSet(), equals({'임진강', '지평'}),
            reason: '서울역 지선 제외');
        // 모든 노선이 정확히 2개의 서로 다른 종점을 갖는다.
        for (final e in names.entries) {
          expect(e.value.length, equals(2), reason: e.key);
          expect(e.value.toSet().length, equals(2), reason: '${e.key} 종점 중복');
        }
      });

      test('배지 색은 지도에 보이는 SVG 선 색이다 (lines.json colorValue 가 아니다)', () {
        for (final b in parseBadges()) {
          final m = RegExp(
                  '<path\\b[^>]*stroke="(#[0-9a-fA-F]{6})"[^>]*data-line="${RegExp.escape(b['code'] as String)}"')
              .firstMatch(svg);
          expect(m, isNotNull, reason: 'data-line ${b['code']} 경로 없음');
          expect(b['fill'], equals(m!.group(1)!.toLowerCase()),
              reason: '${b['lineId']} 배지 색이 SVG 선 색과 다르다');
        }
      });

      test('글자색: 흰 글씨 대비 3:1 미만(AA-large 미달)만 짙은 글씨, 나머지는 흰 글씨 유지', () {
        // WCAG 상대휘도 기준을 테스트에서 독립적으로 다시 계산해 구현과 대조한다.
        double lin(int c) {
          final v = c / 255;
          return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        }

        double lum(String hex) {
          final h = hex.substring(1);
          int p(int i) => int.parse(h.substring(i, i + 2), radix: 16);
          return 0.2126 * lin(p(0)) + 0.7152 * lin(p(2)) + 0.0722 * lin(p(4));
        }

        double whiteContrast(String hex) => 1.05 / (lum(hex) + 0.05);

        final dark = <String>{};
        for (final b in parseBadges()) {
          final fill = b['fill'] as String;
          final cr = whiteContrast(fill);
          if (cr < 3.0) {
            dark.add(b['lineId'] as String);
            expect(b['textFill'], equals('#1f1f1f'),
                reason: '${b['lineId']} 흰 글씨 대비 ${cr.toStringAsFixed(2)} < 3.0');
            expect(contrastRatio(fill, '#1f1f1f'), greaterThanOrEqualTo(4.5),
                reason: '${b['lineId']} 짙은 글씨는 AA(4.5)를 넘겨야 의미가 있다');
          } else {
            // AA(4.5) 미달이어도 흰 글씨 유지 — 노선색+흰 글씨 관습(사용자 결정).
            expect(b['textFill'], equals('#ffffff'),
                reason: '${b['lineId']} 흰 글씨 대비 ${cr.toStringAsFixed(2)} >= 3.0 → 흰 글씨');
          }
        }
        // 현 SVG 에서 전환되는 노선을 고정한다(인천1 3.01 은 아슬하게 흰 글씨 유지).
        expect(dark, equals({'수인분당', '6', '인천2'}));
        // 구현의 대비 계산이 독립 계산과 일치한다.
        for (final b in parseBadges()) {
          expect(contrastRatio(b['fill'] as String, '#ffffff'),
              closeTo(whiteContrast(b['fill'] as String), 1e-9));
        }
      });

      test('contrastRatio/badgeTextColorFor 경계값', () {
        expect(contrastRatio('#ffffff', '#000000'), closeTo(21, 1e-9));
        expect(contrastRatio('#123456', '#123456'), closeTo(1, 1e-9));
        expect(badgeTextColorFor('#000000'), equals('#ffffff'));
        expect(badgeTextColorFor('#ffffff'), equals('#1f1f1f'));
        expect(badgeTextColorFor('#d08d1a'), equals('#1f1f1f')); // 6호선 2.80
        expect(badgeTextColorFor('#6496df'), equals('#ffffff')); // 인천1 3.01
        expect(badgeTextColorFor('#10a643'), equals('#ffffff')); // 2호선 3.20(AA 미달·유지)
        // 3.0 을 기준으로 정확히 갈린다: 임계 바로 위/아래 회색.
        String? firstDark;
        for (var v = 0; v <= 255; v++) {
          final hex = '#${v.toRadixString(16).padLeft(2, '0') * 3}';
          if (badgeTextColorFor(hex) == '#1f1f1f') {
            firstDark = hex;
            break;
          }
        }
        expect(firstDark, isNotNull);
        expect(contrastRatio(firstDark!, '#ffffff'), lessThan(3.0));
      });

      test('JS lineIdToDataLine 과 배지 data-code 가 같은 매핑(단일 소스)이다', () {
        final js = RegExp(r"var lineIdToDataLine = \{([^}]*)\}")
            .firstMatch(htmlContent)!
            .group(1)!;
        final jsMap = {
          for (final m in RegExp(r"'([^']+)': \['([^']+)'\]").allMatches(js))
            m.group(1)!: m.group(2)!,
        };
        expect(jsMap, equals(kLineIdToDataLine));
        for (final b in parseBadges()) {
          expect(b['code'], equals(kLineIdToDataLine[b['lineId']]));
        }
      });

      test('JS 상수(TEXT_BASE_FONT_SIZE/TEXT_COMP_FLOOR/CANVAS)가 Dart 단일 소스에서 주입된다', () {
        expect(htmlContent,
            contains('var TEXT_BASE_FONT_SIZE = ${jsNum(kTextBaseFontSize)};'));
        expect(htmlContent,
            contains('var TEXT_COMP_FLOOR = $kTextCompFloorNum / $kTextCompFloorDen;'));
        expect(htmlContent,
            contains('var CANVAS_W = ${jsNum(kCanvasW)}, CANVAS_H = ${jsNum(kCanvasH)};'));
        expect(kTextCompMax, closeTo(1 / kTextCompFloor, 1e-12));
        // 배지 CSS 글자 크기도 Dart 상수에서 온다.
        expect(htmlContent, contains('font-size: ${jsNum(kBadgeFontPx)}px !important;'));
      });

      test('배지는 캔버스(2416x1560) 안에 있고 서로 겹치지 않는다 (배지는 줌아웃 보정 없이 1배 고정)', () {
        final rects = <String, List<double>>{};
        var i = 0;
        for (final b in parseBadges()) {
          final x0 = (b['ax'] as double) + (b['x'] as double);
          final y0 = (b['ay'] as double) + (b['y'] as double);
          final x1 = x0 + (b['w'] as double);
          final y1 = y0 + (b['h'] as double);
          expect(x0, greaterThanOrEqualTo(0), reason: '${b['lineId']} 좌측');
          expect(y0, greaterThanOrEqualTo(0), reason: '${b['lineId']} 상단');
          expect(x1, lessThanOrEqualTo(kCanvasW), reason: '${b['lineId']} 우측');
          expect(y1, lessThanOrEqualTo(kCanvasH), reason: '${b['lineId']} 하단');
          rects['${i++}:${b['lineId']}'] = [x0, y0, x1, y1];
        }
        final keys = rects.keys.toList();
        for (var a = 0; a < keys.length; a++) {
          for (var c = a + 1; c < keys.length; c++) {
            final r = rects[keys[a]]!, s = rects[keys[c]]!;
            final overlap = r[0] < s[2] && s[0] < r[2] && r[1] < s[3] && s[1] < r[3];
            expect(overlap, isFalse, reason: '${keys[a]} ↔ ${keys[c]} 배지 겹침');
          }
        }
      });

      test('배지는 타 노선 선 위에 얹히지 않고 중심선에서 0.9px 이상 떨어져 있다', () {
        // 금색 김포골드 pill 이 금갈색 9호선 선 위에 얹혀 "9호선 라벨"로 읽히던 회귀(2차 리뷰 HIGH-1)를
        // 막는 가드. 선 위 겹침은 배치 비용(soft)이 아니라 요구사항(hard)이라 여기서 못 박는다.
        final r = run();
        expect(r.otherLineOverlapPx, lessThan(1),
            reason: '배지 사각형 안을 지나는 타 노선 선 총 길이(px) — 빌드 로그 "배지↔타노선 선"');
        // 줄기 제거 후 격자 사이에서 0.0px 밀착이 실제로 나왔다 — 중심선 판정만으로는 선 굵기(3)가 pill 을 덮는다.
        // 0.9 = 줄기 제거 직전(fix4) 산출물의 최소 이격.
        expect(r.minOtherLineClearancePx, greaterThanOrEqualTo(0.9),
            reason: 'pill 과 타 노선 선 중심선의 최소 이격(px)');
        // 자기 노선 선 위는 허용(종점 바로 옆)이지만 측정은 노출한다.
        expect(r.ownLineOverlapPx, greaterThanOrEqualTo(0));
        // 근접(3px 패딩) 합은 로그용 — 겹침보다 클 수는 있어도 작을 수는 없다.
        expect(r.otherLineNearPx, greaterThanOrEqualTo(r.otherLineOverlapPx));
        expect(r.summary.any((l) => l.contains('배지↔타노선 선')), isTrue,
            reason: '빌드 로그에 타 노선 선 겹침이 출력돼야 한다');
      });

      test('미해결 배지 0개, 환승역 마커(rect)·캔버스 이탈 0건 — 하드 위반이 하나도 남지 않는다', () {
        // 3차 리뷰 MEDIUM-2/3. 잔여 위반은 빌드 실패(StateError)라 반환된 결과의 unresolvedCount 는 항상 0 이다.
        final r = run();
        expect(r.unresolvedCount, equals(0), reason: '하드 위반을 못 피한 배지 수');
        expect(r.stationRectOverlapCount, equals(0), reason: '배지↔환승역 마커(rect) 겹침 수');
        expect(r.canvasEscapeCount, equals(0), reason: '캔버스 이탈 배지 수');
        expect(r.summary.any((l) => l.contains('미해결 배지: 0개')), isTrue,
            reason: '빌드 로그에 미해결 배지 수가 출력돼야 한다');
        expect(r.summary.any((l) => l.contains('배지↔환승역마커(rect) 0건') && l.contains('캔버스 이탈 0건')),
            isTrue, reason: '빌드 로그에 환승역 마커·캔버스 이탈 측정이 출력돼야 한다');
      });

      test('생성물 기준으로도 배지 사각형이 환승역 마커(SVG <rect>)와 겹치지 않는다 (독립 계측)', () {
        // 배치기의 stationRects 파싱과 별개로 SVG 원본 <rect> 를 다시 읽어 산출물 좌표와 대조한다.
        final markers = <List<double>>[];
        for (final m in RegExp(r'<rect\b[^>]*>').allMatches(svg)) {
          double? attr(String n) {
            final a = RegExp('\\b$n="(-?[\\d.]+)"').firstMatch(m.group(0)!);
            return a == null ? null : double.parse(a.group(1)!);
          }

          final x = attr('x'), y = attr('y'), w = attr('width'), h = attr('height');
          if (x != null && y != null && w != null && h != null) markers.add([x, y, x + w, y + h]);
        }
        expect(markers.length, greaterThan(40), reason: '환승역 마커 rect 를 못 읽었다(SVG 형태 변경?)');
        for (final b in autoBadges()) {
          final x0 = (b['ax'] as double) + (b['x'] as double);
          final y0 = (b['ay'] as double) + (b['y'] as double);
          final x1 = x0 + (b['w'] as double), y1 = y0 + (b['h'] as double);
          for (final k in markers) {
            final overlap = x0 < k[2] && k[0] < x1 && y0 < k[3] && k[1] < y1;
            expect(overlap, isFalse, reason: '${b['lineId']} 배지 ↔ 환승역 마커 ${k[0]},${k[1]}');
          }
        }
      });

      test('배지 앵커는 그 노선 역 근처이고, 한 노선의 두 배지는 서로 멀리 떨어져 있다', () {
        // 독립 검증: 빌드 스크립트의 종점 선정 로직과 무관하게 "앵커가 자기 노선의
        // 어느 역에서 100px 이내" 이고 "두 배지가 200px 이상 떨어짐" 만 확인한다.
        final badges = parseBadges();
        final byLine = <String, List<Map<String, dynamic>>>{};
        for (final b in badges) {
          byLine.putIfAbsent(b['lineId'] as String, () => []).add(b);
          final mine =
              stations.where((s) => s['lineId'] == b['lineId']).toList();
          final nearest = mine
              .map((s) {
                final dx = (s['svgX'] as num) - (b['ax'] as double);
                final dy = (s['svgY'] as num) - (b['ay'] as double);
                return (dx * dx + dy * dy).toDouble();
              })
              .reduce((a, c) => a < c ? a : c);
          expect(nearest, lessThanOrEqualTo(100 * 100),
              reason: '${b['lineId']} 배지 앵커가 자기 노선 역에서 100px 넘게 떨어짐');
        }
        for (final e in byLine.entries) {
          final a = e.value[0], c = e.value[1];
          final dx = (a['ax'] as double) - (c['ax'] as double);
          final dy = (a['ay'] as double) - (c['ay'] as double);
          expect(dx * dx + dy * dy, greaterThan(200 * 200),
              reason: '${e.key} 의 두 배지가 같은 끝에 몰렸다 — 양 종점이 아니다');
        }
      });

      test('배지는 #text-layer 안에 있고 역명 라벨/탭 대상으로 오인되지 않는다', () {
        final textLayerStart = htmlContent.indexOf('id="text-layer"');
        final textLayerEnd = htmlContent.indexOf('</svg>', textLayerStart);
        final layer = htmlContent.substring(textLayerStart, textLayerEnd);
        expect(layer, contains('id="line-badges"'));
        // 배지 마크업은 라벨 뒤(위)에 그려진다.
        expect(layer.indexOf('id="line-badges"'),
            greaterThan(layer.lastIndexOf('data-station=')));
        final badgeBlock = layer.substring(layer.indexOf('id="line-badges"'));
        // buildTextTargets/highlightLines 가 쓰는 속성이 배지 텍스트에 없어야 한다.
        expect(badgeBlock, isNot(contains('data-station')));
        expect(badgeBlock, isNot(contains('data-line=')));
        // 지도 본문(map-container)에는 배지가 없다.
        final mapEnd =
            htmlContent.indexOf('</div>', htmlContent.indexOf('id="tap-layer"'));
        expect(htmlContent.substring(0, mapEnd), isNot(contains('class="lb"')));
      });

      test('배지는 줌아웃 크기 보정을 받지 않고(--lb-s/.lb-s 없음), 환승 라벨 보정은 그대로다', () {
        // 사용자 결정(2026-10-06): 배지는 지도 좌표계 고정 크기. 라벨 tier 정책(2026-09-22)은 유지.
        expect(htmlContent, isNot(contains('--lb-s')));
        expect(htmlContent, isNot(contains('lb-s')));
        final fnStart = htmlContent.indexOf('function updateTextCompensation()');
        final fnEnd = htmlContent.indexOf('function setInitialView', fnStart);
        final fn = htmlContent.substring(fnStart, fnEnd);
        expect(fn, contains("'--label-fs-major'"));
        expect(fn, contains("'--stroke-w-major'"));
        expect(fn.split('setProperty').length - 1, equals(2),
            reason: 'updateTextCompensation 은 라벨용 프로퍼티 2개만 쓴다');
      });

      test('배지 CSS: 입력 비가로채기 + 레이어 승격 없음', () {
        expect(htmlContent,
            matches(RegExp(r'#text-layer \.lb \{ pointer-events: none; \}')));
        final cssStart = htmlContent.indexOf('#text-layer .lb { pointer-events');
        final cssEnd = htmlContent.indexOf('#text-layer .lb rect', cssStart);
        expect(cssEnd, greaterThan(cssStart));
        expect(htmlContent.substring(cssStart, cssEnd),
            isNot(contains('will-change')),
            reason: '정적 48개 요소에 레이어 승격을 쓰지 않는다(래스터 기아 이력)');
        expect(htmlContent, isNot(contains('transform: scale(var(')));
      });

      test('경로 강조 시 선택되지 않은 노선의 배지도 흐려진다', () {
        final fnStart = htmlContent.indexOf('window.highlightLines = function');
        final fnEnd = htmlContent.indexOf('window.clearLineHighlight', fnStart);
        final fn = htmlContent.substring(fnStart, fnEnd);
        expect(fn, contains(".lb[data-code]"));
        expect(fn, contains('codeSet[lineBadgeEls[i].getAttribute(\'data-code\')]'));
      });

      group('buildLineBadges 는 데이터가 어긋나면 조용히 통과하지 않고 실패한다', () {
        test('정상 입력은 통과하고 48개를 낸다', () {
          expect(run().badgeCount, equals(48));
        });

        test('(1) 노선이 하나 사라지면(매핑과 불일치) 실패', () {
          expect(() => run(ln: lines.sublist(1)), stateErrorWith('불일치'));
        });

        test('(2) 경강선 역 좌표를 엉뚱한 곳으로 옮기면 기하 검증이 실패(보조 검증)', () {
          final moved = [
            for (final s in stations)
              s['lineId'] == '경강' ? {...s, 'svgX': 5.0, 'svgY': 5.0} : s,
          ];
          expect(() => run(st: moved), stateErrorWith('기하 검증 실패'));
        });

        test('(2b) 매핑이 뒤바뀌면(경춘↔경강) 라벨 대조(주 검증)가 먼저 잡는다', () {
          final swapped = {
            ...kLineIdToDataLine,
            '경춘': kLineIdToDataLine['경강']!,
            '경강': kLineIdToDataLine['경춘']!,
          };
          expect(() => run(codes: swapped), stateErrorWith('라벨 대조 실패'));
        });

        test('(3) 오버라이드 없는 노선이 끊기면 실패 — 3호선 충무로~동대입구 엣지 제거', () {
          final a = idOf('충무로', '3'), b = idOf('동대입구', '3');
          final cut = [
            for (final c in conns)
              if (!(c['lineId'] == '3' &&
                  {c['fromStationId'], c['toStationId']}.containsAll({a, b})))
                c,
          ];
          expect(cut.length, equals(conns.length - 1), reason: '엣지 1개만 제거돼야 한다');
          expect(() => run(cn: cut), stateErrorWith('둘 이상의 구간으로 끊겨'));
        });

        test('(4) 오버라이드 역이 더 이상 종점(차수 1)이 아니면 실패 — 동탄에 가상 엣지', () {
          final extended = [
            ...conns,
            {'lineId': 'GTX-A', 'fromStationId': idOf('동탄', 'GTX-A'),
             'toStationId': idOf('성남', 'GTX-A'),
             'travelTimeSeconds': 60, 'isTransfer': false},
          ];
          expect(() => run(cn: extended), stateErrorWith('더 이상 종점'));
        });

        test('(5) 오버라이드 노선이 연결되면 실패 — 오버라이드를 지우도록 강제', () {
          final joined = [
            ...conns,
            {'lineId': 'GTX-A', 'fromStationId': idOf('서울역', 'GTX-A'),
             'toStationId': idOf('수서', 'GTX-A'),
             'travelTimeSeconds': 60, 'isTransfer': false},
          ];
          expect(() => run(cn: joined), stateErrorWith('이제 연결돼 있다'));
        });

        test('(6) 오버라이드 두 역이 같은 구간이면 실패', () {
          expect(
            () => run(overrides: {'GTX-A': ['운정중앙', '서울역']}),
            stateErrorWith('같은 구간'),
          );
        });

        test('(7) 오버라이드가 lines.json 에 없는 노선을 가리키면 실패', () {
          expect(
            () => run(overrides: {...kBadgeTerminalOverrides, '없는노선': ['가', '나']}),
            stateErrorWith('lines.json 에 없다'),
          );
        });

        test('(8) 오버라이드 역명이 노선에 없으면 실패', () {
          expect(
            () => run(overrides: {'GTX-A': ['없는역', '동탄']}),
            stateErrorWith('정확히 1건이 아님'),
          );
        });

        test('(9) 배지 문구가 실제 역명과 같으면 실패 — 의정부경전철 → 의정부(의정부역 실존)', () {
          expect(
            () => run(names: {...kLineBadgeNames, '의정부': '의정부'}),
            stateErrorWith('실제 역명과 같다'),
          );
        });

        test('(9b) 공백이 섞여도 역명과 같으면 실패 — "의 정 부"', () {
          expect(
            () => run(names: {...kLineBadgeNames, '의정부': '의 정 부'}),
            stateErrorWith('실제 역명과 같다'),
          );
        });

        test('(9c) 축약하지 않은 노선의 원래 이름이 역명과 같아져도 실패 — 나중에 역이 추가된 상황', () {
          // "김포골드" 라는 이름의 역이 새로 생기면, 축약 문구(김포골드)가 곧바로 충돌한다.
          final withNewStation = [
            ...stations,
            {...stations.first, 'id': 'ZZ99', 'name': '김포골드', 'lineId': '1'},
          ];
          expect(() => run(st: withNewStation), stateErrorWith('실제 역명과 같다'));
        });

        test('(10) 축약표가 lines.json 에 없는 노선을 가리키면 실패', () {
          expect(
            () => run(names: {...kLineBadgeNames, '없는노선': '없음'}),
            stateErrorWith('lines.json 에 없다'),
          );
        });

        test('(11) 축약 문구가 비어 있으면 실패', () {
          expect(
            () => run(names: {...kLineBadgeNames, '의정부': '  '}),
            stateErrorWith('비어 있다'),
          );
        });

        test('(12) 두 노선이 같은 문구로 축약되면 실패 — 의정부·우이신설 → "경전철"', () {
          expect(
            () => run(names: {...kLineBadgeNames, '의정부': '경전철', '우이신설': '경전철'}),
            stateErrorWith('배지 문구가 같다'),
          );
        });

        test('(12b) 축약 문구가 다른 노선의 (축약 안 한) 이름과 같아도 실패', () {
          // 김포골드 → "의정부경전철" 은 lines.json 의 의정부 노선 이름 그대로다.
          final uijeongbu = lines.firstWhere((l) => l['id'] == '의정부')['name'] as String;
          expect(
            () => run(names: {'김포골드': uijeongbu}),
            stateErrorWith('배지 문구가 같다'),
          );
        });

        test('(12c) 공백만 다른 문구도 같은 문구로 본다 — "경 전 철" vs "경전철"', () {
          expect(
            () => run(names: {...kLineBadgeNames, '의정부': '경 전 철', '우이신설': '경전철'}),
            stateErrorWith('배지 문구가 같다'),
          );
        });

        test('(13) 역명 충돌 메시지에 출처(stations.json 의 어느 역인지)가 들어간다', () {
          final withNewStation = [
            ...stations,
            {...stations.first, 'id': 'ZZ99', 'name': '김포골드', 'lineId': '1'},
          ];
          expect(() => run(st: withNewStation), stateErrorWith('stations.json 역 "김포골드"(id ZZ99'));
        });

        test('(15) 공식 명칭 그대로도 전 노선이 풀린다 — 축약은 승인 2건으로 충분하다', () {
          // 줄기(연결선)로 멀리 보내는 길이 막혀 있어도, 앵커 상한 24px 면 신설동("2호선" 44px)·
          // 청량리("수인분당선" 72px) 허브가 공식 명칭 그대로 풀린다. 한때 상한을 16px 로 잡고
          // '2'→"2호" 까지 줄였다가, 다른 노선이 전부 "N호선" 인데 혼자 표기가 깨져 철회한 경위가
          // [_kMaxAnchorDist] 주석에 있다. 이 테스트는 "축약을 더 늘릴 필요가 없다"를 고정한다.
          final r = run();
          expect(r.unresolvedCount, equals(0));
          expect(r.maxAnchorDistPx, lessThanOrEqualTo(24.0));
          final texts = RegExp(r'>([^<>]+)</text>')
              .allMatches(r.svgFragment)
              .map((m) => m.group(1)!)
              .toSet();
          // 승인 2건 외에는 lines.json 의 name 이 그대로 나와야 한다.
          expect(texts, contains('2호선'));
          expect(texts, contains('수인분당선'));
          expect(texts, isNot(contains('2호')));
        });

        test('(14) 하드 위반을 못 피하는 배지가 있으면 빌드 실패 — 종점 주변을 환승역 마커로 막음', () {
          // 김포골드 첫 배지 앵커 주변 ±150px 를 덮는 rect 를 SVG 에 추가하면 앵커 16px 안의 모든 후보가
          // 환승역 마커와 겹친다 → 미해결. (이 변이는 rect 가 하드 위반 집합에 있다는 증거이기도 하다.)
          final frag = run().svgFragment;
          final m = RegExp(r'data-badge-line="김포골드"[^>]*transform="translate\(([\d.]+),([\d.]+)\)"')
              .firstMatch(frag)!;
          final ax = double.parse(m.group(1)!), ay = double.parse(m.group(2)!);
          final blocked = svg.replaceFirst(
            '</svg>',
            '<rect x="${ax - 150}" y="${ay - 150}" width="300" height="300" fill="none"/></svg>',
          );
          expect(blocked, isNot(equals(svg)), reason: '변이 SVG 가 만들어지지 않았다');
          expect(
            () => buildLineBadges(
              svgContent: blocked,
              stationsJson: stations,
              linesJson: lines,
              connectionsJson: conns,
              transferStationNames: transfer,
            ),
            throwsA(isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('미해결 배지'), contains('김포골드'), contains('환승역 마커('),
                  contains('조치')),
            )),
          );
        });
      });
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
