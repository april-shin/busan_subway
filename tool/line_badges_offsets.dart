part of 'line_badges.dart';

// `line_badges.dart` 의 **수동 위치 보정** 공개 API: 오버라이드 파일(`data/badge_offsets.json`) 파싱·직렬화,
// 배치 결과(편집기 모델), 한 배지를 임의 위치에 놓았을 때의 하드 위반 판정.
//
// 설계(요구사항: 사용자 "배지를 클릭으로 이동하는 식으로 보정", 2026-10-06):
// - 오버라이드는 **앵커 기준 상대 오프셋**(앵커 → pill 중심, [BadgeOffset])이다. 절대 좌표로 두면 나중에 SVG/역
//   데이터가 바뀌어 앵커가 움직였을 때 배지만 엉뚱한 곳에 남는다.
// - 키는 `노선id|종점역명`([badgeKey]) — 한 노선에 배지가 2개라 둘을 함께 식별해야 한다. 노선 id 는
//   `kLineIdToDataLine` 의 키(안정적인 앱 노선 id)다.
// - 오버라이드가 있는 배지는 자동 배치기를 **건너뛴다**(다른 배지의 장애물로만 쓰인다). 하드 위반이어도 빌드를
//   실패시키지 않고 경고만 남긴다 — 사람이 일부러 고른 자리를 기계가 거부하면 이 기능이 무의미해진다.
//   (자동 배치 배지의 하드 실패 정책은 그대로다.)
// - 파일이 없거나 비어 있으면([BadgeOffsets.empty]) 동작·산출물이 이 기능 도입 전과 바이트 동일하다.

/// 오버라이드 파일 경로(프로젝트 루트 기준). 커밋 대상 수기 입력 소스다.
const String kBadgeOffsetsPath = 'data/badge_offsets.json';

/// 파일 포맷 버전. 다르면 읽지 않고 빌드를 막는다(조용히 틀린 해석을 막기 위해).
const int kBadgeOffsetsVersion = 1;

/// 파일에 적을 수 있는 오프셋 절댓값 상한(px). 손으로 적다 생긴 오타(`1e6`·단위 실수)가 배지를 캔버스
/// 밖으로 날리는 것을 막는 방어선이다(캔버스는 2416×1560).
const double kBadgeOffsetMaxAbs = 400;

/// 배지 키: `노선id|종점역명`. 예: `김포골드|양촌`, `2|신설동`.
String badgeKey(String lineId, String stationName) => '$lineId|$stationName';

/// 앵커 → pill **중심**까지의 오프셋(지도 좌표 px). 앵커는 노선 선의 자유 끝점이다.
class BadgeOffset {
  final double dx, dy;
  const BadgeOffset(this.dx, this.dy);

  @override
  bool operator ==(Object other) => other is BadgeOffset && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => '($dx, $dy)';
}

/// 수동 보정 입력 전체 — 키 → [BadgeOffset] + 파싱 단계의 경고(값이 잘못된 항목 등).
class BadgeOffsets {
  final Map<String, BadgeOffset> byKey;

  /// 파싱 중 건너뛴 항목 사유. 건너뛴 배지는 자동 배치로 떨어진다(조용히 무시하지 않고 빌드 로그에 남는다).
  final List<String> warnings;
  const BadgeOffsets(this.byKey, {this.warnings = const []});

  /// 보정 없음 — 이 값이면 산출물은 이 기능 도입 전과 같다.
  static const BadgeOffsets empty = BadgeOffsets(<String, BadgeOffset>{});

  bool get isEmpty => byKey.isEmpty && warnings.isEmpty;

