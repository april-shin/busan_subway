/// SVG 지오메트리(노선 선분 폴리라인 · 환승 마커 rect) 편집의 **순수 로직** — 개발 도구 전용.
///
/// `tool/badge_editor.dart` 의 선분/환승마커 모드가 쓴다(서버는 IO 만, 규칙은 전부 여기).
/// 앱 번들·`lib/` 어디에서도 참조하지 않는다. 입출력이 없는 순수 함수라 `test/tool/` 에서 그대로 검증한다.
///
/// ## 식별 방식
/// 원본 SVG 의 `<path>`(36개)·`<rect>`(56개)에는 id 가 없다. 그래서 **문서 안 등장 순서 index** 로 식별한다
/// (좌표는 편집하면 바뀌므로 키로 못 쓴다). `map.html` 은 SVG 에서 `<text>` 만 떼어 낸 채 같은 순서로 인라인하므로
/// 지도 DOM 의 `path`/`rect` 순서가 이 index 와 같다.
///
/// ## 바이트 보존 편집
/// SVG 는 한 줄짜리 파일이다. 파서로 다시 직렬화하지 않고 **바뀐 태그의 속성값만 문자열 치환**한다 —
/// 편집하지 않은 부분은 바이트 동일(diff 가 의도한 변경만 보인다).
///
/// ## 흰색 이중선
/// `{code}-1`(흰 stroke) path 는 본체와 `d` 가 **완전히 같다**(GTX-A `1-GA-1`, 경춘 `G-1`). 본체를 옮기면 같은 `d`
/// 를 가진 이중선도 같이 옮겨야 한다(안 하면 흰 줄이 선 밖으로 떨어진다). 이중선을 직접 편집하는 요청은 거부한다.
///
/// ## 선로 이탈 가드 (2단계)
/// 역(stations.json svgX/svgY)에서 자기 노선 `data-line` path(흰 이중선은 코드가 달라 자연 제외)의 선분까지
/// 최단거리. **12px 초과 = 하드**(경로 하이라이트가 선로를 벗어난다 — `test/tool/geometry_svg_test.dart` 가 main 에서
/// 실제로 서는 가드다. 브랜치 `fix/line8-jangja-svg-coord` 에만 있는 `station_svg_coords_test` 는 main 에 없다),
/// **4px 초과 = 소프트**(선 두께 4px·dot 반지름 4.5~5px 기준으로 dot 이 선에서 분리돼 "눈에 보이게 벌어진" 상태).
/// 소프트는 하드의 12px 판정을 바꾸지 않는 별도 층이다. 둘 다 저장을 막지 않는다. 공유 환승 마커 3건은 면제.
///
/// ## 마커 드리프트
/// `extract_svg_stations` 가 환승 마커 중심을 역 좌표의 원천으로 쓰는데 편집기는 1·2단계를 돌리지 않는다 — 마커를 끌면
/// `stations.json` 좌표가 옛 자리에 남는다. 두 겹으로 잡는다:
/// - [findMarkerDrift] — 편집 중·저장 직후의 어긋남(이동량). 앵커된 역과의 거리가 늘었는지 본다.
/// - [orphanMarkers] — **영속 신호**. 저장된 SVG 에서 앵커 역이 하나도 없는 마커. 현재 데이터는 56/56 마커가 앵커를
///   가지므로 "앵커 없음 = 옮겨 저장했는데 stations.json 이 안 따라온 마커" 이고 오탐이 0 이다. 앵커 반경 밖으로 크게
///   옮길수록 [findMarkerDrift] 는 침묵하지만 이쪽은 확실히 잡힌다.
library;

import 'dart:math' as math;

import 'line_badges.dart' show kLineIdToDataLine;
import 'map_constants.dart';

/// 역 좌표와 자기 노선 선로 사이 허용 거리(px) — 이 값을 넘으면 **하드** 이탈(브랜치 테스트의 `_maxTrackDistance`).
const double kMaxTrackDistance = 12.0;

