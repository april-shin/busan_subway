/* 지오메트리 편집기(선분 · 환승마커 모드) — tool/badge_editor.dart 가 editor.js 뒤에 합성해 서빙한다.
 * 프로덕션 assets/html/map.html 에는 이 코드가 들어가지 않는다. editor.js 가 만든 패널·탭·`window.BadgeEditorHost` 에 붙는다.
 *
 * 원칙
 * - 편집 대상은 원본 SVG 의 <path>(노선 선, 정점 단위) 와 <rect>(환승 마커). 둘 다 id 가 없어 **문서 안 등장 순서 index** 로
 *   식별한다(좌표는 편집하면 바뀌므로 키로 못 쓴다). map.html 은 SVG 에서 <text> 만 떼어 같은 순서로 인라인하므로
 *   `#map-container > svg` 안의 path/rect 순서가 서버 모델의 index 와 같다.
 * - 규칙 판정은 서버가 한다: 선로 이탈 역(12px 하드 · 4px 소프트)과 환승 마커↔stations.json 좌표 드리프트는
 *   /api/geometry/check (규칙은 tool/geometry_svg.dart 한 곳), 저장·빌드·원복은 /api/geometry/save. 여기에는 기하 규칙을
 *   복제하지 않는다(화면과 빌드 결과가 갈라지는 것을 막는다).
 * - 선 편집은 정점 드래그와 **구간(두 정점 사이 선) 드래그** 둘 다 된다. 구간은 Shift-클릭으로 **같은 선 위의 연속 구간(런)** 으로
 *   확장할 수 있고, 런을 끌면 런의 모든 정점(과 겹친 점)이 **같은 양을 한 번만** 평행 이동한다 — 정점 드래그와 같은
 *   groupFor/undo/12px 판정을 탄다.
 * - 흰색 이중선(`{code}-1`)은 본체와 d 가 같다. 본체를 옮기면 화면에서도 같이 옮긴다(서버도 저장 때 같이 쓴다).
 * - 역 circle·라벨·알약 배지는 옮기지 않는다(사용자 결정 "선만 옮기고 역은 따로").
 */
