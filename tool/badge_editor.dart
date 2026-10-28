/// 노선 배지(P2-4) **수동 위치 보정 편집기** + 노선 선분·환승 마커 **지오메트리 편집기** — 로컬 전용 개발 도구.
///
/// 편집 모드 3개(패널 상단 탭): `배지`(아래 `/api/{model,check,solve,save}`) · `선분` · `환승마커`
/// (아래 `/api/geometry/*`). 선분·환승마커는 SVG 하나를 같이 고치므로 저장도 하나다.
///
/// 실행: `dart run tool/badge_editor.dart [--port=8765]` → http://localhost:8765/
/// (`.claude/launch.json` 의 `badge-editor` 항목으로 `preview_start` 에서도 뜬다.)
///
/// 하는 일:
/// - `GET /` : 실제 지도(`assets/html/map.html`, 즉 `tool/build_map_html.dart` 의 산출물) 그대로에
///   편집기 UI(`tool/badge_editor/editor.{js,css}`)를 **덧붙여** 서빙한다. 프로덕션 `map.html` 에는
///   편집기 코드가 들어가지 않는다(서빙 시점에만 합성). 줌·팬·라벨·선이 실제 렌더와 같다.
/// - `POST /api/check` : 드래그 중 배지를 어느 위치에 놓았을 때의 하드 위반을 즉시 판정한다.
///   판정은 빌드와 **같은 함수**(`LineBadgeSolution.check` → `_BadgePlacer._hard`)다.
/// - `POST /api/solve` : 오버라이드 묶음으로 전체 배치를 다시 푼다(자동 배지가 비켜나는 실제 결과).
/// - `POST /api/save` : 오버라이드를 검증·솔브해 빌드가 성공하는 조합만 `data/badge_offsets.json`
///   에 기록하고, `dart run tool/build_map_html.dart` 를 돌려 그 로그를 돌려준다.
/// - `GET /api/geometry/model` : 노선 path 정점·환승 마커 rect·현재 12px(하드)/4px(소프트) 이탈 역·**고아 마커**
///   (`orphanMarkers` — 앵커 역이 없는 마커, 저장 뒤 새로고침해도 남는 영속 드리프트 신호)(`tool/geometry_svg.dart`).
/// - `POST /api/geometry/check` : 편집 중인 정점으로 12px/4px 이탈 역을, 편집 중인 마커의 stations.json 어긋남을 즉시 판정한다
///   (규칙은 `tool/geometry_svg.dart` 한 곳 — main 에서 서는 CI 가드는 `test/tool/geometry_svg_test.dart`).
/// - `POST /api/geometry/save` : 백업 → `assets/svg/seoul_metro_map.svg` 갱신(tmp+rename) → 빌드 →
///   **빌드가 실패하면 SVG(와 map.html)를 백업으로 되돌린다**(깨진 지도를 디스크에 남기지 않는다).
///
/// 안전:
/// - **127.0.0.1 에만 바인딩**한다(외부 노출 없음). Host 헤더가 localhost 계열이 아니면 거부(DNS rebinding
///   방어), POST 는 `application/json` + 같은 Origin 만 받는다(타 사이트의 CSRF 방어).
/// - **쓰기 경로는 고정**이다: 배지 모드는 `data/badge_offsets.json`, 선분/환승마커 모드는
///   `assets/svg/seoul_metro_map.svg` 하나(+ 빌드가 다시 쓰는 `assets/html/map.html`). 임의 경로를 받는 API 가 없다
///   (서버가 고정 경로에 고정 포맷으로 직렬화하고, 요청 본문은 숫자 좌표·크기만 읽는다).
/// - 보정할 때만 띄우는 도구다 — 앱 번들(`assets/`)이나 `lib/` 어디에서도 참조하지 않는다.
/// - **서버는 한 번에 하나만** 띄운다. 저장 락(`_buildBusy`)이 프로세스 안에서만 유효해, 서버가 둘이면 두 빌드가
///   `assets/html/map.html` 을 교차로 쓸 수 있다(SVG 는 `svgRev` 로 보호되지만 map.html 은 아니다).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'geometry_svg.dart';
import 'line_badges.dart';
import 'map_constants.dart' show kCanvasH, kCanvasW;

const _kDefaultPort = 8765;
const _kMaxBody = 1 << 20;
const _kHtmlPath = 'assets/html/map.html';
const _kBuildScript = 'tool/build_map_html.dart';
const _kSvgPath = 'assets/svg/seoul_metro_map.svg';
const _kStationsPath = 'assets/json/stations.json';
const _kLinesPath = 'assets/json/lines.json';

/// 지오메트리 저장의 백업·임시 파일 폴더. **assets/ 밖**이어야 한다 — `assets/svg/` 는 통째로 앱 번들에
/// 들어가므로 .bak/.tmp 를 거기 두면 배포물에 섞인다. `.dart_tool/` 는 gitignore 대상이다.
const _kGeoWorkDir = '.dart_tool/geometry_editor';
const _kBuildTimeout = Duration(minutes: 3);

