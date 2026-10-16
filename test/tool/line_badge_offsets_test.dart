// 노선 배지 수동 위치 보정(data/badge_offsets.json) — 오버라이드 경로 테스트.
//
// 1순위 회귀 가드: 보정이 없을 때(파일 없음/빈 파일/빈 offsets) 산출물이 보정 기능 도입 전과 같다.
// 그 외: 있을 때(그 배지만 움직임)·하드 위반이어도 빌드 실패 없이 경고·잘못된 키는 경고 + 자동 배치 폴백·
// 자동 배지의 하드 실패 정책 유지·편집기 판정(check)이 빌드 판정과 같은 규칙.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/line_badges.dart';

List<Map<String, dynamic>> _readJsonList(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>();

void main() {
  final svg = File('assets/svg/seoul_metro_map.svg').readAsStringSync();
  final stations = _readJsonList('assets/json/stations.json');
  final lines = _readJsonList('assets/json/lines.json');
  final conns = _readJsonList('assets/json/connections.json');
  final transfer = {
    for (final s in stations)
      if (s['isTransfer'] == true) s['name'] as String,
  };

  LineBadgeSolution solve([BadgeOffsets offsets = BadgeOffsets.empty]) => solveLineBadges(
        svgContent: svg,
        stationsJson: stations,
        linesJson: lines,
        connectionsJson: conns,
        transferStationNames: transfer,
        offsets: offsets,
      );

  BadgeOffsets one(String key, double dx, double dy) => BadgeOffsets({key: BadgeOffset(dx, dy)});

  // 비용이 큰 풀이(~2.5초)는 한 번만 돌리고 공유한다.
  late final LineBadgeSolution base;
  setUpAll(() => base = solve());

  Map<String, BadgePlacement> byKey(LineBadgeResult r) => {for (final p in r.placements) p.key: p};

  group('오프셋 파일 파싱·직렬화', () {
    test('null·빈 문자열·공백·{}·빈 offsets 는 전부 "보정 없음"이다', () {
      for (final text in [null, '', '  \n\t ', '{}', '{"version":1}', '{"version":1,"offsets":{}}']) {
        final o = BadgeOffsets.parse(text);
        expect(o.byKey, isEmpty, reason: 'text=$text');
        expect(o.warnings, isEmpty, reason: 'text=$text');
      }
    });

    test('정상 파일을 읽는다 — 키는 "노선id|종점역명", 값은 앵커→pill 중심 오프셋', () {
      final o = BadgeOffsets.parse('{"version":1,"offsets":{"김포골드|양촌":{"dx":12.5,"dy":-30}}}');
      expect(o.byKey, equals({'김포골드|양촌': const BadgeOffset(12.5, -30)}));
      expect(badgeKey('김포골드', '양촌'), equals('김포골드|양촌'));
    });

    test('문법 오류·형식 오류·미지원 버전은 StateError — 깨진 파일을 "보정 없음"으로 읽지 않는다', () {
      // 조용히 빈 보정으로 읽으면 편집기가 다음 저장에서 사람이 한 보정을 통째로 덮어쓴다.
      expect(() => BadgeOffsets.parse('{ not json'), throwsStateError);
      expect(() => BadgeOffsets.parse('[1,2]'), throwsStateError);
      expect(() => BadgeOffsets.parse('{"version":2,"offsets":{}}'), throwsStateError);
      expect(() => BadgeOffsets.parse('{"version":1,"offsets":[]}'), throwsStateError);
    });

    test('항목 단위 오류(숫자 아님·상한 초과)는 그 항목만 경고와 함께 건너뛴다', () {
      final o = BadgeOffsets.parse(jsonEncode({
        'version': 1,
        'offsets': {
          '2|신설동': {'dx': '3', 'dy': 1}, // 문자열
          '3|오금': {'dx': 1e9, 'dy': 0}, // 오타성 상한 초과
          '4|오이도': {'dx': 5}, // dy 없음
          '5|방화': {'dx': 4, 'dy': -6},
        },
      }));
      expect(o.byKey.keys, equals(['5|방화']));
      expect(o.warnings.length, equals(3));
      expect(o.warnings.join('\n'), allOf(contains('2|신설동'), contains('3|오금'), contains('4|오이도')));
    });

    test('encode 는 키 정렬·1항목 1줄이고 parse 와 왕복한다', () {
      const src = BadgeOffsets({
        '김포골드|양촌': BadgeOffset(12.5, -30),
        '2|신설동': BadgeOffset(-3.25, 7),
      });
      final text = src.encode();
      expect(text.endsWith('}\n'), isTrue);
      expect(text.indexOf('"2|신설동"'), lessThan(text.indexOf('"김포골드|양촌"')), reason: '키 정렬');
      expect(BadgeOffsets.parse(text).byKey, equals(src.byKey));
      expect(BadgeOffsets.parse(BadgeOffsets.empty.encode()).byKey, isEmpty);
      expect(jsonDecode(BadgeOffsets.empty.encode()), equals({'version': 1, 'offsets': {}}));
    });
  });

  group('보정이 없을 때 — 산출물은 도입 전과 같다(1순위 회귀 가드)', () {
    test('빈 보정 입력은 기본 호출과 SVG 조각·요약 로그가 완전히 같고, 수동 정보는 비어 있다', () {
      for (final o in [BadgeOffsets.empty, BadgeOffsets.parse(''), BadgeOffsets.parse('{"version":1,"offsets":{}}')]) {
        final r = solve(o).result;
        expect(r.svgFragment, equals(base.result.svgFragment));
        expect(r.summary, equals(base.result.summary), reason: '보정이 없으면 빌드 로그에 새 줄이 생기지 않는다');
        expect(r.manualCount, equals(0));
        expect(r.offsetWarnings, isEmpty);
        expect(r.manualWarnings, isEmpty);
        expect(r.staleOffsetKeys, isEmpty);
      }
      expect(base.result.placements.length, equals(48));
      expect(base.result.placements.any((p) => p.manual), isFalse);
      expect(base.result.placements.every((p) => p.violations.isEmpty), isTrue);
    });

    test('보정 파일이 없거나 비어 있으면 커밋된 map.html 의 배지 조각이 보정 없는 빌드와 같다', () {
      final f = File(kBadgeOffsetsPath);
      final committed = f.existsSync() ? BadgeOffsets.parse(f.readAsStringSync()) : BadgeOffsets.empty;
      final html = File('assets/html/map.html').readAsStringSync();
      if (committed.byKey.isEmpty) {
        expect(html, contains(base.result.svgFragment),
            reason: 'map.html 이 보정 없는 빌드와 다르다 — dart run tool/build_map_html.dart 를 다시 돌릴 것');
      } else {
        // 보정이 있으면 같은 보정으로 빌드한 조각과 같아야 한다.
        expect(html, contains(solve(committed).result.svgFragment));
      }
    });

    test('프로덕션 map.html 에는 편집기 코드가 없다 — 편집기는 서빙 때만 합성된다', () {
      final html = File('assets/html/map.html').readAsStringSync();
      for (final marker in ['badge-editor', 'be-panel', '/api/solve', '/api/check', '/api/save']) {
        expect(html, isNot(contains(marker)), reason: '프로덕션 HTML 에 편집기 흔적: $marker');
      }
      expect(File('tool/badge_editor/editor.js').readAsStringSync(), isNot(contains('</script')),
          reason: '서빙 시 <script> 안에 인라인되므로 </script 가 있으면 깨진다');
    });
  });

  group('보정이 있을 때', () {
    const key = '김포골드|양촌';
    // 앵커 54px 밖·라벨/역 circle 위 — 하드 위반이 되는 자리(다른 배지에는 영향 없음).
    final bad = one(key, 20, -40);

    test('1건을 넣으면 그 배지만 움직이고 나머지 47개는 좌표 불변', () {
      final r = solve(one(key, 32.5, -13.5)).result; // 위반 없는 자리
      final b0 = byKey(base.result), b1 = byKey(r);
      expect(r.manualCount, equals(1));
      expect(b1[key]!.manual, isTrue);
      expect((b1[key]!.ox, b1[key]!.oy), equals((32.5, -13.5)), reason: '오프셋 = 앵커→pill 중심');
      expect((b1[key]!.ox, b1[key]!.oy), isNot(equals((b0[key]!.ox, b0[key]!.oy))));
      for (final k in b0.keys.where((k) => k != key)) {
        expect(b1[k]!.manual, isFalse, reason: k);
        expect((b1[k]!.ox, b1[k]!.oy), equals((b0[k]!.ox, b0[k]!.oy)), reason: '$k 는 자동 배치 그대로여야 한다');
        expect((b1[k]!.anchorX, b1[k]!.anchorY), equals((b0[k]!.anchorX, b0[k]!.anchorY)));
      }
      // 렌더 조각도 그 배지의 <g> 하나만 다르다.
      List<String> groups(String f) => f.split('\n').where((l) => l.startsWith('<g class="lb"')).toList();
      final g0 = groups(base.result.svgFragment), g1 = groups(r.svgFragment);
      expect(g1.length, equals(48));
      expect([for (var i = 0; i < 48; i++) if (g0[i] != g1[i]) i].length, equals(1));
      // 앵커 기준 상대 오프셋이다 — 앵커(<g transform>)는 그대로.
      expect(b1[key]!.anchorX, equals(b0[key]!.anchorX));
    });

    test('수동 배치가 하드 위반이어도 빌드는 실패하지 않고, 노선·종점·위반 종류·수치가 경고에 남는다', () {
      final r = solve(bad).result; // 던지지 않는다
      expect(r.unresolvedCount, equals(0), reason: '자동 배지 미해결과 무관');
      expect(r.manualWarnings.length, equals(1));
      final w = r.manualWarnings.single;
      expect(w, allOf(contains('경고'), contains('김포골드'), contains('양촌'), contains('(20,-40)')));
      expect(w, contains('역명 라벨'), reason: '위반 종류');
      expect(w, contains('px²'), reason: '겹침 수치');
      expect(w, contains('앵커에서 너무 멂'), reason: '앵커 24px 규칙도 경고로만 처리');
      expect(r.summary.any((l) => l.startsWith('수동 보정 배지: 1개 [김포골드|양촌]')), isTrue);
      expect(r.summary.any((l) => l.startsWith('경고: 수동 보정 배지')), isTrue);
      expect(byKey(r)[key]!.violations, isNotEmpty);
      expect(byKey(r)[key]!.violations.every((v) => !v.soft), isTrue);
    });

    test('수동 배치가 자리를 막아 자동 배지가 하드 위반을 못 피하면 여전히 빌드 실패 — 자동 배지의 실패 정책은 그대로', () {
      // 신설동 허브(2호선·우이신설 배지)의 유일한 좁은 틈을 2호선 수동 배지가 차지한다.
      expect(
        () => solve(one('2|신설동', 22, -24.5)),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('미해결 배지'), contains('우이신설'), contains('수동 보정'), contains('2|신설동')),
        )),
      );
    });

    test('자동 배지는 수동 배지를 장애물로 피한다 — 수동 배지가 놓인 자리에서 비켜난다', () {
      // 5호선·9호선 종점 앵커가 40px 간격으로 이웃해 있다. 5호선 배지를 9호선 자동 배지 자리에 얹으면
      // 9호선 배지가 비켜나야 하고(자리가 있는 곳), 수동 배지는 움직이지 않는다.
      final p5 = base.result.placements.firstWhere((p) => p.lineId == '5' && p.anchorX == 328 && p.anchorY == 336);
      final p9 = base.result.placements.firstWhere((p) => p.lineId == '9' && p.anchorX == 288 && p.anchorY == 336);
      final dx = p9.anchorX + p9.ox - p5.anchorX, dy = p9.anchorY + p9.oy - p5.anchorY;
      final r = solve(one(p5.key, dx, dy)).result;
      final m = byKey(r);
      expect((m[p5.key]!.ox, m[p5.key]!.oy), equals((dx, dy)), reason: '수동 배지는 그대로');
      expect((m[p9.key]!.ox, m[p9.key]!.oy), isNot(equals((p9.ox, p9.oy))), reason: '자동 배지가 비켜났다');
      expect(m[p9.key]!.manual, isFalse);
      expect(m[p9.key]!.violations, isEmpty);
      expect(r.summary.any((l) => l.contains('배지↔배지 0쌍')), isTrue);
      expect(r.unresolvedCount, equals(0));
    });
  });

  group('잘못된 키 — 조용히 무시하지 않고 경고 + 자동 배치 폴백', () {
    test('없는 노선·없는 종점·잘못된 형식은 경고하고 그 항목을 버린다 — 결과는 보정 없는 빌드와 같다', () {
      final r = solve(const BadgeOffsets({
        '없는노선|없는역': BadgeOffset(1, 2),
        '2|없는역': BadgeOffset(3, 4), // 노선은 있고 종점이 틀림
        '김포골드': BadgeOffset(5, 6), // '|' 없음
      })).result;
      expect(r.svgFragment, equals(base.result.svgFragment), reason: '전부 자동 배치로 떨어진다');
      expect(r.manualCount, equals(0));
      expect(r.staleOffsetKeys, equals(['없는노선|없는역', '2|없는역', '김포골드']));
      expect(r.offsetWarnings.length, equals(3));
      final all = r.offsetWarnings.join('\n');
      expect(all, contains('"없는노선|없는역" 가 현재 배지에 없다'));
      expect(all, contains('"2|신설동"'), reason: '같은 노선의 현재 키를 알려 준다');
      expect(all, contains('"2|까치산"'));
      expect(r.summary.any((l) => l.startsWith('경고: 수동 보정 키 "없는노선|없는역"')), isTrue);
      expect(r.unresolvedCount, equals(0));
    });

    test('유효한 키와 잘못된 키가 섞이면 유효한 것만 적용된다', () {
      final r = solve(const BadgeOffsets({
        '김포골드|양촌': BadgeOffset(32.5, -13.5),
        '2|없는역': BadgeOffset(3, 4),
      })).result;
      expect(r.manualCount, equals(1));
      expect(byKey(r)['김포골드|양촌']!.manual, isTrue);
      expect(r.staleOffsetKeys, equals(['2|없는역']));
    });

    test('파싱 단계 경고(값 오류)가 빌드 요약에 그대로 나온다', () {
      final o = BadgeOffsets.parse('{"version":1,"offsets":{"3|오금":{"dx":"x","dy":1}}}');
      final r = solve(o).result;
      expect(r.manualCount, equals(0));
      expect(r.offsetWarnings.single, contains('3|오금'));
      expect(r.summary.any((l) => l.startsWith('경고: 수동 보정 "3|오금"')), isTrue);
    });
  });

  group('편집기 즉시 판정 check() — 빌드와 같은 규칙', () {
    test('빌드가 낸 경고와 같은 위반을 같은 위치에서 낸다', () {
      final built = solve(one('김포골드|양촌', 20, -40));
      final built0 = byKey(built.result)['김포골드|양촌']!.violations.map((v) => v.message).toList();
      final checked = base.check('김포골드|양촌', 20, -40).violations.map((v) => v.message).toList();
      expect(checked, equals(built0), reason: '같은 함수(_hard)를 쓰므로 메시지·수치까지 같아야 한다');
      expect(checked.any((m) => m.contains('역명 라벨')), isTrue);
    });

    test('자동 위치에서는 위반이 없고, 호출은 상태를 바꾸지 않는다', () {
      final p = byKey(base.result)['김포골드|양촌']!;
      final before = base.result.svgFragment;
      expect(base.check('김포골드|양촌', p.ox, p.oy).violations, isEmpty);
      base.check('김포골드|양촌', 20, -40); // 위반 자리로 한 번 찔러 본다
      expect(base.check('김포골드|양촌', p.ox, p.oy).violations, isEmpty, reason: '복원됨');
      expect(base.result.svgFragment, equals(before));
    });

    test('자동 배지와 겹치면 soft(저장하면 비켜남), 타 노선 선·라벨 등은 hard', () {
      // 2호선 신설동 배지를 우이신설 신설동 자동 배지 자리로.
      final u = byKey(base.result)['우이신설|신설동']!;
      final t = byKey(base.result)['2|신설동']!;
      final r = base.check('2|신설동', u.anchorX + u.ox - t.anchorX, u.anchorY + u.oy - t.anchorY);
      final badge = r.violations.where((v) => v.kind == 'badge').toList();
      expect(badge, isNotEmpty);
      expect(badge.every((v) => v.soft), isTrue);
      expect(badge.first.otherKey, equals('우이신설|신설동'));
      expect(badge.first.message, contains('우이신설/신설동'));
    });

    test('알 수 없는 키는 ArgumentError', () {
      expect(() => base.check('없는노선|없는역', 0, 0), throwsArgumentError);
    });

    test('모델 JSON 은 48개 배지의 키·오프셋·위반을 담는다', () {
      final m = base.toJson();
      final badges = (m['badges'] as List).cast<Map<String, dynamic>>();
      expect(badges.length, equals(48));
      expect(badges.map((b) => b['key']).toSet().length, equals(48), reason: '키는 배지마다 유일');
      expect(badges.every((b) => (b['key'] as String).contains('|')), isTrue);
      expect(badges.every((b) => b['manual'] == false), isTrue);
      expect(() => jsonEncode(m), returnsNormally);
    });
  });
}