(function () {
  'use strict';

  var Host = window.BadgeEditorHost;
  if (!Host) { window.alert('지오메트리 편집기: editor.js 가 먼저 올라와야 한다(BadgeEditorHost 없음).'); return; }
  var $ = Host.$, el = Host.el, sv = Host.sv, api = Host.api, toSvg = Host.toSvg, textLayer = Host.textLayer, panel = Host.panel;
  var mapSvg = document.querySelector('#map-container > svg:not(#overlay)');
  if (!mapSvg) { window.alert('지오메트리 편집기: 지도 <svg> 를 찾지 못했다 — map.html 구조가 바뀌었다.'); return; }

  var COLORS = { sel: '#1565d8', changed: '#e08a00', bad: '#d62828', soft: '#d9a000', pre: '#8a909c' };
  var LOG_KEY = 'beGeoLog';

  var G = {
    loaded: false, error: null, rev: null,
    paths: [], byIdx: {}, editIdx: [], rects: [],
    domPaths: [], domRects: [],
    pts: {}, orig: {}, rw: {}, ro: {},          // 작업본/원본 (path index → [[x,y]…], rect index → {x,y,w,h})
    interrupted: null, alerts: [],              // 지난 저장 중단 안내(서버) / 저장 직후 경고 배너
    markerLengths: [16, 20, 24, 28], thick: 8,
    filter: '', snap: 4, joint: true,
    selV: null, selS: null, selR: null,         // {p, v} / {p, v0, v1, ref}(런 = 정점 v0..v1 · 구간 v1-v0 개, ref = 집은 정점) / rect index
    hoverS: null,
    undo: { line: [], marker: [] }, undoStamp: 0,
    drag: null,
    off: [], offSoft: [], drift: [], orphans: [], offBusy: false, offWant: false, offPromise: null, offStale: false,
    saving: false, mismatch: 0,
    log: '', logKind: '', lastScale: 1, drawQueued: false, labels: {}
  };

  // ---------------------------------------------------------------- util
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function snapV(v) { return Math.round(v / G.snap) * G.snap; }
  function r3(v) { return Math.round(v * 1000) / 1000; }
  function scale() { var c = textLayer.getScreenCTM(); return c ? c.a : 1; }
  function same(a, b) { return Math.abs(a - b) < 1e-6; }
  function mode() { return Host.mode; }
  function isGeo() { return Host.mode === 'line' || Host.mode === 'marker'; }

  // ---------------------------------------------------------------- 변경 집계
  function changedVerts() {
    var n = 0, paths = [];
    G.editIdx.forEach(function (i) {
      var a = G.pts[i], b = G.orig[i], c = 0;
      for (var k = 0; k < a.length; k++) if (!same(a[k][0], b[k][0]) || !same(a[k][1], b[k][1])) c++;
      if (c) { n += c; paths.push(i); }
    });
    return { verts: n, paths: paths };
  }
  function changedRects() {
    var out = [];
    Object.keys(G.rw).forEach(function (k) {
      var a = G.rw[k], b = G.ro[k];
      if (!same(a.x, b.x) || !same(a.y, b.y) || !same(a.w, b.w) || !same(a.h, b.h)) out.push(+k);
    });
    return out;
  }
  function vertChanged(p, v) {
    return !same(G.pts[p][v][0], G.orig[p][v][0]) || !same(G.pts[p][v][1], G.orig[p][v][1]);
  }
  function geoCount() { return changedVerts().verts + changedRects().length; }

  Host.dirtyOf.line = function () { return G.loaded && changedVerts().verts > 0; };
  Host.dirtyOf.marker = function () { return G.loaded && changedRects().length > 0; };
  // 고아 마커는 저장 여부와 무관한 **기존 SVG 의 문제**라 배지 모드에서도 보여야 한다.
  Host.alertOf.marker = function () { return G.loaded ? G.orphans.length : 0; };
  Host.geoDirtyCount = function () { return G.loaded ? geoCount() : 0; };

  // ---------------------------------------------------------------- DOM 반영
  function dString(pts) {
    return pts.map(function (q, i) { return (i ? 'L ' : 'M ') + r3(q[0]) + ' ' + r3(q[1]); }).join(' ');
  }
  function placePathDom(i) {
    var d = dString(G.pts[i]);
    var e = G.domPaths[i];
    if (e) e.setAttribute('d', d);
    (G.byIdx[i].twins || []).forEach(function (t) { if (G.domPaths[t]) G.domPaths[t].setAttribute('d', d); });
  }
  function placeRectDom(i) {
    var r = G.rw[i], e = G.domRects[i];
    if (!e) return;
    e.setAttribute('x', r3(r.x)); e.setAttribute('y', r3(r.y));
    e.setAttribute('width', r3(r.w)); e.setAttribute('height', r3(r.h));
    requestCheck();                                   // 마커↔stations.json 드리프트 재판정
  }

  // ---------------------------------------------------------------- 오버레이
  var overlay = sv('g', { id: 'geo-editor-overlay', 'pointer-events': 'none' });
  textLayer.appendChild(overlay);

  function add(tag, attrs) {
    attrs['vector-effect'] = 'non-scaling-stroke';
    var e = sv(tag, attrs);
    overlay.appendChild(e);
    return e;
  }

  function visible(i) { return G.filter === '' || G.filter === String(i); }

  function scheduleDraw() {
    if (G.drawQueued) return;
    G.drawQueued = true;
    requestAnimationFrame(function () { G.drawQueued = false; drawOverlay(); });
  }

  function drawOverlay() {
    while (overlay.firstChild) overlay.removeChild(overlay.firstChild);
    if (!G.loaded || !isGeo()) return;
    G.lastScale = scale();
    var k = 1 / G.lastScale;
    if (mode() === 'line') drawLine(k); else drawMarker(k);
  }

  function drawLine(k) {
    // 12px 밖 역: 신규(빨강 실선) / 편집 전부터 그랬던 것(회색 점선)
    // 4~12px 소프트("눈에 보이게 벌어짐"): 신규는 노랑 실선, 편집 전부터는 옅은 회색 점선
    G.offSoft.forEach(function (o) {
      var a = { cx: o.x, cy: o.y, r: 8 * k, fill: 'none', stroke: o.pre ? COLORS.pre : COLORS.soft, 'stroke-width': o.pre ? 1.1 : 2.2 };
      if (o.pre) { a['stroke-dasharray'] = '2 3'; a.opacity = 0.55; }
      add('circle', a);
    });
    G.off.forEach(function (o) {
      var a = { cx: o.x, cy: o.y, r: 10 * k, fill: 'none', stroke: o.pre ? COLORS.pre : COLORS.bad, 'stroke-width': o.pre ? 1.6 : 2.4 };
      if (o.pre) a['stroke-dasharray'] = '3 3';
      add('circle', a);
    });
    // 선택된 정점/런의 경로 윤곽
    var selP = G.selV ? G.selV.p : (G.selS ? G.selS.p : null);
    if (selP != null && G.pts[selP]) {
      add('polyline', {
        points: G.pts[selP].map(function (q) { return q[0] + ',' + q[1]; }).join(' '),
        fill: 'none', stroke: COLORS.sel, 'stroke-width': 1.4, 'stroke-dasharray': '4 3', opacity: 0.8
      });
    }
    // 호버한 구간 + 선택한 런(연속 구간)의 모든 구간 강조
    var hv = G.hoverS;
    if (hv && G.pts[hv.p] && G.pts[hv.p][hv.v + 1] && !(G.selS && G.selS.p === hv.p && hv.v >= G.selS.v0 && hv.v < G.selS.v1)) {
      var ha = G.pts[hv.p][hv.v], hb = G.pts[hv.p][hv.v + 1];
      add('line', { x1: ha[0], y1: ha[1], x2: hb[0], y2: hb[1], stroke: COLORS.sel, 'stroke-width': 3, opacity: 0.35, 'stroke-linecap': 'round' });
    }
    if (G.selS && G.pts[G.selS.p]) {
      for (var sk = G.selS.v0; sk < G.selS.v1; sk++) {
        var sa = G.pts[G.selS.p][sk], sb2 = G.pts[G.selS.p][sk + 1];
        if (!sa || !sb2) continue;
        add('line', { x1: sa[0], y1: sa[1], x2: sb2[0], y2: sb2[1], stroke: COLORS.sel, 'stroke-width': 4, opacity: 0.55, 'stroke-linecap': 'round' });
      }
    }
    var refs = G.selV ? groupFor(G.selV.p, G.selV.v) : (G.selS ? selRefs() : []);
    G.editIdx.forEach(function (i) {
      if (!visible(i)) return;
      G.pts[i].forEach(function (q, v) {
        var ch = vertChanged(i, v);
        add('circle', {
          cx: q[0], cy: q[1], r: 3.4 * k,
          fill: ch ? '#ffb020' : '#ffffff', stroke: ch ? '#b36b00' : COLORS.sel, 'stroke-width': 1.3
        });
      });
    });
    refs.forEach(function (r, n) {
      var q = G.pts[r.p][r.v];
      add('circle', { cx: q[0], cy: q[1], r: (n === 0 ? 6 : 5) * k, fill: n === 0 ? COLORS.sel : 'none', stroke: n === 0 ? '#ffffff' : COLORS.sel, 'stroke-width': n === 0 ? 1.6 : 2 });
    });
  }

  function drawMarker(k) {
    G.rects.forEach(function (m) {
      var r = G.rw[m.index];
      var ch = !same(r.x, G.ro[m.index].x) || !same(r.y, G.ro[m.index].y) || !same(r.w, G.ro[m.index].w) || !same(r.h, G.ro[m.index].h);
      var sel = G.selR === m.index;
      var pad = (sel ? 3.5 : 2.2);
      var a = {
        x: r.x - pad, y: r.y - pad, width: r.w + 2 * pad, height: r.h + 2 * pad,
        rx: Math.min(r.w, r.h) / 2 + pad, ry: Math.min(r.w, r.h) / 2 + pad,
        fill: sel ? COLORS.sel : 'none', 'fill-opacity': 0.12,
        stroke: sel ? COLORS.sel : (ch ? COLORS.changed : '#6f9bd8'), 'stroke-width': sel ? 2.4 : 1.2
      };
      if (!sel && !ch) a['stroke-dasharray'] = '3 2';
      add('rect', a);
    });
    // 저장된 SVG 에서 앵커 역이 없는 마커(영속 드리프트): 마커에 굵은 빨간 테두리 + 가장 가까운 역까지 점선
    G.orphans.forEach(function (o) {
      var r = G.rw[o.index];
      if (!r) return;
      if (o.nearest) add('line', { x1: o.nearest.x, y1: o.nearest.y, x2: o.cx, y2: o.cy, stroke: COLORS.bad, 'stroke-width': 1.2, 'stroke-dasharray': '2 3', opacity: 0.8 });
      add('rect', { x: r.x - 5, y: r.y - 5, width: r.w + 10, height: r.h + 10, rx: Math.min(r.w, r.h) / 2 + 5, ry: Math.min(r.w, r.h) / 2 + 5, fill: 'none', stroke: COLORS.bad, 'stroke-width': 3 });
    });
    // stations.json 좌표와 어긋난 마커: 역 좌표(옛 자리)에 빨간 고리 + 마커 중심까지 점선
    G.drift.forEach(function (d) {
      var far = d.stations[0];
      add('line', { x1: far.x, y1: far.y, x2: d.cx, y2: d.cy, stroke: COLORS.bad, 'stroke-width': 1.6, 'stroke-dasharray': '4 3' });
      add('circle', { cx: far.x, cy: far.y, r: 7 * k, fill: 'none', stroke: COLORS.bad, 'stroke-width': 2.4 });
    });
  }

  // 줌이 바뀌면 핸들 크기(화면 px 고정)를 다시 맞춘다.
  (function watchScale() {
    if (isGeo() && G.loaded && Math.abs(scale() - G.lastScale) > 1e-4) drawOverlay();
    requestAnimationFrame(watchScale);
  })();

  // ---------------------------------------------------------------- 패널
  var pane = $('be-geo-pane');
  pane.innerHTML =
    '<div class="be-state" id="gp-state"></div>' +
    '<div id="gp-banner"></div>' +
    '<div class="gp-row"><label>스냅 <select id="gp-snap">' +
      '<option value="8">8px</option><option value="4" selected>4px</option><option value="1">1px</option><option value="0.5">0.5px</option>' +
    '</select></label></div>' +
    '<div id="gp-line">' +
      '<div class="be-hint">정점(●)을 끌면 그 점만, <b>정점 사이 선을 집어 끌면 그 구간이 평행 이동</b>(양 끝 정점이 함께)한다. ' +
        '<b>Shift-클릭</b>(정점·구간)으로 같은 선의 <b>연속 구간을 확장</b>해 한 번에 끌 수 있다(모든 정점이 같은 양을 한 번만 움직인다). ' +
        '드래그 중 Shift = 가로/세로 고정 · 방향키 = 스냅 단위(Shift 8px) · Del 선택 원위치 · Esc 선택 해제 · Ctrl+Z 취소 · Ctrl+S 저장. 짧은 구간은 확대해서 집을 것. 정점 추가·삭제는 안 된다. 역·라벨은 안 따라온다.</div>' +
      '<div class="gp-row"><select id="gp-filter" title="노선 선택(그 선의 정점만 표시)"></select></div>' +
      '<div class="gp-row"><label><input type="checkbox" id="gp-joint" checked> 같은 노선의 겹친 점(분기·끝점)도 같이 이동</label><span class="gp-jointn" id="gp-jointn"></span></div>' +
      '<div id="gp-vsel"></div>' +
      '<div class="gp-off-head" id="gp-offhead"></div><div class="gp-off" id="gp-offlist"></div>' +
      '<div class="gp-off-head" id="gp-softhead"></div><div class="gp-off" id="gp-softlist"></div>' +
    '</div>' +
    '<div id="gp-marker">' +
      '<div class="be-hint">환승 마커를 드래그해 옮긴다. 방향키 = 스냅 단위 · Ctrl+Z 취소 · Ctrl+S 저장. 크기는 규격(8×8 · 8×16/20/24/28)으로만 바뀐다. 중심은 그대로다.' +
        ' <b>마커를 옮겨도 stations.json 의 역 좌표는 안 바뀐다</b> — 어긋나면 아래에 빨갛게 표시된다(저장은 막지 않는다). 저장 뒤에도 앵커 역이 없는 마커는 상단 배너·아래 목록에 계속 남는다.</div>' +
      '<div class="gp-row"><select id="gp-mpick" title="마커 찾기"></select></div>' +
      '<div id="gp-msel"></div>' +
      '<div class="gp-off-head" id="gp-orphanhead"></div><div class="gp-off" id="gp-orphanlist"></div>' +
      '<div class="gp-off-head" id="gp-drifthead"></div><div class="gp-off" id="gp-driftlist"></div>' +
    '</div>' +
    '<div class="be-row"><button id="gp-save" class="be-primary">저장 + 재빌드</button>' +
    '<button id="gp-undo">실행 취소</button><button id="gp-reset">이 모드 되돌리기</button></div>' +
    '<details id="gp-logbox"><summary>저장·재빌드 로그</summary><pre id="gp-log"></pre></details>';

  $('gp-snap').addEventListener('change', function (e) { G.snap = parseFloat(e.target.value) || 4; });
  $('gp-joint').addEventListener('change', function (e) { G.joint = !!e.target.checked; scheduleDraw(); });
  $('gp-filter').addEventListener('change', function (e) {
    G.filter = e.target.value;
    G.selV = null; G.selS = null; G.hoverS = null;
    if (G.filter !== '') {
      var pts = G.pts[+G.filter];
      var mid = pts[Math.floor(pts.length / 2)];
      if (typeof window.panTo === 'function') window.panTo(mid[0], mid[1], 250);
    }
    renderPane(); drawOverlay();
  });
  $('gp-mpick').addEventListener('change', function (e) {
    if (e.target.value === '') return;
    selectRect(+e.target.value, true);
  });
  $('gp-save').addEventListener('click', save);
  $('gp-undo').addEventListener('click', undo);
  $('gp-reset').addEventListener('click', resetMode);

  Host.onMode.push(function () { renderPane(); drawOverlay(); });

  function banner() {
    var out = [];
    if (G.error) out.push({ k: 'err', t: G.error });
    if (G.interrupted) out.push({ k: 'err', t: '⚠️ ' + G.interrupted });
    if (G.orphans.length) {
      out.push({ k: 'err', t: '⚠️ 환승 마커 ' + G.orphans.length + '개에 앵커 역이 없다 — SVG 에서 옮겨 저장했는데 stations.json 역 좌표가 따라오지 않은 마커다' +
        '(경로 하이라이트·열차 아이콘이 옛 자리에 남고 12px 선로 가드도 못 잡는다): ' +
        G.orphans.slice(0, 6).map(function (o) {
          return '#' + o.index + ' ' + (G.labels[o.index] || '?') + (o.nearest ? '(가장 가까운 역 ' + o.nearest.name + '|' + o.nearest.lineId + ' ' + o.nearest.dist + 'px)' : '');
        }).join(', ') + (G.orphans.length > 6 ? ' …' : '') +
        '. 해결: stations.json 의 해당 역 svgX/svgY 를 직접 패치하거나(생성기 단독 재실행 금지) 마커를 원위치로. 마커 탭 목록에서 클릭하면 선택된다.' });
    }
    G.alerts.forEach(function (a, i) { out.push({ k: a.k, t: a.t, dismiss: i }); });
    if (G.offStale) out.push({ k: 'warn', t: '12px/마커 판정 요청이 실패했다 — 아래 이탈·어긋남 표시가 낡았을 수 있다(저장 직전에 다시 판정한다).' });
    if (G.loaded && G.mismatch > 0)
      out.push({ k: 'warn', t: '지도(map.html)의 선/마커 ' + G.mismatch + '개가 현재 SVG 와 다르다 — 저장(재빌드)하면 맞춰진다. 편집은 SVG 기준이다.' });
    return out;
  }

  function offSummary(list) {
    var nw = list.filter(function (o) { return !o.pre; }).length;
    return { total: list.length, nw: nw, pre: list.length - nw };
  }

  function renderPane() {
    var cv = changedVerts(), cr = changedRects();
    var st = $('gp-state');
    st.innerHTML = '';
    st.appendChild(document.createTextNode('선분 정점 '));
    st.appendChild(el('b', null, cv.verts + '개(' + cv.paths.length + '선)'));
    st.appendChild(document.createTextNode(' · 마커 '));
    st.appendChild(el('b', null, cr.length + '개'));
    if (G.drift.length) st.appendChild(el('b', { 'class': 'gp-bad' }, ' (역 좌표 어긋남 ' + G.drift.length + ')'));
    st.appendChild(document.createTextNode((geoCount() ? ' 변경 · 저장 안 됨' : ' · 변경 없음') +
      (G.saving ? ' · 저장·재빌드 중…' : '')));

    var bn = $('gp-banner');
    bn.innerHTML = '';
    banner().forEach(function (l) {
      var b = el('div', { 'class': 'be-banner ' + l.k }, l.t);
      if (l.dismiss != null) {
        b.title = '클릭하면 닫는다';
        b.style.cursor = 'pointer';
        b.addEventListener('click', function () { G.alerts.splice(l.dismiss, 1); renderPane(); });
      }
      bn.appendChild(b);
    });
    if (G.log) {
      $('gp-log').textContent = G.log;
      bn.appendChild(el('div', { 'class': 'be-banner ' + G.logKind },
        G.logKind === 'ok' ? '저장·재빌드 완료. 아래 로그 참조.' : G.logKind === 'warn' ? '저장·재빌드 완료(경고 있음). 아래 로그 참조.' : '저장하지 못했다. 아래 로그 참조.'));
      if (G.logKind === 'err') $('gp-logbox').open = true;
    }

    $('gp-line').style.display = mode() === 'line' ? '' : 'none';
    $('gp-marker').style.display = mode() === 'marker' ? '' : 'none';

    var stack = G.undo[mode() === 'marker' ? 'marker' : 'line'];
    var modeCount = mode() === 'marker' ? cr.length : cv.verts;
    $('gp-save').disabled = G.saving || !G.loaded || !!G.error || geoCount() === 0;
    $('gp-undo').disabled = G.saving || stack.length === 0;
    $('gp-reset').disabled = G.saving || modeCount === 0;

    if (mode() === 'line') renderLine(); else if (mode() === 'marker') renderMarker();
    Host.refreshTabs();
  }

  function pathLabel(i) { return G.byIdx[i].label + ' #' + i; }

  function renderLine() {
    var f = $('gp-filter');
    if (!f.getAttribute('data-ready') && G.loaded) {
      f.setAttribute('data-ready', '1');
      f.innerHTML = '';
      f.appendChild(el('option', { value: '' }, '전체 노선(정점 ' + G.editIdx.reduce(function (n, i) { return n + G.pts[i].length; }, 0) + '개)'));
      G.editIdx.forEach(function (i) { f.appendChild(el('option', { value: String(i) }, pathLabel(i) + ' · ' + G.pts[i].length + '점')); });
    }
    f.value = G.filter;

    var box = $('gp-vsel');
    box.innerHTML = '';
    var s = G.selV, sg = G.selS;
    var jn = $('gp-jointn');
    if (jn) {
      var linked0 = s ? groupFor(s.p, s.v).length - 1 : (sg ? selRefs().length - (sg.v1 - sg.v0 + 1) : -1);
      jn.textContent = linked0 > 0 && G.joint ? '→ 겹친 점 ' + linked0 + '개가 같이 움직인다' : '';
    }
    if (sg && G.pts[sg.p]) {
      var qa = G.pts[sg.p][sg.v0], qb = G.pts[sg.p][sg.v1];
      var segRefs = selRefs();
      var nseg = sg.v1 - sg.v0, nvert = nseg + 1;
      var scard = el('div', { 'class': 'gp-card' });
      scard.appendChild(el('div', { 'class': 'nm' }, pathLabel(sg.p) + ' — ' + (nseg > 1 ? '연속 구간 ' + nseg + '개' : '구간')));
      scard.appendChild(el('div', { 'class': 'kv' }, '정점 ' + (sg.v0 + 1) + ' ↔ ' + (sg.v1 + 1) + ' / ' + G.pts[sg.p].length +
        '   (' + r3(qa[0]) + ', ' + r3(qa[1]) + ') ↔ (' + r3(qb[0]) + ', ' + r3(qb[1]) + ')'));
      scard.appendChild(el('div', { 'class': 'kv' }, '정점 ' + nvert + '개가 같은 양을 한 번만 평행 이동한다(이동 정점 ' + segRefs.length + '개' +
        (segRefs.length > nvert ? ' — 겹친 점 ' + (segRefs.length - nvert) + '개 포함' : '') + ')'));
      scard.appendChild(el('div', { 'class': 'kv' }, 'Shift-클릭으로 같은 선의 인접 구간·정점까지 확장한다. 다른 구간을 그냥 끌면 그 구간만 새로 선택된다.'));
      var stw = G.byIdx[sg.p].twins || [];
      if (stw.length) scard.appendChild(el('div', { 'class': 'kv' }, '흰 이중선 ' + stw.length + '개가 같이 움직인다'));
      var changedN = segRefs.filter(function (r) { return vertChanged(r.p, r.v); }).length;
      var srow = el('div', { 'class': 'be-row' });
      var srs = el('button', null, '원위치');
      srs.disabled = changedN === 0;
      srs.addEventListener('click', function () { resetRun(); });
      srow.appendChild(srs);
      scard.appendChild(srow);
      box.appendChild(scard);
    } else if (!s) {
      box.appendChild(el('div', { 'class': 'be-hint' }, '정점이나 정점 사이 선을 클릭·드래그하면 좌표와 연동 정보가 여기 나온다.'));
    } else {
      var q = G.pts[s.p][s.v], o = G.orig[s.p][s.v];
      var card = el('div', { 'class': 'gp-card' });
      card.appendChild(el('div', { 'class': 'nm' }, pathLabel(s.p)));
      card.appendChild(el('div', { 'class': 'kv' }, '정점 ' + (s.v + 1) + ' / ' + G.pts[s.p].length + '   (' + r3(q[0]) + ', ' + r3(q[1]) + ')'));
      if (vertChanged(s.p, s.v)) card.appendChild(el('div', { 'class': 'kv' }, '원래 (' + r3(o[0]) + ', ' + r3(o[1]) + ')  → 이동 ' + r3(q[0] - o[0]) + ', ' + r3(q[1] - o[1])));
      var tw = G.byIdx[s.p].twins || [];
      if (tw.length) card.appendChild(el('div', { 'class': 'kv' }, '흰 이중선 ' + tw.length + '개가 같이 움직인다'));
      var linked = groupFor(s.p, s.v).length - 1;
      if (linked > 0) card.appendChild(el('div', { 'class': 'kv' }, '겹친 점 ' + linked + '개가 같이 움직인다'));
      var row = el('div', { 'class': 'be-row' });
      var prev = el('button', null, '← 이전 정점'), next = el('button', null, '다음 정점 →'), rs = el('button', null, '원위치');
      prev.disabled = s.v === 0; next.disabled = s.v >= G.pts[s.p].length - 1; rs.disabled = !vertChanged(s.p, s.v);
      prev.addEventListener('click', function () { selectVertex(s.p, s.v - 1, true); });
      next.addEventListener('click', function () { selectVertex(s.p, s.v + 1, true); });
      rs.addEventListener('click', function () { resetVertex(s.p, s.v); });
      row.appendChild(prev); row.appendChild(next); row.appendChild(rs);
      card.appendChild(row);
      box.appendChild(card);
    }

    var sum = offSummary(G.off);
    var head = $('gp-offhead');
    head.className = 'gp-off-head ' + (sum.nw ? 'bad' : 'good');
    head.textContent = sum.total === 0
      ? '12px 밖 역 없음'
      : '12px 밖 역 ' + sum.total + '개 (이번 편집으로 생긴 것 ' + sum.nw + ' · 원래부터 ' + sum.pre + ')' + (G.offBusy ? ' …' : '');
    var list = $('gp-offlist');
    list.innerHTML = '';
    G.off.forEach(function (o) {
      var it = el('div', { 'class': 'item' + (o.pre ? ' pre' : '') },
        o.name + ' · ' + o.lineId + ' — 선까지 ' + o.dist + 'px' + (o.pre ? ' (원래부터)' : ' (신규)'));
      it.addEventListener('click', function () { if (typeof window.panTo === 'function') window.panTo(o.x, o.y, 250); });
      list.appendChild(it);
    });

    // 4~12px 소프트 — 하드가 아니라 저장을 막지 않는다. 편집 전부터 있던 것(원래 선과 4~12px 떨어진 역)은 회색.
    var ssum = offSummary(G.offSoft);
    var shead = $('gp-softhead');
    shead.className = 'gp-off-head ' + (ssum.nw ? 'warn' : 'good');
    shead.textContent = ssum.total === 0
      ? '4px 넘게 벌어진 역 없음'
      : '4px 넘게 벌어진 역(12px 이하) ' + ssum.total + '개 (이번 편집으로 생긴 것 ' + ssum.nw + ' · 원래부터 ' + ssum.pre + ')';
    var slist = $('gp-softlist');
    slist.innerHTML = '';
    G.offSoft.slice().sort(function (a, b) { return (a.pre - b.pre) || (b.dist - a.dist); }).forEach(function (o) {
      var it = el('div', { 'class': 'item soft' + (o.pre ? ' pre' : '') },
        o.name + ' · ' + o.lineId + ' — 선까지 ' + o.dist + 'px' + (o.pre ? ' (원래부터)' : ' (신규)'));
      it.addEventListener('click', function () { if (typeof window.panTo === 'function') window.panTo(o.x, o.y, 250); });
      slist.appendChild(it);
    });
  }

  function orientOf(r) { return r.w > r.h + 1e-6 ? 'h' : (r.h > r.w + 1e-6 ? 'v' : 'c'); }
  function nearestLen(v) {
    var best = G.markerLengths[0];
    G.markerLengths.forEach(function (l) { if (Math.abs(l - v) < Math.abs(best - v)) best = l; });
    return best;
  }

  function nearLabel(m) {
    // 마커 중심에서 가장 가까운 역명 라벨(참고용). 라벨은 text-layer 의 <text data-station>.
    var cx = m.x + m.w / 2, cy = m.y + m.h / 2, best = null, bd = 80;
    var ts = textLayer.querySelectorAll('text[data-station]');
    for (var i = 0; i < ts.length; i++) {
      var d = Math.hypot(+ts[i].getAttribute('x') - cx, +ts[i].getAttribute('y') - cy);
      if (d < bd) { bd = d; best = ts[i].getAttribute('data-station'); }
    }
    return best;
  }

  // 규격 마커 크기인가(서버 isStandardMarkerSize 와 같은 규칙 — 표시용. 판정은 서버가 한다).
  function isStdSize(w, h) {
    var t = G.thick;
    function isL(v) { return G.markerLengths.some(function (l) { return same(l, v); }); }
    return (same(w, t) && same(h, t)) || (same(w, t) && isL(h)) || (same(h, t) && isL(w));
  }

  function rectText(i) {
    var r = G.rw[i];
    return '#' + i + ' ' + (G.labels[i] || '?') + ' 부근 · ' + r3(r.w) + '×' + r3(r.h) + (isStdSize(r.w, r.h) ? '' : ' (규격 밖)');
  }

  function renderMarker() {
    var pick = $('gp-mpick');
    var sig = G.rects.map(function (m) { var r = G.rw[m.index]; return m.index + ':' + r.w + 'x' + r.h; }).join(',');
    if (pick.getAttribute('data-sig') !== sig) {
      pick.setAttribute('data-sig', sig);
      pick.innerHTML = '';
      pick.appendChild(el('option', { value: '' }, '마커 찾기… (' + G.rects.length + '개)'));
      G.rects.forEach(function (m) { pick.appendChild(el('option', { value: String(m.index) }, rectText(m.index))); });
    }
    pick.value = '';

    var oh = $('gp-orphanhead'), ol = $('gp-orphanlist');
    oh.className = 'gp-off-head ' + (G.orphans.length ? 'bad' : 'good');
    oh.textContent = G.orphans.length
      ? '저장된 SVG 에 앵커 역이 없는 마커 ' + G.orphans.length + '개 (stations.json 좌표가 안 따라온 상태)'
      : '앵커 역 없는 마커 없음(저장된 SVG 기준)';
    ol.innerHTML = '';
    G.orphans.forEach(function (o) {
      var it = el('div', { 'class': 'item' }, '#' + o.index + ' ' + (G.labels[o.index] || '?') + ' — 앵커 역 없음' +
        (o.nearest ? ' · 가장 가까운 역 ' + o.nearest.name + '|' + o.nearest.lineId + ' ' + o.nearest.dist + 'px' : ''));
      it.addEventListener('click', function () { selectRect(o.index, true); });
      ol.appendChild(it);
    });

    var dh = $('gp-drifthead'), dl = $('gp-driftlist');
    dh.className = 'gp-off-head ' + (G.drift.length ? 'bad' : 'good');
    dh.textContent = G.drift.length
      ? 'stations.json 역 좌표와 어긋난 마커 ' + G.drift.length + '개' + (G.offBusy ? ' …' : '')
      : '역 좌표와 어긋난 마커 없음' + (G.offBusy ? ' …' : '');
    dl.innerHTML = '';
    G.drift.forEach(function (d) {
      var names = {};
      d.stations.forEach(function (st) { names[st.name] = 1; });
      var nm = Object.keys(names);
      var it = el('div', { 'class': 'item' }, '#' + d.index + ' ' + (G.labels[d.index] || nm[0]) + ' — 역 ' + d.stations.length + '개(' + nm.join('·') +
        ')가 마커에서 최대 ' + d.dist + 'px 떨어진 옛 자리에 남는다' + (d.shared ? ' · 공유 캡슐(12px 선로 가드 면제 역 포함)' : ''));
      it.addEventListener('click', function () { selectRect(d.index, true); });
      dl.appendChild(it);
    });

    var box = $('gp-msel');
    box.innerHTML = '';
    var i = G.selR;
    if (i == null) {
      box.appendChild(el('div', { 'class': 'be-hint' }, '마커를 클릭하거나 위 목록에서 고르면 크기·방향 버튼이 여기 나온다.'));
      return;
    }
    var r = G.rw[i], o = G.ro[i], ori = orientOf(r), std = isStdSize(r.w, r.h);
    var card = el('div', { 'class': 'gp-card' });
    card.appendChild(el('div', { 'class': 'nm' }, '마커 ' + rectText(i)));
    if (!std) card.appendChild(el('div', { 'class': 'kv gp-bad' }, '규격 밖 크기(' + r3(r.w) + '×' + r3(r.h) + ') — 옮기기만 하면 그대로 유지된다. 방향·길이 버튼을 누르면 규격(8 × 8/16/20/24/28)으로 맞춰진다(중심 유지, 가장자리가 최대 1px 안쪽으로 바뀐다). 그래서 아래 버튼은 어느 것도 "선택됨" 으로 표시하지 않는다.'));
    card.appendChild(el('div', { 'class': 'kv' }, '좌상단 (' + r3(r.x) + ', ' + r3(r.y) + ')  크기 ' + r3(r.w) + '×' + r3(r.h)));
    if (!same(r.x, o.x) || !same(r.y, o.y) || !same(r.w, o.w) || !same(r.h, o.h))
      card.appendChild(el('div', { 'class': 'kv' }, '원래 (' + r3(o.x) + ', ' + r3(o.y) + ')  ' + r3(o.w) + '×' + r3(o.h)));
    card.appendChild(el('div', { 'class': 'gp-sub' }, '방향'));
    var seg = el('div', { 'class': 'gp-seg' });
    [['h', '가로 ━'], ['v', '세로 ┃'], ['c', '동그라미 ●']].forEach(function (x) {
      var b = el('button', { 'class': std && ori === x[0] ? 'on' : '' }, x[1]);
      b.addEventListener('click', function () { setShape(i, x[0], null); });
      seg.appendChild(b);
    });
    card.appendChild(seg);
    card.appendChild(el('div', { 'class': 'gp-sub' }, '길이(장축)'));
    var seg2 = el('div', { 'class': 'gp-seg' });
    G.markerLengths.forEach(function (l) {
      var on = std && ori !== 'c' && same(Math.max(r.w, r.h), l);
      var b = el('button', { 'class': on ? 'on' : '' }, String(l));
      b.disabled = ori === 'c';
      b.addEventListener('click', function () { setShape(i, ori, l); });
      seg2.appendChild(b);
    });
    card.appendChild(seg2);
    var row = el('div', { 'class': 'be-row' });
    var rs = el('button', null, '이 마커 원위치');
    rs.disabled = same(r.x, o.x) && same(r.y, o.y) && same(r.w, o.w) && same(r.h, o.h);
    rs.addEventListener('click', function () { pushUndo({ kind: 'r', idx: i, from: clone(r) }); G.rw[i] = clone(o); placeRectDom(i); afterChange(); });
    row.appendChild(rs);
    card.appendChild(row);
    box.appendChild(card);
  }

  // ---------------------------------------------------------------- 선택
  function selectVertex(p, v, pan) {
    if (!G.pts[p] || v < 0 || v >= G.pts[p].length) return;
    G.selV = { p: p, v: v }; G.selS = null;
    renderPane(); drawOverlay();
    if (pan && typeof window.panTo === 'function') window.panTo(G.pts[p][v][0], G.pts[p][v][1], 250);
  }
  function selectRun(p, v0, v1, ref) {
    if (!G.pts[p] || v0 < 0 || v1 <= v0 || v1 >= G.pts[p].length) return;
    G.selS = { p: p, v0: v0, v1: v1, ref: ref }; G.selV = null;
    renderPane(); drawOverlay();
  }
  // 선택된 런의 이동 대상 정점들(집은 정점 `ref` 의 그룹이 첫 원소 — 드래그의 스냅 기준이자 강조 원의 기준).
  function selRefs() { return groupForRun(G.selS.p, G.selS.v0, G.selS.v1, G.selS.ref); }
  // Shift-클릭: 이미 선택된 같은 선의 정점/런을 [lo..hi] 정점 범위까지 넓힌다. 넓힐 수 있으면 true.
  function extendSel(p, lo, hi) {
    var cur = G.selS && G.selS.p === p ? { a: G.selS.v0, b: G.selS.v1, ref: G.selS.ref }
      : (G.selV && G.selV.p === p ? { a: G.selV.v, b: G.selV.v, ref: G.selV.v } : null);
    if (!cur) return false;
    var a = Math.min(cur.a, lo), b = Math.max(cur.b, hi);
    if (b <= a) return false;
    G.selS = { p: p, v0: a, v1: b, ref: cur.ref }; G.selV = null;
    return true;
  }
  function selectRect(i, pan) {
    G.selR = i;
    renderPane(); drawOverlay();
    if (pan && typeof window.panTo === 'function') window.panTo(G.rw[i].x + G.rw[i].w / 2, G.rw[i].y + G.rw[i].h / 2, 250);
  }

  // ---------------------------------------------------------------- 되돌리기
  function pushUndo(entry) {
    var st = G.undo[entry.kind === 'r' ? 'marker' : 'line'];
    st.push(entry);
    if (st.length > 80) st.shift();
  }

  function undo() {
    var st = G.undo[mode() === 'marker' ? 'marker' : 'line'];
    if (!st.length || G.saving) return;
    var e = st.pop();
    if (e.kind === 'v') {
      var touched = {};
      e.moves.forEach(function (m) { G.pts[m.p][m.v] = [m.from[0], m.from[1]]; touched[m.p] = 1; });
      Object.keys(touched).forEach(function (p) { placePathDom(+p); });
      requestCheck();
    } else {
      G.rw[e.idx] = e.from;
      placeRectDom(e.idx);
    }
    afterChange();
  }

  function resetMode() {
    if (G.saving) return;
    var line = mode() === 'line';
    var n = line ? changedVerts().verts : changedRects().length;
    if (!n) return;
    if (!window.confirm((line ? '선분 정점 ' : '환승 마커 ') + n + '개를 원래대로 되돌릴까? (저장 전까지는 파일이 바뀌지 않는다)')) return;
    if (line) {
      G.editIdx.forEach(function (i) { G.pts[i] = clone(G.orig[i]); placePathDom(i); });
      G.undo.line = [];
      requestCheck();
    } else {
      Object.keys(G.rw).forEach(function (k) { G.rw[k] = clone(G.ro[k]); placeRectDom(+k); });
      G.undo.marker = [];
    }
    afterChange();
  }

  function resetVertex(p, v) {
    var refs = groupFor(p, v);
    pushUndo({ kind: 'v', moves: refs.map(function (r) { return { p: r.p, v: r.v, from: G.pts[r.p][r.v].slice() }; }) });
    var o = G.orig[p][v];
    moveGroup(refs, o[0], o[1]);
    requestCheck();
    afterChange();
  }

  function resetRun() {
    if (!G.selS) return;
    var refs = selRefs();
    pushUndo({ kind: 'v', moves: refs.map(function (r) { return { p: r.p, v: r.v, from: G.pts[r.p][r.v].slice() }; }) });
    var touched = {};
    refs.forEach(function (r) { var o = G.orig[r.p][r.v]; G.pts[r.p][r.v] = [o[0], o[1]]; touched[r.p] = 1; });
    Object.keys(touched).forEach(function (q) { placePathDom(+q); });
    requestCheck();
    afterChange();
  }

  function afterChange() { renderPane(); scheduleDraw(); }

  // ---------------------------------------------------------------- 정점 이동
  // 같은 노선(코드)의 겹친 점(분기점·끝점 이음새)은 같이 움직인다 — 안 그러면 이음새가 벌어진다.
  function groupFor(p, v) {
    var q = G.pts[p][v], refs = [{ p: p, v: v }];
    if (!G.joint) return refs;
    var code = G.byIdx[p].code;
    G.editIdx.forEach(function (pi) {
      if (G.byIdx[pi].code !== code) return;
      G.pts[pi].forEach(function (r, vi) {
        if (pi === p && vi === v) return;
        if (Math.abs(r[0] - q[0]) < 0.01 && Math.abs(r[1] - q[1]) < 0.01) refs.push({ p: pi, v: vi });
      });
    });
    return refs;
  }

  // 런(정점 v0..v1)을 집으면 그 정점들과 겹친 점이 함께 움직인다. 집은 정점 [ref] 의 그룹이 첫 원소가 된다(스냅 격자에
  // 올라타는 기준 — 집은 쪽이 자연스럽다). 같은 정점은 한 번만 담는다 → 인접 구간이 공유하는 정점이 두 번 움직이지 않는다.
  function groupForRun(p, v0, v1, ref) {
    var order = [ref], seen = {}, out = [];
    for (var k = v0; k <= v1; k++) if (k !== ref) order.push(k);
    order.forEach(function (k) {
      groupFor(p, k).forEach(function (r) { var key = r.p + ':' + r.v; if (!seen[key]) { seen[key] = 1; out.push(r); } });
    });
    return out;
  }

  function clampX(x) { return Math.max(0, Math.min(G.canvas.w, x)); }
  function clampY(y) { return Math.max(0, Math.min(G.canvas.h, y)); }

  function moveGroup(refs, nx, ny) {
    var touched = {};
    refs.forEach(function (r) { G.pts[r.p][r.v] = [r3(nx), r3(ny)]; touched[r.p] = 1; });
    Object.keys(touched).forEach(function (p) { placePathDom(+p); });
  }

  // 각 정점을 (자기 기준 위치 + 같은 이동량)으로 옮긴다 — 구간 평행 이동.
  function moveRefsBy(refs, bases, ddx, ddy) {
    var touched = {};
    refs.forEach(function (r, n) { G.pts[r.p][r.v] = [r3(bases[n][0] + ddx), r3(bases[n][1] + ddy)]; touched[r.p] = 1; });
    Object.keys(touched).forEach(function (q) { placePathDom(+q); });
  }

  // ---------------------------------------------------------------- 12px 판정(서버)
  function editedPaths() {
    var out = {};
    changedVerts().paths.forEach(function (i) { out[i] = G.pts[i]; });
    return out;
  }
  function editedRects() {
    var out = {};
    changedRects().forEach(function (i) { var r = G.rw[i]; out[i] = { x: r.x, y: r.y, w: r.w, h: r.h }; });
    return out;
  }
  // 12px 이탈 + 마커 드리프트 판정(서버). 진행 중이면 다음에 한 번 더 — 그 프로미스를 G.offPromise 에 남겨 저장이 기다린다.
  function requestCheck() {
    G.offWant = true;
    if (G.offBusy) return;
    G.offBusy = true;
    G.offPromise = (async function loop() {
      try {
        while (G.offWant) {
          G.offWant = false;
          try {
            var r = await api('/api/geometry/check', { paths: editedPaths(), rects: editedRects() });
            if (!G.offWant) { G.off = r.offLine; G.offSoft = r.offLineSoft || []; G.drift = r.markerDrift || []; G.offStale = false; renderPane(); scheduleDraw(); }
          } catch (err) { G.offStale = true; }
        }
      } finally {
        G.offBusy = false;
        renderPane();
      }
    })();
  }

  // ---------------------------------------------------------------- 히트 테스트
  function hitVertex(p) {
    var rad = 9 / scale(), best = null, bd = rad;
    G.editIdx.forEach(function (i) {
      if (!visible(i)) return;
      G.pts[i].forEach(function (q, v) {
        var d = Math.hypot(q[0] - p.x, q[1] - p.y);
        // 겹친 점(분기)은 선택된 경로를 우선한다.
        var pref = G.selV && G.selV.p === i ? 0.01 : 0;
        if (d - pref < bd) { bd = d - pref; best = { p: i, v: v }; }
      });
    });
    return best;
  }
  // 정점이 아닌 선 위를 집었는가 → {p, v, t}(구간 v~v+1, t = 구간 위 위치 0..1). 정점 히트가 항상 먼저다.
  function hitSegment(p) {
    var rad = 7 / scale(), best = null, bd = rad;
    G.editIdx.forEach(function (i) {
      if (!visible(i)) return;
      var pts = G.pts[i];
      for (var v = 0; v + 1 < pts.length; v++) {
        var a = pts[v], b = pts[v + 1], dx = b[0] - a[0], dy = b[1] - a[1], len2 = dx * dx + dy * dy;
        if (len2 === 0) continue;
        var t = Math.max(0, Math.min(1, ((p.x - a[0]) * dx + (p.y - a[1]) * dy) / len2));
        var d = Math.hypot(a[0] + t * dx - p.x, a[1] + t * dy - p.y);
        var pref = G.selS && G.selS.p === i ? 0.01 : 0;
        if (d - pref < bd) { bd = d - pref; best = { p: i, v: v, t: t }; }
      }
    });
    return best;
  }
  function hitRect(p) {
    var pad = 4 / scale(), best = null, ba = Infinity;
    G.rects.forEach(function (m) {
      var r = G.rw[m.index];
      if (p.x >= r.x - pad && p.x <= r.x + r.w + pad && p.y >= r.y - pad && p.y <= r.y + r.h + pad) {
        var a = r.w * r.h;
        if (a < ba) { ba = a; best = m.index; }
      }
    });
    return best;
  }

  // ---------------------------------------------------------------- 드래그
  function onDown(e) {
    if (!isGeo() || !G.loaded || G.error) return;
    if (e.button !== 0 || panel.contains(e.target) || G.saving) return;
    var p = toSvg(e);
    if (!p) return;
    if (mode() === 'line') {
      var h = hitVertex(p), sh = h ? null : hitSegment(p);
      if (!h && !sh) return;                // 빈 곳은 지도 팬으로 넘긴다
      e.stopPropagation(); e.preventDefault();
      // Shift-클릭: 같은 선에서 이미 선택한 정점/런을 넓힌다(드래그는 시작하지 않는다).
      if (e.shiftKey && (h ? extendSel(h.p, h.v, h.v) : extendSel(sh.p, sh.v, sh.v + 1))) { renderPane(); scheduleDraw(); return; }
      try { e.target.setPointerCapture(e.pointerId); } catch (err) { /* 무시 */ }
      if (h) {
        G.selV = h; G.selS = null;
        var refs = groupFor(h.p, h.v), base = G.pts[h.p][h.v];
        G.drag = {
          kind: 'v', pid: e.pointerId, p0: p, base: [base[0], base[1]], refs: refs, moved: false,
          before: refs.map(function (r) { return { p: r.p, v: r.v, from: G.pts[r.p][r.v].slice() }; })
        };
      } else {
        // 구간/런 드래그: 선택된 런 안의 구간을 집으면 런 전체가, 아니면 그 구간만 새로 선택돼 모든 정점(+겹친 점)이 같은 양을
        // 한 번만 평행 이동한다. 이동 가능 범위는 캔버스 안에 머무는 양으로 제한한다.
        var grab = sh.t >= 0.5 ? sh.v + 1 : sh.v;           // 집은 쪽에 가까운 끝 정점
        if (G.selS && G.selS.p === sh.p && sh.v >= G.selS.v0 && sh.v < G.selS.v1) G.selS.ref = grab;
        else G.selS = { p: sh.p, v0: sh.v, v1: sh.v + 1, ref: grab };
        G.selV = null;
        var srefs = selRefs();
        var bases = srefs.map(function (r) { return G.pts[r.p][r.v].slice(); });
        var lim = { minDx: -Infinity, maxDx: Infinity, minDy: -Infinity, maxDy: Infinity };
        bases.forEach(function (b) {
          lim.minDx = Math.max(lim.minDx, -b[0]); lim.maxDx = Math.min(lim.maxDx, G.canvas.w - b[0]);
          lim.minDy = Math.max(lim.minDy, -b[1]); lim.maxDy = Math.min(lim.maxDy, G.canvas.h - b[1]);
        });
        G.drag = {
          kind: 's', pid: e.pointerId, p0: p, refs: srefs, bases: bases, lim: lim, moved: false,
          before: srefs.map(function (r) { return { p: r.p, v: r.v, from: G.pts[r.p][r.v].slice() }; })
        };
      }
    } else {
      var idx = hitRect(p);
      if (idx == null) return;
      e.stopPropagation(); e.preventDefault();
      try { e.target.setPointerCapture(e.pointerId); } catch (err) { /* 무시 */ }
      G.selR = idx;
      G.drag = { kind: 'r', pid: e.pointerId, p0: p, base: clone(G.rw[idx]), idx: idx, moved: false };
    }
    document.body.classList.add('be-dragging');
    renderPane(); scheduleDraw();
  }

  function onMove(e) {
    if (!isGeo() || !G.loaded) return;
    var d = G.drag;
    if (!d) {
      if (!e.buttons) {
        var p0 = toSvg(e);
        var vh = p0 && mode() === 'line' ? hitVertex(p0) : null;
        var sh0 = p0 && mode() === 'line' && !vh ? hitSegment(p0) : null;
        var over = p0 && (mode() === 'line' ? (vh || sh0) : hitRect(p0) != null);
        document.documentElement.style.cursor = over ? 'grab' : '';
        if (mode() === 'line') {
          var nh = sh0 ? { p: sh0.p, v: sh0.v } : null;
          if ((nh && (!G.hoverS || G.hoverS.p !== nh.p || G.hoverS.v !== nh.v)) || (!nh && G.hoverS)) { G.hoverS = nh; scheduleDraw(); }
        }
      }
      return;
    }
    if (e.pointerId !== d.pid) return;
    e.stopPropagation();
    var p = toSvg(e);
    if (!p) return;
    var dx = p.x - d.p0.x, dy = p.y - d.p0.y;
    if (e.shiftKey) { if (Math.abs(dx) >= Math.abs(dy)) dy = 0; else dx = 0; }
    if (d.kind === 's') {
      // 기준 정점(refs[0])이 스냅 격자에 오르도록 이동량을 정하고, 모든 정점에 같은 양을 적용한다(평행 이동).
      var b0 = d.bases[0];
      var ddx = Math.max(d.lim.minDx, Math.min(d.lim.maxDx, snapV(b0[0] + dx) - b0[0]));
      var ddy = Math.max(d.lim.minDy, Math.min(d.lim.maxDy, snapV(b0[1] + dy) - b0[1]));
      var c0 = G.pts[d.refs[0].p][d.refs[0].v];
      if (same(r3(b0[0] + ddx), c0[0]) && same(r3(b0[1] + ddy), c0[1])) return;
      d.moved = true;
      moveRefsBy(d.refs, d.bases, ddx, ddy);
      requestCheck();
    } else if (d.kind === 'v') {
      var nx = clampX(snapV(d.base[0] + dx)), ny = clampY(snapV(d.base[1] + dy));
      var cur = G.pts[d.refs[0].p][d.refs[0].v];
      if (same(nx, cur[0]) && same(ny, cur[1])) return;
      d.moved = true;
      moveGroup(d.refs, nx, ny);
      requestCheck();
    } else {
      var rx = snapV(d.base.x + dx), ry = snapV(d.base.y + dy);
      rx = Math.max(0, Math.min(G.canvas.w - d.base.w, rx)); ry = Math.max(0, Math.min(G.canvas.h - d.base.h, ry));
      var r = G.rw[d.idx];
      if (same(rx, r.x) && same(ry, r.y)) return;
      d.moved = true;
      r.x = r3(rx); r.y = r3(ry);
      placeRectDom(d.idx);
    }
    scheduleDraw();
  }

  function onUp(e) {
    var d = G.drag;
    if (!d || e.pointerId !== d.pid) return;
    e.stopPropagation();
    G.drag = null;
    document.body.classList.remove('be-dragging');
    if (d.moved) {
      if (d.kind === 'v' || d.kind === 's') pushUndo({ kind: 'v', moves: d.before });
      else pushUndo({ kind: 'r', idx: d.idx, from: d.base });
    }
    afterChange();
  }

  window.addEventListener('pointerdown', onDown, true);
  window.addEventListener('pointermove', onMove, true);
  window.addEventListener('pointerup', onUp, true);
  window.addEventListener('pointercancel', onUp, true);

  // ---------------------------------------------------------------- 마커 크기·방향
  function setShape(i, ori, len) {
    var r = G.rw[i], t = G.thick;
    var cx = r.x + r.w / 2, cy = r.y + r.h / 2;
    var L = len != null ? len : nearestLen(Math.max(r.w, r.h));
    var w, h;
    if (ori === 'c') { w = t; h = t; }
    else if (ori === 'h') { w = L; h = t; }
    else { w = t; h = L; }
    if (same(w, r.w) && same(h, r.h)) return;
    pushUndo({ kind: 'r', idx: i, from: clone(r) });
    r.w = w; r.h = h;
    r.x = r3(Math.max(0, Math.min(G.canvas.w - w, cx - w / 2)));
    r.y = r3(Math.max(0, Math.min(G.canvas.h - h, cy - h / 2)));
    placeRectDom(i);
    afterChange();
  }

  // ---------------------------------------------------------------- 키보드
  window.addEventListener('keydown', function (e) {
    if (!isGeo() || !G.loaded) return;
    var tag = (e.target && e.target.tagName) || '';
    var mod = e.metaKey || e.ctrlKey;
    if (mod && (e.key === 's' || e.key === 'S')) { e.preventDefault(); save(); return; }
    if (mod && (e.key === 'z' || e.key === 'Z')) { e.preventDefault(); undo(); return; }
    if (tag === 'SELECT' || tag === 'INPUT' || tag === 'TEXTAREA') return;
    if (G.saving || G.drag) return;
    if (e.key === 'Escape') { G.selV = null; G.selS = null; G.selR = null; renderPane(); drawOverlay(); return; }
    var step = e.shiftKey ? 8 : G.snap, dx = 0, dy = 0;
    if (e.key === 'ArrowLeft') dx = -step; else if (e.key === 'ArrowRight') dx = step;
    else if (e.key === 'ArrowUp') dy = -step; else if (e.key === 'ArrowDown') dy = step;
    else if ((e.key === 'Delete' || e.key === 'Backspace') && mode() === 'line' && G.selV) { e.preventDefault(); resetVertex(G.selV.p, G.selV.v); return; }
    else if ((e.key === 'Delete' || e.key === 'Backspace') && mode() === 'line' && G.selS) { e.preventDefault(); resetRun(); return; }
    else return;
    e.preventDefault();
    var now = Date.now(), fresh = now - G.undoStamp > 900;
    G.undoStamp = now;
    if (mode() === 'line' && G.selS && G.pts[G.selS.p]) {
      // 런: 이동량 그대로(step) 평행 이동, 캔버스 안으로 제한
      var srefs = selRefs();
      var sb = srefs.map(function (r) { return G.pts[r.p][r.v].slice(); });
      var kdx = dx, kdy = dy;
      sb.forEach(function (b) {
        kdx = Math.max(-b[0], Math.min(G.canvas.w - b[0], kdx)); kdy = Math.max(-b[1], Math.min(G.canvas.h - b[1], kdy));
      });
      if (fresh) pushUndo({ kind: 'v', moves: srefs.map(function (r) { return { p: r.p, v: r.v, from: G.pts[r.p][r.v].slice() }; }) });
      moveRefsBy(srefs, sb, kdx, kdy);
      requestCheck();
    } else if (mode() === 'line' && G.selV) {
      var refs = groupFor(G.selV.p, G.selV.v), q = G.pts[G.selV.p][G.selV.v];
      if (fresh) pushUndo({ kind: 'v', moves: refs.map(function (r) { return { p: r.p, v: r.v, from: G.pts[r.p][r.v].slice() }; }) });
      moveGroup(refs, clampX(snapV(q[0] + dx)), clampY(snapV(q[1] + dy)));
      requestCheck();
    } else if (mode() === 'marker' && G.selR != null) {
      var r = G.rw[G.selR];
      if (fresh) pushUndo({ kind: 'r', idx: G.selR, from: clone(r) });
      r.x = r3(Math.max(0, Math.min(G.canvas.w - r.w, snapV(r.x + dx))));
      r.y = r3(Math.max(0, Math.min(G.canvas.h - r.h, snapV(r.y + dy))));
      placeRectDom(G.selR);
    } else return;
    afterChange();
  });

  // ---------------------------------------------------------------- 저장
  function newOff() { return G.off.filter(function (o) { return !o.pre; }); }

  // 저장 직전 확인 문구. 신규 12px 이탈 · 마커↔stations.json 어긋남 · 판정 실패 중 하나라도 있으면 문자열, 없으면 ''.
  function riskText() {
    var out = [], nw = newOff();
    if (nw.length) {
      var names = nw.slice(0, 8).map(function (o) { return '  - ' + o.name + '(' + o.lineId + ') ' + o.dist + 'px'; });
      out.push('이번 편집으로 12px 밖으로 벗어나는 역이 ' + nw.length + '개 생긴다:\n' + names.join('\n') + (nw.length > names.length ? '\n  …' : '') +
        '\n(경로 하이라이트가 선로를 벗어난다 — 커밋 전에 `flutter test test/tool/geometry_svg_test.dart` 가 같은 계산으로 잡는다.)');
    }
    if (G.drift.length) {
      var ds = G.drift.slice(0, 8).map(function (d) {
        return '  - 마커 #' + d.index + ' ' + (G.labels[d.index] || d.stations[0].name) + ' — 역 ' + d.stations.length + '개, 최대 ' + d.dist + 'px' + (d.shared ? ' (공유 캡슐)' : '');
      });
      out.push('환승 마커 ' + G.drift.length + '개가 stations.json 역 좌표와 어긋난다:\n' + ds.join('\n') + (G.drift.length > ds.length ? '\n  …' : '') +
        '\n(역 좌표는 이 도구가 고치지 않는다 — 경로 하이라이트·열차 아이콘이 옛 자리에 남고, 12px 선로 가드는 이걸 못 잡는다. 14px 넘게 옮겨 저장하면 상단 배너(앵커 없는 마커)에 계속 남고, 어느 거리든 `flutter test test/tool/geometry_svg_test.dart` 가 커밋 전에 잡는다.)');
    }
    if (G.offStale) out.push('12px/마커 판정을 끝내 받지 못했다 — 위 목록이 없거나 낡았을 수 있다.');
    return out.join('\n\n');
  }

  async function save() {
    if (G.saving || !G.loaded || G.error || geoCount() === 0) return;
    // 마지막 드래그의 판정이 아직 서버에 있을 수 있다 — 낡은 G.off/G.drift 로 확인창을 띄우면 신규 이탈을 경고 없이 저장한다.
    // 그래서 저장 전에 **항상 새로 판정**하고 끝날 때까지 기다린다(그동안 편집은 막는다).
    G.saving = true;
    renderPane();
    requestCheck();
    // fetch 가 매달려도 저장이 영원히 잠기지 않게 10초까지만 기다린다(넘기면 낡은 판정으로 보고 confirm 에 알린다).
    try {
      await Promise.race([G.offPromise, new Promise(function (_, rej) { setTimeout(function () { rej(new Error('판정 대기 시간 초과')); }, 10000); })]);
    } catch (err) { G.offStale = true; }
    var risk = riskText();
    if (risk && !window.confirm(risk + '\n\n그래도 저장할까?')) { G.saving = false; renderPane(); return; }
    if (Host.badgeDirty() && !window.confirm('배지에 저장하지 않은 보정이 있다. 저장하면 페이지가 새로 고쳐져 그 보정이 사라진다. 계속할까?')) { G.saving = false; renderPane(); return; }
    G.log = ''; G.logKind = '';
    renderPane();
    var r;
    try {
      r = await api('/api/geometry/save', { svgRev: G.rev, paths: editedPaths(), rects: editedRects() });
    } catch (err) {
      G.saving = false;
      G.log = String(err.message || err); G.logKind = 'err';
      renderPane();
      return;
    }
    G.saving = false;
    var text = geoLogText(r);
    if (r.saved && r.ok) {
      var alerts = saveAlerts(r);
      try { sessionStorage.setItem(LOG_KEY, JSON.stringify({ text: text, kind: alerts.length ? 'warn' : 'ok', alerts: alerts })); } catch (e) { /* 무시 */ }
      Host.suppressUnload = true;
      location.reload();
      return;
    }
    G.log = text || '저장하지 못했다'; G.logKind = r.ok ? 'ok' : 'err';
    renderPane();
  }

  // 저장 성공 응답에서 **배너로 올릴 경고**를 뽑는다(접힌 로그에 묻히면 안 되는 것들).
  function saveAlerts(r) {
    var out = [];
    var bw = r.badgeWarnings || [];
    if (bw.length) {
      out.push({ k: 'warn', t: '⚠️ 이번 저장으로 새로 생기거나 값이 바뀐 수동 보정 배지 경고 ' + bw.length + '건(전체 ' + (r.badgeWarningsTotal || bw.length) +
        '건 중, 저장 전부터 있던 것 제외). 배지 오프셋은 노선 선 끝점(앵커) 기준 상대값이라 선을 옮기면 손으로 넣은 보정이 같이 움직인다 — 배지 탭에서 확인·재보정할 것.\n' +
        bw.slice(0, 6).map(function (l) { return '  - ' + l.replace(/^경고:\s*/, ''); }).join('\n') + (bw.length > 6 ? '\n  …(전체는 아래 로그)' : '') });
    }
    var md = r.markerDrift || [];
    if (md.length) {
      out.push({ k: 'warn', t: '⚠️ 환승 마커 ' + md.length + '개가 stations.json 역 좌표와 어긋났다(역 좌표는 수정되지 않았다): ' +
        md.slice(0, 6).map(function (d) { return '#' + d.index + ' ' + d.stations[0].name + ' ' + d.dist + 'px' + (d.shared ? '(공유)' : ''); }).join(', ') + (md.length > 6 ? ' …' : '') +
        '. 14px 넘게 옮긴 마커는 이후에도 상단 배너(앵커 없는 마커)에 계속 남는다. 어느 거리든 flutter test test/tool/geometry_svg_test.dart 가 커밋 전에 잡는다 — stations.json 좌표를 같이 맞출 것.' });
    }
    var nw = (r.offLine || []).filter(function (o) { return !o.pre; });
    if (nw.length) {
      out.push({ k: 'warn', t: '⚠️ 12px 밖으로 벗어난 역 ' + nw.length + '개(이번 편집): ' + nw.slice(0, 6).map(function (o) { return o.name + '(' + o.lineId + ') ' + o.dist + 'px'; }).join(', ') + (nw.length > 6 ? ' …' : '') });
    }
    var sw = (r.offLineSoft || []).filter(function (o) { return !o.pre; });
    if (sw.length) {
      out.push({ k: 'warn', t: 'ℹ️ 4px 넘게 벌어져 눈에 보이는 역 ' + sw.length + '개(12px 이하, 이번 편집): ' + sw.slice(0, 6).map(function (o) { return o.name + '(' + o.lineId + ') ' + o.dist + 'px'; }).join(', ') + (sw.length > 6 ? ' …' : '') +
        '. 선만 옮기고 역은 따로 두는 편집이라 의도일 수 있다 — 역 dot 이 선에서 분리돼 보이는지 확인할 것.' });
    }
    var mb = r.movedManualBadges || [];
    if (mb.length) {
      out.push({ k: 'warn', t: '⚠️ 선 끝점(앵커)이 움직여 손으로 보정한 배지 ' + mb.length + '개(전체 ' + (r.manualBadgeTotal || mb.length) + '개 중)가 최대 ' + mb[0].dist +
        'px 같이 움직였다(위반 여부와 무관). 배지 오프셋은 앵커 기준 상대값이다 — 배지 탭에서 자리를 확인할 것: ' +
        mb.slice(0, 6).map(function (m) { return m.key + ' ' + m.dist + 'px'; }).join(', ') + (mb.length > 6 ? ' …' : '') });
    }
    return out;
  }

  function geoLogText(r) {
    var out = [];
    if (r.error) out.push(r.error);
    if (r.message) out.push(r.message);
    if (r.saved && r.ok) {
      out.push('SVG 저장 · 선 ' + r.changed.paths + '개 · 마커 ' + r.changed.rects + '개 변경, 재빌드 완료');
      var off = r.offLine || [];
      var nw = off.filter(function (o) { return !o.pre; }), pre = off.filter(function (o) { return o.pre; });
      if (nw.length) out.push('⚠️ 12px 밖으로 벗어난 역(이번 편집):\n' + nw.map(function (o) { return '  - ' + o.name + ' (' + o.lineId + ') ' + o.dist + 'px'; }).join('\n'));
      var sw = (r.offLineSoft || []).filter(function (o) { return !o.pre; });
      if (sw.length) out.push('4px 넘게 벌어진 역(12px 이하, 이번 편집):\n' + sw.map(function (o) { return '  - ' + o.name + ' (' + o.lineId + ') ' + o.dist + 'px'; }).join('\n'));
      var mb = r.movedManualBadges || [];
      if (mb.length) out.push('선 끝점이 움직여 같이 움직인 수동 보정 배지 ' + mb.length + '개:\n' + mb.map(function (m) { return '  - ' + m.key + ' ' + m.dist + 'px (' + m.dx + ', ' + m.dy + ')'; }).join('\n'));
      if (pre.length) out.push('원래부터 12px 밖인 역:\n' + pre.map(function (o) { return '  - ' + o.name + ' (' + o.lineId + ') ' + o.dist + 'px'; }).join('\n'));
      var md = r.markerDrift || [];
      if (md.length) out.push('⚠️ stations.json 역 좌표와 어긋난 환승 마커:\n' + md.map(function (d) {
        return '  - 마커 #' + d.index + ' (' + d.stations.map(function (x) { return x.name + '|' + x.lineId; }).join(', ') + ') 최대 ' + d.dist + 'px' + (d.shared ? ' [공유 캡슐]' : '');
      }).join('\n'));
    }
    if (r.log) out.push(r.log);
    return out.join('\n\n');
  }

  window.addEventListener('beforeunload', function (e) {
    if (!Host.suppressUnload && G.loaded && geoCount() > 0) { e.preventDefault(); e.returnValue = ''; }
  });

  // ---------------------------------------------------------------- 시작
  function parseD(d) {
    var n = (d || '').match(/-?\d+(?:\.\d+)?/g) || [], out = [];
    for (var i = 0; i + 1 < n.length; i += 2) out.push([+n[i], +n[i + 1]]);
    return out;
  }

  (async function init() {
    try {
      var saved = sessionStorage.getItem(LOG_KEY);
      if (saved) { var l = JSON.parse(saved); G.log = l.text; G.logKind = l.kind; G.alerts = l.alerts || []; sessionStorage.removeItem(LOG_KEY); }
    } catch (e) { /* 무시 */ }
    var m;
    try {
      m = await api('/api/geometry/model');
    } catch (err) {
      G.error = '지오메트리 모델을 불러오지 못했다: ' + (err.message || err);
      renderPane();
      return;
    }
    G.rev = m.svgRev; G.canvas = m.canvas; G.interrupted = m.interrupted ? (m.interruptedNotice || '지난 저장이 중단된 흔적이 있다.') : null;
    G.markerLengths = m.markerLengths; G.thick = m.markerThickness;
    G.paths = m.paths; G.rects = m.rects; G.off = m.offLine || []; G.offSoft = m.offLineSoft || []; G.orphans = m.orphanMarkers || [];
    var dp = mapSvg.querySelectorAll('path'), dr = mapSvg.querySelectorAll('rect');
    if (dp.length !== G.paths.length || dr.length !== G.rects.length) {
      G.error = '지도 DOM 의 path/rect 수(' + dp.length + '/' + dr.length + ')가 SVG(' + G.paths.length + '/' + G.rects.length +
        ')와 다르다 — map.html 이 현재 SVG 로 빌드되지 않았다. dart run tool/build_map_html.dart 후 새로고침할 것. 편집을 막는다.';
      renderPane();
      return;
    }
    G.domPaths = Array.prototype.slice.call(dp); G.domRects = Array.prototype.slice.call(dr);
    G.paths.forEach(function (p) {
      G.byIdx[p.index] = p;
      if (p.editable) { G.editIdx.push(p.index); G.pts[p.index] = clone(p.points); G.orig[p.index] = clone(p.points); }
      var dd = parseD(G.domPaths[p.index].getAttribute('d'));
      var diff = dd.length !== p.points.length;
      for (var k = 0; !diff && k < dd.length; k++) if (Math.abs(dd[k][0] - p.points[k][0]) > 0.01 || Math.abs(dd[k][1] - p.points[k][1]) > 0.01) diff = true;
      if (diff) G.mismatch++;
    });
    G.rects.forEach(function (r) {
      G.rw[r.index] = { x: r.x, y: r.y, w: r.w, h: r.h };
      G.ro[r.index] = { x: r.x, y: r.y, w: r.w, h: r.h };
      var dd = G.domRects[r.index];
      if (Math.abs(+dd.getAttribute('x') - r.x) > 0.01 || Math.abs(+dd.getAttribute('y') - r.y) > 0.01 ||
          Math.abs(+dd.getAttribute('width') - r.w) > 0.01 || Math.abs(+dd.getAttribute('height') - r.h) > 0.01) G.mismatch++;
      G.labels[r.index] = nearLabel(G.rw[r.index]);
    });
    G.loaded = true;
    renderPane(); drawOverlay();
  })();
})();
