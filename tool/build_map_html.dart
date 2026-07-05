/// 원본 SVG를 HTML 템플릿에 인라인 삽입하여 WebView용 map.html을 생성하는 스크립트.
///
/// 입력: assets/svg/seoul_metro_map.svg
/// 출력: assets/html/map.html
///
/// SVG 최소 변환:
/// - width="100%" height="100%" → width="2416" height="1560"
/// - style="background: white;" 제거
///
/// 사용법: dart run tool/build_map_html.dart
///
/// ⛔ 실시간 열차 애니메이션 4원칙 — 변경 금지 (CLAUDE.md 최상위 정책)
///   이 파일의 `estimateTrainPosition`, `startTrainAnimation`, `showTrains`,
///   `expandPathWithSnap(stationIndices)` 는 4원칙을 구현하는 핵심 코드다.
///   수정 전 반드시 CLAUDE.md 의 "실시간 열차 애니메이션 4원칙" 섹션을 확인하고,
///   원칙을 유지한 채 필요한 최소 변경만 가해야 한다. 원칙 자체를 바꾸려면
///   사용자 승인이 필요하다.
///   - 원칙 1: recptnDt 기반 realRemaining + 단조 감소 clamp
///   - 원칙 2: estimateTrainPosition — 뒤에서부터 역산
///   - 원칙 3: stationIndices 기반 3-way 클램프 (현재역 ↔ 다음역 안에만 머뭄)
///   - 원칙 4: HALF_LIFE_MS 지수 감쇠 catch-up (refresh 시 점프 방지).
///       예외 — 역 전환(stationChanged) 또는 path 시작점 점프(headMoved>8px) 시
///       `existing.currentPos = null` 로 리셋해 다음 frame 에서 새 target 으로 즉시
///       초기화. 이건 "API 지터 흡수"라는 원칙 4 의 의도에 반하지 않음 — 실제
///       열차가 다음 역으로 진행한 상황까지 catch-up 을 끌고 가면 stale 좌표가
///       SVG 선과 분리되어 "탈선처럼 보임" (사용자 보고). showTrains 의 existing-
///       train 분기 참조.
library;

import 'dart:convert';
import 'dart:io';

void main() {
  const svgPath = 'assets/svg/seoul_metro_map.svg';
  const htmlPath = 'assets/html/map.html';

  final svgFile = File(svgPath);
  if (!svgFile.existsSync()) {
    stderr.writeln('입력 파일 없음: $svgPath');
    exit(1);
  }

  var svgContent = svgFile.readAsStringSync();

  // SVG 최소 변환
  svgContent = svgContent.replaceFirst(
    'width="100%" height="100%"',
    'width="2416" height="1560"',
  );
  svgContent = svgContent.replaceFirst(
    RegExp(r'\s*style="background:\s*white;"'),
    '',
  );

  // 열차 이미지 Base64 인코딩
  const trainImagePath = 'assets/images/train.webp';
  final trainImageFile = File(trainImagePath);
  if (!trainImageFile.existsSync()) {
    stderr.writeln('열차 이미지 없음: $trainImagePath');
    exit(1);
  }
  final trainImageBase64 = base64Encode(trainImageFile.readAsBytesSync());

  final html = _buildHtml(svgContent, trainImageBase64);

  final htmlFile = File(htmlPath);
  htmlFile.parent.createSync(recursive: true);
  htmlFile.writeAsStringSync(html);

  final svgSize = svgFile.lengthSync();
  final htmlSize = htmlFile.lengthSync();

  stdout.writeln('HTML 생성 완료');
  stdout.writeln('  SVG: ${(svgSize / 1024).toStringAsFixed(1)}KB');
  stdout.writeln('  HTML: ${(htmlSize / 1024).toStringAsFixed(1)}KB');
}