/// 이 값을 넘고 [kMaxTrackDistance] 이하이면 **소프트** — "눈에 보이게 벌어짐". 선 두께 4px · 역 dot 반지름 4.5~5px 이라
/// 4px 를 넘으면 dot 이 선에서 완전히 분리돼 보인다. 실측 시나리오: 망우 부근 경춘(G)↔경의중앙(K) 수직 간격 8px,
/// `망우|경춘` 은 선에서 4px — G 를 8px 올려 두 선을 떼면 정확히 12.0px 가 되어 하드(`> 12`)는 침묵한다.
const double kSoftTrackDistance = 4.0;

/// 여러 노선이 하나의 환승 캡슐을 공유해 개별 노선 선로에서 멀어도 정상인 (역명|lineId) — 테스트의
/// `_sharedTransferMarkers`.
const Set<String> kSharedTransferMarkers = {
  '서울역|경의중앙',
  '김포공항|김포골드',
  '김포공항|9',
};

/// 환승 마커의 규격 길이(장축). 단축은 항상 8(동그라미 = 8×8).
const List<double> kMarkerLengths = [16, 20, 24, 28];
const double kMarkerThickness = 8;

/// 좌표/크기 허용 오차(같은 값 판정).
const double _eps = 1e-6;

typedef Pt = (double, double);

// ======================================================================
// 파싱
// ======================================================================

/// SVG 안의 `<path>` 하나.
class SvgPath {
  final int index;
  final int start, end; // 태그의 문서 내 오프셋 [start, end)
  final String tag;
  final String d;
  final String? code; // data-line
  final String? stroke;
  final List<Pt> points;

  SvgPath(this.index, this.start, this.end, this.tag, this.d, this.code, this.stroke, this.points);

  /// 흰색 이중선(본체 위에 같은 좌표로 겹쳐 그린 안쪽 흰 선)인가.
  bool get isWhite => (stroke ?? '').toLowerCase() == '#ffffff';
}

/// SVG 안의 `<rect>` 하나(환승 마커).
class SvgRect {
  final int index;
  final int start, end;
  final String tag;
  final double x, y, w, h;

  SvgRect(this.index, this.start, this.end, this.tag, this.x, this.y, this.w, this.h);
}

/// 환승 마커 편집 요청 1건(좌상단 x,y + 크기).
class RectEdit {
  final double x, y, w, h;
  const RectEdit(this.x, this.y, this.w, this.h);
}

class GeometryDoc {
  final String svg;
  final List<SvgPath> paths;
  final List<SvgRect> rects;

  GeometryDoc._(this.svg, this.paths, this.rects);

  static final RegExp _pathTag = RegExp(r'<path\b[^>]*>');
  static final RegExp _rectTag = RegExp(r'<rect\b[^>]*>');
  // d 속성: ` d="..."` — `data-line` 같은 접두 d 속성을 오인하지 않도록 앞 공백 + `="` 로 고정한다.
  static final RegExp _dAttr = RegExp(r'\sd="([^"]*)"');
  static final RegExp _vertex = RegExp(r'([ML])\s*(-?\d+(?:\.\d+)?)[ ,]+(-?\d+(?:\.\d+)?)');

  /// 파싱 실패(M/L 외 명령, 좌표 깨짐 등)는 [StateError].
  static GeometryDoc parse(String svg) {
    final paths = <SvgPath>[];
    for (final m in _pathTag.allMatches(svg)) {
      final tag = m.group(0)!;
      final d = _dAttr.firstMatch(tag)?.group(1);
      if (d == null) throw StateError('path #${paths.length} 에 d 속성이 없다');
      final pts = parsePolyline(d, 'path #${paths.length}');
      paths.add(SvgPath(paths.length, m.start, m.end, tag, d, attr(tag, 'data-line'), attr(tag, 'stroke'), pts));
    }
    final rects = <SvgRect>[];
    for (final m in _rectTag.allMatches(svg)) {
      final tag = m.group(0)!;
      double? n(String a) => double.tryParse(attr(tag, a) ?? '');
      final x = n('x'), y = n('y'), w = n('width'), h = n('height');
      if (x == null || y == null || w == null || h == null) {
        throw StateError('rect #${rects.length} 의 x/y/width/height 가 숫자가 아니다');
      }
      rects.add(SvgRect(rects.length, m.start, m.end, tag, x, y, w, h));
    }
    return GeometryDoc._(svg, paths, rects);
  }

