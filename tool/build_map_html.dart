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

  final html = _buildHtml(svgContent);

  final htmlFile = File(htmlPath);
  htmlFile.parent.createSync(recursive: true);
  htmlFile.writeAsStringSync(html);

  final svgSize = svgFile.lengthSync();
  final htmlSize = htmlFile.lengthSync();

  stdout.writeln('HTML 생성 완료');
  stdout.writeln('  SVG: ${(svgSize / 1024).toStringAsFixed(1)}KB');
  stdout.writeln('  HTML: ${(htmlSize / 1024).toStringAsFixed(1)}KB');
}

String _buildHtml(String svgContent) {
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
svg text {
  stroke: white;
  stroke-width: 2px;
  paint-order: stroke;
  stroke-linejoin: round;
}
</style>
</head>
<body>
<div id="map-container">
$svgContent
<svg id="overlay" xmlns="http://www.w3.org/2000/svg" width="2416" height="1560">
  <rect id="route-overlay-bg" width="2416" height="1560" fill="white" opacity="0" />
  <g id="route-lines"></g>
  <g id="route-markers"></g>
  <g id="selection-markers"></g>
</svg>
<div id="tap-layer"></div>
</div>

<div id="tooltip" class="tooltip"></div>

<script>
(function() {
  'use strict';

  // ============================================================
  // 상수
  // ============================================================
  var CANVAS_W = 2416, CANVAS_H = 1560;
  var MIN_SCALE = 1.0, MAX_SCALE = 5.0;
  var TAP_RADIUS = 12;
  var INITIAL_SCALE = 1.0;
  var INITIAL_CENTER_X = 1040, INITIAL_CENTER_Y = 618;

  // ============================================================
  // 상태
  // ============================================================
  var scale = INITIAL_SCALE;
  var tx = 0, ty = 0;
  var stations = [];
  var connections = [];
  var lineColors = {};
  var lineNames = {};

  var container = document.getElementById('map-container');
  var tapLayer = document.getElementById('tap-layer');
  var tooltip = document.getElementById('tooltip');
  var overlayBg = document.getElementById('route-overlay-bg');
  var routeLines = document.getElementById('route-lines');
  var routeMarkers = document.getElementById('route-markers');
  var selectionMarkers = document.getElementById('selection-markers');

  // ============================================================
  // 변환 적용
  // ============================================================
  function applyTransform() {
    container.style.transform = 'matrix(' + scale + ',0,0,' + scale + ',' + tx + ',' + ty + ')';
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
      if (Math.abs(dx) > 3 || Math.abs(dy) > 3) hasMoved = true;
      tx = dragStartTx + dx;
      ty = dragStartTy + dy;
      clampTranslation();
      applyTransform();
    } else if (getPointerCount() === 2) {
      hasMoved = true;
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
      applyTransform();
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
    applyTransform();
  }, { passive: false });

  // ============================================================
  // 탭 감지 (텍스트 라벨 + circle 좌표 하이브리드)
  // ============================================================
  var svgTextTargets = []; // SVG text 요소의 바운딩 박스

  function buildTextTargets() {
    svgTextTargets = [];
    var texts = document.querySelectorAll('text[data-station]');
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
        routeMarkers.appendChild(bg);
      } else {
        var dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        dot.setAttribute('cx', s.svgX);
        dot.setAttribute('cy', s.svgY);
        dot.setAttribute('r', r);
        dot.setAttribute('fill', color);
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
    g.appendChild(bg);

    // 테두리 링
    var ring = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    ring.setAttribute('cx', svgX);
    ring.setAttribute('cy', svgY);
    ring.setAttribute('r', '9');
    ring.setAttribute('fill', 'none');
    ring.setAttribute('stroke', color);
    ring.setAttribute('stroke-width', '2.5');
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
    applyTransform();
  });
})();
</script>
</body>
</html>''';
}