String _buildHtml(String svgContent, String trainImageBase64) {
  // text 요소를 별도 레이어로 분리 (줌아웃 시 역명 크기 유지)
  final textPattern = RegExp(r'<text[^>]*>.*?</text>', dotAll: true);
  final textElements =
      textPattern.allMatches(svgContent).map((m) => m.group(0)!).join('\n');
  final mapOnlyContent = svgContent.replaceAll(textPattern, '');

  return '''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body {
  width: 100%; height: 100%;
  overflow: hidden;
  background: #f5f5f5;
  -webkit-user-select: none;
  user-select: none;
  touch-action: none;
}
#map-container {
  position: absolute;
  transform-origin: 0 0;
  will-change: transform;
}
#overlay {
  position: absolute;
  top: 0; left: 0;
  pointer-events: none;
}
#tap-layer {
  position: absolute;
  top: 0; left: 0;
  width: 2416px; height: 1560px;
  pointer-events: auto;
}
.tooltip {
  position: absolute;
  background: white;
  border-radius: 12px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.2);
  padding: 12px;
  pointer-events: auto;
  z-index: 100;
  display: none;
  min-width: 140px;
}
.tooltip-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}
.line-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  color: white;
  font-size: 11px;
  font-weight: bold;
  white-space: nowrap;
}
.station-name {
  font-size: 16px;
  font-weight: bold;
  white-space: nowrap;
}
.close-btn {
  cursor: pointer;
  color: #999;
  font-size: 18px;
  margin-left: 4px;
  pointer-events: auto;
}
.transfer-lines {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
  margin-bottom: 8px;
}
.transfer-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 3px;
  color: white;
  font-size: 9px;
  white-space: nowrap;
}
.actions {
  display: flex;
  gap: 12px;
  justify-content: center;
}
.action-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  cursor: pointer;
  pointer-events: auto;
  border: none;
  background: none;
  padding: 4px;
}
.action-btn .icon {
  width: 20px; height: 20px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  margin-bottom: 2px;
}
.action-btn .label {
  font-size: 10px;
}
#text-layer {
  position: absolute;
  top: 0; left: 0;
  width: 100%; height: 100%;
  pointer-events: none;
  overflow: hidden;
}
#text-layer text {
  font-size: inherit !important;
  font-weight: 800;
  stroke: white;
  stroke-width: var(--stroke-w, 2px);
  paint-order: stroke;
  stroke-linejoin: round;
}
#train-layer {
  position: absolute;
  top: 0; left: 0;
  width: 100%; height: 100%;
  pointer-events: none;
  overflow: hidden;
}
path[data-line] { stroke-width: 5 !important; }
/* GTX-A 등 이중선 노선의 흰색 테두리(원본 1px)가 본체 색상을 덮지 않도록 유지 */
path[data-line][stroke="#ffffff"] { stroke-width: 1 !important; }
path[data-line], text[data-line], circle, rect:not(#route-overlay-bg) {
  transition: opacity 0.3s;
}
.dimmed {
  opacity: 0.12;
}
.route-toolbar {
  position: absolute;
  display: none;
  flex-direction: column;
  z-index: 99;
  pointer-events: auto;
  background: white;
  border-radius: 14px;
  box-shadow: 0 2px 12px rgba(0,0,0,0.18);
  padding: 4px;
  padding-top: 28px;
  gap: 2px;
  /* 드래그 핸들: 상단 28px 빈 바(X 버튼 왼쪽 영역)를 잡아 툴바 이동 */
  cursor: move;
  touch-action: none;
  -webkit-user-select: none;
  user-select: none;
}
.route-toolbar-btn {
  display: block;
  width: 100%;
  padding: 7px 16px;
  border-radius: 10px;
  border: none;
  background: none;
  font-size: 13px;
  font-weight: 500;
  color: #666;
  cursor: pointer;
  pointer-events: auto;
  transition: all 0.2s;
  white-space: nowrap;
  text-align: center;
}
.route-toolbar-btn.active {
  background: #2196F3;
  color: white;
  font-weight: 600;
}
.route-toolbar-btn.close-btn {
  position: absolute;
  top: 2px;
  right: 2px;
  width: auto;
  padding: 2px 8px;
  color: #999;
  font-size: 16px;
  font-weight: bold;
  border-radius: 10px;
}
</style>
</head>
<body>
<div id="map-container">
$mapOnlyContent
<svg id="overlay" xmlns="http://www.w3.org/2000/svg" width="2416" height="1560">
  <rect id="route-overlay-bg" width="2416" height="1560" fill="white" opacity="0" />
  <g id="route-lines"></g>
  <g id="route-markers"></g>
  <g id="selection-markers"></g>
</svg>
<div id="tap-layer"></div>
</div>

<svg id="text-layer" xmlns="http://www.w3.org/2000/svg"
  viewBox="0 0 2416 1560">
$textElements
</svg>

<svg id="train-layer" xmlns="http://www.w3.org/2000/svg"
  viewBox="0 0 2416 1560">
  <g id="live-trains"></g>
</svg>

<div id="tooltip" class="tooltip"></div>
<div id="route-toolbar" class="route-toolbar"></div>

<script>
(function() {
  'use strict';

  // ============================================================
  // 상수
  // ============================================================
  var CANVAS_W = 2416, CANVAS_H = 1560;
  var MIN_SCALE = 0.5, MAX_SCALE = 5.0;
  var TAP_RADIUS = 12;
  var TEXT_BASE_FONT_SIZE = 12;
  var TEXT_BASE_STROKE_W = 2;
  var INITIAL_SCALE = 1.0;
  var INITIAL_CENTER_X = 1040, INITIAL_CENTER_Y = 618;
  var TRAIN_IMG = 'data:image/webp;base64,$trainImageBase64';

  // ============================================================
  // 상태
  // ============================================================
  var scale = INITIAL_SCALE;
  var tx = 0, ty = 0;
  var stations = [];
  var connections = [];
  var lineColors = {};
  var lineNames = {};
  var stationLineMap = {};
  var stationMap = {};       // stationId → station 객체
  var waypointIndex = {};    // "fromId_toId" → [{x,y}, ...] (중간점 포함 좌표 배열)

  var rafPending = false;
  function scheduleTransform() {
    if (rafPending) return;
    rafPending = true;
    requestAnimationFrame(function() {
      rafPending = false;
      applyTransform();
    });
  }

  var container = document.getElementById('map-container');
  var tapLayer = document.getElementById('tap-layer');
  var tooltip = document.getElementById('tooltip');
  var routeToolbar = document.getElementById('route-toolbar');
  var toolbarSvgX = 0, toolbarSvgY = 0;
  var toolbarVisible = false;
  var cachedTbW = 0, cachedTbH = 0;
  var overlayBg = document.getElementById('route-overlay-bg');
  var routeLines = document.getElementById('route-lines');
  var routeMarkers = document.getElementById('route-markers');
  var selectionMarkers = document.getElementById('selection-markers');
  var liveTrainsGroup = document.getElementById('live-trains');
  var activeTrains = {};
  var arrivedTrains = {};
  // [원칙 1 보강] 보조키 기반 단조 감소 메모리.
  // trainNo 가 흔들리는 노선(신분당선 등 btrainNo 미제공) 에서도 단조 감소 clamp 가
  // 작동하도록 (lineId|direction|destination|currentStation) 슬롯별로 마지막 prev
  // 정보를 60초 TTL 로 보존한다. activeTrains[trainNo] 매칭 miss 시에만 보조 매칭 사용.
  var trainSlotMemory = {};
  var SVG_NS = 'http://www.w3.org/2000/svg';
  var textLayer = document.getElementById('text-layer');
  var trainLayer = document.getElementById('train-layer');

  // ============================================================
  // 변환 적용
  // ============================================================
  function applyTransform() {
    container.style.transform = 'matrix(' + scale + ',0,0,' + scale + ',' + tx + ',' + ty + ')';

    // 텍스트 레이어: viewBox로 맵과 동일 영역 표시
    var vw = window.innerWidth, vh = window.innerHeight;
    var x0 = -tx / scale, y0 = -ty / scale;
    var vbW = vw / scale, vbH = vh / scale;
    textLayer.setAttribute('viewBox', x0 + ' ' + y0 + ' ' + vbW + ' ' + vbH);
    // 열차 레이어: text-layer와 동일한 viewBox 동기화로 map-container와 같은
    // 화면 매핑을 만든다 (좌표/크기는 그대로, z-order만 text-layer 위로 분리).
    // font-size/stroke 보정(아래)은 텍스트 전용이므로 trainLayer에는 적용하지 않는다.
    trainLayer.setAttribute('viewBox', x0 + ' ' + y0 + ' ' + vbW + ' ' + vbH);

    // scale < 1일 때 텍스트 크기/stroke-width 보상 (줌인은 기존대로)
    var cs = Math.min(scale, 1);
    textLayer.style.fontSize = (TEXT_BASE_FONT_SIZE / cs) + 'px';
    textLayer.style.setProperty('--stroke-w', (TEXT_BASE_STROKE_W / cs) + 'px');

    updateRouteToolbarPosition();
  }

  function setInitialView() {
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    tx = vw / 2 - INITIAL_CENTER_X * scale;
    ty = vh / 2 - INITIAL_CENTER_Y * scale;
    applyTransform();
  }

  // ============================================================
  // 터치/마우스 이벤트 (줌/팬)
  // ============================================================
  var pointers = {};
  var lastDist = 0;
  var lastMidX = 0, lastMidY = 0;
  var isDragging = false;
  var dragStartX = 0, dragStartY = 0;
  var dragStartTx = 0, dragStartTy = 0;
  var hasMoved = false;

  function getPointerCount() {
    return Object.keys(pointers).length;
  }

  function getMidpoint() {
    var keys = Object.keys(pointers);
    if (keys.length < 2) return null;
    var p1 = pointers[keys[0]], p2 = pointers[keys[1]];
    return { x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 };
  }

  function getDist() {
    var keys = Object.keys(pointers);
    if (keys.length < 2) return 0;
    var p1 = pointers[keys[0]], p2 = pointers[keys[1]];
    var dx = p2.x - p1.x, dy = p2.y - p1.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function clampTranslation() {
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    var minTx = vw - CANVAS_W * scale - 70;
    var minTy = vh - CANVAS_H * scale - 70;
    tx = Math.min(70, Math.max(minTx, tx));
    ty = Math.min(70, Math.max(minTy, ty));
  }

  document.addEventListener('pointerdown', function(e) {
    panAnimId++;
    pointers[e.pointerId] = { x: e.clientX, y: e.clientY };
    if (getPointerCount() === 1) {
      isDragging = true;
      hasMoved = false;
      dragStartX = e.clientX;
      dragStartY = e.clientY;
      dragStartTx = tx;
      dragStartTy = ty;
    } else if (getPointerCount() === 2) {
      isDragging = false;
      lastDist = getDist();
      var mid = getMidpoint();
      lastMidX = mid.x;
      lastMidY = mid.y;
    }
  });

  document.addEventListener('pointermove', function(e) {
    if (!pointers[e.pointerId]) return;
    pointers[e.pointerId] = { x: e.clientX, y: e.clientY };

    if (getPointerCount() === 1 && isDragging) {
      var dx = e.clientX - dragStartX;
      var dy = e.clientY - dragStartY;
      if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
        hasMoved = true;
        if (tooltip.style.display !== 'none') {
          tooltip.style.display = 'none';
          sendToFlutter({ action: 'dismiss' });
        }
      }
      tx = dragStartTx + dx;
      ty = dragStartTy + dy;
      clampTranslation();
      scheduleTransform();
    } else if (getPointerCount() === 2) {
      hasMoved = true;
      if (tooltip.style.display !== 'none') {
        tooltip.style.display = 'none';
        sendToFlutter({ action: 'dismiss' });
      }
      var dist = getDist();
      var mid = getMidpoint();
      if (lastDist > 0) {
        var newScale = scale * (dist / lastDist);
        newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, newScale));

        // 핀치 중심점 기준으로 줌
        var contentX = (mid.x - tx) / scale;
        var contentY = (mid.y - ty) / scale;
        scale = newScale;
        tx = mid.x - contentX * scale;
        ty = mid.y - contentY * scale;
      }
      // 팬
      tx += mid.x - lastMidX;
      ty += mid.y - lastMidY;

      lastDist = dist;
      lastMidX = mid.x;
      lastMidY = mid.y;

      clampTranslation();
      scheduleTransform();
    }
  });

  document.addEventListener('pointerup', function(e) {
    delete pointers[e.pointerId];
    if (getPointerCount() === 0) {
      isDragging = false;
    } else if (getPointerCount() === 1) {
      // 핀치 → 드래그 전환: 남은 포인터로 드래그 재시작
      var keys = Object.keys(pointers);
      var p = pointers[keys[0]];
      isDragging = true;
      dragStartX = p.x;
      dragStartY = p.y;
      dragStartTx = tx;
      dragStartTy = ty;
    }
  });

  document.addEventListener('pointercancel', function(e) {
    delete pointers[e.pointerId];
  });

  // 마우스 휠 줌
  document.addEventListener('wheel', function(e) {
    e.preventDefault();
    var factor = e.deltaY < 0 ? 1.1 : 0.9;
    var newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale * factor));

    var contentX = (e.clientX - tx) / scale;
    var contentY = (e.clientY - ty) / scale;
    scale = newScale;
    tx = e.clientX - contentX * scale;
    ty = e.clientY - contentY * scale;

    clampTranslation();
    scheduleTransform();
  }, { passive: false });

  // ============================================================
  // 탭 감지 (텍스트 라벨 + circle 좌표 하이브리드)
  // ============================================================
  var svgTextTargets = []; // SVG text 요소의 바운딩 박스

  function buildTextTargets() {
    svgTextTargets = [];
    var texts = textLayer.querySelectorAll('text[data-station]');
    for (var i = 0; i < texts.length; i++) {
      var el = texts[i];
      var name = el.getAttribute('data-station').split('\\n').join('').split('\\r').join('');
      try {
        var bbox = el.getBBox();
        svgTextTargets.push({
          name: name,
          cx: bbox.x + bbox.width / 2,
          cy: bbox.y + bbox.height / 2,
          halfW: bbox.width / 2 + 6,
          halfH: bbox.height / 2 + 6
        });
      } catch(e) {}
    }
  }

  // SVG 렌더링 후 텍스트 타겟 구축
  buildTextTargets();

  function findStationByName(name) {
    for (var i = 0; i < stations.length; i++) {
      if (stations[i].name === name) return stations[i];
    }
    return null;
  }

  tapLayer.addEventListener('pointerup', function(e) {
    if (hasMoved) return;

    // 화면 좌표 → SVG 좌표
    var rect = container.getBoundingClientRect();
    var svgX = (e.clientX - rect.left) / scale;
    var svgY = (e.clientY - rect.top) / scale;

    var nearest = null;

    // 1차: SVG 텍스트 라벨 영역 매칭 (사용자가 보는 역명 기준)
    for (var i = 0; i < svgTextTargets.length; i++) {
      var t = svgTextTargets[i];
      if (Math.abs(svgX - t.cx) <= t.halfW && Math.abs(svgY - t.cy) <= t.halfH) {
        nearest = findStationByName(t.name);
        if (nearest) break;
      }
    }

    // 2차: circle 좌표 기반 근접 매칭 (폴백)
    if (!nearest) {
      var nearestDistSq = TAP_RADIUS * TAP_RADIUS;
      for (var i = 0; i < stations.length; i++) {
        var s = stations[i];
        var dx = s.svgX - svgX;
        var dy = s.svgY - svgY;
        var distSq = dx * dx + dy * dy;
        if (distSq < nearestDistSq) {
          nearestDistSq = distSq;
          nearest = s;
        }
      }
    }

    if (nearest) {
      sendToFlutter({
        action: 'stationTapped',
        stationId: nearest.id,
        stationName: nearest.name
      });
    } else {
      sendToFlutter({ action: 'dismiss' });
    }
  });

  // ============================================================
  // Flutter 통신
  // ============================================================
  function sendToFlutter(data) {
    try {
      if (window.StationChannel) {
        window.StationChannel.postMessage(JSON.stringify(data));
      }
    } catch (err) {
      // 채널 미등록 시 무시
    }
  }

  // ============================================================
  // Flutter에서 호출할 API
  // ============================================================

  // 역/연결 데이터 초기화
  window.initStations = function(stationsJson, connectionsJson, colorsJson, namesJson) {
    stations = JSON.parse(stationsJson);
    connections = JSON.parse(connectionsJson);
    lineColors = JSON.parse(colorsJson);
    lineNames = JSON.parse(namesJson);

    // stationMap 구축 (모듈 스코프)
    stationMap = {};
    for (var i = 0; i < stations.length; i++) {
      stationMap[stations[i].id] = stations[i];
    }

    // 역명 → 소속 노선 lineId 집합 캐시 (환승역 text/circle 매칭용)
    stationLineMap = {};
    for (var i = 0; i < stations.length; i++) {
      var sn = stations[i].name;
      if (!stationLineMap[sn]) stationLineMap[sn] = {};
      stationLineMap[sn][stations[i].lineId] = true;
    }

    // SVG path에서 waypoint 인덱스 구축
    buildWaypointIndex();
  };

  // 경로 하이라이트
  window.highlightRoute = function(routeStationIdsJson) {
    var routeIds = JSON.parse(routeStationIdsJson);
    var routeSet = {};
    for (var i = 0; i < routeIds.length; i++) {
      routeSet[routeIds[i]] = true;
    }

    // 오버레이 배경 활성화
    overlayBg.setAttribute('opacity', '0.6');

    // 기존 경로 초기화
    routeLines.replaceChildren();
    routeMarkers.replaceChildren();

    // 경로 구간 그리기
    for (var i = 0; i < connections.length; i++) {
      var conn = connections[i];
      if (conn.isTransfer) continue;

      var from = stationMap[conn.fromStationId];
      var to = stationMap[conn.toStationId];
      if (!from || !to) continue;

      if (!routeSet[from.id] || !routeSet[to.id]) continue;

      var color = lineColors[conn.lineId] || '#999';

      // waypointIndex에서 중간점 조회
      var key = conn.fromStationId + '_' + conn.toStationId;
      var revKey = conn.toStationId + '_' + conn.fromStationId;
      var wp = waypointIndex[key] || waypointIndex[revKey];

      if (wp && wp.length > 2) {
        // 중간점이 있으면 polyline으로 렌더링
        var pts = '';
        for (var wi = 0; wi < wp.length; wi++) {
          if (wi > 0) pts += ' ';
          pts += wp[wi].x + ',' + wp[wi].y;
        }
        var polyline = document.createElementNS(SVG_NS, 'polyline');
        polyline.setAttribute('points', pts);
        polyline.setAttribute('stroke', color);
        polyline.setAttribute('stroke-width', '5');
        polyline.setAttribute('stroke-linecap', 'round');
        polyline.setAttribute('stroke-linejoin', 'round');
        polyline.setAttribute('fill', 'none');
        routeLines.appendChild(polyline);
      } else {
        // 중간점 없으면 기존 직선 폴백
        var line = document.createElementNS(SVG_NS, 'line');
        line.setAttribute('x1', from.svgX);
        line.setAttribute('y1', from.svgY);
        line.setAttribute('x2', to.svgX);
        line.setAttribute('y2', to.svgY);
        line.setAttribute('stroke', color);
        line.setAttribute('stroke-width', '5');
        line.setAttribute('stroke-linecap', 'round');
        routeLines.appendChild(line);
      }
    }

    // 경로 위 역 마커
    var routeKeys = Object.keys(routeSet);
    for (var ri = 0; ri < routeKeys.length; ri++) {
      var id = routeKeys[ri];
      var s = stationMap[id];
      if (!s) continue;

      var color = lineColors[s.lineId] || '#999';
      var r = s.isTransfer ? 5 : 3.5;

      if (s.isTransfer) {
        var bg = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        bg.setAttribute('cx', s.svgX);
        bg.setAttribute('cy', s.svgY);
        bg.setAttribute('r', r);
        bg.setAttribute('fill', 'white');
        bg.setAttribute('stroke', color);
        bg.setAttribute('stroke-width', '2');
        bg.setAttribute('data-overlay', '');
        routeMarkers.appendChild(bg);
      } else {
        var dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        dot.setAttribute('cx', s.svgX);
        dot.setAttribute('cy', s.svgY);
        dot.setAttribute('r', r);
        dot.setAttribute('fill', color);
        dot.setAttribute('data-overlay', '');
        routeMarkers.appendChild(dot);
      }
    }
  };

  // 경로 하이라이트 제거
  window.clearRoute = function() {
    overlayBg.setAttribute('opacity', '0');
    routeLines.replaceChildren();
    routeMarkers.replaceChildren();
  };

  // 출발/도착 마커 설정
  window.setMarker = function(type, svgX, svgY) {
    var markerId = 'marker-' + type;
    var existing = document.getElementById(markerId);
    if (existing) existing.remove();

    var color = type === 'departure' ? '#2196F3' : '#F44336';
    var g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.setAttribute('id', markerId);

    // 반투명 배경 원
    var bg = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    bg.setAttribute('cx', svgX);
    bg.setAttribute('cy', svgY);
    bg.setAttribute('r', '12');
    bg.setAttribute('fill', color);
    bg.setAttribute('opacity', '0.2');
    bg.setAttribute('data-overlay', '');
    g.appendChild(bg);

    // 테두리 링
    var ring = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    ring.setAttribute('cx', svgX);
    ring.setAttribute('cy', svgY);
    ring.setAttribute('r', '9');
    ring.setAttribute('fill', 'none');
    ring.setAttribute('stroke', color);
    ring.setAttribute('stroke-width', '2.5');
    ring.setAttribute('data-overlay', '');
    g.appendChild(ring);

    selectionMarkers.appendChild(g);
  };

  // 마커 제거
  window.clearMarkers = function() {
    selectionMarkers.replaceChildren();
  };

  // 툴팁 표시 (DOM API로 XSS 방지)
  window.showTooltip = function(stationJson) {
    var s = JSON.parse(stationJson);

    // 기존 내용 제거
    tooltip.textContent = '';

    // 헤더: 역명 + X 만 (호선 배지는 모두 하단으로 이동)
    var header = document.createElement('div');
    header.className = 'tooltip-header';

    var nameEl = document.createElement('span');
    nameEl.className = 'station-name';
    nameEl.textContent = s.name;
    header.appendChild(nameEl);

    var closeBtn = document.createElement('span');
    closeBtn.className = 'close-btn';
    closeBtn.textContent = '\u00d7';
    closeBtn.addEventListener('click', function() { window._dismissTooltip(); });
    header.appendChild(closeBtn);

    tooltip.appendChild(header);

    // 노선 배지: 현재 노선 + 환승 노선 모두 역명 하단에 동일 형식으로 표시
    var linesDiv = document.createElement('div');
    linesDiv.className = 'transfer-lines';

    var displayLines = [s.lineId];
    if (s.transferLines && s.transferLines.length) {
      for (var i = 0; i < s.transferLines.length; i++) {
        if (s.transferLines[i] !== s.lineId) displayLines.push(s.transferLines[i]);
      }
    }

    for (var i = 0; i < displayLines.length; i++) {
      var lid = displayLines[i];
      var b = document.createElement('span');
      b.className = 'transfer-badge';
      b.style.background = lineColors[lid] || '#999';
      b.textContent = lineNames[lid] || lid;
      linesDiv.appendChild(b);
    }
    tooltip.appendChild(linesDiv);

    // 액션 버튼
    var actions = document.createElement('div');
    actions.className = 'actions';

    function makeBtn(icon, label, labelColor, handler) {
      var btn = document.createElement('button');
      btn.className = 'action-btn';
      var iconDiv = document.createElement('div');
      iconDiv.className = 'icon';
      iconDiv.style.color = labelColor;
      iconDiv.textContent = icon;
      btn.appendChild(iconDiv);
      var labelDiv = document.createElement('div');
      labelDiv.className = 'label';
      labelDiv.style.color = labelColor;
      labelDiv.textContent = label;
      btn.appendChild(labelDiv);
      btn.addEventListener('click', handler);
      return btn;
    }

    actions.appendChild(makeBtn('\u25c9', '출발', '#2196F3', function() { window._setDeparture(s.id); }));
    actions.appendChild(makeBtn('\u26b2', '도착', '#F44336', function() { window._setArrival(s.id); }));
    actions.appendChild(makeBtn('\u23f0', '도착정보', '#4CAF50', function() { window._viewArrivalInfo(s.name); }));

    tooltip.appendChild(actions);
    tooltip.style.display = 'block';

    // 툴팁 위치 (화면 좌표)
    var screenX = s.svgX * scale + tx;
    var screenY = s.svgY * scale + ty;
    var tooltipW = tooltip.offsetWidth;

    var left = screenX - tooltipW / 2;
    left = Math.max(8, Math.min(window.innerWidth - tooltipW - 8, left));
    var top = screenY - tooltip.offsetHeight - 16;
    if (top < 8) top = screenY + 16;

    tooltip.style.left = left + 'px';
    tooltip.style.top = top + 'px';
  };

  // 툴팁 숨기기
  window.hideTooltip = function() {
    tooltip.style.display = 'none';
  };

  // 내부 액션 핸들러
  window._dismissTooltip = function() {
    window.hideTooltip();
    sendToFlutter({ action: 'dismiss' });
  };

  window._setDeparture = function(stationId) {
    window.hideTooltip();
    sendToFlutter({ action: 'setDeparture', stationId: stationId });
  };

  window._setArrival = function(stationId) {
    window.hideTooltip();
    sendToFlutter({ action: 'setArrival', stationId: stationId });
  };

  window._viewArrivalInfo = function(stationName) {
    window.hideTooltip();
    sendToFlutter({ action: 'viewArrivalInfo', stationName: stationName });
  };

  // ============================================================
  // 노선 강조/흐림 처리
  // ============================================================

  // 앱 lineId → SVG data-line 코드 매핑
  var lineIdToDataLine = {
    '1': ['2-1'],
    '2': ['3-2'],
    '3': ['4-3'],
    '4': ['5-4'],
    '5': ['6-5'],
    '6': ['7-6'],
    '7': ['8-7'],
    '8': ['9-8'],
    '9': ['10-9'],
    'SB': ['S'],
    '경의중앙': ['K'],
    '경춘': ['G', 'KK'],
    '공항철도': ['A'],
    '수인분당': ['B'],
    '신림': ['SL'],
    '에버라인': ['E'],
    '인천1': ['I'],
    '인천2': ['I2'],
    '김포골드': ['KP'],
    '서해': ['SH'],
    '의정부': ['U'],
    '우이신설': ['W'],
    'GTX-A': ['1-GA']
  };

  // ============================================================
  // SVG path 파싱 및 waypoint 인덱스 구축
  // ============================================================

  // SVG path d 속성에서 좌표 배열 추출 (M/L 명령어만 사용하는 SVG)
  function parseSvgPath(d) {
    var coords = [];
    var re = /([ML])\\s*([\\d.]+)\\s+([\\d.]+)/g;
    var m;
    while ((m = re.exec(d)) !== null) {
      coords.push({ x: parseFloat(m[2]), y: parseFloat(m[3]) });
    }
    return coords;
  }

  // 좌표 배열에서 (x,y)에 가장 가까운 인덱스 찾기 (tolerance 이내)
  function findNearestIdx(path, x, y, tolerance) {
    var bestIdx = -1;
    var bestDist = tolerance * tolerance;
    for (var i = 0; i < path.length; i++) {
      var dx = path[i].x - x;
      var dy = path[i].y - y;
      var d2 = dx * dx + dy * dy;
      if (d2 < bestDist) {
        bestDist = d2;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  // 모든 connection의 waypoints를 사전 계산하여 waypointIndex에 저장
  function buildWaypointIndex() {
    waypointIndex = {};
    var TOLERANCE = 20;

    // data-line 코드별 SVG path 좌표 캐시
    var pathsByDl = {};
    var svgPaths = document.querySelectorAll('path[data-line]');
    for (var i = 0; i < svgPaths.length; i++) {
      var dl = svgPaths[i].getAttribute('data-line');
      var d = svgPaths[i].getAttribute('d');
      if (!d) continue;
      var coords = parseSvgPath(d);
      if (coords.length < 2) continue;
      if (!pathsByDl[dl]) pathsByDl[dl] = [];
      pathsByDl[dl].push(coords);
    }

    for (var ci = 0; ci < connections.length; ci++) {
      var conn = connections[ci];
      if (conn.isTransfer) continue;

      var from = stationMap[conn.fromStationId];
      var to = stationMap[conn.toStationId];
      if (!from || !to) continue;

      var dlCodes = lineIdToDataLine[conn.lineId];
      if (!dlCodes) continue;

      var found = false;
      for (var di = 0; di < dlCodes.length && !found; di++) {
        var paths = pathsByDl[dlCodes[di]];
        if (!paths) continue;
        for (var pi = 0; pi < paths.length && !found; pi++) {
          var path = paths[pi];
          var fi = findNearestIdx(path, from.svgX, from.svgY, TOLERANCE);
          var ti = findNearestIdx(path, to.svgX, to.svgY, TOLERANCE);
          if (fi < 0 || ti < 0 || fi === ti) continue;

          var lo = Math.min(fi, ti);
          var hi = Math.max(fi, ti);
          var segment = path.slice(lo, hi + 1);
          if (fi > ti) segment.reverse();

          // 중간점이 있는 경우만 저장 (2개 = 직선이므로 불필요)
          if (segment.length > 2) {
            var key = conn.fromStationId + '_' + conn.toStationId;
            waypointIndex[key] = segment;
          }
          found = true;
        }
      }
    }
  }

  // 특정 노선만 강조, 나머지 흐림 처리
  window.highlightLines = function(lineIdsJson) {
    if (!lineColors || Object.keys(lineColors).length === 0) return;
    var lineIds = JSON.parse(lineIdsJson);

    // lineId → data-line 코드 집합 변환
    var codeSet = {};
    for (var i = 0; i < lineIds.length; i++) {
      var codes = lineIdToDataLine[lineIds[i]];
      if (codes) {
        for (var j = 0; j < codes.length; j++) {
          codeSet[codes[j]] = true;
        }
      }
    }

    // path[data-line] 요소 처리
    var paths = document.querySelectorAll('path[data-line]');
    for (var i = 0; i < paths.length; i++) {
      var dl = paths[i].getAttribute('data-line');
      if (codeSet[dl]) {
        paths[i].classList.remove('dimmed');
      } else {
        paths[i].classList.add('dimmed');
      }
    }

    // lineId 집합 (text의 역명→노선 확인용, circle 좌표 매칭용)
    var lineIdSet = {};
    for (var i = 0; i < lineIds.length; i++) {
      lineIdSet[lineIds[i]] = true;
    }

    // text[data-line] 요소 처리
    var texts = document.querySelectorAll('text[data-line]');
    for (var i = 0; i < texts.length; i++) {
      var dl = texts[i].getAttribute('data-line');
      var matched = !!codeSet[dl];

      // data-line 불일치 시 역명의 소속 노선으로 재확인 (환승역 대응)
      if (!matched) {
        var sName = (texts[i].getAttribute('data-station') || '').replace(/[\\n\\r]/g, '');
        var sLines = stationLineMap[sName];
        if (sLines) {
          for (var lid in sLines) {
            if (lineIdSet[lid]) { matched = true; break; }
          }
        }
      }

      if (matched) {
        texts[i].classList.remove('dimmed');
      } else {
        texts[i].classList.add('dimmed');
      }
    }

    // 강조 노선에 속하는 역의 SVG 좌표 집합 (circle 매칭용)
    var highlightCoords = {};
    var highlightCoordsList = [];
    for (var si = 0; si < stations.length; si++) {
      var s = stations[si];
      if (lineIdSet[s.lineId]) {
        var px = parseFloat(s.svgX), py = parseFloat(s.svgY);
        highlightCoords[px + ',' + py] = true;
        highlightCoordsList.push([px, py]);
      }
    }

    // circle 요소 처리 (좌표 매칭, overlay 제외)
    var circles = document.querySelectorAll('circle:not([data-overlay])');
    for (var i = 0; i < circles.length; i++) {
      var c = circles[i];
      var coordKey = parseFloat(c.getAttribute('cx')) + ',' + parseFloat(c.getAttribute('cy'));
      if (highlightCoords[coordKey]) {
        c.classList.remove('dimmed');
      } else {
        c.classList.add('dimmed');
      }
    }

    // rect 요소 처리 (환승역 연결선, 확장 영역 매칭)
    // 여유값 8px: 환승역 circle 반지름(r=5) + 3px 마진
    var RECT_MATCH_MARGIN = 8;
    var rects = document.querySelectorAll('rect:not(#route-overlay-bg)');
    for (var i = 0; i < rects.length; i++) {
      var r = rects[i];
      var rx = parseFloat(r.getAttribute('x') || '0');
      var ry = parseFloat(r.getAttribute('y') || '0');
      var rw = parseFloat(r.getAttribute('width') || '0');
      var rh = parseFloat(r.getAttribute('height') || '0');
      var matched = false;
      for (var k = 0; k < highlightCoordsList.length; k++) {
        var sx = highlightCoordsList[k][0];
        var sy = highlightCoordsList[k][1];
        if (sx >= rx - RECT_MATCH_MARGIN && sx <= rx + rw + RECT_MATCH_MARGIN &&
            sy >= ry - RECT_MATCH_MARGIN && sy <= ry + rh + RECT_MATCH_MARGIN) {
          matched = true;
          break;
        }
      }
      if (matched) {
        r.classList.remove('dimmed');
      } else {
        r.classList.add('dimmed');
      }
    }
  };

  // 강조 해제, 모든 요소 원래 opacity로 복원
  window.clearLineHighlight = function() {
    var dimmed = document.querySelectorAll('.dimmed');
    for (var i = 0; i < dimmed.length; i++) {
      dimmed[i].classList.remove('dimmed');
    }
  };

  // ============================================================
  // 부드러운 카메라 이동
  // ============================================================
  var panAnimId = 0;

  // SVG 좌표(svgX, svgY)를 화면 중앙에 배치하도록 부드럽게 이동
  window.panTo = function(svgX, svgY, durationMs) {
    var dur = durationMs || 400;
    var vw = window.innerWidth;
    var vh = window.innerHeight;

    var targetTx = vw / 2 - svgX * scale;
    var targetTy = vh / 2 - svgY * scale;

    // clamp 적용
    var minTx = vw - CANVAS_W * scale - 70;
    var minTy = vh - CANVAS_H * scale - 70;
    targetTx = Math.min(70, Math.max(minTx, targetTx));
    targetTy = Math.min(70, Math.max(minTy, targetTy));

    var startTx = tx, startTy = ty;
    var startTime = performance.now();
    var animId = ++panAnimId;

    function easeInOut(t) {
      return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
    }

    function step(now) {
      if (animId !== panAnimId) return;
      var elapsed = now - startTime;
      var progress = Math.min(1, elapsed / dur);
      var ease = easeInOut(progress);

      tx = startTx + (targetTx - startTx) * ease;
      ty = startTy + (targetTy - startTy) * ease;
      applyTransform();

      if (progress < 1) {
        requestAnimationFrame(step);
      }
    }

    requestAnimationFrame(step);
  };

  // ============================================================
  // 실시간 열차 표시 (애니메이션)
  // ============================================================

  // [디버그용] 열차 아이콘의 녹색 디버그 정보 박스 표시 여부.
  // false 로 두면 buildDebugGroup/updateTrainDebugInfo 호출과 1초 setInterval
  // 갱신이 모두 스킵된다. 함수 정의 자체는 남겨두어 필요 시 true 로 복구 가능.
  var SHOW_TRAIN_DEBUG = false;

  // 행선지 레이블 박스의 최소 너비(px). 열차 아이콘(-18~+18, 36px)과 동일하게
  // 설정해 짧은 행선(예: "김포공항") 은 기존과 동일 모양으로 보이도록 한다.
  // ============================================================
  // 도착 말풍선 (2줄: "{행선}행" / "N초 후 도착")
  // ============================================================
  // [원칙 1 준수] 카운트다운 줄은 오직 startTrainAnimation.step() 이 계산하는
  // realRemaining(단조 감소) 만을 입력으로 받는다. 이 파일 어디에도 별도의
  // 카운트다운 변수를 신설하지 않는다 — 기존 setInterval 의
  // `lastArrivalSeconds - elapsed` 방식과 절대 혼용하지 않는다.
  var BUBBLE_KO_CHAR_W = 9;      // 한글/CJK 전각 1자 근사 너비(px, font-size 9 기준)
  var BUBBLE_NARROW_CHAR_W = 4.5; // 숫자·공백·영문·괄호 등 반각 1자 근사 너비(px)
  var BUBBLE_PADDING = 8;       // 좌우 여백 합계(최장 문구도 배경 내 수용)
  var BUBBLE_MIN_WIDTH = 34;
  var BUBBLE_LINE_H = 14;      // 줄 1개 높이
  var BUBBLE_HEIGHT = BUBBLE_LINE_H * 2; // 2줄(행선/카운트다운)
  var BUBBLE_Y = -20 - BUBBLE_HEIGHT;    // 열차 아이콘(image y=-6.5) 위에 배치
  var BUBBLE_TAIL_H = 5;

  // realRemaining(초, 단조 감소) → 표시 문구.
  function formatArrivalBubbleText(remainingSeconds) {
    var sec = Math.ceil(remainingSeconds);
    // 10초 미만(9초 이하)은 "곧 도착"으로 표시. 10초부터 "N초 후 도착".
    if (sec < 10) return '곧 도착';
    if (sec < 60) return sec + '초 후 도착';
    var min = Math.floor(sec / 60);
    var rem = sec % 60;
    // 정확히 분 단위면 "N분 후 도착"으로 축약(예 120초 → "2분 후 도착").
    return rem === 0 ? (min + '분 후 도착') : (min + '분 ' + rem + '초 후 도착');
  }

  // 행선지 → 1줄("{destination}행"). destination 이 비면 빈 문자열.
  function formatDestinationLine(destination) {
    return destination ? (destination + '행') : '';
  }

  // 문자열의 근사 렌더링 너비를 글자 종류별로 추정한다.
  // CJK(한글 등, code point > 0x2E80)는 전각 폭, 그 외(숫자·공백·영문·괄호 등)는 반각 폭.
  function textWidthApprox(s) {
    s = s || '';
    var w = 0;
    for (var i = 0; i < s.length; i++) {
      w += (s.charCodeAt(i) > 0x2E80) ? BUBBLE_KO_CHAR_W : BUBBLE_NARROW_CHAR_W;
    }
    return w;
  }

  // 두 줄 중 더 긴 줄 기준으로 말풍선 너비를 계산한다.
  function computeBubbleWidth(line1, line2) {
    var w = Math.max(textWidthApprox(line1), textWidthApprox(line2));
    return Math.max(BUBBLE_MIN_WIDTH, w + BUBBLE_PADDING);
  }

  // 말풍선(둥근 사각형 배경 + 아래쪽 꼬리 + 2줄 텍스트) DOM 을 생성해 g 에
  // 부착한다. 배경/꼬리는 노선색(color)으로 채색하고 텍스트는 흰색 유지.
  // 1줄: "{destination}행", 2줄: 카운트다운("N초 후 도착" 등).
  function createArrivalBubble(g, destination, countdownText, color) {
    destination = destination || '';
    countdownText = countdownText || '';
    var destLine = formatDestinationLine(destination);

    var bubble = document.createElementNS(SVG_NS, 'g');
    bubble.setAttribute('class', 'train-arrival-bubble');

    var w = computeBubbleWidth(destLine, countdownText);
    var bg = document.createElementNS(SVG_NS, 'rect');
    bg.setAttribute('x', String(-w / 2));
    bg.setAttribute('y', String(BUBBLE_Y));
    bg.setAttribute('width', String(w));
    bg.setAttribute('height', String(BUBBLE_HEIGHT));
    bg.setAttribute('rx', '4');
    bg.setAttribute('fill', color || '#333');
    bg.setAttribute('opacity', '0.9');
    bubble.appendChild(bg);

    // 말풍선 꼬리: 배경 하단 중앙에서 아래로 향하는 작은 삼각형.
    var tailY0 = BUBBLE_Y + BUBBLE_HEIGHT;
    var tail = document.createElementNS(SVG_NS, 'polygon');
    tail.setAttribute('points',
      (-4) + ',' + tailY0 + ' ' +
      4 + ',' + tailY0 + ' ' +
      0 + ',' + (tailY0 + BUBBLE_TAIL_H));
    tail.setAttribute('fill', color || '#333');
    tail.setAttribute('opacity', '0.9');
    bubble.appendChild(tail);

    var destText = document.createElementNS(SVG_NS, 'text');
    destText.setAttribute('class', 'bubble-dest');
    destText.setAttribute('x', '0');
    destText.setAttribute('y', String(BUBBLE_Y + BUBBLE_LINE_H / 2 + 3.2));
    destText.setAttribute('text-anchor', 'middle');
    destText.setAttribute('font-size', '9');
    destText.setAttribute('font-weight', 'bold');
    destText.setAttribute('fill', '#fff');
    destText.setAttribute('font-family', 'sans-serif');
    destText.textContent = destLine;
    bubble.appendChild(destText);

    var countText = document.createElementNS(SVG_NS, 'text');
    countText.setAttribute('class', 'bubble-count');
    countText.setAttribute('x', '0');
    countText.setAttribute('y', String(BUBBLE_Y + BUBBLE_LINE_H + BUBBLE_LINE_H / 2 + 3.2));
    countText.setAttribute('text-anchor', 'middle');
    countText.setAttribute('font-size', '9');
    countText.setAttribute('font-weight', 'bold');
    countText.setAttribute('fill', '#fff');
    countText.setAttribute('font-family', 'sans-serif');
    countText.textContent = countdownText;
    bubble.appendChild(countText);

    g.appendChild(bubble);
    return { group: bubble, bg: bg, destText: destText, countText: countText };
  }

  // 말풍선 배경 너비를 현재 두 줄 텍스트 기준으로 재계산한다.
  function resizeArrivalBubble(trainGroup) {
    var bubble = trainGroup.querySelector('.train-arrival-bubble');
    if (!bubble) return;
    var destEl = bubble.querySelector('.bubble-dest');
    var countEl = bubble.querySelector('.bubble-count');
    var bg = bubble.querySelector('rect');
    if (!bg) return;
    var w = computeBubbleWidth(
      destEl ? destEl.textContent : '',
      countEl ? countEl.textContent : ''
    );
    bg.setAttribute('x', String(-w / 2));
    bg.setAttribute('width', String(w));
  }

  // 카운트다운 줄(.bubble-count)만 갱신한다 (원칙 1: realRemaining 표시 전용).
  function updateArrivalBubbleText(trainGroup, displayText) {
    var textEl = trainGroup.querySelector('.train-arrival-bubble .bubble-count');
    if (!textEl) return;
    textEl.textContent = displayText;
    resizeArrivalBubble(trainGroup);
  }

  // 행선지 줄(.bubble-dest)만 갱신한다 (refresh 시 행선 변경 반영).
  function updateArrivalBubbleDestination(trainGroup, destination) {
    var textEl = trainGroup.querySelector('.train-arrival-bubble .bubble-dest');
    if (!textEl) return;
    textEl.textContent = formatDestinationLine(destination);
    resizeArrivalBubble(trainGroup);
  }

  function createTrainIcon(train, color) {
    var g = document.createElementNS(SVG_NS, 'g');

    var img = document.createElementNS(SVG_NS, 'image');
    img.setAttribute('href', TRAIN_IMG);
    img.setAttribute('x', '-18');
    img.setAttribute('y', '-6.5');
    img.setAttribute('width', '36');
    img.setAttribute('height', '13');
    g.appendChild(img);

    // 급행 딱지: trainType이 '급행'이면 열차 아이콘 우측에 빨간 "급" 배지
    if (train.trainType === '급행') {
      var badgeBg = document.createElementNS(SVG_NS, 'rect');
      badgeBg.setAttribute('x', '18');
      badgeBg.setAttribute('y', '-6');
      badgeBg.setAttribute('width', '12');
      badgeBg.setAttribute('height', '12');
      badgeBg.setAttribute('rx', '2');
      badgeBg.setAttribute('fill', '#E53935');
      g.appendChild(badgeBg);

      var badgeText = document.createElementNS(SVG_NS, 'text');
      badgeText.setAttribute('x', '24');
      badgeText.setAttribute('y', '3');
      badgeText.setAttribute('text-anchor', 'middle');
      badgeText.setAttribute('font-size', '8.5');
      badgeText.setAttribute('font-weight', 'bold');
      badgeText.setAttribute('fill', '#fff');
      badgeText.setAttribute('font-family', 'sans-serif');
      badgeText.textContent = '급';
      g.appendChild(badgeText);
    }

    // [디버그용] 열차 위치 결정 요소 표시 (SHOW_TRAIN_DEBUG=false 면 생성 스킵)
    if (SHOW_TRAIN_DEBUG) {
      g.appendChild(buildDebugGroup(train));
    }

    // 도착 말풍선(2줄: 행선/카운트다운): 초기 표시는 arrivalSeconds 기반
    // (원칙 1의 realRemaining 과 동일 포맷 함수 사용). step() 이 시작되면
    // realRemaining 기준으로 카운트다운 줄만 갱신됨. 배경은 노선색(color).
    var initialBubbleText = formatArrivalBubbleText(train.arrivalSeconds || 0);
    createArrivalBubble(g, train.destination, initialBubbleText, color);

    // initialProgress 반영: 첫 세그먼트 내 보간 위치에 배치
    var startX = train.fromSvgX;
    var startY = train.fromSvgY;
    var path = train.pathToTarget;
    if (train.initialProgress > 0 && path && path.length >= 2) {
      var p = train.initialProgress;
      startX = path[0].x + (path[1].x - path[0].x) * p;
      startY = path[0].y + (path[1].y - path[0].y) * p;
    }

    g.setAttribute('transform', 'translate(' + startX + ',' + startY + ')');
    return g;
  }

  // [디버그용] 열차 위치 결정 요소를 멀티라인 텍스트로 생성한다.
  function buildDebugGroup(train) {
    var dg = document.createElementNS(SVG_NS, 'g');
    dg.setAttribute('class', 'train-debug-info');

    var lines = [
      '#' + (train.trainNo || '?'),
      '방향: ' + (train.direction || '?'),
      '행선: ' + (train.destination || '?'),
      '현재역: ' + (train.currentStation || '?'),
      'code: ' + (train.arrivalCode != null ? train.arrivalCode : '?'),
      '상태: ' + (train.positionStatus || '?'),
      'prog: ' + (train.initialProgress != null ? train.initialProgress.toFixed(2) : '?'),
      '초: ' + (train.arrivalSeconds != null ? train.arrivalSeconds : '?'),
      'msg: ' + (train.message || '?'),
      '경유: ' + (train.pathToTarget ? train.pathToTarget.length : '0'),
      '구간: [' + (train.segmentDurations ? train.segmentDurations.join(',') : '') + ']',
    ];

    var bgW = 90;
    var bgH = lines.length * 9 + 4;
    var bg = document.createElementNS(SVG_NS, 'rect');
    bg.setAttribute('x', String(-bgW / 2));
    bg.setAttribute('y', '8');
    bg.setAttribute('width', String(bgW));
    bg.setAttribute('height', String(bgH));
    bg.setAttribute('rx', '2');
    bg.setAttribute('fill', 'rgba(0,0,0,0.75)');
    dg.appendChild(bg);

    for (var i = 0; i < lines.length; i++) {
      var t = document.createElementNS(SVG_NS, 'text');
      t.setAttribute('x', String(-bgW / 2 + 3));
      t.setAttribute('y', String(8 + 9 + i * 9));
      t.setAttribute('font-size', '6');
      t.setAttribute('fill', '#0f0');
      t.setAttribute('font-family', 'monospace');
      if (lines[i].indexOf('\uCD08: ') === 0) t.setAttribute('class', 'debug-seconds');
      t.textContent = lines[i];
      dg.appendChild(t);
    }

    return dg;
  }

  // [디버그용] 기존 열차 아이콘의 디버그 정보 텍스트를 갱신한다.
  // SHOW_TRAIN_DEBUG=false 면 갱신/생성 없이 즉시 반환 (기존 박스도 남기지 않음).
  function updateTrainDebugInfo(element, train) {
    if (!SHOW_TRAIN_DEBUG) return;
    var old = element.querySelector('.train-debug-info');
    if (old) old.remove();
    element.appendChild(buildDebugGroup(train));
  }

  // ============================================================
  // SVG 선로 스냅 시스템
  // ============================================================
  // 열차 애니메이션은 pathToTarget(역 좌표 배열)을 받아 각 역 쌍을 직선 보간한다.
  // SVG 선로가 꺾이는 구간(예: 분당선 강남구청↔선정릉)에서는 직선이 선로를 벗어나
  // 탈선해 보이므로, 페이지 로드 시 각 노선 path의 좌표를 파싱해두고
  // 열차 경로의 각 역 쌍을 실제 선로 위 좌표 시퀀스로 확장한다.
  // segmentDurations는 확장된 subseg의 거리 비율로 재분배한다.

  var pathSnapPolylines = {}; // data-line 코드 → [polyline, polyline, ...]
  var pathSnapReady = false;
  var SNAP_THRESHOLD_PX = 12; // 역 중심과 선로 간 허용 오차(px)

  function parseSvgPathD(d) {
    if (!d) return [];
    // 허용 문자(M, L, 숫자, 지수, 공백, 쉼표, 부호, 소수점) 외가 있으면 스냅 비대상.
    // H/V/C/S/Q/T/A/Z 등 미지원 명령이나 소문자 상대좌표(m/l 등)가 섞여 있으면
    // silent-fail 대신 빈 배열을 반환해 직선 fallback을 유도한다.
    if (/[^MLeE0-9.,\\s+\\-]/.test(d)) return [];
    var pts = [];
    var tokens = d.replace(/,/g, ' ').split(/\\s+/);
    var i = 0;
    while (i < tokens.length) {
      var tk = tokens[i];
      if (tk === 'M' || tk === 'L') {
        i++;
        while (i + 1 < tokens.length) {
          var x = parseFloat(tokens[i]);
          var y = parseFloat(tokens[i + 1]);
          if (isNaN(x) || isNaN(y)) break;
          pts.push({ x: x, y: y });
          i += 2;
        }
      } else {
        i++;
      }
    }
    return pts;
  }

  function buildPathSnapLookup() {
    if (pathSnapReady) return;
    var paths = document.querySelectorAll('path[data-line]');
    for (var i = 0; i < paths.length; i++) {
      var dl = paths[i].getAttribute('data-line');
      if (!dl) continue;
      // 흰색 이중선 테두리(예: 1-GA-1)는 본체와 동일 좌표이므로 제외.
      // 대소문자/축약형(#FFF, white)도 방어.
      var stroke = (paths[i].getAttribute('stroke') || '').toLowerCase();
      if (stroke === '#ffffff' || stroke === '#fff' || stroke === 'white') continue;
      var pts = parseSvgPathD(paths[i].getAttribute('d'));
      if (pts.length < 2) continue;
      if (!pathSnapPolylines[dl]) pathSnapPolylines[dl] = [];
      pathSnapPolylines[dl].push(pts);
    }
    pathSnapReady = true;
  }

  function projectOnPolyline(px, py, polyline) {
    var bestIdx = -1, bestT = 0, bestDist = Infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      var ax = polyline[i].x, ay = polyline[i].y;
      var bx = polyline[i + 1].x, by = polyline[i + 1].y;
      var dx = bx - ax, dy = by - ay;
      var lenSq = dx * dx + dy * dy;
      var t = lenSq > 0
        ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        : 0;
      var cx = ax + t * dx, cy = ay + t * dy;
      var d = Math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      if (d < bestDist) { bestDist = d; bestIdx = i; bestT = t; }
    }
    return { segIdx: bestIdx, t: bestT, dist: bestDist };
  }

  // 역 A(ax,ay) → 역 B(bx,by)를 lineId의 SVG 선로 위 좌표 시퀀스로 반환.
  // 후보 polyline들 중 투영 거리 합이 최소인 것을 선택하고, slice 길이가
  // 직선 거리의 3배를 넘으면 오매칭으로 간주해 탈락시킨다. 모두 탈락하면 null.
  function getSnappedSlice(ax, ay, bx, by, lineId) {
    if (!pathSnapReady) buildPathSnapLookup();
    var dataLines = lineIdToDataLine[lineId];
    if (!dataLines) return null;

    var straightDist = Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    var bestSlice = null;
    var bestScore = Infinity;

    for (var di = 0; di < dataLines.length; di++) {
      var polylines = pathSnapPolylines[dataLines[di]];
      if (!polylines) continue;
      for (var pi = 0; pi < polylines.length; pi++) {
        var poly = polylines[pi];
        var pa = projectOnPolyline(ax, ay, poly);
        if (pa.dist > SNAP_THRESHOLD_PX) continue;
        var pb = projectOnPolyline(bx, by, poly);
        if (pb.dist > SNAP_THRESHOLD_PX) continue;

        var candidate;
        if (pa.segIdx === pb.segIdx) {
          candidate = [{ x: ax, y: ay }, { x: bx, y: by }];
        } else {
          candidate = [{ x: ax, y: ay }];
          if (pa.segIdx < pb.segIdx) {
            for (var j = pa.segIdx + 1; j <= pb.segIdx; j++) {
              candidate.push({ x: poly[j].x, y: poly[j].y });
            }
          } else {
            for (var j = pa.segIdx; j >= pb.segIdx + 1; j--) {
              candidate.push({ x: poly[j].x, y: poly[j].y });
            }
          }
          candidate.push({ x: bx, y: by });
        }

        // Sanity: slice 총 길이가 직선거리의 3배를 넘으면 분기/지선 오매칭으로 탈락
        var sliceLen = 0;
        for (var k = 0; k < candidate.length - 1; k++) {
          var sdx = candidate[k + 1].x - candidate[k].x;
          var sdy = candidate[k + 1].y - candidate[k].y;
          sliceLen += Math.sqrt(sdx * sdx + sdy * sdy);
        }
        if (straightDist > 0 && sliceLen > straightDist * 3) continue;

        var score = pa.dist + pb.dist;
        if (score < bestScore) {
          bestScore = score;
          bestSlice = candidate;
        }
      }
    }
    return bestSlice;
  }

  // pathToTarget을 SVG 선로 좌표 시퀀스로 확장. segmentDurations는 subseg 거리 비율로 분배.
  // `stationIndices`: 원본 path 의 각 역이 newPath 에서 어느 index 에 있는지 매핑.
  // 예: 원본 [A,B,C] 가 확장 후 [A,c1,c2,B,c3,C] 면 stationIndices=[0,3,5].
  // 3-way 클램프가 "원래 역" 기준으로 범위 판정할 수 있도록 추가.
  function expandPathWithSnap(path, segDurations, lineId) {
    if (!path || path.length < 2 || !lineId) {
      var stIdx = [];
      var len = path ? path.length : 0;
      for (var k = 0; k < len; k++) stIdx.push(k);
      return {
        path: path ? path.slice() : [],
        durations: segDurations ? segDurations.slice() : [],
        stationIndices: stIdx
      };
    }
    var newPath = [{ x: path[0].x, y: path[0].y }];
    var newDurations = [];
    var stationIndices = [0];
    for (var i = 0; i < path.length - 1; i++) {
      var a = path[i], b = path[i + 1];
      var slice = getSnappedSlice(a.x, a.y, b.x, b.y, lineId);
      if (!slice) slice = [a, b];
      var origDur = (segDurations && segDurations[i] != null) ? segDurations[i] : 0;

      var subDists = [];
      var totalDist = 0;
      for (var j = 0; j < slice.length - 1; j++) {
        var dx = slice[j + 1].x - slice[j].x;
        var dy = slice[j + 1].y - slice[j].y;
        var d = Math.sqrt(dx * dx + dy * dy);
        subDists.push(d);
        totalDist += d;
      }
      for (var j = 1; j < slice.length; j++) {
        newPath.push({ x: slice[j].x, y: slice[j].y });
      }
      if (totalDist > 0) {
        for (var j = 0; j < subDists.length; j++) {
          newDurations.push(origDur * subDists[j] / totalDist);
        }
      } else if (slice.length > 1) {
        var n = slice.length - 1;
        for (var j = 0; j < n; j++) newDurations.push(origDur / n);
      }
      // slice 끝 = 원본 path[i+1] 의 확장 path 상 위치
      stationIndices.push(newPath.length - 1);
    }
    return { path: newPath, durations: newDurations, stationIndices: stationIndices };
  }

  // [원칙 2] 매 frame 남은시간 역산으로 위치 결정. dwell=0 전제.
  // - remaining 이 세그먼트 i 안에서 남은 시간이면 progress=(s[i]-t)/s[i]
  // - 모든 세그먼트 다 소진하고 t>0 남으면 outOfPath (경로 시작점보다 더 뒤)
  function estimateTrainPosition(remaining, segTravel) {
    if (!segTravel || segTravel.length === 0) {
      return { outOfPath: false, segmentIndex: 0, progress: 0 };
    }
    if (remaining <= 0) {
      return {
        outOfPath: false,
        segmentIndex: segTravel.length - 1,
        progress: 1
      };
    }
    var t = remaining;
    for (var i = segTravel.length - 1; i >= 0; i--) {
      if (t <= segTravel[i]) {
        return {
          outOfPath: false,
          segmentIndex: i,
          progress: (segTravel[i] - t) / segTravel[i]
        };
      }
      t -= segTravel[i];
    }
    return { outOfPath: true, segmentIndex: 0, progress: 0 };
  }

  function startTrainAnimation(trainState, trainData) {
    // SVG 선로 스냅: pathToTarget을 실제 선로 위 좌표 시퀀스로 확장 (꺾임 구간 탈선 방지)
    var _snap = expandPathWithSnap(
      trainData.pathToTarget,
      trainData.segmentDurations,
      trainData.lineId
    );
    var path = _snap.path;
    if (!path || path.length < 2) {
      if (path && path.length === 1) {
        // 단일 점 path = "현재역 == 출발역" 케이스 (예: arvlMsg2='진입'/'도착').
        // 좌표는 출발역에 고정. 도착 이펙트는 arrivalSeconds<=0 일 때만 발동 —
        // 양수면 아직 도착 전이므로 이펙트 없이 그 자리에 머물러 표시한다
        // (그대로 사라지면 사용자가 '열차 누락'으로 오인 — 5호선 양평/영등포 등
        // 짧은 잔여시간 train 이 화면에서 사라지던 회귀를 차단).
        trainState.element.setAttribute('transform',
          'translate(' + path[0].x + ',' + path[0].y + ')');
        // rAF 루프(step)를 타지 않는 경로이므로 말풍선을 1회만 표시한다.
        // arrivalSeconds<=0 이면 formatArrivalBubbleText 가 "곧 도착"을 반환.
        // 2줄(행선/카운트다운) 모두 세팅 — refresh 로 재호출될 수 있으므로
        // 행선 줄도 매번 갱신한다.
        var singlePointSec = Math.ceil(trainData.arrivalSeconds || 0);
        updateArrivalBubbleDestination(trainState.element, trainData.destination);
        updateArrivalBubbleText(trainState.element,
          formatArrivalBubbleText(trainData.arrivalSeconds || 0));
        trainState.lastShownSec = singlePointSec;
        if ((trainData.arrivalSeconds || 0) <= 0) {
          playArrivalEffect(trainState, trainData.trainNo);
        }
      }
      return;
    }

    var segDurations = _snap.durations;
    if (!segDurations || segDurations.length !== path.length - 1) {
      // 데이터 불일치 — path[0] 에 고정 (이펙트 없이 return)
      trainState.element.setAttribute('transform',
        'translate(' + path[0].x + ',' + path[0].y + ')');
      return;
    }

    // [원칙 1] recptnDt 기준 매 frame 실시간 남은시간 계산을 위한 베이스.
    var receivedAt = (trainData.receivedAtEpochMs != null)
      ? trainData.receivedAtEpochMs : Date.now();
    var baseArrival = trainData.arrivalSeconds || 0;

    // [원칙 3] 역 index → 확장 path 상 index 매핑.
    // `currentStationIndex` 는 원본 pathToTarget 기준 "현재역(arvlMsg3)" 위치.
    // SVG 곡선 스냅으로 path 가 세분화됐을 수 있으니 stationIndices 를 경유해
    // 확장 후 newPath 에서의 "현재역"/"다음역" 위치로 변환한다.
    var stationIndices = _snap.stationIndices || [];
    var origCurIdx = trainData.currentStationIndex || 0;
    if (origCurIdx < 0) origCurIdx = 0;
    if (stationIndices.length > 0 && origCurIdx > stationIndices.length - 2) {
      origCurIdx = Math.max(0, stationIndices.length - 2);
    }
    var curIdx = (stationIndices.length > origCurIdx)
      ? stationIndices[origCurIdx] : origCurIdx;
    var nextIdx = (stationIndices.length > origCurIdx + 1)
      ? stationIndices[origCurIdx + 1] : path.length - 1;

    // [원칙 4] 점프 방지 — target 을 지수 감쇠로 catch-up.
    // refresh 로 target 이 갑자기 이동해도 currentPos 는 부드럽게 따라잡는다.
    // frame rate 에 독립적이도록 실제 경과 ms 기반 반감기로 수렴.
    //
    // 거리 기반 dynamic 반감기:
    //   - 작은 흔들림 (dist <= 30px): 3000ms 반감기 — 정상 catch-up.
    //     API 지터/라운딩 노이즈 흡수, 동일 cycle 내 forward animation.
    //   - 큰 점프 (dist > 30px): 500ms 반감기 — 빠르게 수렴.
    //     역 전환·path 축소 등으로 stale currentPos 가 새 target 에서 멀리
    //     떨어진 상황에서, 시각적으로 ~1.5s 안에 정착해 "탈선" 인상 방지.
    //   거리가 줄어들면서 자동으로 짧은 반감기 → 긴 반감기로 전환됨.
    //
    // 임계치 미만 즉시 클램프 정책은 시각적 점프를 유발하므로 사용 안 함.
    // 충분히 가까워지면(< SNAP_PX) target 으로 스냅 (마지막 0.5px 잔여 정리).
    var SNAP_PX = 0.5;
    var HALF_LIFE_FAR_MS = 500;   // dist > 30px
    var HALF_LIFE_NEAR_MS = 3000; // dist <= 30px
    var FAST_DIST_THRESHOLD = 30;

    // refresh 시 매번 step 재시작되므로 lastFrameMs 를 리셋하여 첫 frame 에서
    // 거대한 deltaMs 로 순간 수렴해버리는 현상을 방지.
    trainState.lastFrameMs = null;

    function step() {
      // [원칙 1] realRemaining = arrivalSeconds - (now - recptnDt)
      var realRemaining = Math.max(0,
        baseArrival - (Date.now() - receivedAt) / 1000);

      // 도착 말풍선: realRemaining(단조 감소, 원칙 1) 을 그대로 정수화해 표시.
      // 별도 카운트다운 변수를 두지 않고, 정수 초가 바뀔 때만 DOM 을 갱신해
      // 매 frame(~60fps) textContent 쓰기를 피한다.
      var shownSec = Math.ceil(realRemaining);
      if (trainState.lastShownSec !== shownSec) {
        trainState.lastShownSec = shownSec;
        updateArrivalBubbleText(trainState.element,
          formatArrivalBubbleText(realRemaining));
      }

      // [원칙 2] 역산
      var res = estimateTrainPosition(realRemaining, segDurations);

      // [원칙 3] 3-way 클램프 (확장 path 상 "역" index 기준).
      // 현재역-다음역 사이 서브세그먼트(curIdx..nextIdx-1) 에서는 정상 보간,
      // 그 외 범위 세그먼트는 현재역/다음역 좌표에 고정.
      var target;
      if (res.outOfPath) {
        target = path[curIdx];
      } else if (res.segmentIndex < curIdx) {
        target = path[curIdx];
      } else if (res.segmentIndex >= nextIdx) {
        target = path[nextIdx];
      } else {
        var p0 = path[res.segmentIndex];
        var p1 = path[res.segmentIndex + 1];
        target = {
          x: p0.x + (p1.x - p0.x) * res.progress,
          y: p0.y + (p1.y - p0.y) * res.progress
        };
      }

      // [원칙 4] currentPos → target 지수 감쇠 보간.
      // 첫 frame 에는 target 으로 즉시 초기화(점프 없음).
      if (!trainState.currentPos) {
        trainState.currentPos = { x: target.x, y: target.y };
      }
      var nowPerf = (typeof performance !== 'undefined' && performance.now)
        ? performance.now() : Date.now();
      var deltaMs = (trainState.lastFrameMs != null)
        ? Math.min(nowPerf - trainState.lastFrameMs, 100) : 16.67;
      trainState.lastFrameMs = nowPerf;

      var cp = trainState.currentPos;
      var dx = target.x - cp.x;
      var dy = target.y - cp.y;
      var dist = Math.sqrt(dx * dx + dy * dy);

      // 항상 지수 감쇠 적용 — 작은 차이도 즉시 클램프하지 않아 점프를 차단.
      if (dist < SNAP_PX) {
        cp.x = target.x;
        cp.y = target.y;
        trainState.catchingUp = false;
      } else {
        // dist 가 SNAP_PX 이상이면 catch-up 진행 중으로 표시 (도착 가드용).
        trainState.catchingUp = true;
        // [원칙 4 dynamic] 거리 클수록 짧은 반감기로 빨리 수렴.
        var halfLife = (dist > FAST_DIST_THRESHOLD)
          ? HALF_LIFE_FAR_MS : HALF_LIFE_NEAR_MS;
        var factor = Math.pow(0.5, deltaMs / halfLife);
        cp.x = target.x + (cp.x - target.x) * factor;
        cp.y = target.y + (cp.y - target.y) * factor;
        if (Math.abs(target.x - cp.x) < SNAP_PX &&
            Math.abs(target.y - cp.y) < SNAP_PX) {
          cp.x = target.x;
          cp.y = target.y;
          trainState.catchingUp = false;
        }
      }
      var pos = cp;

      trainState.element.setAttribute('transform',
        'translate(' + pos.x + ',' + pos.y + ')');

      // 도착 이펙트는 catch-up 이 끝난 뒤에 발동 (달리다 중간에 사라지는 현상 방지)
      if (realRemaining <= 0 && !trainState.catchingUp) {
        playArrivalEffect(trainState, trainData.trainNo);
        return;
      }
      trainState.animationId = requestAnimationFrame(step);
    }

    trainState.animationId = requestAnimationFrame(step);
  }

  function playArrivalEffect(trainState, trainNo) {
    arrivedTrains[trainNo] = true;
    // [원칙 1 보강] 도착한 trainNo 의 슬롯 메모리만 정리.
    // 같은 슬롯에 매 refresh 다른 trainNo 가 들어오는 노선(신분당선 등)에서
    // 무조건 slotKey 를 지우면 새 train 의 prev 정보까지 잃어 단조 감소가 깨짐.
    // 따라서 메모리의 trainNo 가 자기 자신과 일치할 때만 삭제.
    for (var k in trainSlotMemory) {
      if (trainSlotMemory[k].trainNo === trainNo) delete trainSlotMemory[k];
    }
    var el = trainState.element;
    var currentTransform = el.getAttribute('transform') || '';

    // 펄스 확대 + 페이드아웃 애니메이션 (0.6초)
    var duration = 600;
    var startTime = performance.now();

    function animate(now) {
      var elapsed = now - startTime;
      var progress = Math.min(elapsed / duration, 1.0);

      // easeOutCubic
      var eased = 1 - Math.pow(1 - progress, 3);

      var scale = 1 + eased;
      var opacity = 1 - eased;

      el.setAttribute('transform', currentTransform + ' scale(' + scale + ')');
      el.setAttribute('opacity', opacity);

      if (progress < 1.0) {
        trainState.animationId = requestAnimationFrame(animate);
      } else {
        trainState.animationId = null;
        if (el.parentNode) {
          el.parentNode.removeChild(el);
        }
        delete activeTrains[trainNo];
      }
    }

    trainState.animationId = requestAnimationFrame(animate);

    sendToFlutter({ action: 'trainArrived', trainNo: trainNo, destination: trainState.destination || '' });
  }

  function cancelTrainAnimation(trainState) {
    if (trainState.animationId) {
      cancelAnimationFrame(trainState.animationId);
      trainState.animationId = null;
    }
  }

  // [원칙 1 보강] 슬롯 보조키: trainNo 가 흔들려도 같은 노선/방향/행선/현재역
  // 조합이면 단조 감소를 강제하기 위한 식별자.
  function makeSlotKey(t) {
    return (t.lineId || '') + '|' + (t.direction || '') + '|' +
           (t.destination || '') + '|' + (t.currentStation || '');
  }

  // 슬롯 메모리에 현재 t 의 baseArrival/baseReceivedAt 을 기록한다.
  // clamp 적용 후 호출해 다음 refresh 의 prev 비교에 쓰인다.
  function rememberSlot(t, nowMs) {
    var k = makeSlotKey(t);
    if (k === '|||') return; // 빈 보조키 방어
    trainSlotMemory[k] = {
      trainNo: t.trainNo,
      baseArrival: (t.arrivalSeconds != null) ? t.arrivalSeconds : 0,
      baseReceivedAt: t.receivedAtEpochMs || nowMs,
      lastSeenMs: nowMs
    };
  }

  window.showTrains = function(trainsJson) {
    var trains = JSON.parse(trainsJson);
    var newTrainIds = {};

    // [원칙 1 보강] 보조키 fallback 충돌 검사용 사전 점유 카운트.
    // 같은 슬롯에 동시에 존재하는 train(기존 + 신규) 의 총 수를 센다. 점유가 1 일
    // 때만 trainSlotMemory 의 prev 정보를 신규 train 에 적용 — 동일 슬롯에 기존
    // train + 신규 train 이 공존하는 비정상 상황(잘못된 prev 인계 위험)에서도
    // fallback 을 비활성화해 안전 측 동작.
    var slotOccupancy = {};
    for (var pi = 0; pi < trains.length; pi++) {
      var pt = trains[pi];
      if (arrivedTrains[pt.trainNo]) continue;
      var pk = makeSlotKey(pt);
      slotOccupancy[pk] = (slotOccupancy[pk] || 0) + 1;
    }

    for (var i = 0; i < trains.length; i++) {
      var t = trains[i];
      if (arrivedTrains[t.trainNo]) continue;
      newTrainIds[t.trainNo] = true;
      var color = lineColors[t.lineId] || '#999';

      if (activeTrains[t.trainNo]) {
        var existing = activeTrains[t.trainNo];
        var nowMs = Date.now();

        // [원칙 1 보강] 단조 감소 강제 clamp.
        // API 가 arvlMsg2 라운딩 등으로 arrivalSeconds 를 동일 값으로 반복 반환하면
        // recptnDt 만 갱신되어 realRemaining 이 원복된다. 이전 refresh 기반 예상
        // realRemaining 보다 새 값이 크면 이전 값으로 clamp.
        if (existing.baseArrival != null && existing.baseReceivedAt != null) {
          var prevReal = Math.max(0,
            existing.baseArrival - (nowMs - existing.baseReceivedAt) / 1000);
          var newReceivedAt = (t.receivedAtEpochMs != null)
            ? t.receivedAtEpochMs : nowMs;
          var newReal = Math.max(0,
            (t.arrivalSeconds || 0) - (nowMs - newReceivedAt) / 1000);
          if (newReal > prevReal + 2) { // 2초 오차 허용 (네트워크 지터)
            t.arrivalSeconds = Math.round(prevReal);
            t.receivedAtEpochMs = nowMs;
          }
        }

        // 도착 임박 열차는 기존 애니메이션 유지 (15초 갱신에서 끊김 방지)
        // 단, 이미 도착역에 있는 열차(pathToTarget 1점)는 즉시 도착 처리
        if (t.arrivalSeconds <= 2 && (t.initialProgress || 0) >= 0.7 && existing.animationId
            && t.pathToTarget && t.pathToTarget.length >= 2) {
          existing.destination = t.destination || '';
          existing.lastArrivalSeconds = t.arrivalSeconds;
          existing.lastUpdateTime = nowMs;
          existing.baseArrival = t.arrivalSeconds;
          existing.baseReceivedAt = t.receivedAtEpochMs || nowMs;
          // 행선지는 말풍선의 .bubble-dest 줄(class 기반)로 갱신 —
          // 길이 변화에 맞춰 말풍선 너비도 재계산(짧아질 때도 재축소).
          updateArrivalBubbleDestination(existing.element, t.destination);
          updateTrainDebugInfo(existing.element, t);
          existing.slotKey = makeSlotKey(t);
          rememberSlot(t, nowMs);
          continue;
        }
        // [jitter grace] train 이 다시 보고됨 → 누락 카운트 리셋.
        existing.missedCycles = 0;
        cancelTrainAnimation(existing);
        existing.destination = t.destination || '';
        existing.lastArrivalSeconds = t.arrivalSeconds;
        existing.lastUpdateTime = nowMs;
        existing.baseArrival = t.arrivalSeconds;
        existing.baseReceivedAt = t.receivedAtEpochMs || nowMs;
        existing.slotKey = makeSlotKey(t);
        updateArrivalBubbleDestination(existing.element, t.destination);
        // [디버그용] 기존 열차의 디버그 정보 갱신
        updateTrainDebugInfo(existing.element, t);
        startTrainAnimation(existing, t);
        rememberSlot(t, nowMs);
      } else {
        var nowMs2 = Date.now();

        // [원칙 1 보강] 보조키 fallback clamp.
        // trainNo 가 흔들려 activeTrains miss 가 났더라도, 같은 슬롯
        // (lineId|direction|destination|currentStation) 의 prev 정보가 60초 이내이고
        // 신규 train 충돌이 없으면 단조 감소를 강제한다. 신분당선 등 btrainNo
        // 미제공 노선의 카운트다운 역행을 차단.
        var slotKey = makeSlotKey(t);
        var slotMem = trainSlotMemory[slotKey];
        if (slotMem != null
            && slotOccupancy[slotKey] === 1
            && (nowMs2 - slotMem.lastSeenMs) < 60000) {
          var prevReal = Math.max(0,
            slotMem.baseArrival - (nowMs2 - slotMem.baseReceivedAt) / 1000);
          var newReceivedAt2 = (t.receivedAtEpochMs != null)
            ? t.receivedAtEpochMs : nowMs2;
          var newReal2 = Math.max(0,
            (t.arrivalSeconds || 0) - (nowMs2 - newReceivedAt2) / 1000);
          if (newReal2 > prevReal + 2) {
            t.arrivalSeconds = Math.round(prevReal);
            t.receivedAtEpochMs = nowMs2;
          }
        }

        var g = createTrainIcon(t, color);
        liveTrainsGroup.appendChild(g);
        activeTrains[t.trainNo] = {
          element: g, animationId: null, destination: t.destination || '',
          lastArrivalSeconds: t.arrivalSeconds,
          lastUpdateTime: nowMs2,
          baseArrival: t.arrivalSeconds,
          baseReceivedAt: t.receivedAtEpochMs || nowMs2,
          // [원칙 1 보강] playArrivalEffect 시 이 trainNo 가 차지한 슬롯 메모리를
          // trainNo 매칭이 흔들려도 정확히 정리하기 위한 보조키 저장.
          slotKey: slotKey
        };
        startTrainAnimation(activeTrains[t.trainNo], t);
        rememberSlot(t, nowMs2);
      }
    }

    var toRemove = [];
    for (var id in activeTrains) {
      if (!newTrainIds[id]) {
        toRemove.push(id);
      }
    }
    // [도착/필터변경/jitter 분리 가드]
    // toRemove 는 "API 응답에서 더 이상 보이지 않는 train". 세 가지 원인.
    //   (A) 진짜 도착: API 가 보고 안 함 → 도착 애니메이션 발동 ✓
    //   (B) routeFilter 변경: 다른 노선/방향 → silent 제거
    //   (C) API jitter: Seoul 공공 API 가 same-cycle 에 train 을 일관성 없이 누락
    //       (다음 cycle 에 다시 보고됨). 즉시 제거 시 train 이 화면에서 증발 후
    //       재등장 → 사용자 인식 "탈선/증발". (5호선 영등포구청 이슈 원인)
    //
    // 처리:
    //   - ETA = lastArrivalSeconds - (now - lastUpdateTime)/1000
    //   - ETA > GRACE_S (예: 60s): 아직 도착 안 했고 jitter 일 가능성 높음 → 한 cycle
    //     grace. activeTrains 에 유지하고 다음 cycle 까지 기다림. 연속 누락 카운트 증가.
    //   - 누락 카운트 >= MAX_MISS (2): 진짜 사라진 것으로 판단해 제거.
    //   - ETA <= GRACE_S: 도착 임박 또는 도착 → 기존 처리 (도착 이펙트 / silent).
    var SILENT_REMOVE_THRESHOLD_S = 60;
    var JITTER_GRACE_S = 60;
    // 8 cycle ≈ 2분 grace. step() 이 자체적으로 ETA<=0 시 도착 처리하므로
    // 운행 종료 train 도 자연스럽게 정리됨. 짧게 잡으면 jitter 로 사라졌다 재등장
    // 패턴 발생 (5호선 영등포구청 케이스).
    var MAX_MISS_CYCLES = 8;
    for (var i = 0; i < toRemove.length; i++) {
      var id = toRemove[i];
      var trainState = activeTrains[id];
      var last = trainState.lastArrivalSeconds;
      var lastUpdate = trainState.lastUpdateTime;
      var eta = (last != null && lastUpdate != null)
        ? Math.max(0, last - (Date.now() - lastUpdate) / 1000)
        : 0;

      // ETA 양수 + 누락 카운트 한도 미만 → grace (애니메이션 유지, 제거 보류).
      if (eta > JITTER_GRACE_S) {
        trainState.missedCycles = (trainState.missedCycles || 0) + 1;
        if (trainState.missedCycles < MAX_MISS_CYCLES) {
          // 다음 cycle 까지 활성 유지. cancel/remove 안 함.
          continue;
        }
      }

      cancelTrainAnimation(trainState);
      if (last != null && last > SILENT_REMOVE_THRESHOLD_S) {
        // silent 제거: 도착 펄스 / trainArrived 이벤트 발동 안 함
        if (trainState.element && trainState.element.parentNode) {
          trainState.element.parentNode.removeChild(trainState.element);
        }
        // [원칙 1 보강] slotKey 직접 삭제 시 같은 슬롯에 이미 새 trainNo 가
        // 등록되어 있을 수 있으므로(신분당선처럼 매 refresh trainNo 가 흔들림),
        // 메모리의 trainNo 가 자기 자신일 때만 삭제. 이 가드 누락 시 새 train 의
        // prev 정보까지 같이 지워져 다음 cycle 의 fallback clamp 가 무력화됨.
        if (trainState.slotKey
            && trainSlotMemory[trainState.slotKey]
            && trainSlotMemory[trainState.slotKey].trainNo === id) {
          delete trainSlotMemory[trainState.slotKey];
        }
        delete activeTrains[id];
        continue;
      }
      playArrivalEffect(trainState, id);
    }

    // API에서 더 이상 보고하지 않는 열차는 arrivedTrains에서도 제거
    // 단, 아직 도착 애니메이션이 진행 중인(activeTrains에 남아있는) 열차는 유지
    var trainNoSet = {};
    for (var i = 0; i < trains.length; i++) trainNoSet[trains[i].trainNo] = true;
    for (var id in arrivedTrains) {
      if (!trainNoSet[id] && !activeTrains[id]) delete arrivedTrains[id];
    }

    // [원칙 1 보강] 60초 이상 미관측 슬롯 메모리 sweep.
    // 도착했거나 운행 종료된 슬롯의 prev 가 잔류해 새 열차 clamp 에 잘못 적용되는
    // 상황 방지. activeTrains 와 분리되어 있으므로 별도 TTL 로 만료.
    var sweepNow = Date.now();
    for (var sk in trainSlotMemory) {
      if (sweepNow - trainSlotMemory[sk].lastSeenMs > 60000) {
        delete trainSlotMemory[sk];
      }
    }
  };

  window.clearTrains = function() {
    for (var id in activeTrains) {
      cancelTrainAnimation(activeTrains[id]);
    }
    activeTrains = {};
    arrivedTrains = {};
    trainSlotMemory = {};
    liveTrainsGroup.replaceChildren();
  };

  // 1초마다 디버그 남은시간 카운트다운 (SHOW_TRAIN_DEBUG=false 면 즉시 스킵)
  setInterval(function() {
    if (!SHOW_TRAIN_DEBUG) return;
    var now = Date.now();
    for (var id in activeTrains) {
      var train = activeTrains[id];
      if (train.lastArrivalSeconds == null || train.lastUpdateTime == null) continue;
      var elapsed = Math.floor((now - train.lastUpdateTime) / 1000);
      var remaining = Math.max(0, train.lastArrivalSeconds - elapsed);
      var secEl = train.element.querySelector('.debug-seconds');
      if (secEl) secEl.textContent = '\uCD08: ' + remaining;
    }
  }, 1000);

  // ============================================================
  // 경로 선택 툴바
  // ============================================================

  function updateRouteToolbarPosition() {
    if (!toolbarVisible) return;
    // toolbarSvgX/Y가 앵커(출발역 또는 사용자가 드래그한 위치의 SVG 좌표)를
    // 나타내므로 항상 맵 pan/zoom에 맞춰 화면 좌표로 재계산한다.
    // 결과: 툴바가 맵에 부착된 것처럼 카메라 이동과 함께 따라 움직임.
    var screenX = toolbarSvgX * scale + tx;
    var screenY = toolbarSvgY * scale + ty;

    var left = screenX;
    var top = screenY - cachedTbH - 18;

    routeToolbar.style.left = left + 'px';
    routeToolbar.style.top = top + 'px';
  }

  window.showRouteToolbar = function(svgX, svgY, hasTwoRoutes) {
    toolbarSvgX = svgX;
    toolbarSvgY = svgY;

    routeToolbar.textContent = '';

    var closeBtn = document.createElement('button');
    closeBtn.className = 'route-toolbar-btn close-btn';
    closeBtn.textContent = '\u00d7';
    closeBtn.addEventListener('click', function() {
      sendToFlutter({ action: 'routeToolbarSelect', mode: 'cancel' });
    });
    routeToolbar.appendChild(closeBtn);

    var modes = [{key: 'fastest', label: '최단경로'}];
    if (hasTwoRoutes) {
      modes.push({key: 'leastTransfer', label: '최소환승'});
    }
    modes.push({key: 'result', label: '경로 검색결과'});

    for (var i = 0; i < modes.length; i++) {
      var m = modes[i];
      var btn = document.createElement('button');
      btn.className = 'route-toolbar-btn';
      btn.textContent = m.label;
      btn.setAttribute('data-mode', m.key);
      if (m.key === 'fastest') btn.classList.add('active');

      btn.addEventListener('click', (function(mode) {
        return function() {
          if (mode !== 'result') {
            var btns = routeToolbar.querySelectorAll('.route-toolbar-btn:not(.close-btn)');
            for (var j = 0; j < btns.length; j++) {
              btns[j].classList.remove('active');
            }
            this.classList.add('active');
          }
          sendToFlutter({ action: 'routeToolbarSelect', mode: mode });
        };
      })(m.key));

      routeToolbar.appendChild(btn);
    }

    toolbarVisible = true;
    routeToolbar.style.display = 'flex';
    cachedTbW = routeToolbar.offsetWidth;
    cachedTbH = routeToolbar.offsetHeight;
    updateRouteToolbarPosition();
  };

  window.hideRouteToolbar = function() {
    routeToolbar.style.display = 'none';
    toolbarVisible = false;
  };

  // 경로 결과 툴바 드래그 이동: 상단 빈 바 영역(padding-top:28px)을 잡아서
  // 끌면 툴바 위치를 옮긴다. 선로/열차를 가릴 때 사용자가 치울 수 있도록 한다.
  // .route-toolbar-btn(X 포함)은 드래그 시작 대상에서 제외해 클릭 동작 보존.
  // 드래그 종료 시 툴바의 화면 위치를 SVG 좌표로 역변환해 앵커(toolbarSvgX/Y)로
  // 저장하므로, 이후 맵 pan/zoom 시 툴바가 맵에 부착된 듯 함께 이동한다.
  //
  // 중요: 지도 팬 핸들러가 document의 pointerdown/pointermove에 등록돼 있으므로
  // 반드시 같은 Pointer Events 계열로 구현하고, 드래그 시작 시 stopPropagation()으로
  // document 핸들러 전파를 끊어야 툴바 드래그와 지도 팬이 겹치지 않는다.
  (function initRouteToolbarDrag() {
    var dragState = null;

    function onDragStart(e) {
      if (e.target.closest('.route-toolbar-btn')) return; // 버튼 영역 제외
      if (e.target !== routeToolbar) return; // 상단 빈 바(컨테이너 자체)만 드래그 핸들

      // document의 지도 pan 핸들러로 이벤트 전파 차단
      e.stopPropagation();
      e.preventDefault();

      // 맵 pan state를 강제 초기화: 동시에 맵 pan이 진행 중이거나
      // 이전 터치 잔재가 남아있지 않도록 보장
      for (var __k in pointers) if (pointers.hasOwnProperty(__k)) delete pointers[__k];
      isDragging = false;

      var rect = routeToolbar.getBoundingClientRect();
      dragState = {
        pointerId: e.pointerId,
        startX: e.clientX,
        startY: e.clientY,
        toolbarLeft: rect.left,
        toolbarTop: rect.top
      };
    }

    function onDragMove(e) {
      if (!dragState || e.pointerId !== dragState.pointerId) return;
      e.stopPropagation();
      e.preventDefault();

      var dx = e.clientX - dragState.startX;
      var dy = e.clientY - dragState.startY;
      var newLeft = dragState.toolbarLeft + dx;
      var newTop = dragState.toolbarTop + dy;

      // 화면 경계 clamp: 툴바가 화면 밖으로 나가 못 되돌리는 상황 방지
      var tw = routeToolbar.offsetWidth;
      var th = routeToolbar.offsetHeight;
      newLeft = Math.max(8, Math.min(window.innerWidth - tw - 8, newLeft));
      newTop = Math.max(8, Math.min(window.innerHeight - th - 8, newTop));

      routeToolbar.style.left = newLeft + 'px';
      routeToolbar.style.top = newTop + 'px';
    }

    function onDragEnd(e) {
      if (!dragState) return;
      if (e && e.pointerId !== dragState.pointerId) return;
      // 혹시 어디서 capture가 걸려 있다면 해제 (방어)
      if (routeToolbar.hasPointerCapture &&
          routeToolbar.hasPointerCapture(dragState.pointerId) &&
          routeToolbar.releasePointerCapture) {
        try { routeToolbar.releasePointerCapture(dragState.pointerId); } catch (_) {}
      }
      // 드래그로 옮긴 툴바의 화면 위치를 SVG 좌표로 역변환하여 앵커로 저장.
      // 이후 맵 pan/zoom 시 updateRouteToolbarPosition이 이 앵커 기준으로
      // 툴바를 재배치하므로 툴바가 맵에 부착된 듯 함께 이동한다.
      // updateRouteToolbarPosition의 기준: left = screenX, top = screenY - cachedTbH - 18
      // 따라서 screenX = rect.left, screenY = rect.top + cachedTbH + 18
      var rect = routeToolbar.getBoundingClientRect();
      toolbarSvgX = (rect.left - tx) / scale;
      toolbarSvgY = (rect.top + cachedTbH + 18 - ty) / scale;
      dragState = null;
      // 맵 pan state 완전 클리어: 다음 맵 터치가 깨끗하게 pan을 시작하도록 보장
      for (var __k in pointers) if (pointers.hasOwnProperty(__k)) delete pointers[__k];
      isDragging = false;
    }

    routeToolbar.addEventListener('pointerdown', onDragStart);
    document.addEventListener('pointermove', onDragMove);
    document.addEventListener('pointerup', onDragEnd);
    document.addEventListener('pointercancel', onDragEnd);
  })();

  // ============================================================
  // 디버그: 탭 영역 시각화
  // ============================================================
  window.debugTapTargets = function(show) {
    var svg = document.querySelector('svg');
    var existing = document.getElementById('debug-tap-overlay');
    if (existing) existing.remove();
    if (show === false) return;

    var ns = 'http://www.w3.org/2000/svg';
    var g = document.createElementNS(ns, 'g');
    g.id = 'debug-tap-overlay';

    // 텍스트 바운딩 박스 (1차 탭 영역, 파란색)
    for (var i = 0; i < svgTextTargets.length; i++) {
      var t = svgTextTargets[i];
      var rect = document.createElementNS(ns, 'rect');
      rect.setAttribute('x', t.cx - t.halfW);
      rect.setAttribute('y', t.cy - t.halfH);
      rect.setAttribute('width', t.halfW * 2);
      rect.setAttribute('height', t.halfH * 2);
      rect.setAttribute('fill', 'rgba(0,100,255,0.25)');
      rect.setAttribute('stroke', 'rgba(0,100,255,0.6)');
      rect.setAttribute('stroke-width', '0.5');
      g.appendChild(rect);
    }

    // circle 좌표 기반 TAP_RADIUS (2차 폴백, 빨간색)
    for (var i = 0; i < stations.length; i++) {
      var s = stations[i];
      var circle = document.createElementNS(ns, 'circle');
      circle.setAttribute('cx', s.svgX);
      circle.setAttribute('cy', s.svgY);
      circle.setAttribute('r', TAP_RADIUS);
      circle.setAttribute('fill', 'rgba(255,50,50,0.2)');
      circle.setAttribute('stroke', 'rgba(255,50,50,0.5)');
      circle.setAttribute('stroke-width', '0.5');
      g.appendChild(circle);
    }

    svg.appendChild(g);
  };

  // ============================================================
  // 초기화
  // ============================================================
  setInitialView();
  window.addEventListener('resize', function() {
    clampTranslation();
    scheduleTransform();
  });
})();
</script>
</body>
</html>''';
}