  /// `M x y L x y ...` 만 허용한다 — 다른 명령(C/Q/A/Z 등)이 있으면 `build_map_html` 도 하드페일하므로 여기서 먼저 막는다.
  static List<Pt> parsePolyline(String d, String what) {
    final pts = <Pt>[];
    var cursor = 0;
    for (final m in _vertex.allMatches(d)) {
      if (d.substring(cursor, m.start).trim().isNotEmpty) {
        throw StateError('$what 의 d 에 M/L 외 내용이 있다: "${d.substring(cursor, m.start).trim()}"');
      }
      cursor = m.end;
      pts.add((double.parse(m.group(2)!), double.parse(m.group(3)!)));
    }
    if (d.substring(cursor).trim().isNotEmpty) {
      throw StateError('$what 의 d 에 M/L 외 내용이 있다: "${d.substring(cursor).trim()}"');
    }
    if (pts.length < 2) throw StateError('$what 의 정점이 2개 미만이다');
    return pts;
  }

  /// 본체 path [i] 와 `d` 가 같은 흰색 이중선들의 index(`{code}-1`).
  List<int> twinsOf(int i) {
    final p = paths[i];
    if (p.isWhite || p.code == null) return const [];
    return [
      for (final q in paths)
        if (q.isWhite && q.code == '${p.code}-1' && _sameD(q.d, p.d)) q.index,
    ];
  }

  static bool _sameD(String a, String b) => a.replaceAll(RegExp(r'\s+'), ' ').trim() == b.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 편집 대상 본체 path 인가(흰 이중선·data-line 없는 path 는 직접 편집 불가).
  bool isEditablePath(int i) => i >= 0 && i < paths.length && !paths[i].isWhite && paths[i].code != null;
}

/// 태그에서 속성 문자열 값. 앞 공백을 요구해 `data-line` 이 `line` 으로 잡히는 일을 막는다.
String? attr(String tag, String name) =>
    RegExp('\\s${RegExp.escape(name)}="([^"]*)"').firstMatch(tag)?.group(1);

// ======================================================================
// 변경 판정용 개정 번호
// ======================================================================

