/* 노선 배지 수동 보정 편집기 — tool/badge_editor.dart 가 서빙할 때만 map.html 뒤에 합성된다.
 * 프로덕션 assets/html/map.html 에는 이 코드가 들어가지 않는다.
 *
 * 모드: 패널 상단 탭 `배지 | 선분 | 환승마커`. 이 파일은 패널·탭·모드 전환(`window.BadgeEditorHost`)과 배지 모드를
 * 맡고, 선분/환승마커 모드는 geometry.js 가 같은 패널에 붙는다. 배지 모드가 아니면 이 파일의 포인터·키 처리는
 * 전부 물러난다(Host.mode !== 'badge').
 *
 * 원칙
 * - 지도(배지·라벨·선)는 실제 map.html 그대로다. 이 스크립트는 (1) 배지 <g.lb> 의 위치를 서버 모델로
 *   맞추고 (2) 배지 위 드래그만 가로채며 (3) 편집용 오버레이/패널을 얹는다. 줌·팬·휠은 지도 것을 그대로 쓴다.
 * - 겹침 판정은 여기서 하지 않는다. 서버(/api/check, /api/solve)가 빌드와 같은 Dart 함수로 판정한다
 *   (JS 에 기하 규칙을 복제하면 화면과 빌드 결과가 갈라진다).
 * - 오버라이드 = 키 `노선id|종점역명` → {dx, dy} (앵커 → pill 중심 오프셋, 지도 좌표 px).
 */