Future<void> main(List<String> args) async {
  var port = _kDefaultPort;
  for (final a in args) {
    if (a.startsWith('--port=')) {
      port = int.tryParse(a.substring(7)) ?? -1;
      if (port < 1 || port > 65535) {
        stderr.writeln('잘못된 --port: $a');
        exit(64);
      }
    } else {
      stderr.writeln('알 수 없는 인자: $a  (사용법: dart run tool/badge_editor.dart [--port=8765])');
      exit(64);
    }
  }
  final root = File.fromUri(Platform.script).parent.parent;
  for (final p in ['pubspec.yaml', _kHtmlPath, _kSvgPath, 'tool/badge_editor/editor.js', 'tool/badge_editor/geometry.js']) {
    if (!File('${root.path}/$p').existsSync()) {
      stderr.writeln('프로젝트 루트(${root.path})에서 $p 를 찾지 못했다 — '
          'tool/badge_editor.dart 를 저장소의 tool/ 에서 실행할 것');
      exit(1);
    }
  }
  final HttpServer server;
  try {
    // 루프백만: 외부 인터페이스에는 바인딩하지 않는다.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException catch (e) {
    stderr.writeln('포트 $port 를 열 수 없다: ${e.message} — --port=NNNN 으로 다른 포트를 쓸 것');
    exit(1);
  }
  final app = _EditorApp(root, port);
  stdout.writeln('노선 배지 편집기: http://localhost:$port/  (127.0.0.1 전용, Ctrl+C 로 종료)');
  stdout.writeln('쓰기 대상: 배지 모드 → $kBadgeOffsetsPath, 선분/환승마커 모드 → $_kSvgPath (둘 다 고정 경로).');
  app.warnIfInterruptedSave();
  await for (final req in server) {
    unawaited(app.handle(req));
  }
}

class _HttpError implements Exception {
  final int status;
  final String message;
  _HttpError(this.status, this.message);
}

class _EditorApp {
  final Directory root;
  final int port;
  _EditorApp(this.root, this.port);

  /// 마지막으로 푼 배치 — `/api/check` 가 이 상태에서 판정한다.
  LineBadgeSolution? _current;

  File _file(String rel) => File('${root.path}/$rel');

