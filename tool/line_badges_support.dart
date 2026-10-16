part of 'line_badges.dart';

// `line_badges.dart` 의 보조 코드: 자료구조·SVG 파싱·기하 유틸·글자색(대비) 계산.
// 배치·검증 흐름은 `line_badges.dart` 에 있다. (`part` 로 같은 라이브러리를 공유해
// private 이름을 그대로 쓴다 — 파일 크기 분할 목적이지 모듈 경계가 아니다.)

// ======================================================================
// 자료구조
// ======================================================================
class _P {
  final double x, y;
  const _P(this.x, this.y);
}

class _R {
  final double x0, y0, x1, y1;
  const _R(this.x0, this.y0, this.x1, this.y1);
  double overlapArea(_R o) {
    final w = math.min(x1, o.x1) - math.max(x0, o.x0);
    final h = math.min(y1, o.y1) - math.max(y0, o.y0);
    return (w > 0 && h > 0) ? w * h : 0;
  }

  /// 사방으로 [m] 만큼 부푼 사각형.
  _R inflate(double m) => _R(x0 - m, y0 - m, x1 + m, y1 + m);
}

class _Label {
  final String name;
  final String? code; // 원본 SVG `<text data-line>` — 매핑 대조 검증용
  final bool major;
  final double ax, ay; // 앵커 (text x,y)
  final List<_R> lines; // f=1.0 기준 줄별 bbox
  _Label(this.name, this.code, this.major, this.ax, this.ay, this.lines);

  /// 환승역(tl-major)만 줌아웃 시 앵커 기준으로 f 배 커진다(textTargetRect 와 동일).
  List<_R> at(double f) {
    if (!major || f == 1) return lines;
    return [
      for (final r in lines)
        _R(ax + (r.x0 - ax) * f, ay + (r.y0 - ay) * f, ax + (r.x1 - ax) * f,
            ay + (r.y1 - ay) * f),
    ];
  }
}

class _Circle {
  final double cx, cy, r;
  const _Circle(this.cx, this.cy, this.r);
}

class _Seg {
  final double x0, y0, x1, y1;
  const _Seg(this.x0, this.y0, this.x1, this.y1);
}

class _Poly {
  final String code;
  final String stroke;
  final List<_P> pts;
  _Poly(this.code, this.stroke, this.pts);
}

class _Badge {
  final String lineId;
  final String code;
  final String text;
  final String color;
  final String textColor;
  final String stationName;
  final _P anchor;
  final double anchorGap; // 종점 역 ↔ 앵커 거리(경로상 연장분 확인용)
  final _P dir; // 바깥 방향 단위벡터
  final double w;
  _Badge({
    required this.lineId,
    required this.code,
    required this.text,
    required this.color,
    required this.textColor,
    required this.stationName,
    required this.anchor,
    required this.anchorGap,
    required this.dir,
    required this.w,
  });
  /// 수동 보정 키(`노선id|종점역명`) — `data/badge_offsets.json` 의 키와 같다.
  String get key => badgeKey(lineId, stationName);

  /// 수동 보정 배지 — 자동 배치기가 건너뛰고(장애물로만 쓰임) 하드 위반이어도 빌드를 실패시키지 않는다.
  bool manual = false;

  // 선택된 중심 오프셋(앵커 기준). 자동 배치는 배치 후, 수동 보정은 [_applyOffsets] 가 채운다.
  double ox = 0, oy = 0;
  double chosenGap = 0;
  double chosenAngle = 0;
  double chosenAbsAng = 0; // 선택된 배치 방향의 절대 각도(rad) — [_BadgePlacer._polish] 용