/// SVG 내용의 개정 식별자(길이 + FNV-1a 32). 편집기가 SVG 를 읽은 뒤 디스크의 SVG 가 바뀌었는지 저장 때 확인한다.
/// 편집은 index 로 식별하므로 낡은 탭이 바뀐 SVG 에 저장하면 엉뚱한 선을 건드린다 — 그걸 막는 용도다.
String svgRevision(String svg) {
  var h = 0x811c9dc5;
  for (final c in svg.codeUnits) {
    h ^= c & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
    h ^= (c >> 8) & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return '${svg.length}-${h.toRadixString(16)}';
}

// ======================================================================
// 편집 적용
// ======================================================================

/// 숫자 직렬화 — 원본 SVG 와 같은 꼴(정수값은 `N.0`)로 쓴다. 부동소수 잡음은 소수 3자리에서 끊는다.
String fmtNum(double v) {
  final r = (v * 1000).round() / 1000;
  if (r == r.roundToDouble()) return '${r.toInt()}.0';
  return r.toString();
}

bool _same(double a, double b) => (a - b).abs() < _eps;

/// [edits] 를 적용한 새 SVG. 잘못된 요청은 [ArgumentError](서버가 400 으로 바꾼다).
///
/// - [pathEdits]: path index → 새 정점 목록. **정점 수는 원본과 같아야 한다**(추가·삭제는 범위 밖). 본체만 허용하며
///   같은 `d` 의 흰색 이중선이 자동으로 같이 바뀐다.
/// - [rectEdits]: rect index → 새 x,y,width,height. 크기는 규격(8×8 / 8×{16,20,24,28} / 그 가로형)이어야 한다
///   (편집하지 않은 값 그대로인 기존 비규격 마커는 통과).
///
/// 편집이 현재 값과 같으면 그 태그는 건드리지 않는다(바이트 동일).
String applyGeometryEdits(
  GeometryDoc doc, {
  Map<int, List<Pt>> pathEdits = const {},
  Map<int, RectEdit> rectEdits = const {},
}) {
  final repl = <({int start, int end, String text})>[];

  for (final e in pathEdits.entries) {
    final i = e.key;
    if (i < 0 || i >= doc.paths.length) throw ArgumentError('없는 path index: $i');
    final p = doc.paths[i];
    if (p.isWhite) {
      throw ArgumentError('path #$i 는 흰색 이중선이다 — 본체를 옮기면 같이 움직인다(직접 편집 불가)');
    }
    if (p.code == null) throw ArgumentError('path #$i 에 data-line 이 없어 편집할 수 없다');
    final pts = e.value;
    if (pts.length != p.points.length) {
      throw ArgumentError('path #$i 정점 수가 다르다(${p.points.length} → ${pts.length}) — 정점 추가·삭제는 지원하지 않는다');
    }
    for (final q in pts) {
      if (!q.$1.isFinite || !q.$2.isFinite || q.$1 < 0 || q.$2 < 0 || q.$1 > kCanvasW || q.$2 > kCanvasH) {
        throw ArgumentError('path #$i 좌표(${q.$1}, ${q.$2}) 가 캔버스(0..${kCanvasW.toInt()}×0..${kCanvasH.toInt()}) 밖이다');
      }
    }
    var changed = false;
    for (var k = 0; k < pts.length; k++) {
      if (!_same(pts[k].$1, p.points[k].$1) || !_same(pts[k].$2, p.points[k].$2)) changed = true;
    }
    if (!changed) continue;
    final newD = _rebuildD(p.d, pts);
    for (final target in [i, ...doc.twinsOf(i)]) {
      final t = doc.paths[target];
      // 이중선이 다른 본체의 twin 이기도 한 경우(같은 d 본체가 둘)는 모호하다 — 두 본체가 같은 d 라 실제로는 없지만 방어한다.
      repl.add((start: t.start, end: t.end, text: _setAttr(t.tag, 'd', newD)));
    }
  }

  for (final e in rectEdits.entries) {
    final i = e.key;
    if (i < 0 || i >= doc.rects.length) throw ArgumentError('없는 rect index: $i');
    final r = doc.rects[i];
    final v = e.value;
    for (final n in [v.x, v.y, v.w, v.h]) {
      if (!n.isFinite) throw ArgumentError('rect #$i 값이 숫자가 아니다');
    }
    if (v.x < 0 || v.y < 0 || v.x + v.w > kCanvasW || v.y + v.h > kCanvasH) {
      throw ArgumentError('rect #$i 가 캔버스 밖으로 나간다');
    }
    final sameSize = _same(v.w, r.w) && _same(v.h, r.h);
    if (!sameSize && !isStandardMarkerSize(v.w, v.h)) {
      throw ArgumentError('rect #$i 크기 ${v.w}×${v.h} 는 규격이 아니다 — 8×8 또는 8×{16,20,24,28}(가로/세로)만 허용');
    }
    if (_same(v.x, r.x) && _same(v.y, r.y) && sameSize) continue;
    var tag = r.tag;
    if (!_same(v.x, r.x)) tag = _setAttr(tag, 'x', fmtNum(v.x));
    if (!_same(v.y, r.y)) tag = _setAttr(tag, 'y', fmtNum(v.y));
    if (!_same(v.w, r.w)) tag = _setAttr(tag, 'width', fmtNum(v.w));
    if (!_same(v.h, r.h)) tag = _setAttr(tag, 'height', fmtNum(v.h));
    repl.add((start: r.start, end: r.end, text: tag));
  }

  if (repl.isEmpty) return doc.svg;
  repl.sort((a, b) => b.start.compareTo(a.start)); // 뒤에서부터 치환해 앞쪽 오프셋을 보존한다
  var out = doc.svg;
  var prevStart = doc.svg.length + 1;
  for (final r in repl) {
    if (r.end > prevStart) throw StateError('편집 태그가 겹친다(내부 오류)');
    out = out.replaceRange(r.start, r.end, r.text);
    prevStart = r.start;
  }
  return out;
}

/// 규격 마커 크기인가: 8×8(동그라미) · 8×L / L×8 (L ∈ [kMarkerLengths]).
bool isStandardMarkerSize(double w, double h) {
  bool isL(double v) => kMarkerLengths.any((l) => _same(l, v));
  final t = kMarkerThickness;
  if (_same(w, t) && _same(h, t)) return true;
  if (_same(w, t) && isL(h)) return true;
  if (_same(h, t) && isL(w)) return true;
  return false;
}

/// 원본 `d` 의 토큰 모양을 살려 새 정점으로 다시 쓴다 — 안 바뀐 정점은 원본 문자열 그대로.
String _rebuildD(String oldD, List<Pt> pts) {
  final toks = GeometryDoc._vertex.allMatches(oldD).toList();
  assert(toks.length == pts.length);
  final parts = <String>[];
  for (var k = 0; k < toks.length; k++) {
    final cmd = toks[k].group(1)!;
    final ox = double.parse(toks[k].group(2)!), oy = double.parse(toks[k].group(3)!);
    parts.add(_same(ox, pts[k].$1) && _same(oy, pts[k].$2)
        ? toks[k].group(0)!
        : '$cmd ${fmtNum(pts[k].$1)} ${fmtNum(pts[k].$2)}');
  }
  return parts.join(' ');
}

/// 태그의 [name] 속성 값을 [value] 로 바꾼다(없으면 오류 — 우리가 만들지 않는 속성이다).
String _setAttr(String tag, String name, String value) {
  final re = RegExp('(\\s${RegExp.escape(name)}=")[^"]*(")');
  if (!re.hasMatch(tag)) throw StateError('태그에 $name 속성이 없다: $tag');
  return tag.replaceFirstMapped(re, (m) => '${m.group(1)}$value${m.group(2)}');
}

// ======================================================================
// 12px 가드
// ======================================================================

/// 12px 밖 역 1건.
class OffLineStation {
  final String name;
  final String lineId;
  final double x, y;
  final double dist;
  OffLineStation(this.name, this.lineId, this.x, this.y, this.dist);

  String get key => '$name|$lineId';

  /// [kMaxTrackDistance] 를 넘는가(아니면 소프트 대역 — [kSoftTrackDistance] 초과 12 이하).
  bool get hard => dist > kMaxTrackDistance;

  Map<String, dynamic> toJson({bool? preexisting}) => {
        'name': name,
        'lineId': lineId,
        'x': x,
        'y': y,
        'dist': double.parse(dist.toStringAsFixed(1)),
        'pre': ?preexisting,
      };
}

double _distPtSeg(double px, double py, Pt a, Pt b) {
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) return math.sqrt(math.pow(px - a.$1, 2) + math.pow(py - a.$2, 2));
  final t = (((px - a.$1) * dx + (py - a.$2) * dy) / lenSq).clamp(0.0, 1.0);
  final cx = a.$1 + t * dx, cy = a.$2 + t * dy;
  return math.sqrt(math.pow(px - cx, 2) + math.pow(py - cy, 2));
}