  Future<void> handle(HttpRequest req) async {
    final started = DateTime.now();
    var status = 200;
    try {
      _guard(req);
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/') {
        await _sendText(req, 'text/html; charset=utf-8', _editorHtml());
      } else if (req.method == 'GET' && path == '/api/model') {
        await _sendJson(req, _model());
      } else if (req.method == 'POST' && path == '/api/check') {
        await _sendJson(req, _check(await _readJson(req)));
      } else if (req.method == 'POST' && path == '/api/solve') {
        await _sendJson(req, _solveRequest(await _readJson(req)));
      } else if (req.method == 'POST' && path == '/api/save') {
        await _sendJson(req, await _save(await _readJson(req)));
      } else if (req.method == 'GET' && path == '/api/geometry/model') {
        await _sendJson(req, _geometryModel());
      } else if (req.method == 'POST' && path == '/api/geometry/check') {
        await _sendJson(req, _geometryCheck(await _readJson(req)));
      } else if (req.method == 'POST' && path == '/api/geometry/save') {
        await _sendJson(req, await _geometrySave(await _readJson(req)));
      } else {
        throw _HttpError(404, '없는 경로: ${req.method} $path');
      }
    } on _HttpError catch (e) {
      status = e.status;
      await _sendJson(req, {'ok': false, 'error': e.message}, status: e.status);
    } catch (e, st) {
      status = 500;
      stderr.writeln('요청 처리 실패 ${req.method} ${req.uri.path}: $e\n$st');
      try {
        await _sendJson(req, {'ok': false, 'error': '서버 오류: $e'}, status: 500);
      } catch (_) {}
    } finally {
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (req.uri.path != '/api/check' && req.uri.path != '/api/geometry/check') {
        stdout.writeln('[badge-editor] ${req.method} ${req.uri.path} -> $status (${ms}ms)');
      }
    }
  }

  // ---- 보안 가드 -------------------------------------------------------------------------------

  void _guard(HttpRequest req) {
    // DNS rebinding 방어: 브라우저가 보내는 Host 는 우리가 연 localhost 계열이어야 한다.
    final host = req.headers.value('host') ?? '';
    final hostName = host.startsWith('[') ? host.substring(0, host.indexOf(']') + 1) : host.split(':').first;
    if (!const {'localhost', '127.0.0.1', '[::1]'}.contains(hostName)) {
      throw _HttpError(403, '허용되지 않은 Host: $host');
    }
    if (req.method == 'POST') {
      // CSRF 방어: JSON 본문(= CORS preflight 필요) + 같은 출처에서 온 요청만.
      if (req.headers.contentType?.mimeType != 'application/json') {
        throw _HttpError(415, 'Content-Type 은 application/json 이어야 한다');
      }
      final origin = req.headers.value('origin');
      if (origin != null) {
        final u = Uri.tryParse(origin);
        if (u == null || !const {'localhost', '127.0.0.1', '[::1]'}.contains(u.host) || u.port != port) {
          throw _HttpError(403, '허용되지 않은 Origin: $origin');
        }
      }
    }
  }

  // ---- 응답 유틸 -------------------------------------------------------------------------------

  Future<void> _sendText(HttpRequest req, String type, String body, {int status = 200}) async {
    req.response
      ..statusCode = status
      ..headers.set('content-type', type)
      ..headers.set('cache-control', 'no-store')
      ..headers.set('x-content-type-options', 'nosniff')
      ..add(utf8.encode(body));
    await req.response.close();
  }

  Future<void> _sendJson(HttpRequest req, Object body, {int status = 200}) =>
      _sendText(req, 'application/json; charset=utf-8', jsonEncode(body), status: status);

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    if (req.contentLength > _kMaxBody) throw _HttpError(413, '본문이 너무 크다');
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > _kMaxBody) throw _HttpError(413, '본문이 너무 크다');
    }
    try {
      final v = jsonDecode(utf8.decode(bytes));
      if (v is Map<String, dynamic>) return v;
    } on FormatException {
      // fallthrough
    }
    throw _HttpError(400, '본문은 JSON 객체여야 한다');
  }

  // ---- 편집기 HTML ----------------------------------------------------------------------------

  /// 실제 지도 산출물 + 편집기 UI. 편집기 코드는 서빙할 때만 합성한다(디스크의 map.html 은 불변).
  String _editorHtml() {
    final html = _file(_kHtmlPath).readAsStringSync();
    final i = html.lastIndexOf('</body>');
    if (i < 0) throw _HttpError(500, '$_kHtmlPath 에 </body> 가 없다');
    final css = _file('tool/badge_editor/editor.css').readAsStringSync();
    final js = _file('tool/badge_editor/editor.js').readAsStringSync();
    final geoJs = _file('tool/badge_editor/geometry.js').readAsStringSync();
    if (js.contains('</script')) throw _HttpError(500, 'editor.js 에 </script 가 있으면 안 된다');
    if (geoJs.contains('</script')) throw _HttpError(500, 'geometry.js 에 </script 가 있으면 안 된다');
    // 순서가 중요하다: editor.js 가 패널·모드 탭·`window.BadgeEditorHost` 를 만들고, geometry.js 가 거기에 붙는다.
    return '${html.substring(0, i)}<style id="badge-editor-css">\n$css\n</style>\n'
        '<script id="badge-editor-js">\n$js\n</script>\n'
        '<script id="geometry-editor-js">\n$geoJs\n</script>\n${html.substring(i)}';
  }

  // ---- 배치 풀이 -------------------------------------------------------------------------------

  /// 빌드와 같은 입력 — 호출마다 디스크에서 다시 읽는다(세션 중 SVG/역 데이터를 고쳐도 반영).
  LineBadgeSolution _solve(BadgeOffsets offsets) {
    dynamic json(String rel) => jsonDecode(_file(rel).readAsStringSync());
    final stations = json('assets/json/stations.json') as List<dynamic>;
    final transfer = {
      for (final s in stations.cast<Map<String, dynamic>>())
        if (s['isTransfer'] == true) s['name'] as String,
    };
    return solveLineBadges(
      svgContent: _file('assets/svg/seoul_metro_map.svg').readAsStringSync(),
      stationsJson: stations,
      linesJson: json('assets/json/lines.json') as List<dynamic>,
      connectionsJson: json('assets/json/connections.json') as List<dynamic>,
      transferStationNames: transfer,
      offsets: offsets,
    );
  }

  Map<String, dynamic> _overridesJson(BadgeOffsets o) => {
        for (final e in o.byKey.entries) e.key: {'dx': e.value.dx, 'dy': e.value.dy},
      };

  /// 요청 본문의 `overrides`(키→{dx,dy})를 엄격히 읽는다 — 형식이 틀리면 400.
  BadgeOffsets _parseOverrides(Map<String, dynamic> body) {
    final raw = body['overrides'];
    if (raw is! Map) throw _HttpError(400, '"overrides" 객체가 없다');
    if (raw.length > 200) throw _HttpError(400, '오버라이드가 너무 많다');
    final out = <String, BadgeOffset>{};
    for (final e in raw.entries) {
      final v = e.value;
      final dx = v is Map ? v['dx'] : null, dy = v is Map ? v['dy'] : null;
      if (e.key is! String || dx is! num || dy is! num || !dx.isFinite || !dy.isFinite) {
        throw _HttpError(400, '"${e.key}" 값이 {"dx": 숫자, "dy": 숫자} 가 아니다');
      }
      if (dx.abs() > kBadgeOffsetMaxAbs || dy.abs() > kBadgeOffsetMaxAbs) {
        throw _HttpError(400, '"${e.key}" 오프셋이 ±${kBadgeOffsetMaxAbs.toInt()}px 를 넘는다');
      }
      out[e.key as String] = BadgeOffset(dx.toDouble(), dy.toDouble());
    }
    return BadgeOffsets(out);
  }

  /// 초기 모델: 파일의 현재 오버라이드로 푼 결과. 파일이 깨졌거나 그 조합이 빌드 실패면 빈 보정으로 대신
  /// 보여 주고 사유를 같이 돌려준다(편집기를 열 수 없는 함정을 막는다 — 그 상태에서는 저장이 막힌다).
  Map<String, dynamic> _model() {
    final f = _file(kBadgeOffsetsPath);
    String? fileError, solveError;
    var offsets = BadgeOffsets.empty;
    try {
      offsets = BadgeOffsets.parse(f.existsSync() ? f.readAsStringSync() : null);
    } on StateError catch (e) {
      fileError = e.message;
    }
    LineBadgeSolution sol;
    try {
      sol = _solve(offsets);
    } on StateError catch (e) {
      solveError = e.message;
      sol = _solve(BadgeOffsets.empty); // 이것도 실패하면 500 — 보정 이전에 빌드가 깨진 상태다.
    }
    _current = sol;
    return {
      'ok': fileError == null && solveError == null,
      'fileError': fileError,
      'solveError': solveError,
      'fileExists': f.existsSync(),
      'overrides': _overridesJson(offsets),
      'model': sol.toJson(),
    };
  }

  Map<String, dynamic> _solveRequest(Map<String, dynamic> body) {
    final offsets = _parseOverrides(body);
    try {
      final sol = _solve(offsets);
      _current = sol;
      return {'ok': true, 'model': sol.toJson()};
    } on StateError catch (e) {
      return {'ok': false, 'error': e.message};
    }
  }

  Map<String, dynamic> _check(Map<String, dynamic> body) {
    final cur = _current;
    if (cur == null) throw _HttpError(409, '아직 배치를 푼 적이 없다 — /api/model 먼저');
    final key = body['key'], dx = body['dx'], dy = body['dy'];
    if (key is! String || dx is! num || dy is! num || !dx.isFinite || !dy.isFinite) {
      throw _HttpError(400, 'key(문자열), dx/dy(숫자)가 필요하다');
    }
    try {
      final r = cur.check(key, dx.toDouble(), dy.toDouble());
      return {
        'ok': true,
        'anchorDist': r.anchorDist,
        'violations': [for (final v in r.violations) v.toJson()],
      };
    } on ArgumentError catch (e) {
      throw _HttpError(404, '${e.message}');
    }
  }

  // ---- 저장 + 재빌드 --------------------------------------------------------------------------

  /// 빌드는 `assets/html/map.html` 을 쓰므로 두 저장(배지·지오메트리)이 동시에 돌면 안 된다.
  bool _buildBusy = false;
  void _acquireBuild() {
    if (_buildBusy) throw _HttpError(409, '다른 저장·재빌드가 진행 중이다 — 끝난 뒤 다시 시도할 것');
    _buildBusy = true;
  }

  Future<Map<String, dynamic>> _save(Map<String, dynamic> body) async {
    _acquireBuild();
    try {
      return await _saveLocked(body);
    } finally {
      _buildBusy = false;
    }
  }

  Future<Map<String, dynamic>> _saveLocked(Map<String, dynamic> body) async {
    final offsets = _parseOverrides(body);
    final target = _file(kBadgeOffsetsPath);
    // 기존 파일이 깨져 있으면 덮어쓰지 않는다(사람이 한 보정을 날리지 않도록).
    try {
      BadgeOffsets.parse(target.existsSync() ? target.readAsStringSync() : null);
    } on StateError catch (e) {
      throw _HttpError(409, '기존 $kBadgeOffsetsPath 가 읽히지 않아 덮어쓰지 않는다 — 먼저 고칠 것: ${e.message}');
    }
    // 빌드가 성공하는 조합만 저장한다(자동 배지가 자리를 못 찾는 보정을 커밋 대상 파일에 남기지 않는다).
    final LineBadgeSolution sol;
    try {
      sol = _solve(offsets);
    } on StateError catch (e) {
      return {'ok': false, 'saved': false, 'error': '이 보정으로는 빌드가 실패해 저장하지 않았다:\n${e.message}'};
    }
    // 현재 배지에 없는 키(노선 삭제·종점 변경 등)는 저장 때 정리한다.
    final stale = [for (final k in offsets.byKey.keys) if (!sol.keys.contains(k)) k];
    final kept = BadgeOffsets({
      for (final e in offsets.byKey.entries)
        if (sol.keys.contains(e.key)) e.key: e.value,
    });
    // 고정 경로에 임시 파일로 쓴 뒤 교체한다(쓰다 죽어도 반쪽 파일이 남지 않는다).
    target.parent.createSync(recursive: true);
    final tmp = File('${target.path}.tmp');
    tmp.writeAsStringSync(kept.encode());
    tmp.renameSync(target.path);
    _current = sol;

    final r = await Process.run(Platform.resolvedExecutable, ['run', _kBuildScript],
        workingDirectory: root.path);
    // `Running build hooks...` 는 개행 없이 찍혀 실패 메시지와 **같은 줄**에 붙기도 한다 — 줄째 버리면 실패 사유가
    // 사라진다(배지 빌드 실패 로그는 badge_offsets.json 롤백 판단의 유일한 근거다). 문구만 지운다.
    final log = [
      for (final line in '${r.stdout}\n${r.stderr}'.replaceAll('Running build hooks...', '').split('\n'))
        if (line.trim().isNotEmpty) line,
    ].join('\n');
    return {
      'ok': r.exitCode == 0,
      'saved': true,
      'exitCode': r.exitCode,
      'log': log,
      'droppedStaleKeys': stale,
      'savedCount': kept.byKey.length,
      if (r.exitCode != 0) 'error': '보정 파일은 저장됐지만 빌드가 실패했다(exit ${r.exitCode}) — 로그 참조',
      'model': sol.toJson(),
    };
  }

  // ---- 지오메트리: 노선 선분 · 환승 마커 -----------------------------------------------------------

  List<dynamic> _stations() => jsonDecode(_file(_kStationsPath).readAsStringSync()) as List<dynamic>;

  GeometryDoc _geoDoc() {
    try {
      return GeometryDoc.parse(_file(_kSvgPath).readAsStringSync());
    } on StateError catch (e) {
      throw _HttpError(500, 'SVG 를 읽을 수 없다: ${e.message}');
    }
  }

  Map<String, dynamic> _geometryModel() {
    final svg = _file(_kSvgPath).readAsStringSync();
    final GeometryDoc doc;
    try {
      doc = GeometryDoc.parse(svg);
    } on StateError catch (e) {
      throw _HttpError(500, 'SVG 를 읽을 수 없다: ${e.message}');
    }
    // 코드 → 노선 이름(드롭다운용). 한 코드에 노선이 여럿이면(없지만) '/' 로 잇는다.
    final lineNames = {
      for (final l in (jsonDecode(_file(_kLinesPath).readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>())
        l['id'] as String: l['name'] as String,
    };
    final codeName = <String, String>{};
    for (final e in kLineIdToDataLine.entries) {
      final n = lineNames[e.key] ?? e.key;
      codeName[e.value] = codeName.containsKey(e.value) ? '${codeName[e.value]}/$n' : n;
    }
    String label(SvgPath p) {
      final c = p.code;
      if (c == null) return 'path #${p.index}';
      if (p.isWhite) return '${codeName[c.replaceAll(RegExp(r'-1$'), '')] ?? c} 이중선(흰색)';
      return '${codeName[c] ?? c} ($c)';
    }

    final stations = _stations();
    final tiers = findOffLineTiers(polylinesByCode(doc), stations);
    return {
      'ok': true,
      'svgRev': svgRevision(svg),
      'canvas': {'w': kCanvasW, 'h': kCanvasH},
      'maxTrackDistance': kMaxTrackDistance,
      'markerLengths': kMarkerLengths,
      'markerThickness': kMarkerThickness,
      'paths': [
        for (final p in doc.paths)
          {
            'index': p.index,
            'code': p.code,
            'label': label(p),
            'white': p.isWhite,
            'editable': doc.isEditablePath(p.index),
            'twins': doc.twinsOf(p.index),
            'points': [for (final q in p.points) [q.$1, q.$2]],
          },
      ],
      'rects': [
        for (final r in doc.rects) {'index': r.index, 'x': r.x, 'y': r.y, 'w': r.w, 'h': r.h},
      ],
      'offLine': [for (final o in tiers.hard) o.toJson(preexisting: true)],
      'offLineSoft': [for (final o in tiers.soft) o.toJson(preexisting: true)],
      'softTrackDistance': kSoftTrackDistance,
      // 영속 드리프트 신호 — 저장된 SVG 에서 앵커 역이 없는 마커(저장 뒤 새로고침해도 남는다).
      'orphanMarkers': [
        for (final i in orphanMarkers(doc.rects, stations))
          {
            'index': i,
            'cx': doc.rects[i].x + doc.rects[i].w / 2,
            'cy': doc.rects[i].y + doc.rects[i].h / 2,
            'nearest': nearestStation(doc.rects[i].x + doc.rects[i].w / 2, doc.rects[i].y + doc.rects[i].h / 2, stations),
          },
      ],
      // 지난 저장이 중단된 흔적 — stderr 만으로는 preview_start 로 띄운 사용자가 못 본다.
      'interrupted': interruptedNotice() != null,
      'interruptedNotice': interruptedNotice(),
    };
  }

  static const _kMaxEditedPaths = 64;
  static const _kMaxVerticesPerPath = 2000;

  /// 요청의 `paths`(index 문자열 → [[x,y],...])를 엄격히 읽는다 — 형식이 틀리면 400.
  Map<int, List<Pt>> _parsePathEdits(Object? raw, GeometryDoc doc) {
    if (raw == null) return const {};
    if (raw is! Map) throw _HttpError(400, '"paths" 는 객체여야 한다');
    if (raw.length > _kMaxEditedPaths) throw _HttpError(400, '편집한 path 가 너무 많다');
    final out = <int, List<Pt>>{};
    for (final e in raw.entries) {
      final i = int.tryParse('${e.key}');
      if (i == null || !doc.isEditablePath(i)) {
        throw _HttpError(400, 'path "${e.key}" 는 편집할 수 없다(없는 index 이거나 흰색 이중선/무코드 path)');
      }
      final v = e.value;
      if (v is! List || v.length > _kMaxVerticesPerPath) throw _HttpError(400, 'path ${e.key} 정점 목록이 올바르지 않다');
      final pts = <Pt>[];
      for (final q in v) {
        if (q is! List || q.length != 2 || q[0] is! num || q[1] is! num || !(q[0] as num).isFinite || !(q[1] as num).isFinite) {
          throw _HttpError(400, 'path ${e.key} 정점은 [x, y] 숫자 쌍이어야 한다');
        }
        pts.add(((q[0] as num).toDouble(), (q[1] as num).toDouble()));
      }
      if (pts.length != doc.paths[i].points.length) {
        throw _HttpError(400, 'path $i 정점 수가 다르다(${doc.paths[i].points.length} → ${pts.length}) — 정점 추가·삭제는 지원하지 않는다');
      }
      out[i] = pts;
    }
    return out;
  }

  Map<int, RectEdit> _parseRectEdits(Object? raw, GeometryDoc doc) {
    if (raw == null) return const {};
    if (raw is! Map) throw _HttpError(400, '"rects" 는 객체여야 한다');
    if (raw.length > doc.rects.length) throw _HttpError(400, '편집한 rect 가 너무 많다');
    final out = <int, RectEdit>{};
    for (final e in raw.entries) {
      final i = int.tryParse('${e.key}');
      final v = e.value;
      if (i == null || i < 0 || i >= doc.rects.length) throw _HttpError(400, '없는 rect index: "${e.key}"');
      if (v is! Map || v['x'] is! num || v['y'] is! num || v['w'] is! num || v['h'] is! num) {
        throw _HttpError(400, 'rect ${e.key} 는 {x,y,w,h} 숫자여야 한다');
      }
      out[i] = RectEdit((v['x'] as num).toDouble(), (v['y'] as num).toDouble(), (v['w'] as num).toDouble(), (v['h'] as num).toDouble());
    }
    return out;
  }

  /// 편집 중인 정점으로 본 12px 이탈 역(`pre` = 디스크의 현재 SVG 에서도 이미 이탈이던 역, 편집과 무관한 기존 문제)과,
  /// 편집 중인 환승 마커 중심이 `stations.json` 좌표에서 벌어진 정도(`markerDrift`).
  Map<String, dynamic> _geometryCheck(Map<String, dynamic> body) {
    final doc = _geoDoc();
    final edits = _parsePathEdits(body['paths'], doc);
    final rectEdits = _parseRectEdits(body['rects'], doc);
    final stations = _stations();
    final base = findOffLineTiers(polylinesByCode(doc), stations);
    final baseHard = {for (final o in base.hard) o.key};
    final baseSoft = {for (final o in base.soft) o.key};
    final cur = findOffLineTiers(polylinesByCode(doc, edits), stations);
    return {
      'ok': true,
      'offLine': [for (final o in cur.hard) o.toJson(preexisting: baseHard.contains(o.key))],
      // 소프트("눈에 보이게 벌어짐")는 하드와 달리 편집 전에도 20건 안팎 있다 — 그 `pre` 분은 회색으로만 보인다. 하드로 승격한 건
      // 편집 전에 하드이면 pre, 아니면 신규다(소프트였다가 하드가 되면 baseHard 에 없으니 신규).
      'offLineSoft': [for (final o in cur.soft) o.toJson(preexisting: baseSoft.contains(o.key) || baseHard.contains(o.key))],
      'markerDrift': [for (final d in findMarkerDrift(doc.rects, rectEdits, stations)) d.toJson()],
    };
  }

  Future<Map<String, dynamic>> _geometrySave(Map<String, dynamic> body) async {
    _acquireBuild();
    try {
      return await _geometrySaveLocked(body);
    } finally {
      _buildBusy = false;
    }
  }

  /// 고정 경로(`assets/svg/seoul_metro_map.svg`)에 tmp → rename 으로 쓴다. tmp 는 assets/ 밖(.dart_tool)에 둔다.
  void _atomicWrite(File target, List<int> bytes) {
    final dir = Directory('${root.path}/$_kGeoWorkDir')..createSync(recursive: true);
    final tmp = File('${dir.path}/${target.uri.pathSegments.last}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    try {
      tmp.renameSync(target.path);
    } on FileSystemException {
      // 드물게 다른 볼륨이면 rename 이 안 된다 — 직접 쓰고 tmp 는 지운다.
      target.writeAsBytesSync(bytes, flush: true);
      try {
        tmp.deleteSync();
      } catch (_) {}
    }
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 디스크 파일이 [bytes] 와 다르면 되돌려 쓴다. 되돌린 뒤 바이트까지 확인해 성공 여부를 돌려준다.
  bool _restore(File f, List<int> bytes) {
    try {
      if (!f.existsSync() || !_sameBytes(f.readAsBytesSync(), bytes)) _atomicWrite(f, bytes);
      return _sameBytes(f.readAsBytesSync(), bytes);
    } catch (e) {
      stderr.writeln('원복 실패 ${f.path}: $e');
      return false;
    }
  }

  Future<({int exitCode, String log})> _runBuild() async {
    final p = await Process.start(Platform.resolvedExecutable, ['run', _kBuildScript], workingDirectory: root.path);
    final out = StringBuffer();
    final drain = Future.wait([
      p.stdout.transform(utf8.decoder).forEach(out.write),
      p.stderr.transform(utf8.decoder).forEach(out.write),
    ]);
    int code;
    try {
      code = await p.exitCode.timeout(_kBuildTimeout);
    } on TimeoutException {
      p.kill(ProcessSignal.sigkill);
      code = -1;
      out.writeln('\n빌드가 ${_kBuildTimeout.inSeconds}초 안에 끝나지 않아 중단했다.');
    }
    try {
      await drain.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // 자식 프로세스가 파이프를 쥐고 있어도 로그 수집 때문에 영원히 기다리지 않는다.
    }
    // `Running build hooks...` 는 개행 없이 찍혀 실패 메시지와 **같은 줄**에 붙기도 한다 — 줄째 버리면 실패 사유가 사라진다.
    final log = [
      for (final line in out.toString().replaceAll('Running build hooks...', '').split('\n'))
        if (line.trim().isNotEmpty) line,
    ].join('\n');
    return (exitCode: code, log: log);
  }

  /// 복구 안내(원복 실패·중단 흔적 공통). **1순위는 `.bak`** 이다 — 같은 저장 직전 사본이라 세션 중 먼저 성공한
  /// 미커밋 저장을 건드리지 않는다. `git checkout` 은 마지막 커밋 이후 다른 저장이 전혀 없을 때만 안전하다(있으면 그것까지 날린다).
  String get _recoveryHint =>
      '복구: cp $_kGeoWorkDir/seoul_metro_map.svg.bak $_kSvgPath && dart run $_kBuildScript   '
      '(.bak 은 마지막 저장 직전 사본). 마지막 커밋 이후 저장한 변경이 없을 때만 git checkout -- $_kSvgPath $_kHtmlPath 도 된다. '
      '복구를 확인한 뒤 $_kGeoWorkDir/save_in_progress 를 지울 것.';

  /// 이전 저장이 도중에 죽었는지(표식 파일이 남았는지). 있으면 사용자에게 보일 안내문, 없으면 null.
  /// 자동 복구는 하지 않는다 — 그 사이 사람이 SVG 를 고쳤을 수 있어 덮어쓰면 오히려 작업을 날린다.
  String? interruptedNotice() {
    final marker = File('${root.path}/$_kGeoWorkDir/save_in_progress');
    if (!marker.existsSync()) return null;
    return '지난 지오메트리 저장이 끝나기 전에 중단된 흔적이 있다. SVG 가 저장 도중 상태일 수 있다. 표식을 지울 때까지 새 저장은 거부된다. $_recoveryHint';
  }

  /// 서버 시작 때 stderr 로 알린다(UI 는 `/api/geometry/model` 의 `interrupted` 로 배너를 띄운다).
  void warnIfInterruptedSave() {
    final n = interruptedNotice();
    if (n != null) stderr.writeln('⚠️ $n');
  }

  Future<Map<String, dynamic>> _geometrySaveLocked(Map<String, dynamic> body) async {
    // 지난 저장이 중단된 흔적(표식)이 있으면 새 저장을 받지 않는다 — 저장은 `.bak` 을 덮어써 복구 소스를 잃게 하고, 표식도
    // 지워 중단을 아무도 확인하지 않은 채 닫는다. 사람이 복구를 확인하고 표식을 지울 때까지 거부한다.
    final pending = interruptedNotice();
    if (pending != null) {
      throw _HttpError(409, '지난 저장이 중단된 흔적이 있어 새 저장을 받지 않았다 — 먼저 복구를 확인하고 표식을 지운 뒤 다시 저장할 것. $pending');
    }
    final svgFile = _file(_kSvgPath), htmlFile = _file(_kHtmlPath);
    final origSvgBytes = svgFile.readAsBytesSync();
    final origSvg = utf8.decode(origSvgBytes);
    // 편집은 index 로 식별한다 — 편집기를 연 뒤 SVG 가 바뀌었으면 엉뚱한 선을 건드린다. 거부.
    final rev = body['svgRev'];
    if (rev is! String) throw _HttpError(400, '"svgRev" 가 필요하다(/api/geometry/model 의 값)');
    if (rev != svgRevision(origSvg)) {
      throw _HttpError(409, '편집기를 연 뒤 $_kSvgPath 가 바뀌었다(git 전환·다른 편집 등) — 페이지를 새로고침해 다시 편집할 것. 저장하지 않았다.');
    }
    final GeometryDoc doc;
    try {
      doc = GeometryDoc.parse(origSvg);
    } on StateError catch (e) {
      throw _HttpError(500, 'SVG 를 읽을 수 없다: ${e.message}');
    }
    final pathEdits = _parsePathEdits(body['paths'], doc);
    final rectEdits = _parseRectEdits(body['rects'], doc);
    final String newSvg;
    try {
      newSvg = applyGeometryEdits(doc, pathEdits: pathEdits, rectEdits: rectEdits);
    } on ArgumentError catch (e) {
      throw _HttpError(400, '${e.message}');
    }
    final stations = _stations();
    final baseTiers = findOffLineTiers(polylinesByCode(doc), stations);
    final baseHardKeys = {for (final o in baseTiers.hard) o.key};
    final baseSoftKeys = {for (final o in baseTiers.soft) o.key};
    if (newSvg == origSvg) {
      return {'ok': true, 'saved': false, 'unchanged': true, 'message': '바뀐 내용이 없어 저장하지 않았다.', 'svgRev': rev};
    }

    // 수동 보정 배지의 하드 위반 경고 **기준선**(이번 저장 전) — 보정 배지는 의도적으로 앵커에서 24px 넘게 둔 것이 많아
    // 저장 전에도 경고가 10건 안팎 상시 있다. 그것까지 배너로 올리면 소음이라 "이번 저장으로 새로 생기거나 값이 바뀐 것"만 올린다.
    // 기준선을 못 구하면(보정 파일 훼손 등) null — 그땐 전부 새 것으로 취급한다.
    final baseline = _manualBadgeStateNow();

    // ① 백업 — 메모리(원복의 기준) + assets/ 밖 디스크 사본(서버가 죽었을 때의 보험).
    final origHtmlBytes = htmlFile.readAsBytesSync();
    final work = Directory('${root.path}/$_kGeoWorkDir')..createSync(recursive: true);
    File('${work.path}/seoul_metro_map.svg.bak').writeAsBytesSync(origSvgBytes, flush: true);
    File('${work.path}/map.html.bak').writeAsBytesSync(origHtmlBytes, flush: true);
    final marker = File('${work.path}/save_in_progress')..writeAsStringSync('${DateTime.now().toIso8601String()}\n', flush: true);

    var exitCode = -2;
    var log = '';
    var built = false;
    var reverted = false;
    try {
      // ② SVG 갱신(원자적) → ③ 빌드.
      _atomicWrite(svgFile, utf8.encode(newSvg));
      final r = await _runBuild();
      exitCode = r.exitCode;
      log = r.log;
      built = exitCode == 0;
    } catch (e, st) {
      stderr.writeln('지오메트리 저장 중 예외: $e\n$st');
      log = '저장 중 예외: $e';
    } finally {
      if (!built) {
        // ④ 실패 — SVG 와 map.html 을 저장 직전 바이트로 되돌린다(깨진 지도를 남기지 않는다).
        final svgOk = _restore(svgFile, origSvgBytes);
        final htmlOk = _restore(htmlFile, origHtmlBytes);
        if (svgOk && htmlOk) {
          if (marker.existsSync()) marker.deleteSync();
          reverted = true;
        } else {
          stderr.writeln('⚠️ 원복에 실패했다 — $_recoveryHint');
        }
      }
    }
    if (!built) {
      return {
        'ok': false,
        'saved': false,
        'reverted': reverted,
        'exitCode': exitCode,
        'log': log,
        'error': reverted
            ? '빌드가 실패해($exitCode) SVG 를 저장 직전 상태로 되돌렸다 — 지도는 그대로다. 로그 참조.'
            : '⚠️ 빌드가 실패했고 원복도 실패했다. $_recoveryHint',
        'svgRev': svgRevision(origSvg),
      };
    }
    if (marker.existsSync()) marker.deleteSync();
    _current = null; // 앵커(노선 선 끝점)가 움직였을 수 있다 — 배지 모델은 다시 풀어야 한다.
    final off = findOffLineTiers(polylinesByCode(GeometryDoc.parse(newSvg)), stations);
    // 선을 옮기면 배지 앵커(노선 선 끝점)가 움직여 손으로 보정한 배지 오프셋이 통째로 따라간다. 수동 배지의 하드 위반은
    // 빌드를 실패시키지 않고 로그 경고만 남기므로, 로그에 묻히지 않게 따로 뽑아 UI 가 배너로 올리게 한다.
    final allBadgeWarnings = [for (final l in log.split('\n')) if (l.contains('경고: 수동 보정 배지')) l.trim()];
    final badgeWarnings = [
      for (final w in allBadgeWarnings)
        if (baseline == null || !baseline.warnings.contains(w)) w,
    ];
    // 위반이 없어도 선 끝점(앵커)이 움직이면 손으로 고른 수동 배지의 **절대 위치**가 같이 움직인다 — 그 이동량을 따로 보고한다
    // (하드 위반 경고만으로는 "그냥 틀어진" 배지가 조용하다). 앵커는 노선 선 끝점이라 path 를 안 건드린 저장(마커만)에선 건너뛴다.
    final movedBadges = pathEdits.isEmpty ? const <Map<String, dynamic>>[] : _movedManualBadges(baseline);
    return {
      'ok': true,
      'saved': true,
      'exitCode': exitCode,
      'log': log,
      'svgRev': svgRevision(newSvg),
      'changed': {'paths': pathEdits.length, 'rects': rectEdits.length},
      'offLine': [for (final o in off.hard) o.toJson(preexisting: baseHardKeys.contains(o.key))],
      'offLineSoft': [for (final o in off.soft) o.toJson(preexisting: baseSoftKeys.contains(o.key) || baseHardKeys.contains(o.key))],
      'markerDrift': [for (final d in findMarkerDrift(doc.rects, rectEdits, stations)) d.toJson()],
      'badgeWarnings': badgeWarnings,
      'badgeWarningsTotal': allBadgeWarnings.length,
      'movedManualBadges': movedBadges,
      'manualBadgeTotal': baseline?.anchors.length ?? 0,
    };
  }

  /// 현재 디스크(SVG·보정 파일)로 푼 수동 배지 상태 — 경고 문자열 집합과 배지 키별 앵커 좌표. 풀 수 없으면 null.
  ({Set<String> warnings, Map<String, (double, double)> anchors})? _manualBadgeStateNow() {
    try {
      final f = _file(kBadgeOffsetsPath);
      final offsets = BadgeOffsets.parse(f.existsSync() ? f.readAsStringSync() : null);
      final r = _solve(offsets).result;
      return (
        warnings: {for (final w in r.manualWarnings) w.trim()},
        anchors: {for (final b in r.placements) if (b.manual) b.key: (b.anchorX, b.anchorY)},
      );
    } catch (e) {
      stderr.writeln('수동 배지 기준선을 구하지 못했다(경고는 전부 새 것으로, 이동량은 생략하고 보고한다): $e');
      return null;
    }
  }

  /// 저장 뒤 다시 푼 수동 배지 앵커를 [before] 와 비교해 **움직인 배지**(키·이동 px)를 큰 순으로 돌려준다. 기준선이 없거나
  /// 다시 풀 수 없으면 빈 목록.
  List<Map<String, dynamic>> _movedManualBadges(({Set<String> warnings, Map<String, (double, double)> anchors})? before) {
    if (before == null) return const [];
    final after = _manualBadgeStateNow();
    if (after == null) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in before.anchors.entries) {
      final a = after.anchors[e.key];
      if (a == null) continue;
      final dx = a.$1 - e.value.$1, dy = a.$2 - e.value.$2;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > 0.05) out.add({'key': e.key, 'dist': double.parse(d.toStringAsFixed(1)), 'dx': double.parse(dx.toStringAsFixed(1)), 'dy': double.parse(dy.toStringAsFixed(1))});
    }
    out.sort((a, b) => (b['dist'] as double).compareTo(a['dist'] as double));
    return out;
  }
}