  /// 앵커↔pill 사각형 **실제 최단 거리**(px). 줄기가 없어 이것이 귀속(인접성) 단서다.
  /// 앵커가 사각형 안이면 0.
  double get anchorDist {
    final r = rect;
    final dx = math.max(math.max(r.x0 - anchor.x, anchor.x - r.x1), 0.0);
    final dy = math.max(math.max(r.y0 - anchor.y, anchor.y - r.y1), 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// 배지 사각형(지도 좌표). 줌아웃 보정이 없어 항상 1배다.
  _R get rect => _R(
        anchor.x + ox - w / 2,
        anchor.y + oy - _kBadgeH / 2,
        anchor.x + ox + w / 2,
        anchor.y + oy + _kBadgeH / 2,
      );
}

// ======================================================================
// 1. 입력 정리
// ======================================================================
class _MapData {
  final Map<String, Map<String, dynamic>> stations;
  final List<Map<String, dynamic>> lines;
  final Map<String, String> lineCodes; // lineId → data-line 코드
  final List<_Poly> polys;
  final List<_Label> labels;
  final Map<String, Map<String, Set<String>>> adj; // lineId → node → neighbors
  final List<_Circle> circles;
  final List<_R> stationRects;

  // polys 에서 파생
  final Map<String, List<_Seg>> segsByCode = {};
  final Map<String, String> colorByCode = {};
  final Map<String, List<List<_P>>> orientedByCode = {}; // 끝점이 마지막이 되도록 정렬

  _MapData({
    required this.stations,
    required this.lines,
    required this.lineCodes,
    required this.polys,
    required this.labels,
    required this.adj,
    required this.circles,
    required this.stationRects,
  }) {
    for (final p in polys) {
      final list = segsByCode.putIfAbsent(p.code, () => []);
      for (var i = 0; i + 1 < p.pts.length; i++) {
        list.add(_Seg(p.pts[i].x, p.pts[i].y, p.pts[i + 1].x, p.pts[i + 1].y));
      }
    }
    for (final p in polys) {
      final prev = colorByCode[p.code];
      if (prev != null && prev != p.stroke) {
        throw StateError('data-line ${p.code} 의 stroke 색이 둘 이상: $prev / ${p.stroke}');
      }
      colorByCode[p.code] = p.stroke;
    }
    for (final p in polys) {
      final list = orientedByCode.putIfAbsent(p.code, () => []);
      list.add(p.pts);
      list.add(p.pts.reversed.toList());
    }
  }

  Set<String> get codes => lineCodes.values.toSet();

  Map<String, dynamic> station(String sid) =>
      stations[sid] ?? (throw StateError('connections/lines 의 역 $sid 가 stations.json 에 없음'));

  (double, double) xy(String sid) {
    final s = station(sid);
    return ((s['svgX'] as num).toDouble(), (s['svgY'] as num).toDouble());
  }
}

_MapData _parseInputs(
  String svgContent,
  List<dynamic> stationsJson,
  List<dynamic> linesJson,
  List<dynamic> connectionsJson,
  Set<String> transferStationNames,
  Map<String, String> lineCodes,
) {
  final adj = <String, Map<String, Set<String>>>{};
  for (final c in connectionsJson.cast<Map<String, dynamic>>()) {
    if (c['isTransfer'] == true) continue;
    final g = adj.putIfAbsent(c['lineId'] as String, () => {});
    final a = c['fromStationId'] as String, b = c['toStationId'] as String;
    g.putIfAbsent(a, () => {}).add(b);
    g.putIfAbsent(b, () => {}).add(a);
  }
  return _MapData(
    stations: {
      for (final s in stationsJson.cast<Map<String, dynamic>>()) s['id'] as String: s,
    },
    lines: linesJson.cast<Map<String, dynamic>>(),
    lineCodes: lineCodes,
    polys: _parsePolys(svgContent, lineCodes.values.toSet()),
    labels: _parseLabels(svgContent, transferStationNames),
    adj: adj,
    circles: [
      for (final m in RegExp(r'<circle\b[^>]*>').allMatches(svgContent))
        _Circle(_attr(m.group(0)!, 'cx'), _attr(m.group(0)!, 'cy'),
            _attr(m.group(0)!, 'r') + 1.5),
    ],
    stationRects: [
      for (final m in RegExp(r'<rect\b[^>]*>').allMatches(svgContent))
        if (_attrStr(m.group(0)!, 'x') != null)
          _R(
            _attr(m.group(0)!, 'x') - 1,
            _attr(m.group(0)!, 'y') - 1,
            _attr(m.group(0)!, 'x') + _attr(m.group(0)!, 'width') + 1,
            _attr(m.group(0)!, 'y') + _attr(m.group(0)!, 'height') + 1,
          ),
    ],
  );
}

// ======================================================================
// 텍스트 폭 근사 — 한글 등 전각은 1em, 숫자/라틴은 좁다. (Chrome getBBox 로 교차검증함)
// ======================================================================

/// 라틴/숫자 글리프 보정(font-weight 800/700 은 약간 넓다). 라벨·배지 모두 같은 값.
const double _kLatinBoost = 1.08;

double _glyphEm(int r) {
  if ((r >= 0xAC00 && r <= 0xD7A3) ||
      (r >= 0x3130 && r <= 0x318F) ||
      (r >= 0x4E00 && r <= 0x9FFF) ||
      r == 0xB7) {
    return 1.0;
  }
  if (r >= 0x30 && r <= 0x39) return 0.6;
  if (r >= 0x41 && r <= 0x5A) return 0.7;
  if (r >= 0x61 && r <= 0x7A) return 0.58;
  if (r == 0x2D) return 0.38; // -
  if (r == 0x28 || r == 0x29) return 0.4; // ( )
  if (r == 0x20) return 0.3;
  return 0.6;
}

double _textWidth(String s, double fontPx) {
  var w = 0.0;
  for (final r in s.runes) {
    final em = _glyphEm(r);
    w += em * fontPx * (em < 1.0 ? _kLatinBoost : 1.0);
  }
  return w;
}

// ======================================================================
// SVG 파싱 (이 저장소의 SVG 는 M/L 만 쓰는 polyline 이다)
// ======================================================================
String _normName(String raw) => raw
    .replaceAll('&#10;', '')
    .replaceAll('&#13;', '')
    .replaceAll('\n', '')
    .replaceAll('\r', '')
    .trim();

double _attr(String tag, String name) {
  final m = RegExp('\\s$name="([^"]*)"').firstMatch(tag);
  if (m == null) throw StateError('속성 없음: $name in $tag');
  return double.parse(m.group(1)!);
}

String? _attrStr(String tag, String name) =>
    RegExp('\\s$name="([^"]*)"').firstMatch(tag)?.group(1);

/// SVG 조각(속성값·텍스트)에 넣는 문자열의 XML 이스케이프. 노선명이 바뀌어
/// `& < > "` 가 들어와도 생성 HTML 이 깨지지 않게 한다.
String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// `data-line` 이 있는 `<path>` 를 polyline 으로 읽는다.
///
/// stroke 없는 `data-line` path 는 여기서 조용히 건너뛰지만, 같은 입력을
/// `_verifySvgCodes`(line_badges.dart)가 **먼저** 명시적 StateError 로 막으므로
/// 실제 빌드에서는 이 경로가 도달되지 않는다(stroke 검증 담당은 그쪽). `d` 없는 path 는
/// 어느 쪽에서도 막지 않고 건너뛴다 — 아래 "파서 한계"의 조용한 누락 부류.
///
/// **파서 한계(하드페일 조건)** — 현재 SVG(34개 path)는 모두 `M x y L x y …` 의 명시형이라
/// 안전하다. 아래는 파이프라인이 바뀌면 *조용히* 점을 잃을 수 있는 형태다:
/// - M/L 외 명령(C/Q/A/Z/H/V/상대좌표 소문자)은 즉시 StateError 로 빌드를 막는다(아래 검사).
/// - 그러나 쉼표 구분(`M1,2`), 음수 좌표, 명령 생략(암묵적 lineto `L 1 2 3 4`)은
///   정규식이 **조용히 건너뛴다**. SVG 내보내기 설정이 바뀌어 이런 형태가 나오면
///   앵커 좌표가 틀어질 수 있으므로, 그때는 이 파서(와 JS `parseSvgPath`)를 함께 고칠 것.
List<_Poly> _parsePolys(String svg, Set<String> codes) {
  final out = <_Poly>[];
  for (final m in RegExp(r'<path\b[^>]*>').allMatches(svg)) {
    final tag = m.group(0)!;
    final code = _attrStr(tag, 'data-line');
    final stroke = _attrStr(tag, 'stroke');
    final d = _attrStr(tag, 'd');
    if (code == null || stroke == null || d == null) continue;
    if (!codes.contains(code)) continue; // `1-GA-1` 같은 흰색 내부선 제외
    if (RegExp(r'[A-KN-Za-z]').hasMatch(d.replaceAll(RegExp(r'[ML]'), ''))) {
      throw StateError('M/L 외의 path 명령 발견 — polyline 파서 가정 위반: $code');
    }
    final pts = [
      for (final p in RegExp(r'([ML])\s*([\d.]+)\s+([\d.]+)').allMatches(d))
        _P(double.parse(p.group(2)!), double.parse(p.group(3)!)),
    ];
    if (pts.length < 2) continue;
    out.add(_Poly(code, stroke.toLowerCase(), pts));
  }
  return out;
}

List<_Label> _parseLabels(String svg, Set<String> transferNames) {
  final out = <_Label>[];
  for (final m in RegExp(r'<text[^>]*>.*?</text>', dotAll: true).allMatches(svg)) {
    final el = m.group(0)!;
    final open = RegExp(r'^<text[^>]*>').firstMatch(el)!.group(0)!;
    final name = _attrStr(open, 'data-station');
    if (name == null) continue;
    final x = _attr(open, 'x'), y = _attr(open, 'y');
    final anchor = _attrStr(open, 'text-anchor') ?? 'start';
    final tspans = RegExp(r'<tspan[^>]*>(.*?)</tspan>', dotAll: true)
        .allMatches(el)
        .toList();
    final rows = <(String, double)>[]; // (텍스트, baseline y)
    if (tspans.isEmpty) {
      final t = el.replaceAll(RegExp(r'<[^>]*>'), '');
      rows.add((t, y));
    } else {
      var yy = y;
      for (final t in tspans) {
        final tag = RegExp(r'^<tspan[^>]*>').firstMatch(t.group(0)!)!.group(0)!;
        final dy = double.tryParse(_attrStr(tag, 'dy') ?? '0') ?? 0;
        yy += dy;
        rows.add((t.group(1)!, yy));
      }
    }
    final rects = <_R>[];
    for (final (text, by) in rows) {
      final w = _textWidth(text, kTextBaseFontSize);
      final x0 = anchor == 'end'
          ? x - w
          : anchor == 'middle'
              ? x - w / 2
              : x;
      rects.add(_R(x0, by - 11, x0 + w, by + 3));
    }
    final norm = _normName(name);
    out.add(_Label(norm, _attrStr(open, 'data-line'), transferNames.contains(norm),
        x, y, rects));
  }
  return out;
}

// ======================================================================
// 기하 유틸
// ======================================================================
double _distPtSeg(double px, double py, _Seg s) {
  final dx = s.x1 - s.x0, dy = s.y1 - s.y0;
  final l2 = dx * dx + dy * dy;
  final t = l2 == 0
      ? 0.0
      : (((px - s.x0) * dx + (py - s.y0) * dy) / l2).clamp(0.0, 1.0);
  return math.sqrt(math.pow(px - s.x0 - t * dx, 2) + math.pow(py - s.y0 - t * dy, 2));
}

/// 선분이 사각형 안에서 차지하는 길이(Liang–Barsky).
double _segLenInRect(_Seg s, _R r) {
  var t0 = 0.0, t1 = 1.0;
  final dx = s.x1 - s.x0, dy = s.y1 - s.y0;
  bool clip(double p, double q) {
    if (p == 0) return q >= 0;
    final t = q / p;
    if (p < 0) {
      if (t > t1) return false;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return false;
      if (t < t1) t1 = t;
    }
    return true;
  }

  if (clip(-dx, s.x0 - r.x0) &&
      clip(dx, r.x1 - s.x0) &&
      clip(-dy, s.y0 - r.y0) &&
      clip(dy, r.y1 - s.y0)) {
    return (t1 - t0) * math.sqrt(dx * dx + dy * dy);
  }
  return 0;
}

/// 두 선분 사이 최단 거리(교차하면 0).
double _segSegDist(_Seg a, _Seg b) {
  double cross(double ax, double ay, double bx, double by) => ax * by - ay * bx;
  final rx = a.x1 - a.x0, ry = a.y1 - a.y0;
  final sx = b.x1 - b.x0, sy = b.y1 - b.y0;
  final den = cross(rx, ry, sx, sy);
  if (den != 0) {
    final qx = b.x0 - a.x0, qy = b.y0 - a.y0;
    final t = cross(qx, qy, sx, sy) / den;
    final u = cross(qx, qy, rx, ry) / den;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return 0;
  }
  return math.min(
    math.min(_distPtSeg(a.x0, a.y0, b), _distPtSeg(a.x1, a.y1, b)),
    math.min(_distPtSeg(b.x0, b.y0, a), _distPtSeg(b.x1, b.y1, a)),
  );
}

/// 선분 [s] 와 사각형 [r] 사이 최단 거리(겹치면 0).
double _segRectDist(_Seg s, _R r) {
  if (_segLenInRect(s, r) > 0) return 0;
  final edges = [
    _Seg(r.x0, r.y0, r.x1, r.y0),
    _Seg(r.x1, r.y0, r.x1, r.y1),
    _Seg(r.x1, r.y1, r.x0, r.y1),
    _Seg(r.x0, r.y1, r.x0, r.y0),
  ];
  var best = double.infinity;
  for (final e in edges) {
    best = math.min(best, _segSegDist(s, e));
  }
  return best;
}

bool _circleHitsRect(_Circle c, _R r) {
  final nx = c.cx.clamp(r.x0, r.x1), ny = c.cy.clamp(r.y0, r.y1);
  final dx = c.cx - nx, dy = c.cy - ny;
  return dx * dx + dy * dy <= c.r * c.r;
}

double _segLen(_P a, _P b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

String _fmt(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

// ======================================================================
// 글자색 — WCAG 상대휘도 대비
// ======================================================================

/// 배경이 흰 글씨와 이 대비비(WCAG)보다 낮으면 짙은 글씨로 바꾼다.
/// 3.0 = WCAG AA-large 기준. **AA(4.5) 미달이라도 3.0 이상이면 흰 글씨를 유지한다** —
/// 지하철 앱의 "노선색 + 흰 글씨" 관습을 지키라는 사용자 결정(2026-10-06, "최악만 손본다").
const double kBadgeMinWhiteContrast = 3.0;
const String kBadgeLightText = '#ffffff';
const String kBadgeDarkText = '#1f1f1f';

/// `#rrggbb` 의 WCAG 2.x 상대휘도(선형화한 sRGB 가중합).
double relativeLuminance(String hex) {
  final h = hex.replaceFirst('#', '');
  double lin(int from) {
    final c = int.parse(h.substring(from, from + 2), radix: 16) / 255;
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * lin(0) + 0.7152 * lin(2) + 0.0722 * lin(4);
}

/// 두 색의 WCAG 대비비(1~21).
double contrastRatio(String hexA, String hexB) {
  final a = relativeLuminance(hexA), b = relativeLuminance(hexB);
  final hi = math.max(a, b), lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// 노선색 배경 위 배지 글자색: 흰 글씨 대비가 [kBadgeMinWhiteContrast] 미만일 때만 짙은 글씨.
String badgeTextColorFor(String bgHex) =>
    contrastRatio(bgHex, kBadgeLightText) < kBadgeMinWhiteContrast
        ? kBadgeDarkText
        : kBadgeLightText;