/// data-line 코드 → 그 코드의 모든 path 정점열. [pathEdits] 가 있으면 그 index 의 정점으로 대체한다.
Map<String, List<List<Pt>>> polylinesByCode(GeometryDoc doc, [Map<int, List<Pt>> pathEdits = const {}]) {
  final out = <String, List<List<Pt>>>{};
  for (final p in doc.paths) {
    final code = p.code;
    if (code == null) continue;
    out.putIfAbsent(code, () => []).add(pathEdits[p.index] ?? p.points);
  }
  return out;
}

/// [maxDist] 밖 역 목록(거리 내림차순). 기본값 [kMaxTrackDistance]. main 의 CI 가드는 `test/tool/geometry_svg_test.dart` 다.
///
/// [stationsJson] 은 `assets/json/stations.json` 의 항목(name/lineId/svgX/svgY). 좌표가 없거나 매핑 없는 노선은 건너뛴다.
List<OffLineStation> findOffLineStations(
  Map<String, List<List<Pt>>> byCode,
  List<dynamic> stationsJson, {
  double maxDist = kMaxTrackDistance,
}) {
  final out = <OffLineStation>[];
  for (final s in stationsJson) {
    if (s is! Map) continue;
    final name = s['name'], lineId = s['lineId'];
    final sx = s['svgX'], sy = s['svgY'];
    if (name is! String || lineId is! String || sx is! num || sy is! num) continue;
    if (kSharedTransferMarkers.contains('$name|$lineId')) continue;
    final code = kLineIdToDataLine[lineId];
    final lines = code == null ? null : byCode[code];
    if (lines == null) continue;
    final x = sx.toDouble(), y = sy.toDouble();
    var best = double.infinity;
    for (final pl in lines) {
      for (var i = 0; i + 1 < pl.length; i++) {
        final d = _distPtSeg(x, y, pl[i], pl[i + 1]);
        if (d < best) best = d;
      }
    }
    if (best > maxDist) out.add(OffLineStation(name, lineId, x, y, best));
  }
  out.sort((a, b) => b.dist.compareTo(a.dist));
  return out;
}