  /// 파일 내용을 읽는다. `null`/공백뿐이면 [empty]. **문법 오류·형식 오류는 [StateError]** 로 빌드를 막는다 —
  /// 깨진 파일을 "보정 없음"으로 취급하면 편집기가 다음 저장 때 사람이 한 보정을 통째로 덮어쓴다.
  /// 항목 단위 문제(숫자 아님·범위 초과)는 그 항목만 경고와 함께 건너뛴다.
  factory BadgeOffsets.parse(String? text) {
    if (text == null || text.trim().isEmpty) return empty;
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      throw StateError('$kBadgeOffsetsPath JSON 문법 오류: ${e.message}');
    }
    if (root is! Map) {
      throw StateError('$kBadgeOffsetsPath 최상위는 객체여야 한다: {"version": $kBadgeOffsetsVersion, "offsets": {...}}');
    }
    final version = root['version'];
    if (version != null && version != kBadgeOffsetsVersion) {
      throw StateError('$kBadgeOffsetsPath version $version 은 지원하지 않는다(지원: $kBadgeOffsetsVersion)');
    }
    final raw = root['offsets'];
    if (raw == null) return empty;
    if (raw is! Map) {
      throw StateError('$kBadgeOffsetsPath 의 "offsets" 는 객체여야 한다: {"노선id|종점역명": {"dx": 0, "dy": 0}}');
    }
    final out = <String, BadgeOffset>{};
    final warnings = <String>[];
    for (final e in raw.entries) {
      final key = e.key.toString();
      final v = e.value;
      final dx = v is Map ? v['dx'] : null;
      final dy = v is Map ? v['dy'] : null;
      if (dx is! num || dy is! num || !dx.isFinite || !dy.isFinite) {
        warnings.add('수동 보정 "$key" 의 값이 {"dx": 숫자, "dy": 숫자} 가 아니다($v) — 이 배지는 자동 배치로 처리한다');
        continue;
      }
      if (dx.abs() > kBadgeOffsetMaxAbs || dy.abs() > kBadgeOffsetMaxAbs) {
        warnings.add('수동 보정 "$key" 의 오프셋 ($dx, $dy) 이 상한 ±${kBadgeOffsetMaxAbs.toInt()}px 를 넘는다 — '
            '오타로 보고 이 배지는 자동 배치로 처리한다');
        continue;
      }
      out[key] = BadgeOffset(dx.toDouble(), dy.toDouble());
    }
    return BadgeOffsets(out, warnings: warnings);
  }

  /// 파일에 쓰는 정규형 — 키 정렬·소수 둘째 자리 반올림·1항목 1줄이라 diff 가 깔끔하다.
  String encode() {
    String num2(double v) {
      final r = (v * 100).round() / 100;
      return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
    }

    final keys = byKey.keys.toList()..sort();
    final sb = StringBuffer('{\n  "version": $kBadgeOffsetsVersion,\n  "offsets": {');
    if (keys.isEmpty) {
      sb.write('}\n}\n');
      return sb.toString();
    }
    sb.writeln();
    for (var i = 0; i < keys.length; i++) {
      final o = byKey[keys[i]]!;
      sb.write('    ${jsonEncode(keys[i])}: {"dx": ${num2(o.dx)}, "dy": ${num2(o.dy)}}');
      sb.writeln(i == keys.length - 1 ? '' : ',');
    }
    sb.write('  }\n}\n');
    return sb.toString();
  }
}

/// 하드 위반 한 건. 빌드 로그·편집기가 같은 [kind]/[message] 를 쓴다(판정은 [_BadgePlacer] 한 벌).
class BadgeViolation {
  /// `canvas`·`otherLine`·`label`·`circle`·`rect`·`badge`·`anchor`.
  final String kind;
  final String message;

  /// 겹친 대상이 **자동 배치 배지**라 저장·재빌드 때 비켜날 수 있는 경우(편집기 전용 안내, 빌드 판정엔 없다).
  final bool soft;

  /// kind == `badge` 일 때 상대 배지 키.
  final String? otherKey;

  /// 겹친 대상의 사각형(지도 좌표) — 편집기가 강조 표시한다. 선처럼 사각형이 없으면 null.
  final double? x0, y0, x1, y1;
  const BadgeViolation(this.kind, this.message,
      {this.soft = false, this.otherKey, this.x0, this.y0, this.x1, this.y1});

