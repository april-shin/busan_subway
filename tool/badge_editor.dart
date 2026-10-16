/// 노선 배지(P2-4) **수동 위치 보정 편집기** — 로컬 전용 개발 도구.
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
///
/// 안전:
/// - **127.0.0.1 에만 바인딩**한다(외부 노출 없음). Host 헤더가 localhost 계열이 아니면 거부(DNS rebinding
///   방어), POST 는 `application/json` + 같은 Origin 만 받는다(타 사이트의 CSRF 방어).
/// - **쓰기 경로는 `data/badge_offsets.json` 하나뿐**이다. 임의 경로를 받는 API 가 없다(서버가 고정 경로에
///   고정 포맷으로 직렬화하고, 요청 본문은 키→{dx,dy} 숫자만 읽는다).
/// - 보정할 때만 띄우는 도구다 — 앱 번들(`assets/`)이나 `lib/` 어디에서도 참조하지 않는다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'line_badges.dart';

const _kDefaultPort = 8765;
const _kMaxBody = 1 << 20;
const _kHtmlPath = 'assets/html/map.html';
const _kBuildScript = 'tool/build_map_html.dart';

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
  for (final p in ['pubspec.yaml', _kHtmlPath, 'tool/badge_editor/editor.js']) {
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
  stdout.writeln('쓰기 대상은 $kBadgeOffsetsPath 하나뿐이다.');
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
      if (req.uri.path != '/api/check') {
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
    if (js.contains('</script')) throw _HttpError(500, 'editor.js 에 </script 가 있으면 안 된다');
    return '${html.substring(0, i)}<style id="badge-editor-css">\n$css\n</style>\n'
        '<script id="badge-editor-js">\n$js\n</script>\n${html.substring(i)}';
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

  Future<Map<String, dynamic>> _save(Map<String, dynamic> body) async {
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
    final log = [
      for (final line in '${r.stdout}\n${r.stderr}'.split('\n'))
        if (line.trim().isNotEmpty && !line.startsWith('Running build hooks')) line,
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
}