/// 선로 이탈 2단계 판정 결과: [hard] = 12px 초과(기존 가드와 같은 목록), [soft] = 4px 초과 12px 이하. 서로 겹치지 않는다.
typedef OffLineTiers = ({List<OffLineStation> hard, List<OffLineStation> soft});

OffLineTiers findOffLineTiers(Map<String, List<List<Pt>>> byCode, List<dynamic> stationsJson) {
  final all = findOffLineStations(byCode, stationsJson, maxDist: kSoftTrackDistance);
  return (hard: [for (final o in all) if (o.hard) o], soft: [for (final o in all) if (!o.hard) o]);
}

// ======================================================================
// 환승 마커 ↔ stations.json 좌표 드리프트
// ======================================================================

/// 마커 중심이 역 좌표에서 이만큼(px) 넘게 멀어지면 어긋난 것으로 본다(스냅 최소 단위 0.5 의 절반).
const double kMarkerDriftTolerance = 0.25;

/// 역 좌표가 마커 원래 중심과 이 거리(px) 안이면 "그 마커에 앵커된 역"으로 본다.
/// 실측(2026-10-28): 56개 마커 중 54개는 역 좌표가 마커 중심과 **정확히 같다**(0.00px) — `tool/extract_svg_stations.dart`
/// 가 `rx` 있는 rect 의 중심을 역 dot 후보로 등록하기 때문이다. 정확히 같지 않은 예외는 둘: 김포공항 캡슐(#40, 역 좌표가 12px
/// 옆 원형 dot 에서 왔다)과 왕십리 알약(8.94px, 손으로 `<circle>`→`<rect>` 변환 — 커밋 1a4f116). 그래서 0.5px 이내는 모두, 0.5~14px 은 **환승역(isTransfer)만** 앵커로 친다 — 14px 이하에는
/// 김포공항·왕십리 외 환승역이 없고, 비환승 역(보라매공원 16.5px 등)은 반경 밖이라 섞이지 않는다.
const double kMarkerAnchorRadius = 14.0;
const double _kMarkerExactMatch = 0.5;

