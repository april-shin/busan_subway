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
  stroke: white;
  stroke-width: var(--stroke-w, 2px);
  paint-order: stroke;
  stroke-linejoin: round;
}
path[data-line] { stroke-width: 5 !important; }
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
  <g id="live-trains"></g>
</svg>
<div id="tap-layer"></div>
</div>

<svg id="text-layer" xmlns="http://www.w3.org/2000/svg"
  viewBox="0 0 2416 1560">
$textElements
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
  var SVG_NS = 'http://www.w3.org/2000/svg';
  var textLayer = document.getElementById('text-layer');

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

    // 역명 → 소속 노선 lineId 집합 캐시 (환승역 text/circle 매칭용)
    stationLineMap = {};
    for (var i = 0; i < stations.length; i++) {
      var sn = stations[i].name;
      if (!stationLineMap[sn]) stationLineMap[sn] = {};
      stationLineMap[sn][stations[i].lineId] = true;
    }
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

    // 스테이션 맵 구축
    var stationMap = {};
    for (var i = 0; i < stations.length; i++) {
      stationMap[stations[i].id] = stations[i];
    }

    // 경로 구간 그리기
    for (var i = 0; i < connections.length; i++) {
      var conn = connections[i];
      if (conn.isTransfer) continue;

      var from = stationMap[conn.fromStationId];
      var to = stationMap[conn.toStationId];
      if (!from || !to) continue;

      if (!routeSet[from.id] || !routeSet[to.id]) continue;

      var color = lineColors[conn.lineId] || '#999';
      var line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      line.setAttribute('x1', from.svgX);
      line.setAttribute('y1', from.svgY);
      line.setAttribute('x2', to.svgX);
      line.setAttribute('y2', to.svgY);
      line.setAttribute('stroke', color);
      line.setAttribute('stroke-width', '5');
      line.setAttribute('stroke-linecap', 'round');
      routeLines.appendChild(line);
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
    var color = lineColors[s.lineId] || '#999';
    var lineName = lineNames[s.lineId] || s.lineId;

    // 기존 내용 제거
    tooltip.textContent = '';

    // 헤더
    var header = document.createElement('div');
    header.className = 'tooltip-header';

    var badge = document.createElement('span');
    badge.className = 'line-badge';
    badge.style.background = color;
    badge.textContent = lineName;
    header.appendChild(badge);

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

    // 환승 노선 표시
    if (s.isTransfer && s.transferLines && s.transferLines.length > 1) {
      var transferDiv = document.createElement('div');
      transferDiv.className = 'transfer-lines';
      for (var i = 0; i < s.transferLines.length; i++) {
        var tl = s.transferLines[i];
        if (tl === s.lineId) continue;
        var tc = lineColors[tl] || '#999';
        var tn = lineNames[tl] || tl;
        var tb = document.createElement('span');
        tb.className = 'transfer-badge';
        tb.style.background = tc;
        tb.textContent = tn;
        transferDiv.appendChild(tb);
      }
      tooltip.appendChild(transferDiv);
    }

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

  function createTrainIcon(train, color) {
    var g = document.createElementNS(SVG_NS, 'g');

    var img = document.createElementNS(SVG_NS, 'image');
    img.setAttribute('href', TRAIN_IMG);
    img.setAttribute('x', '-18');
    img.setAttribute('y', '-6.5');
    img.setAttribute('width', '36');
    img.setAttribute('height', '13');
    g.appendChild(img);

    var labelBg = document.createElementNS(SVG_NS, 'rect');
    labelBg.setAttribute('x', '-18');
    labelBg.setAttribute('y', '-20');
    labelBg.setAttribute('width', '36');
    labelBg.setAttribute('height', '11');
    labelBg.setAttribute('rx', '3');
    labelBg.setAttribute('fill', color);
    labelBg.setAttribute('opacity', '0.85');
    g.appendChild(labelBg);

    var label = document.createElementNS(SVG_NS, 'text');
    label.setAttribute('x', '0');
    label.setAttribute('y', '-11.5');
    label.setAttribute('text-anchor', 'middle');
    label.setAttribute('font-size', '8');
    label.setAttribute('fill', '#fff');
    label.setAttribute('font-family', 'sans-serif');
    label.textContent = train.destination || '';
    g.appendChild(label);

    // [디버그용] 열차 위치 결정 요소 표시
    g.appendChild(buildDebugGroup(train));

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
      t.textContent = lines[i];
      dg.appendChild(t);
    }

    return dg;
  }

  // [디버그용] 기존 열차 아이콘의 디버그 정보 텍스트를 갱신한다.
  function updateTrainDebugInfo(element, train) {
    var old = element.querySelector('.train-debug-info');
    if (old) old.remove();
    element.appendChild(buildDebugGroup(train));
  }

  function startTrainAnimation(trainState, trainData) {
    var path = trainData.pathToTarget;
    if (!path || path.length < 2) {
      if (path && path.length === 1) {
        trainState.element.setAttribute('transform',
          'translate(' + path[0].x + ',' + path[0].y + ')');
        playArrivalEffect(trainState, trainData.trainNo);
      }
      return;
    }

    var animPath = path;
    var durationMs = Math.max(trainData.arrivalSeconds, 1) * 1000;
    var segDurations = trainData.segmentDurations || [];
    var initProgress = trainData.initialProgress || 0;
    var sliceOffset = 0; // 이어서 진행 시 잘린 세그먼트 수

    // 기존 열차의 현재 시각적 위치 읽기
    // 15초마다 API 갱신 시, 같은 역을 보고하면 애니메이션이 처음으로 되돌아가는 문제 방지
    var transformAttr = trainState.element.getAttribute('transform');
    if (transformAttr) {
      var match = transformAttr.match(/translate\\(\\s*([^,]+)\\s*,\\s*([^)]+)\\s*\\)/);
      if (match) {
        var curX = parseFloat(match[1]);
        var curY = parseFloat(match[2]);
        var dx0 = curX - path[0].x;
        var dy0 = curY - path[0].y;
        var distFromStart = Math.sqrt(dx0 * dx0 + dy0 * dy0);

        if (distFromStart > 2) {
          // 경로에서 현재 위치와 가장 가까운 세그먼트 찾기
          var bestSeg = 0;
          var minDist = Infinity;
          for (var si = 0; si < path.length - 1; si++) {
            var ax = path[si].x, ay = path[si].y;
            var bx = path[si + 1].x, by = path[si + 1].y;
            var sdx = bx - ax, sdy = by - ay;
            var len2 = sdx * sdx + sdy * sdy;
            var t = len2 > 0
              ? Math.max(0, Math.min(1, ((curX - ax) * sdx + (curY - ay) * sdy) / len2))
              : 0;
            var px = ax + t * sdx, py = ay + t * sdy;
            var d = Math.sqrt((curX - px) * (curX - px) + (curY - py) * (curY - py));
            if (d < minDist) { minDist = d; bestSeg = si; }
          }

          // 경로에서 가까운 위치(30px 이내)면 현재 위치에서 이어서 진행
          if (minDist < 30) {
            var remaining = path.slice(bestSeg + 1);
            if (remaining.length > 0) {
              animPath = [{ x: curX, y: curY }].concat(remaining);
              sliceOffset = bestSeg; // 잘린 세그먼트 수 기록
              initProgress = 0; // 이어서 진행 시 initialProgress 무시
            } else {
              // 마지막 세그먼트를 지남 → 목적지에 고정
              var last = path[path.length - 1];
              trainState.element.setAttribute('transform',
                'translate(' + last.x + ',' + last.y + ')');
              return;
            }
          }
        }
      }
    }

    // 세그먼트별 시간 가중치 구축
    var segTimes = [];
    var hasDurations = segDurations.length === path.length - 1;

    if (sliceOffset > 0 && hasDurations) {
      // 이어서 진행: 첫 세그먼트는 현재→다음역 (잘린 세그먼트 시간 사용)
      var slicedDurations = segDurations.slice(sliceOffset);
      // 첫 세그먼트는 부분 구간이므로 원래 시간 그대로 사용 (근사)
      segTimes = slicedDurations.length > 0 ? slicedDurations : [];
      // animPath 첫 점은 현재 위치이므로 segTimes 길이가 animPath.length-1과 다를 수 있음
      // animPath = [curPos, path[bestSeg+1], ...] → segTimes에 첫 세그먼트 추가
      if (segTimes.length < animPath.length - 1) {
        segTimes.unshift(segTimes.length > 0 ? segTimes[0] : 120);
      }
    } else if (hasDurations) {
      segTimes = segDurations.slice();
    }

    // segTimes가 유효하지 않으면 SVG 거리 기반 폴백
    var useTimes = segTimes.length === animPath.length - 1;
    var totalTime = 0;
    var segDists = [];

    if (useTimes) {
      for (var i = 0; i < segTimes.length; i++) {
        totalTime += segTimes[i];
      }
    }

    // SVG 거리도 항상 계산 (보간에 필요)
    var totalDist = 0;
    for (var i = 1; i < animPath.length; i++) {
      var dx = animPath[i].x - animPath[i - 1].x;
      var dy = animPath[i].y - animPath[i - 1].y;
      var d = Math.sqrt(dx * dx + dy * dy);
      segDists.push(d);
      totalDist += d;
    }

    if (totalDist === 0) return;
    if (useTimes && totalTime === 0) useTimes = false;

    var startTime = performance.now();

    function step(now) {
      var elapsed = now - startTime;
      var timeProgress = Math.min(elapsed / durationMs, 1.0);

      var pos = animPath[animPath.length - 1];

      if (useTimes) {
        // 시간 가중 보간
        // initialProgress: 첫 세그먼트 시간의 일정 비율을 이미 진행한 것으로 간주
        var startTimeOffset = initProgress * segTimes[0];
        var effectiveTotalTime = totalTime - startTimeOffset;
        if (effectiveTotalTime <= 0) effectiveTotalTime = totalTime;

        var targetTime = startTimeOffset + timeProgress * effectiveTotalTime;
        var accumulated = 0;

        for (var i = 0; i < segTimes.length; i++) {
          if (accumulated + segTimes[i] >= targetTime) {
            var segProgress = segTimes[i] > 0
              ? (targetTime - accumulated) / segTimes[i]
              : 0;
            pos = {
              x: animPath[i].x + (animPath[i + 1].x - animPath[i].x) * segProgress,
              y: animPath[i].y + (animPath[i + 1].y - animPath[i].y) * segProgress
            };
            break;
          }
          accumulated += segTimes[i];
        }
      } else {
        // SVG 거리 기반 폴백 (기존 방식)
        var targetDist = timeProgress * totalDist;
        var accumulated = 0;

        for (var i = 0; i < segDists.length; i++) {
          if (accumulated + segDists[i] >= targetDist) {
            var segProgress = segDists[i] > 0
              ? (targetDist - accumulated) / segDists[i]
              : 0;
            pos = {
              x: animPath[i].x + (animPath[i + 1].x - animPath[i].x) * segProgress,
              y: animPath[i].y + (animPath[i + 1].y - animPath[i].y) * segProgress
            };
            break;
          }
          accumulated += segDists[i];
        }
      }

      trainState.element.setAttribute('transform',
        'translate(' + pos.x + ',' + pos.y + ')');

      if (timeProgress < 1.0) {
        trainState.animationId = requestAnimationFrame(step);
      } else {
        playArrivalEffect(trainState, trainData.trainNo);
      }
    }

    trainState.animationId = requestAnimationFrame(step);
  }

  function playArrivalEffect(trainState, trainNo) {
    arrivedTrains[trainNo] = true;
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

  window.showTrains = function(trainsJson) {
    var trains = JSON.parse(trainsJson);
    var newTrainIds = {};

    for (var i = 0; i < trains.length; i++) {
      var t = trains[i];
      if (arrivedTrains[t.trainNo]) continue;
      newTrainIds[t.trainNo] = true;
      var color = lineColors[t.lineId] || '#999';

      if (activeTrains[t.trainNo]) {
        cancelTrainAnimation(activeTrains[t.trainNo]);
        activeTrains[t.trainNo].destination = t.destination || '';
        var texts = activeTrains[t.trainNo].element.querySelectorAll('text');
        if (texts.length > 0) {
          texts[0].textContent = t.destination || '';
        }
        // [디버그용] 기존 열차의 디버그 정보 갱신
        updateTrainDebugInfo(activeTrains[t.trainNo].element, t);
        startTrainAnimation(activeTrains[t.trainNo], t);
      } else {
        var g = createTrainIcon(t, color);
        liveTrainsGroup.appendChild(g);
        activeTrains[t.trainNo] = { element: g, animationId: null, destination: t.destination || '' };
        startTrainAnimation(activeTrains[t.trainNo], t);
      }
    }

    var toRemove = [];
    for (var id in activeTrains) {
      if (!newTrainIds[id]) {
        toRemove.push(id);
      }
    }
    for (var i = 0; i < toRemove.length; i++) {
      var id = toRemove[i];
      cancelTrainAnimation(activeTrains[id]);
      playArrivalEffect(activeTrains[id], id);
    }

    // API에서 더 이상 보고하지 않는 열차는 arrivedTrains에서도 제거
    // 단, 아직 도착 애니메이션이 진행 중인(activeTrains에 남아있는) 열차는 유지
    var trainNoSet = {};
    for (var i = 0; i < trains.length; i++) trainNoSet[trains[i].trainNo] = true;
    for (var id in arrivedTrains) {
      if (!trainNoSet[id] && !activeTrains[id]) delete arrivedTrains[id];
    }
  };

  window.clearTrains = function() {
    for (var id in activeTrains) {
      cancelTrainAnimation(activeTrains[id]);
    }
    activeTrains = {};
    arrivedTrains = {};
    liveTrainsGroup.replaceChildren();
  };

  // ============================================================
  // 경로 선택 툴바
  // ============================================================

  function updateRouteToolbarPosition() {
    if (!toolbarVisible) return;
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