(function () {
  'use strict';

  var SVG_NS = 'http://www.w3.org/2000/svg';
  var GRID = 0.5;            // 드래그/방향키 스냅(px)
  var HIT_PAD = 3;           // 배지 히트 여유(지도 좌표 px)
  var COLORS = { manual: '#d81b8a', bad: '#d62828', soft: '#e08a00', sel: '#1565d8' };

  var textLayer = document.getElementById('text-layer');
  var badgeGroup = document.getElementById('line-badges');
  if (!textLayer || !badgeGroup) {
    window.alert('편집기: #text-layer / #line-badges 를 찾지 못했다 — map.html 구조가 바뀌었다.');
    return;
  }

  var S = {
    badges: [], byKey: {}, els: [],
    overrides: {}, savedOverrides: {},
    staleKeys: [], warnings: [], summary: [],
    maxAnchorDist: 24,
    selected: null, drag: null,
    undo: [], undoStamp: 0,
    solving: false, solveSeq: 0, solveTimer: 0, pendingModel: null,
    solveError: null, fileError: null, fileExists: false,
    saving: false,
    mapMismatch: 0, checkBusy: false, checkWant: null,
    log: '', logKind: ''
  };

  // ---------------------------------------------------------------- util
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function snap(v) { return Math.round(v / GRID) * GRID; }
  function f1(v) { return (Math.round(v * 10) / 10).toString(); }
  function num(v) { return (Math.round(v * 100) / 100); }

  function el(tag, attrs, text) {
    var e = document.createElement(tag);
    if (attrs) for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (text != null) e.textContent = text;
    return e;
  }
  function sv(tag, attrs) {
    var e = document.createElementNS(SVG_NS, tag);
    if (attrs) for (var k in attrs) e.setAttribute(k, attrs[k]);
    return e;
  }

  async function api(path, body) {
    var res = await fetch(path, body === undefined ? undefined : {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body)
    });
    var data = null;
    try { data = await res.json(); } catch (e) { /* 아래에서 처리 */ }
    if (!res.ok) throw new Error((data && data.error) || ('HTTP ' + res.status));
    return data;
  }

  function dirty() {
    return JSON.stringify(sortedKeys(S.overrides)) !== JSON.stringify(sortedKeys(S.savedOverrides));
  }
  function sortedKeys(o) {
    return Object.keys(o).sort().map(function (k) { return [k, num(o[k].dx), num(o[k].dy)]; });
  }

  // ---------------------------------------------------------------- 좌표
  function toSvg(e) {
    var ctm = textLayer.getScreenCTM();
    if (!ctm) return null;
    var pt = textLayer.createSVGPoint();
    pt.x = e.clientX; pt.y = e.clientY;
    return pt.matrixTransform(ctm.inverse());
  }

  function center(b) { return { x: b.ax + b.ox, y: b.ay + b.oy }; }

  function hitTest(p) {
    var best = null, bestD = Infinity;
    for (var i = 0; i < S.badges.length; i++) {
      var b = S.badges[i], c = center(b);
      if (Math.abs(p.x - c.x) <= b.w / 2 + HIT_PAD && Math.abs(p.y - c.y) <= b.h / 2 + HIT_PAD) {
        var d = Math.abs(p.x - c.x) + Math.abs(p.y - c.y);
        if (d < bestD) { bestD = d; best = b; }
      }
    }
    return best;
  }

  // ---------------------------------------------------------------- 모델 반영
  function collectEls() {
    var gs = badgeGroup.querySelectorAll(':scope > g.lb');
    S.els = [];
    for (var i = 0; i < gs.length; i++) {
      S.els.push({ g: gs[i], rect: gs[i].querySelector('rect'), text: gs[i].querySelector('text') });
    }
  }

  // map.html 의 배지 마크업이 서버 모델과 같은지(= map.html 이 현재 데이터·보정으로 빌드됐는지).
  function countMismatch(badges) {
    if (S.els.length !== badges.length) return badges.length;
    var n = 0;
    for (var i = 0; i < badges.length; i++) {
      var b = badges[i], e = S.els[i];
      var ok = e.g.getAttribute('data-badge-line') === b.lineId;
      var m = /translate\(([-\d.]+),([-\d.]+)\)/.exec(e.g.getAttribute('transform') || '');
      if (!m || Math.abs(+m[1] - b.ax) > 0.11 || Math.abs(+m[2] - b.ay) > 0.11) ok = false;
      if (Math.abs(parseFloat(e.rect.getAttribute('x')) - (b.ox - b.w / 2)) > 0.11) ok = false;
      if (Math.abs(parseFloat(e.rect.getAttribute('y')) - (b.oy - b.h / 2)) > 0.11) ok = false;
      if (!ok) n++;
    }
    return n;
  }

  function placeDom(b) {
    var e = S.els[b.index];
    if (!e) return;
    e.rect.setAttribute('x', f1(b.ox - b.w / 2));
    e.rect.setAttribute('y', f1(b.oy - b.h / 2));
    e.text.setAttribute('x', f1(b.ox));
    e.text.setAttribute('y', f1(b.oy));
  }

  function applyModel(m) {
    S.badges = m.badges;
    S.byKey = {};
    m.badges.forEach(function (b) { S.byKey[b.key] = b; });
    S.staleKeys = m.staleKeys || [];
    S.warnings = m.warnings || [];
    S.summary = m.summary || [];
    S.maxAnchorDist = m.maxAnchorDist;
    if (S.selected && !S.byKey[S.selected]) S.selected = null;
    S.badges.forEach(placeDom);
    redraw();
  }

  // ---------------------------------------------------------------- 오버레이
  var overlay = sv('g', { id: 'badge-editor-overlay' });
  textLayer.appendChild(overlay);

  function box(x, y, w, h, color, opts) {
    opts = opts || {};
    var r = sv('rect', {
      x: x, y: y, width: w, height: h, rx: opts.rx == null ? 3 : opts.rx,
      fill: opts.fill || 'none', stroke: color, 'stroke-width': opts.sw || 1.8
    });
    if (opts.dash) r.setAttribute('stroke-dasharray', opts.dash);
    if (opts.fillOpacity != null) r.setAttribute('fill-opacity', opts.fillOpacity);
    overlay.appendChild(r);
    return r;
  }

  function hardOf(b) { return (b.violations || []).filter(function (v) { return !v.soft; }); }

  function drawOverlay() {
    while (overlay.firstChild) overlay.removeChild(overlay.firstChild);
    if (window.BadgeEditorHost && window.BadgeEditorHost.mode !== 'badge') return;   // 배지 모드가 아니면 그리지 않는다
    S.badges.forEach(function (b) {
      var c = center(b), x = c.x - b.w / 2, y = c.y - b.h / 2;
      var bad = b.manual && hardOf(b).length > 0;
      if (b.manual) {
        box(x - 2.5, y - 2.5, b.w + 5, b.h + 5, bad ? COLORS.bad : COLORS.manual,
            { dash: bad ? null : '4 3', rx: b.h / 2 + 2 });
      }
    });
    var s = S.selected && S.byKey[S.selected];
    if (s) {
      var c = center(s), x = c.x - s.w / 2, y = c.y - s.h / 2;
      // 위반 대상 강조
      (s.violations || []).forEach(function (v) {
        if (!v.box) return;
        box(v.box[0], v.box[1], v.box[2] - v.box[0], v.box[3] - v.box[1],
            v.soft ? COLORS.soft : COLORS.bad, { fill: v.soft ? COLORS.soft : COLORS.bad, fillOpacity: 0.22, rx: 1 });
      });
      // 앵커(노선 선의 자유 끝점)와 pill 의 관계
      var ln = sv('line', { x1: s.ax, y1: s.ay, x2: c.x, y2: c.y, stroke: COLORS.sel, 'stroke-width': 1, 'stroke-dasharray': '2 3' });
      overlay.appendChild(ln);
      overlay.appendChild(sv('circle', { cx: s.ax, cy: s.ay, r: 3.2, fill: COLORS.sel, stroke: '#fff', 'stroke-width': 1 }));
      box(x - 3.5, y - 3.5, s.w + 7, s.h + 7, COLORS.sel, { sw: 2.4, rx: s.h / 2 + 3 });
    }
  }

  // ---------------------------------------------------------------- 패널
  var panel = el('div', { id: 'be-panel' });
  panel.innerHTML =
    '<div class="be-head">' +
      '<div class="be-title">지도 편집기</div>' +
      '<button id="be-side" title="좌/우 반대편으로">⇄</button>' +
      '<button id="be-collapse" title="접기/펴기">–</button>' +
    '</div>' +
    '<div class="be-tabs" id="be-tabs">' +
      '<button data-mode="badge" class="be-tab">배지</button>' +
      '<button data-mode="line" class="be-tab">선분</button>' +
      '<button data-mode="marker" class="be-tab">환승마커</button>' +
    '</div>' +
    '<div class="be-modenote" id="be-modenote"></div>' +
    '<div id="be-badge-pane">' +
    '<div class="be-state" id="be-state"></div>' +
    '<div class="be-hint">배지를 드래그해 옮긴다. 방향키 0.5px(Shift 5px) · Del 자동 배치로 · Ctrl+Z 취소 · Ctrl+S 저장. 지도 줌·팬·휠은 그대로.</div>' +
    '<div class="be-legend"><i class="l-manual"></i>수동 보정 <i class="l-bad"></i>위반(경고) <i class="l-sel"></i>선택</div>' +
    '<div id="be-banner"></div>' +
    '<div class="be-row"><button id="be-save" class="be-primary">저장 + 재빌드</button>' +
    '<button id="be-undo">실행 취소</button><button id="be-reset-all">전체 초기화</button></div>' +
    '<select id="be-pick" title="배지 찾기"></select>' +
    '<div id="be-sel"></div>' +
    '<div id="be-warns"></div>' +
    '<details id="be-sum"><summary>빌드 요약(현재 배치)</summary><pre id="be-sum-pre"></pre></details>' +
    '<details id="be-logbox"><summary>저장·재빌드 로그</summary><pre id="be-log-pre"></pre></details>' +
    '</div>' +
    '<div id="be-geo-pane"></div>';
  document.body.appendChild(panel);
  // 패널 위 입력이 지도 팬/줌으로 새지 않게 한다.
  ['pointerdown', 'pointerup', 'pointermove', 'wheel', 'click', 'dblclick'].forEach(function (t) {
    panel.addEventListener(t, function (e) { e.stopPropagation(); }, { passive: t !== 'wheel' ? true : true });
  });
  var $ = function (id) { return document.getElementById(id); };

  // ------------------------------------------------- 모드 전환 (배지 / 선분 / 환승마커)
  // geometry.js 가 Host.dirtyOf.line/marker·Host.geoDirtyCount·Host.onMode 에 붙는다. 한 번에 한 모드만 활성이고,
  // 다른 모드의 편집 상태(미저장 변경)는 버리지 않고 유지한다 — 탭의 ● 와 안내 문구로 알린다.
  var MODE_KEY = 'be.mode';
  var Host = window.BadgeEditorHost = {
    mode: 'badge', panel: panel, $: $, el: el, sv: sv, api: api, toSvg: toSvg, textLayer: textLayer,
    clone: clone, f1: f1,
    dirtyOf: { badge: function () { return dirty(); }, line: function () { return false; }, marker: function () { return false; } },
    // 모드별 **경고 개수**. 배너는 그 모드 pane 안에 있어 다른 모드에서는 숨겨지는데,
    // 고아 마커처럼 "이 SVG 에 이미 들어 있는 문제" 는 어느 모드로 열든 보여야 한다
    // (새 탭은 기본이 배지 모드라 배너만 두면 아무도 못 본다). 탭 라벨에 ⚠N 으로 올린다.
    alertOf: { badge: function () { return 0; }, line: function () { return 0; }, marker: function () { return 0; } },
    geoDirtyCount: function () { return 0; },   // geometry.js 가 덮어쓴다(저장 안 된 선분+마커 변경 수)
    badgeDirty: function () { return dirty(); },
    // 저장 성공 뒤 location.reload() 직전에 세운다. 배지/지오메트리 어느 쪽이 저장하든 **양쪽** beforeunload 가 이 하나를 본다
    // (모드별로 따로 두면 교차 저장 때 "페이지를 나가시겠습니까?" 가 한 번 더 떠, 머무르면 화면이 디스크와 어긋난다).
    suppressUnload: false,
    onMode: [], refreshTabs: null, setMode: null
  };
  function modeGroup(m) { return m === 'badge' ? 'badge' : 'geo'; }
  Host.refreshTabs = function () {
    var tabs = panel.querySelectorAll('#be-tabs .be-tab');
    for (var i = 0; i < tabs.length; i++) {
      var m = tabs[i].getAttribute('data-mode');
      var base = m === 'badge' ? '배지' : m === 'line' ? '선분' : '환승마커';
      var d = Host.dirtyOf[m] && Host.dirtyOf[m]();
      var a = (Host.alertOf[m] && Host.alertOf[m]()) || 0;
      tabs[i].textContent = base + (a ? ' ⚠' + a : '') + (d ? ' ●' : '');
      tabs[i].classList.toggle('be-tab-on', Host.mode === m);
    }
  };
  Host.setMode = function (m) {
    if (m !== 'badge' && m !== 'line' && m !== 'marker') return;
    if (S.saving || S.drag) return;
    var prev = Host.mode;
    Host.mode = m;
    panel.classList.toggle('be-mode-badge', m === 'badge');
    panel.classList.toggle('be-mode-geo', m !== 'badge');
    document.documentElement.style.cursor = '';
    var note = '';
    if (modeGroup(prev) !== modeGroup(m)) {
      if (prev === 'badge' && dirty()) note = '배지 보정이 저장되지 않았다(유지됨 — 배지 탭으로 돌아가면 이어서 편집·저장).';
      else if (modeGroup(prev) === 'geo' && Host.geoDirtyCount() > 0) note = '선분/환승마커 변경 ' + Host.geoDirtyCount() + '건이 저장되지 않았다(유지됨 — 돌아가면 이어서 편집·저장).';
    }
    $('be-modenote').textContent = note;
    $('be-modenote').style.display = note ? 'block' : 'none';
    try { sessionStorage.setItem(MODE_KEY, m); } catch (e) { /* 무시 */ }
    if (typeof drawOverlay === 'function') redraw();
    Host.onMode.forEach(function (fn) { try { fn(m, prev); } catch (e) { console.error(e); } });
    Host.refreshTabs();
  };
  panel.querySelectorAll('#be-tabs .be-tab').forEach(function (b) {
    b.addEventListener('click', function () { Host.setMode(b.getAttribute('data-mode')); });
  });

  // ------------------------------------------------- 패널 위치/접기 (지도 가림 방지)
  // 제목줄을 잡고 끌면 패널이 움직이고, ⇄ 는 좌/우 끝을 오간다. 접으면 제목만 남는다.
  // 위치·접힘 상태는 localStorage 에 남겨 새로고침·재빌드 후에도 유지된다.
  var PANEL_KEY = 'badge-editor.panel';
  function clampPanel(left, top) {
    var w = panel.offsetWidth, h = panel.offsetHeight;
    return {
      left: Math.max(4, Math.min(window.innerWidth - w - 4, left)),
      top: Math.max(4, Math.min(window.innerHeight - Math.min(h, 80) - 4, top))
    };
  }
  function applyPanel(st) {
    panel.classList.toggle('be-collapsed', !!st.collapsed);
    var btn = $('be-collapse');
    if (btn) btn.textContent = st.collapsed ? '+' : '–';
    if (typeof st.left === 'number' && typeof st.top === 'number') {
      var c = clampPanel(st.left, st.top);
      panel.style.right = 'auto';
      panel.style.left = c.left + 'px';
      panel.style.top = c.top + 'px';
    }
  }
  function panelState() {
    var st = { collapsed: panel.classList.contains('be-collapsed') };
    if (panel.style.left && panel.style.left !== 'auto') {
      st.left = parseFloat(panel.style.left);
      st.top = parseFloat(panel.style.top);
    }
    return st;
  }
  function savePanel() {
    try { localStorage.setItem(PANEL_KEY, JSON.stringify(panelState())); } catch (e) {}
  }
  (function restorePanel() {
    var st = null;
    try { st = JSON.parse(localStorage.getItem(PANEL_KEY) || 'null'); } catch (e) {}
    if (st && typeof st === 'object') applyPanel(st);
  })();
  $('be-collapse').addEventListener('click', function () {
    panel.classList.toggle('be-collapsed');
    $('be-collapse').textContent = panel.classList.contains('be-collapsed') ? '+' : '–';
    savePanel();
  });
  $('be-side').addEventListener('click', function () {
    var r = panel.getBoundingClientRect();
    var toLeft = r.left + r.width / 2 > window.innerWidth / 2;
    applyPanel({
      collapsed: panel.classList.contains('be-collapsed'),
      left: toLeft ? 12 : window.innerWidth - panel.offsetWidth - 12,
      top: r.top
    });
    savePanel();
  });
  (function dragPanel() {
    var head = panel.querySelector('.be-head'), from = null;
    head.addEventListener('pointerdown', function (ev) {
      if (ev.target.tagName === 'BUTTON') return;      // 버튼 클릭은 드래그가 아니다
      var r = panel.getBoundingClientRect();
      from = { x: ev.clientX, y: ev.clientY, left: r.left, top: r.top };
      panel.classList.add('be-dragging');
      head.setPointerCapture(ev.pointerId);
      ev.preventDefault();
    });
    head.addEventListener('pointermove', function (ev) {
      if (!from) return;
      applyPanel({
        collapsed: panel.classList.contains('be-collapsed'),
        left: from.left + (ev.clientX - from.x),
        top: from.top + (ev.clientY - from.y)
      });
    });
    ['pointerup', 'pointercancel'].forEach(function (t) {
      head.addEventListener(t, function (ev) {
        if (!from) return;
        from = null;
        panel.classList.remove('be-dragging');
        try { head.releasePointerCapture(ev.pointerId); } catch (e) {}
        savePanel();
      });
    });
  })();
  // 창 크기가 바뀌면 패널이 화면 밖으로 나가지 않게 당겨 온다.
  window.addEventListener('resize', function () { applyPanel(panelState()); });

  function bannerLines() {
    var out = [];
    if (S.fileError) out.push({ k: 'err', t: '보정 파일을 읽을 수 없다(빈 보정으로 표시 중 · 저장 막힘):\n' + S.fileError });
    if (S.solveError) out.push({ k: 'err', t: '이 보정으로는 빌드가 실패한다(저장 막힘 — 실행 취소하거나 해당 배지를 되돌릴 것):\n' + S.solveError });
    if (S.mapMismatch > 0 && !S.fileError && !S.solveError)
      out.push({ k: 'warn', t: 'map.html 의 배지 ' + S.mapMismatch + '개가 현재 보정/데이터와 다르다 — 저장(재빌드)하면 맞춰진다. 화면은 서버 모델 기준이다.' });
    if (S.staleKeys.length)
      out.push({ k: 'warn', t: '파일에 현재 배지와 맞지 않는 키 ' + S.staleKeys.length + '개(' + S.staleKeys.join(', ') + ') — 자동 배치로 처리 중이며 저장하면 파일에서 제거된다.' });
    return out;
  }

  function renderPanel() {
    var manualN = S.badges.filter(function (b) { return b.manual; }).length;
    var st = $('be-state');
    st.innerHTML = '';
    st.appendChild(document.createTextNode('수동 '));
    st.appendChild(el('b', null, manualN + ' / ' + S.badges.length));
    st.appendChild(document.createTextNode(
      (dirty() ? ' · 저장 안 됨' : ' · 저장됨') +
      (S.solving ? ' · 재배치 계산 중…' : '') + (S.saving ? ' · 저장·재빌드 중…' : '')));

    var bn = $('be-banner');
    bn.innerHTML = '';
    bannerLines().forEach(function (l) { bn.appendChild(el('div', { 'class': 'be-banner ' + l.k }, l.t)); });
    if (S.log) {
      var logOpen = $('be-logbox');
      $('be-log-pre').textContent = S.log;
      if (S.logKind) bn.appendChild(el('div', { 'class': 'be-banner ' + S.logKind },
        S.logKind === 'ok' ? '저장·재빌드 완료. 아래 로그 참조.' : '저장·재빌드에 문제가 있다. 아래 로그 참조.'));
      if (S.logKind === 'err') logOpen.open = true;
    }

    var busy = S.solving || S.saving;
    $('be-save').disabled = busy || !!S.solveError || !!S.fileError || S.badges.length === 0;
    $('be-undo').disabled = busy || S.undo.length === 0;
    $('be-reset-all').disabled = busy || Object.keys(S.overrides).length === 0;

    // 배지 선택 드롭다운
    var pick = $('be-pick');
    var want = S.badges.map(function (b) { return b.key + '|' + b.manual + '|' + hardOf(b).length; }).join(';');
    if (pick.getAttribute('data-sig') !== want) {
      pick.setAttribute('data-sig', want);
      pick.innerHTML = '';
      pick.appendChild(el('option', { value: '' }, '배지 찾기…'));
      S.badges.forEach(function (b) {
        pick.appendChild(el('option', { value: b.key },
          b.lineName + ' · ' + b.station + (b.manual ? ' [수동]' : '') + (b.manual && hardOf(b).length ? ' [경고]' : '')));
      });
    }
    pick.value = '';

    // 선택 배지 정보
    var sel = $('be-sel');
    sel.innerHTML = '';
    var s = S.selected && S.byKey[S.selected];
    if (!s) {
      sel.appendChild(el('div', { 'class': 'be-hint' }, '배지를 클릭하거나 위 목록에서 고르면 오프셋과 겹침이 여기 나온다.'));
    } else {
      var card = el('div', { 'class': 'be-sel' });
      var nm = el('div', { 'class': 'nm' }, s.lineName + ' · ' + s.station);
      nm.appendChild(el('span', { 'class': 'tag ' + (s.manual ? 'manual' : 'auto') }, s.manual ? '수동 보정' : '자동 배치'));
      card.appendChild(nm);
      card.appendChild(el('div', { 'class': 'kv' }, '키 ' + s.key));
      card.appendChild(el('div', { 'class': 'kv' }, '오프셋 dx=' + f1(s.ox) + '  dy=' + f1(s.oy) + '  (앵커→pill 중심)'));
      var far = s.anchorDist > S.maxAnchorDist + 1e-9;
      card.appendChild(el('div', { 'class': 'kv' }, '앵커까지 최단 거리 ' + f1(s.anchorDist) + 'px (자동 배치 상한 ' + f1(S.maxAnchorDist) + 'px' + (far ? ' 초과' : '') + ')'));
      var ul = el('ul');
      var vs = s.violations || [];
      if (!vs.length) ul.appendChild(el('li', { 'class': 'good' }, '겹침 없음'));
      vs.forEach(function (v) { ul.appendChild(el('li', { 'class': v.soft ? 'soft' : 'hard' }, v.message)); });
      card.appendChild(ul);
      var row = el('div', { 'class': 'be-row' });
      var rb = el('button', null, '자동 배치로 되돌리기');
      rb.disabled = !s.manual || busy;
      rb.addEventListener('click', function () { resetOne(s.key); });
      row.appendChild(rb);
      card.appendChild(row);
      sel.appendChild(card);
    }

    // 수동 배치 경고 목록
    var wn = $('be-warns');
    wn.innerHTML = '';
    var bad = S.badges.filter(function (b) { return b.manual && hardOf(b).length; });
    if (bad.length) {
      wn.appendChild(el('div', { 'class': 'be-hint' }, '수동 배치 경고 ' + bad.length + '건 (빌드는 실패하지 않고 로그에 남는다)'));
      bad.forEach(function (b) {
        var it = el('div', { 'class': 'item' }, b.lineName + ' · ' + b.station + ' — ' + hardOf(b).map(function (v) { return v.message; }).join(' / '));
        it.addEventListener('click', function () { select(b.key, true); });
        wn.appendChild(it);
      });
    }
    $('be-sum-pre').textContent = S.summary.join('\n') + (S.warnings.length ? '\n\n' + S.warnings.join('\n') : '');
    if (window.BadgeEditorHost && Host.refreshTabs) Host.refreshTabs();
  }

  $('be-pick').addEventListener('change', function (e) { if (e.target.value) select(e.target.value, true); });
  $('be-save').addEventListener('click', save);
  $('be-undo').addEventListener('click', undo);
  $('be-reset-all').addEventListener('click', resetAll);

  function redraw() { drawOverlay(); renderPanel(); }

  function select(key, pan) {
    S.selected = key;
    redraw();
    var b = S.byKey[key];
    if (pan && b && typeof window.panTo === 'function') window.panTo(b.ax + b.ox, b.ay + b.oy, 250);
  }

  // ---------------------------------------------------------------- 오버라이드 변경 + 솔브
  function pushUndo() {
    S.undo.push(clone(S.overrides));
    if (S.undo.length > 60) S.undo.shift();
  }

  function setOverride(key, dx, dy) {
    S.overrides[key] = { dx: num(dx), dy: num(dy) };
  }

  function scheduleSolve(delay) {
    S.solving = true;
    S.solveSeq++;
    S.pendingModel = null;
    clearTimeout(S.solveTimer);
    S.solveTimer = setTimeout(doSolve, delay || 0);
    renderPanel();
  }

  async function doSolve() {
    var seq = S.solveSeq;
    var r;
    try {
      r = await api('/api/solve', { overrides: S.overrides });
    } catch (err) {
      if (seq !== S.solveSeq) return;
      S.solving = false;
      S.solveError = String(err.message || err);
      renderPanel();
      return;
    }
    if (seq !== S.solveSeq) return;          // 더 새 요청이 있다
    if (S.drag) { S.pendingModel = r; return; } // 드래그 중엔 화면을 흔들지 않는다(놓을 때 처리)
    finishSolve(r);
  }

  function finishSolve(r) {
    S.solving = false;
    if (r.ok) {
      S.solveError = null;
      applyModel(r.model);
    } else {
      S.solveError = r.error || '알 수 없는 오류';
      renderPanel();
    }
  }

  function resetOne(key) {
    if (!S.overrides[key]) return;
    pushUndo();
    delete S.overrides[key];
    scheduleSolve(0);
  }

  function resetAll() {
    if (!Object.keys(S.overrides).length) return;
    if (!window.confirm('수동 보정 ' + Object.keys(S.overrides).length + '개를 모두 자동 배치로 되돌릴까? (저장 전까지는 파일이 바뀌지 않는다)')) return;
    pushUndo();
    S.overrides = {};
    scheduleSolve(0);
  }

  function undo() {
    if (!S.undo.length) return;
    S.overrides = S.undo.pop();
    scheduleSolve(0);
  }

  // ---------------------------------------------------------------- 즉시 겹침 판정(서버)
  function requestCheck(b) {
    S.checkWant = { key: b.key, dx: b.ox, dy: b.oy };
    if (S.checkBusy) return;
    S.checkBusy = true;
    (async function loop() {
      while (S.checkWant) {
        var w = S.checkWant;
        S.checkWant = null;
        try {
          var r = await api('/api/check', w);
          var cur = S.byKey[w.key];
          if (cur && cur.ox === w.dx && cur.oy === w.dy) {
            cur.violations = r.violations;
            cur.anchorDist = r.anchorDist;
            redraw();
          }
        } catch (err) { /* 일시 오류는 다음 이동 때 다시 판정한다 */ }
      }
      S.checkBusy = false;
    })();
  }

  // ---------------------------------------------------------------- 드래그
  function onDown(e) {
    if (Host.mode !== 'badge') return;
    if (e.button !== 0 || panel.contains(e.target) || S.saving) return;
    var p = toSvg(e);
    if (!p) return;
    var b = hitTest(p);
    if (!b) return;                       // 빈 곳은 지도 팬으로 넘긴다
    e.stopPropagation();
    e.preventDefault();
    try { e.target.setPointerCapture(e.pointerId); } catch (err) { /* 무시 */ }
    S.selected = b.key;
    S.drag = { key: b.key, pid: e.pointerId, p0: p, ox0: b.ox, oy0: b.oy, moved: false, before: clone(S.overrides) };
    document.body.classList.add('be-dragging');
    redraw();
  }

  function onMove(e) {
    var d = S.drag;
    if (!d) {
      // 호버: 배지 위면 잡을 수 있다는 표시만(이벤트는 지도로 흘려보낸다).
      if (Host.mode !== 'badge') return;
      if (!e.buttons) {
        var p0 = toSvg(e);
        document.documentElement.style.cursor = (p0 && hitTest(p0)) ? 'grab' : '';
      }
      return;
    }
    if (e.pointerId !== d.pid) return;
    e.stopPropagation();
    var p = toSvg(e);
    if (!p) return;
    var b = S.byKey[d.key];
    var nx = snap(d.ox0 + (p.x - d.p0.x)), ny = snap(d.oy0 + (p.y - d.p0.y));
    if (nx === b.ox && ny === b.oy) return;
    d.moved = true;
    b.ox = nx; b.oy = ny;
    b.manual = true;
    placeDom(b);
    redraw();
    requestCheck(b);
  }

  function onUp(e) {
    var d = S.drag;
    if (!d || e.pointerId !== d.pid) return;
    e.stopPropagation();
    S.drag = null;
    document.body.classList.remove('be-dragging');
    var b = S.byKey[d.key];
    if (d.moved) {
      S.undo.push(d.before);
      if (S.undo.length > 60) S.undo.shift();
      setOverride(b.key, b.ox, b.oy);
      scheduleSolve(0);               // 자동 배지가 비켜나는 실제 결과를 받아 온다(~3초)
    } else if (S.pendingModel) {
      var m = S.pendingModel; S.pendingModel = null; finishSolve(m);
    } else {
      redraw();
    }
  }

  window.addEventListener('pointerdown', onDown, true);
  window.addEventListener('pointermove', onMove, true);
  window.addEventListener('pointerup', onUp, true);
  window.addEventListener('pointercancel', onUp, true);

  // ---------------------------------------------------------------- 키보드
  window.addEventListener('keydown', function (e) {
    if (Host.mode !== 'badge') return;      // 선분/환승마커 모드의 키 처리는 geometry.js
    var tag = (e.target && e.target.tagName) || '';
    var mod = e.metaKey || e.ctrlKey;
    if (mod && (e.key === 's' || e.key === 'S')) { e.preventDefault(); save(); return; }
    if (mod && (e.key === 'z' || e.key === 'Z')) { e.preventDefault(); undo(); return; }
    if (tag === 'SELECT' || tag === 'INPUT' || tag === 'TEXTAREA') return;
    var s = S.selected && S.byKey[S.selected];
    if (!s) return;
    if (e.key === 'Escape') { S.selected = null; redraw(); return; }
    if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); resetOne(s.key); return; }
    var step = e.shiftKey ? 5 : GRID, dx = 0, dy = 0;
    if (e.key === 'ArrowLeft') dx = -step; else if (e.key === 'ArrowRight') dx = step;
    else if (e.key === 'ArrowUp') dy = -step; else if (e.key === 'ArrowDown') dy = step;
    else return;
    e.preventDefault();
    if (S.saving) return;
    // 연타는 한 번의 실행 취소 단위로 묶는다.
    var now = Date.now();
    if (now - S.undoStamp > 900) pushUndo();
    S.undoStamp = now;
    s.ox = snap(s.ox + dx); s.oy = snap(s.oy + dy); s.manual = true;
    setOverride(s.key, s.ox, s.oy);
    placeDom(s);
    redraw();
    requestCheck(s);
    scheduleSolve(500);
  });

  // ---------------------------------------------------------------- 저장
  async function save() {
    if (S.saving || S.solving || S.solveError || S.fileError) return;
    // 저장 성공 시 페이지를 새로 고치므로 선분/환승마커의 저장 안 된 변경이 같이 사라진다 — 미리 확인한다.
    if (Host.geoDirtyCount() > 0 && !window.confirm('선분/환승마커에 저장하지 않은 변경 ' + Host.geoDirtyCount() +
        '건이 있다. 배지를 저장하면 페이지가 새로 고쳐져 그 변경이 사라진다. 계속할까?')) return;
    S.saving = true; S.log = ''; S.logKind = '';
    renderPanel();
    var r;
    try {
      r = await api('/api/save', { overrides: S.overrides });
    } catch (err) {
      S.saving = false;
      S.log = String(err.message || err); S.logKind = 'err';
      renderPanel();
      return;
    }
    S.saving = false;
    var text = (r.error ? r.error + '\n\n' : '') + (r.log || '') +
      (r.droppedStaleKeys && r.droppedStaleKeys.length ? '\n\n파일에서 제거한 키: ' + r.droppedStaleKeys.join(', ') : '');
    if (r.saved && r.ok) {
      // 실제 재빌드된 map.html 로 다시 불러와 결과를 확인한다(로그는 새로 고친 뒤 패널에 남긴다).
      try { sessionStorage.setItem('beLog', JSON.stringify({ text: 'data/badge_offsets.json 저장 · ' + r.savedCount + '개 수동 보정\n\n' + text, kind: 'ok' })); } catch (e) { /* 무시 */ }
      Host.suppressUnload = true;
      location.reload();
      return;
    }
    S.log = text || '저장하지 못했다'; S.logKind = 'err';
    if (r.saved) S.savedOverrides = clone(S.overrides);
    renderPanel();
  }

  window.addEventListener('beforeunload', function (e) {
    if (!Host.suppressUnload && dirty()) { e.preventDefault(); e.returnValue = ''; }
  });

  // ---------------------------------------------------------------- 시작
  (async function init() {
    collectEls();
    try {
      var saved = sessionStorage.getItem('beLog');
      if (saved) {
        var l = JSON.parse(saved);
        S.log = l.text; S.logKind = l.kind;
        sessionStorage.removeItem('beLog');
      }
    } catch (e) { /* 무시 */ }
    var r;
    try {
      r = await api('/api/model');
    } catch (err) {
      S.fileError = '서버 모델을 불러오지 못했다: ' + (err.message || err);
      renderPanel();
      return;
    }
    S.fileError = r.fileError || null;
    S.solveError = r.solveError || null;
    S.fileExists = !!r.fileExists;
    S.overrides = clone(r.overrides);
    S.savedOverrides = clone(r.overrides);
    S.mapMismatch = countMismatch(r.model.badges);
    applyModel(r.model);
  })();

  // 저장 후 새로 고침해도 보던 모드로 돌아온다(geometry.js 가 모두 올라온 뒤 적용되도록 한 틱 미룬다).
  setTimeout(function () {
    var m = 'badge';
    try { m = sessionStorage.getItem(MODE_KEY) || 'badge'; } catch (e) { /* 무시 */ }
    Host.setMode(m);
  }, 0);
})();