/// 편집으로 stations.json 좌표와 벌어진 마커 1개(그 마커에 앵커된 역들 묶음).
class MarkerDrift {
  final int index;
  final double cx, cy; // 편집된 마커 중심
  final List<({String name, String lineId, double x, double y, double dist})> stations;
  MarkerDrift(this.index, this.cx, this.cy, this.stations);

  double get dist => stations.fold(0.0, (m, s) => math.max(m, s.dist));

  /// 공유 환승 캡슐(여러 노선이 하나를 공유 — 12px 선로 가드가 면제하는 역)을 포함하는가.
  bool get shared => stations.any((s) => kSharedTransferMarkers.contains('${s.name}|${s.lineId}'));

  Map<String, dynamic> toJson() => {
        'index': index,
        'cx': double.parse(cx.toStringAsFixed(2)),
        'cy': double.parse(cy.toStringAsFixed(2)),
        'dist': double.parse(dist.toStringAsFixed(1)),
        'shared': shared,
        'stations': [
          for (final s in stations)
            {'name': s.name, 'lineId': s.lineId, 'x': s.x, 'y': s.y, 'dist': double.parse(s.dist.toStringAsFixed(1))},
        ],
      };
}

/// 마커에 앵커된 역 1개(`stations.json` 항목 하나). [d0] = 디스크 SVG 의 마커 중심까지의 거리.
typedef MarkerAnchor = ({String name, String lineId, double x, double y, double d0});