  BadgeViolation _asSoft() => BadgeViolation(kind, '$message — 자동 배치 배지라 저장하면 비켜난다(자리가 없으면 빌드 실패)',
      soft: true, otherKey: otherKey, x0: x0, y0: y0, x1: x1, y1: y1);

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'message': message,
        'soft': soft,
        if (x0 != null) 'box': [x0, y0, x1, y1],
      };

  @override
  String toString() => message;
}

/// [LineBadgeSolution.check] 결과.
class BadgeCheck {
  final List<BadgeViolation> violations;

  /// 앵커↔pill 실제 최단 거리(px).
  final double anchorDist;
  const BadgeCheck(this.violations, this.anchorDist);
}

/// 확정된 배지 한 장의 배치(편집기·테스트용 읽기 전용 뷰).
class BadgePlacement {
  final int index;
  final String key, lineId, lineName, stationName, text, color, textColor;
  final double anchorX, anchorY, w, h;

  /// 앵커 → pill 중심 오프셋(= 오버라이드 `dx`/`dy` 와 같은 양).
  final double ox, oy;
  final double anchorDist;
  final bool manual;

  /// 현재 배치 기준 하드 위반. 자동 배치 배지는 항상 비어 있다(있으면 빌드가 실패한다).
  final List<BadgeViolation> violations;
  const BadgePlacement({
    required this.index,
    required this.key,
    required this.lineId,
    required this.lineName,
    required this.stationName,
    required this.text,
    required this.color,
    required this.textColor,
    required this.anchorX,
    required this.anchorY,
    required this.w,
    required this.h,
    required this.ox,
    required this.oy,
    required this.anchorDist,
    required this.manual,
    required this.violations,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'key': key,
        'lineId': lineId,
        'lineName': lineName,
        'station': stationName,
        'text': text,
        'color': color,
        'textColor': textColor,
        'ax': anchorX,
        'ay': anchorY,
        'w': w,
        'h': h,
        'ox': ox,
        'oy': oy,
        'anchorDist': anchorDist,
        'manual': manual,
        'violations': [for (final v in violations) v.toJson()],
      };
}

/// [solveLineBadges] 의 결과 + 배치 상태 핸들. 편집기 서버가 드래그 중에 [check] 로 즉시 판정한다.
class LineBadgeSolution {
  final LineBadgeResult result;
  final List<_Badge> _badges;
  final _BadgePlacer _placer;
  LineBadgeSolution._(this.result, this._badges, this._placer);

  /// 현재 배지 키 집합(오버라이드 파일의 유효 키).
  Set<String> get keys => {for (final b in _badges) b.key};

  /// [key] 배지를 앵커 기준 ([dx],[dy]) 에 놓았을 때의 하드 위반(다른 배지는 현재 위치 그대로).
  /// 빌드 타임 판정([_BadgePlacer.hardViolations])과 **같은 함수**를 쓴다 — 편집기와 빌드 결과가 갈라지지 않는다.
  /// 상대가 자동 배치 배지면 [BadgeViolation.soft] 로 표시한다(저장 시 그 배지가 비켜나기 때문).
  BadgeCheck check(String key, double dx, double dy) {
    final b = _badges.firstWhere((b) => b.key == key,
        orElse: () => throw ArgumentError('알 수 없는 배지 키: $key'));
    final ox = b.ox, oy = b.oy;
    try {
      b.ox = dx;
      b.oy = dy;
      final byKey = {for (final o in _badges) o.key: o};
      final vs = [
        for (final v in _placer._hard(b, _badges))
          (v.kind == 'badge' && byKey[v.otherKey]?.manual == false) ? v._asSoft() : v,
      ];
      return BadgeCheck(vs, b.anchorDist);
    } finally {
      b.ox = ox;
      b.oy = oy;
    }
  }

  /// 편집기가 쓰는 전체 모델.
  Map<String, dynamic> toJson() => {
        'canvas': {'w': kCanvasW, 'h': kCanvasH},
        'maxAnchorDist': _kMaxAnchorDist,
        'badges': [for (final p in result.placements) p.toJson()],
        'summary': result.summary,
        'manualCount': result.manualCount,
        'warnings': [...result.offsetWarnings, ...result.manualWarnings],
        'staleKeys': result.staleOffsetKeys,
      };
}