/// rect index → 그 마커에 앵커된 역들. **앵커가 없는 rect 는 키가 없다.**
///
/// 앵커 = 역을 가장 가까운 마커에 배정했을 때 거리가 [_kMarkerExactMatch] 이내이거나, [kMarkerAnchorRadius] 이내의 환승역.
Map<int, List<MarkerAnchor>> markerAnchors(List<SvgRect> rects, List<dynamic> stationsJson) {
  final centers = [for (final r in rects) (r.x + r.w / 2, r.y + r.h / 2)];
  final byRect = <int, List<MarkerAnchor>>{};
  for (final s in stationsJson) {
    if (s is! Map) continue;
    final name = s['name'], lineId = s['lineId'], sx = s['svgX'], sy = s['svgY'];
    if (name is! String || lineId is! String || sx is! num || sy is! num) continue;
    final x = sx.toDouble(), y = sy.toDouble();
    var best = -1;
    var bd = double.infinity;
    for (var i = 0; i < centers.length; i++) {
      final d = math.sqrt(math.pow(centers[i].$1 - x, 2) + math.pow(centers[i].$2 - y, 2));
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    if (best < 0) continue;
    final anchored = bd <= _kMarkerExactMatch || (bd <= kMarkerAnchorRadius && s['isTransfer'] == true);
    if (!anchored) continue;
    byRect.putIfAbsent(best, () => []).add((name: name, lineId: lineId, x: x, y: y, d0: bd));
  }
  return byRect;
}

/// 앵커 역이 하나도 없는 마커의 index(오름차순).
///
/// **영속 드리프트 신호.** 현재 `stations.json` 은 56/56 마커가 앵커를 가진다(54개는 역 좌표 = 마커 중심 0.00px, 김포공항
/// #40 12px · 왕십리 8.94px 옆 환승역). 그러니 앵커가 없다면 ① 마커를 옮겨 저장했는데 `stations.json` 이 안 따라왔거나 ② 추출기가 못
/// 보는 마커가 새로 생긴 것이다 — 둘 다 사람이 봐야 한다. 마커를 앵커 반경 밖으로 크게 옮길수록 [findMarkerDrift]
/// (저장 직전 이동량 기준)는 침묵하지만 이쪽은 확실히 걸린다. "역 → 가장 가까운 마커" 방향의 최근접 역추적이 아니라
/// **마커가 역을 하나라도 갖는가**를 묻는 것이라 비환승 원형 dot 때문에 생기는 오탐이 없다.
///
/// 한계: 옮긴 마커가 우연히 (a) 다른 마커 위에 정확히 겹치거나 (b) 어떤 환승역의 14px 안에 놓이면 앵커가 생겨 안 걸린다.
/// (a)는 겹친 둘 중 하나가 앵커를 잃어 걸리고, (b)는 `findMarkerDrift` 가 저장 시점에 따로 잡는다.
List<int> orphanMarkers(List<SvgRect> rects, List<dynamic> stationsJson) {
  final anchored = markerAnchors(rects, stationsJson);
  return [for (var i = 0; i < rects.length; i++) if (!anchored.containsKey(i)) i];
}

/// ([x],[y]) 에서 가장 가까운 역 — 고아 마커 안내용(`{name, lineId, x, y, dist}` 또는 null).
Map<String, dynamic>? nearestStation(double x, double y, List<dynamic> stationsJson) {
  Map<String, dynamic>? best;
  var bd = double.infinity;
  for (final s in stationsJson) {
    if (s is! Map) continue;
    final name = s['name'], lineId = s['lineId'], sx = s['svgX'], sy = s['svgY'];
    if (name is! String || lineId is! String || sx is! num || sy is! num) continue;
    final d = math.sqrt(math.pow(sx - x, 2) + math.pow(sy - y, 2));
    if (d < bd) {
      bd = d;
      best = {'name': name, 'lineId': lineId, 'x': sx.toDouble(), 'y': sy.toDouble(), 'dist': double.parse(d.toStringAsFixed(1))};
    }
  }
  return best;
}

/// [edits] 로 중심이 움직인 환승 마커와 그 마커에 앵커된 역(`stations.json`)의 어긋남(거리 내림차순).
///
/// `extract_svg_stations` 가 마커 중심을 역 좌표의 원천으로 쓰는데 편집기는 1·2단계를 다시 돌리지 않으므로(돌리면 데이터가
/// 파손된다 — CLAUDE.md), 마커를 끌면 `stations.json` 좌표가 옛 자리에 남는다. 12px 선로 가드는 역↔선 거리만 재서 이걸
/// 못 잡는다(공유 캡슐 3건은 아예 면제). 길이·방향 변경은 중심을 보존하므로 어긋나지 않는다 — 드래그만 걸린다.
///
/// 판정: 앵커된 역마다 `d0`(원래 중심까지)·`d1`(편집 중심까지)을 재고 `d1 > d0 + [tol]` 이면 어긋남. 역에 더 가까워지는
/// 이동은 보고하지 않는다(역을 통과해 반대편으로 나가는 이동도 d1 ≤ d0 이면 무보고 — 영향 ≤ d0). [rects] 는 **디스크의
/// 원본** 마커(편집 전 중심이 앵커 기준이다). 이 함수는 저장 **전** 이동량만 본다 — 저장 후에도 남는 어긋남은 [orphanMarkers].
List<MarkerDrift> findMarkerDrift(
  List<SvgRect> rects,
  Map<int, RectEdit> edits,
  List<dynamic> stationsJson, {
  double tol = kMarkerDriftTolerance,
}) {
  if (edits.isEmpty) return const [];
  final byRect = markerAnchors(rects, stationsJson);
  final out = <MarkerDrift>[];
  for (final e in edits.entries) {
    final i = e.key;
    final group = byRect[i];
    if (group == null || i < 0 || i >= rects.length) continue;
    final cx = e.value.x + e.value.w / 2, cy = e.value.y + e.value.h / 2;
    final drifted = <({String name, String lineId, double x, double y, double dist})>[];
    for (final s in group) {
      final d1 = math.sqrt(math.pow(cx - s.x, 2) + math.pow(cy - s.y, 2));
      if (d1 > s.d0 + tol) drifted.add((name: s.name, lineId: s.lineId, x: s.x, y: s.y, dist: d1));
    }
    if (drifted.isEmpty) continue;
    drifted.sort((a, b) => b.dist.compareTo(a.dist));
    out.add(MarkerDrift(i, cx, cy, drifted));
  }
  out.sort((a, b) => b.dist.compareTo(a.dist));
  return out;
}
