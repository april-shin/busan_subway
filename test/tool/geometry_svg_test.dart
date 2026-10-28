// 지오메트리 편집기(tool/geometry_svg.dart) — 선분 정점·환승 마커 편집의 순수 로직.
//
// 1순위: 편집하지 않은 부분은 **바이트 동일**(한 줄짜리 SVG 의 diff 가 의도한 태그만 보인다), 흰색 이중선 동기화,
// 정점 추가·삭제/이중선 직접 편집/규격 밖 마커 거부, 12px 가드(브랜치 station_svg_coords_test 와 같은 계산)·4px 소프트 층·마커 드리프트.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/geometry_svg.dart';

void main() {
  final svg = File('assets/svg/seoul_metro_map.svg').readAsStringSync();
  final stations = jsonDecode(File('assets/json/stations.json').readAsStringSync()) as List<dynamic>;
  final doc = GeometryDoc.parse(svg);

  group('파싱', () {
    test('실제 SVG: path 36 · rect 56, 전부 M/L 폴리라인', () {
      expect(doc.paths.length, 36);
      expect(doc.rects.length, 56);
      for (final p in doc.paths) {
        expect(p.points.length, greaterThanOrEqualTo(2), reason: 'path #${p.index}');
      }
    });

    test('흰색 이중선은 GTX-A(1-GA-1)·경춘(G-1) 두 쌍(path 4개)이고 각각 본체와 d 가 같다', () {
      final whites = doc.paths.where((p) => p.isWhite).toList();
      expect(whites.map((p) => p.code).toSet(), {'1-GA-1', 'G-1'});
      expect(whites.length, 4);
      var twinned = 0;
      for (final p in doc.paths) {
        if (p.isWhite) {
          expect(doc.isEditablePath(p.index), isFalse);
          continue;
        }
        twinned += doc.twinsOf(p.index).length;
      }
      expect(twinned, 4, reason: '본체가 이중선 4개를 모두 하나씩 거느린다');
    });

    test('M/L 외 명령이 있으면 거부(build_map_html 도 하드페일하는 입력)', () {
      expect(() => GeometryDoc.parse('<svg><path d="M 0 0 C 1 1 2 2 3 3" data-line="X" /></svg>'), throwsStateError);
      expect(() => GeometryDoc.parse('<svg><path d="M 0 0 L 1 1 Z" data-line="X" /></svg>'), throwsStateError);
    });
  });

  group('편집 적용', () {
    test('원래 값 그대로의 편집은 SVG 를 바꾸지 않는다(바이트 동일)', () {
      final same = {for (final p in doc.paths.where((p) => doc.isEditablePath(p.index))) p.index: p.points};
      final rects = {for (final r in doc.rects) r.index: RectEdit(r.x, r.y, r.w, r.h)};
      expect(applyGeometryEdits(doc, pathEdits: same, rectEdits: rects), svg);
    });

    test('정점 하나만 옮기면 본체 + 흰 이중선 태그만 바뀌고 나머지는 바이트 동일', () {
      // 경춘선 본체(G)의 첫 path.
      final body = doc.paths.firstWhere((p) => p.code == 'G' && !p.isWhite);
      final twins = doc.twinsOf(body.index);
      expect(twins, hasLength(1));
      final pts = [...body.points];
      pts[3] = (pts[3].$1 + 8, pts[3].$2 - 4);
      final out = applyGeometryEdits(doc, pathEdits: {body.index: pts});

      final redoc = GeometryDoc.parse(out);
      expect(redoc.paths[body.index].points[3], pts[3]);
      expect(redoc.paths[twins.single].points[3], pts[3], reason: '흰 이중선도 같은 정점이 움직여야 한다');
      expect(redoc.paths[twins.single].d, redoc.paths[body.index].d);
      // 다른 정점은 그대로.
      for (var k = 0; k < pts.length; k++) {
        if (k == 3) continue;
        expect(redoc.paths[body.index].points[k], body.points[k]);
      }
      // 바뀐 태그(본체+이중선)를 빼면 문서 전체가 동일하다.
      String strip(String s, GeometryDoc d) {
        var t = s;
        for (final i in ([body.index, ...twins]..sort()).reversed) {
          t = t.replaceRange(d.paths[i].start, d.paths[i].end, '');
        }
        return t;
      }

      expect(strip(out, redoc), strip(svg, doc));
      // 원본 d 의 안 바뀐 토큰 서식("2048.0" 같은 `N.0` 표기)이 보존된다.
      //
      // ⚠ 좌표를 상수로 박지 말 것. 이 선분은 **편집기로 옮기라고 있는 값**이라,
      // 사용자가 지도를 고치면 테스트가 깨진다 — 2026-10-28 경춘선 정점을 옮기자
      // 실제로 `L 1584.0 416.0` 하드코딩이 깨졌다. 원본 `d` 에서 안 바뀐 정점의
      // 토큰을 그대로 뽑아 비교한다.
      final origTokens = body.d.split(' L ');
      expect(redoc.paths[body.index].d, contains(origTokens[1]),
          reason: '안 바뀐 정점(${origTokens[1]})은 원본 토큰 서식 그대로여야 한다');
    });

    test('정점 수가 다르거나 이중선을 직접 편집하거나 캔버스 밖이면 거부', () {
      final body = doc.paths.firstWhere((p) => p.code == '3-2' && !p.isWhite);
      expect(() => applyGeometryEdits(doc, pathEdits: {body.index: body.points.sublist(1)}), throwsArgumentError);
      expect(() => applyGeometryEdits(doc, pathEdits: {body.index: [...body.points, (1.0, 1.0)]}), throwsArgumentError);
      final white = doc.paths.firstWhere((p) => p.isWhite);
      expect(() => applyGeometryEdits(doc, pathEdits: {white.index: white.points}), throwsArgumentError);
      expect(() => applyGeometryEdits(doc, pathEdits: {999: body.points}), throwsArgumentError);
      final off = [...body.points]..[0] = (5000.0, 10.0);
      expect(() => applyGeometryEdits(doc, pathEdits: {body.index: off}), throwsArgumentError);
      final nan = [...body.points]..[0] = (double.nan, 10.0);
      expect(() => applyGeometryEdits(doc, pathEdits: {body.index: nan}), throwsArgumentError);
    });

    test('마커: 이동·방향·길이 변경은 그 rect 태그만 바꾼다', () {
      final r = doc.rects.firstWhere((r) => r.w == 16 && r.h == 8);
      // 가로 16×8 → 세로 8×20, 중심 유지.
      final cx = r.x + r.w / 2, cy = r.y + r.h / 2;
      final out = applyGeometryEdits(doc, rectEdits: {r.index: RectEdit(cx - 4, cy - 10, 8, 20)});
      final re = GeometryDoc.parse(out).rects[r.index];
      expect((re.x, re.y, re.w, re.h), (cx - 4, cy - 10, 8.0, 20.0));
      expect(out.replaceRange(re.start, re.end, ''), svg.replaceRange(r.start, r.end, ''));
      expect(re.tag, contains('rx="4" ry="4"'), reason: 'rx/ry/style 은 건드리지 않는다');
    });

    test('마커: 규격 밖 크기·캔버스 밖 거부, 기존 비규격 마커는 크기를 안 바꾸면 이동 가능', () {
      final r = doc.rects.first;
      expect(() => applyGeometryEdits(doc, rectEdits: {r.index: RectEdit(r.x, r.y, 13, 8)}), throwsArgumentError);
      expect(() => applyGeometryEdits(doc, rectEdits: {r.index: RectEdit(-1, r.y, r.w, r.h)}), throwsArgumentError);
      expect(() => applyGeometryEdits(doc, rectEdits: {500: RectEdit(1, 1, 8, 8)}), throwsArgumentError);
      final odd = doc.rects.firstWhere((r) => !isStandardMarkerSize(r.w, r.h));
      expect(
        () => applyGeometryEdits(doc, rectEdits: {odd.index: RectEdit(odd.x + 4, odd.y, odd.w, odd.h)}),
        returnsNormally,
      );
      expect(isStandardMarkerSize(8, 8), isTrue);
      expect(isStandardMarkerSize(28, 8), isTrue);
      expect(isStandardMarkerSize(8, 20), isTrue);
      expect(isStandardMarkerSize(12, 12), isFalse);
    });

    test('fmtNum — 원본과 같은 꼴(정수는 N.0)·부동소수 잡음 제거', () {
      expect(fmtNum(2048), '2048.0');
      expect(fmtNum(861.6), '861.6');
      expect(fmtNum(9.599999999999909), '9.6');
      expect(fmtNum(-3), '-3.0');
    });

    test('svgRevision — 같은 내용은 같고 한 글자만 달라도 다르다', () {
      expect(svgRevision(svg), svgRevision(String.fromCharCodes(svg.codeUnits)));
      final changed = applyGeometryEdits(doc, rectEdits: {0: RectEdit(doc.rects[0].x + 4, doc.rects[0].y, doc.rects[0].w, doc.rects[0].h)});
      expect(svgRevision(changed), isNot(svgRevision(svg)));
    });
  });

  // ⚠️ 이 그룹의 첫 테스트가 **main 의 유일한 "역이 선로 위" 가드**다. `test/data/station_svg_coords_test.dart` 는 아직 main 에
  // 없고 브랜치 `fix/line8-jangja-svg-coord`(aa3b249)에만 있다. 선분을 옮긴 뒤 커밋하면 이 테스트가 깨지는 구조이므로,
  // 이 테스트를 지우거나 허용 집합(`{'장자호수공원|8'}`)을 늘리는 것은 그 가드를 푸는 일이다.
  //
  // 브랜치 병합 시 통합 방법(병합 자체는 사용자 결정 사항 — 이 작업에서는 하지 않았다): 브랜치 테스트의 `_maxTrackDistance` ·
  // `_sharedTransferMarkers` · `_linePathIds` · `_distanceToSegment` 를 지우고, 이 파일이 쓰는
  // `kMaxTrackDistance` · `kSharedTransferMarkers` · `kLineIdToDataLine`(tool/line_badges.dart) · `findOffLineStations`
  // (tool/geometry_svg.dart)를 import 해 쓴다. 두 구현은 규칙이 동일함을 확인했다(2026-10-28 대조) — 단일 소스로 합쳐
  // 규칙이 한쪽만 바뀌어 편집기 경고와 CI 판정이 갈라지는 일을 막을 것.
  group('선로 이탈 가드 — 12px 하드 (브랜치 station_svg_coords_test 와 같은 계산)', () {
    test('현재 SVG: 이탈은 장자호수공원(stations.json 좌표 드리프트, 선분과 무관)뿐이다', () {
      final off = findOffLineStations(polylinesByCode(doc), stations);
      // 편집기가 "원래부터" 로 구분해 보여 주는 기존 이탈. 이 목록이 늘면 SVG 나 stations.json 이 어긋난 것이다.
      expect(off.map((o) => o.key).toSet().difference({'장자호수공원|8'}), isEmpty, reason: off.map((o) => o.toJson()).toString());
    });

    test('선을 멀리 옮기면 그 노선 역들이 이탈로 잡힌다', () {
      final body = doc.paths.firstWhere((p) => p.code == '3-2' && !p.isWhite && p.points.length > 20);
      final moved = [for (final q in body.points) (q.$1, q.$2 + 40)];
      final off = findOffLineStations(polylinesByCode(doc, {body.index: moved}), stations);
      expect(off.where((o) => o.lineId == '2'), isNotEmpty);
      expect(off.first.dist, greaterThanOrEqualTo(off.last.dist), reason: '거리 내림차순');
    });

    test('경계: 12px 이내는 통과, 넘으면 이탈 · 공유 환승 마커 3건은 면제', () {
      final line = <String, List<List<Pt>>>{
        '3-2': [
          [(0.0, 0.0), (100.0, 0.0)],
        ],
      };
      List<dynamic> st(double y) => [
            {'name': 'A', 'lineId': '2', 'svgX': 50, 'svgY': y},
          ];
      expect(findOffLineStations(line, st(12)), isEmpty);
      expect(findOffLineStations(line, st(12.1)), hasLength(1));
      final shared = [
        {'name': '서울역', 'lineId': '경의중앙', 'svgX': 5000, 'svgY': 5000},
        {'name': '김포공항', 'lineId': '9', 'svgX': 5000, 'svgY': 5000},
      ];
      expect(findOffLineStations({'K': line['3-2']!, '10-9': line['3-2']!}, shared), isEmpty);
    });
  });

  group('선로 이탈 가드 — 4px 소프트 층(12px 하드는 그대로)', () {
    final line = <String, List<List<Pt>>>{
      '3-2': [
        [(0.0, 0.0), (100.0, 0.0)],
      ],
    };
    List<dynamic> st(double y) => [
          {'name': 'A', 'lineId': '2', 'svgX': 50, 'svgY': y},
        ];

    test('경계: 4.0 이하는 무경고, 4 초과~12 는 소프트, 12 초과는 하드 — 서로 겹치지 않는다', () {
      OffLineTiers t(double y) => findOffLineTiers(line, st(y));
      expect(t(4).hard, isEmpty);
      expect(t(4).soft, isEmpty);
      expect(t(4.1).soft, hasLength(1));
      expect(t(4.1).hard, isEmpty);
      expect(t(12).soft, hasLength(1), reason: '정확히 12.0 은 하드가 아니라 소프트(하드 판정 `> 12` 불변)');
      expect(t(12).hard, isEmpty);
      expect(t(12.1).hard, hasLength(1));
      expect(t(12.1).soft, isEmpty);
    });

    test('하드 목록은 기존 findOffLineStations(기본 12px)와 똑같다', () {
      final all = findOffLineTiers(polylinesByCode(doc), stations);
      final legacy = findOffLineStations(polylinesByCode(doc), stations);
      expect([for (final o in all.hard) o.key], [for (final o in legacy) o.key]);
      expect(all.hard.every((o) => o.hard), isTrue);
      expect(all.soft.every((o) => !o.hard && o.dist > kSoftTrackDistance), isTrue);
    });

    test('핵심 시나리오: 망우 부근 경춘(G)을 8px 올려 경의중앙(K)과 떼면 망우·중랑이 정확히 12.0px — 하드는 침묵, 소프트가 잡는다', () {
      final g = doc.paths.where((p) => p.code == 'G' && !p.isWhite).toList();
      expect(g, isNotEmpty);
      final edits = {
        for (final p in g) p.index: [for (final q in p.points) (q.$1, q.$2 - 8)],
      };
      final before = findOffLineTiers(polylinesByCode(doc), stations);
      final after = findOffLineTiers(polylinesByCode(doc, edits), stations);
      expect(after.hard.map((o) => o.key).toSet(), before.hard.map((o) => o.key).toSet(), reason: '하드(12px)는 새로 걸리지 않는다 — 이 구멍이 소프트 층의 존재 이유');
      final mangu = after.soft.firstWhere((o) => o.key == '망우|경춘');
      expect(mangu.dist, closeTo(12.0, 1e-6));
      expect(before.soft.any((o) => o.key == '망우|경춘'), isFalse, reason: '편집 전엔 4px — 소프트도 아님');
      expect(after.soft.where((o) => o.lineId == '경춘').length, greaterThan(5));
    });
  });

  group('환승 마커 ↔ stations.json 좌표 드리프트', () {
    SvgRect rectAt(double cx, double cy) =>
        doc.rects.firstWhere((r) => (r.x + r.w / 2 - cx).abs() < 1e-6 && (r.y + r.h / 2 - cy).abs() < 1e-6);
    RectEdit moved(SvgRect r, double dx, double dy) => RectEdit(r.x + dx, r.y + dy, r.w, r.h);

    // ⚠️ 이 테스트가 "마커를 옮겨 커밋하면 stations.json 도 같이 고치라"를 강제하는 **영속 가드**다(편집기 세션 경고는
    // 저장 시점 1회뿐이고 앵커 반경 밖으로 크게 옮기면 침묵한다). 이전 버전은 항등 편집(원래 값 그대로)을 넣어 d1 == d0 이라
    // 어떤 데이터에서도 통과하는 공허한 검사였다 — 아래는 실제 거리를 센다.
    test('실측 전제: 56개 마커 전부 앵커 역을 갖고, 거리 분포는 ≤0.5px 54 · 0.5~14px 2(김포공항·왕십리) · >14px 0', () {
      expect(doc.rects.length, 56);
      // (1) 앵커 판정과 독립: 마커 중심 ↔ stations.json 의 **가장 가까운 역** 거리.
      var exact = 0, loose = 0, far = 0;
      final looseIdx = <int>[];
      final nearest = <int, double>{};
      for (final r in doc.rects) {
        final cx = r.x + r.w / 2, cy = r.y + r.h / 2;
        var best = double.infinity;
        for (final s in stations.cast<Map>()) {
          final dx = (s['svgX'] as num) - cx, dy = (s['svgY'] as num) - cy;
          final d = math.sqrt(dx * dx + dy * dy);
          if (d < best) best = d;
        }
        nearest[r.index] = best;
        if (best <= 0.5) {
          exact++;
        } else if (best <= 14) {
          loose++;
          looseIdx.add(r.index);
        } else {
          far++;
        }
      }
      expect((exact, loose, far), (54, 2, 0), reason: '마커를 옮기거나 stations.json 좌표를 바꿨다면 둘을 같이 맞출 것');
      // 0.5~14px 두 건은 **의도된** 어긋남이다.
      //  - 김포공항: `extract_svg_stations` 가 캡슐 옆 원형 dot 을 더 가깝다고 골라 5개
      //    노선 좌표가 dot 에 잡혔다(12.00px). 예전부터 그랬다.
      //  - 왕십리: 2026-10-28 사용자가 수인분당선 선분을 옮겨 역에서 8px 떨어지자,
      //    `<circle>` 환승 동그라미를 24×8 가로 알약으로 바꿔 네 노선(2·5·경의중앙·
      //    수인분당)을 다시 묶었다. 보기 좋은 자리를 우선해 중심을 (1576,600) →
      //    (1580,608) 로 옮겼으므로 stations.json 좌표와 8.94px 어긋난다.
      //    ⚠ `extract_svg_stations` 를 재실행하면 왕십리 좌표가 이 알약 중심으로
      //    끌려가고, **네 노선이 그 좌표를 공유**하므로 같이 움직인다. 돌리지 말 것.
      expect({for (final i in looseIdx) i},
          {rectAt(328, 532).index, rectAt(1580, 608).index},
          reason: '0.5~14px 은 김포공항 캡슐과 왕십리 알약 둘뿐');
      // 칸 수와 index 만 보면 **대역 안에서 더 멀어지는 것**을 못 잡는다 — 김포공항을
      // 2px, 왕십리를 5px 더 옮겨도 여전히 0.5~14px 칸이라 통과해 버린다. 거리 자체를
      // 고정해 그 경로를 막는다. 값을 바꿔야 한다면 **왜 더 멀어져도 되는지**를 먼저
      // 여기 주석에 적을 것.
      expect(nearest[rectAt(328, 532).index], closeTo(12.0, 0.01),
          reason: '김포공항 캡슐 ↔ 역 좌표');
      expect(nearest[rectAt(1580, 608).index], closeTo(8.944, 0.01),
          reason: '왕십리 알약 ↔ 역 좌표');

      // (2) 앵커/고아 판정: 전 마커가 앵커를 갖고, 12px 대역의 앵커는 김포공항 5개 노선 레코드뿐이다.
      final anchors = markerAnchors(doc.rects, stations);
      expect(orphanMarkers(doc.rects, stations), isEmpty, reason: '앵커 없는 마커 = SVG ↔ stations.json 드리프트');
      expect(anchors.length, doc.rects.length);
      final looseAnchors = {
        for (final e in anchors.entries)
          for (final a in e.value)
            if (a.d0 > 0.5) '${a.name}|${a.lineId}',
      };
      expect(looseAnchors, {
        '김포공항|5', '김포공항|9', '김포공항|공항철도', '김포공항|서해', '김포공항|김포골드',
        '왕십리|2', '왕십리|5', '왕십리|경의중앙', '왕십리|수인분당',
      });
    });

    test('가드가 공허하지 않다: 마커를 앵커 반경(14px) 밖으로 옮겨 저장한 SVG 는 고아 마커로 잡힌다(findMarkerDrift 는 침묵)', () {
      for (final dist in [8.0, 16.0, 32.0, 200.0]) {
        final r = rectAt(1040, 618); // 서울역 캡슐(역 레코드 3개가 앵커)
        final movedSvg = applyGeometryEdits(doc, rectEdits: {r.index: moved(r, dist, 0)});
        final reloaded = GeometryDoc.parse(movedSvg); // 새 세션: 디스크 SVG 를 다시 읽는다
        final orphans = orphanMarkers(reloaded.rects, stations);
        if (dist <= kMarkerAnchorRadius) {
          // 반경 안이면 환승역이라 여전히 앵커 — 이 대역은 저장 시점 findMarkerDrift 가 맡는다.
          expect(orphans, isEmpty, reason: '${dist}px');
        } else {
          expect(orphans, [r.index], reason: '${dist}px 옮겨 저장한 뒤 새 세션에서도 고아로 잡혀야 한다');
          // 이동량 기준 경고는 새 세션에서 옮긴 마커를 더 옮겨도 침묵한다(앵커 소실) — 영속 신호가 따로 있는 이유.
          final r2 = reloaded.rects[r.index];
          expect(findMarkerDrift(reloaded.rects, {r2.index: moved(r2, 32, 0)}, stations), isEmpty);
        }
      }
    });

    test('nearestStation — 고아 마커 안내용(가장 가까운 역)', () {
      final n = nearestStation(1040, 618, stations)!;
      expect(n['name'], '서울역');
      expect(n['dist'], 0.0);
      expect(nearestStation(0, 0, const []), isNull);
    });

    test('서울역 마커를 16px 옮기면 그 마커에 앵커된 역들이 어긋남으로 잡힌다 · 공유 캡슐', () {
      final r = rectAt(1040, 618);
      final d = findMarkerDrift(doc.rects, {r.index: moved(r, 16, 0)}, stations);
      expect(d, hasLength(1));
      expect(d.single.index, r.index);
      expect(d.single.dist, closeTo(16, 1e-6));
      expect(d.single.shared, isTrue, reason: '서울역|경의중앙 은 12px 선로 가드가 면제하는 공유 캡슐');
      expect(d.single.stations.map((s) => s.name).toSet(), {'서울역'});
      expect(d.single.stations.map((s) => s.lineId), containsAll(['1', '4', '경의중앙']));
    });

    test('길이·방향 변경은 중심을 보존하므로 어긋나지 않는다(미금 16×9.6 → 8×16 포함)', () {
      final a = rectAt(1040, 618); // 8×28 → 28×8 중심 보존
      final b = rectAt(1700, 1335.2); // 규격 밖 16×9.6
      final edits = {
        a.index: RectEdit(1040 - 14, 618 - 4, 28, 8),
        b.index: RectEdit(1700 - 4, 1335.2 - 8, 8, 16),
      };
      expect(findMarkerDrift(doc.rects, edits, stations), isEmpty);
    });

    test('0.25px 이하의 미세 이동은 허용 오차로 무시, 그 이상은 보고', () {
      final r = rectAt(1040, 618);
      expect(findMarkerDrift(doc.rects, {r.index: moved(r, 0.25, 0)}, stations), isEmpty);
      expect(findMarkerDrift(doc.rects, {r.index: moved(r, 0.5, 0)}, stations), hasLength(1));
    });

    test('김포공항 캡슐(#40)은 역 좌표가 12px 옆이다 — 역 위로 옮기면 무사, 더 멀어질 때만 어긋남', () {
      final r = rectAt(328, 532);
      final gimpo = stations.cast<Map>().firstWhere((s) => s['name'] == '김포공항' && s['lineId'] == '9');
      final sx = (gimpo['svgX'] as num).toDouble(), sy = (gimpo['svgY'] as num).toDouble();
      // 마커 중심을 김포공항 역 좌표 위로(거리 12 → 0): 보고 없음.
      expect(findMarkerDrift(doc.rects, {r.index: moved(r, sx - 328, sy - 532)}, stations), isEmpty);
      // 역에서 12px 반대편으로 멀리(거리 12 → 24 이상): 보고, 공유 캡슐.
      final away = findMarkerDrift(doc.rects, {r.index: moved(r, (328 - sx) * 2, (532 - sy) * 2)}, stations);
      expect(away, hasLength(1));
      expect(away.single.shared, isTrue);
      expect(away.single.stations.every((s) => s.name == '김포공항'), isTrue);
    });

    test('편집하지 않은 마커·없는 index 는 결과에 없다', () {
      final r = rectAt(1040, 618);
      expect(findMarkerDrift(doc.rects, const {}, stations), isEmpty);
      final d = findMarkerDrift(doc.rects, {r.index: moved(r, 40, 0), 9999: RectEdit(0, 0, 8, 8)}, stations);
      expect(d.map((x) => x.index), [r.index]);
    });
  });

  test('편집기 에셋은 </script 를 담지 않는다(서버가 <script> 로 인라인한다)', () {
    for (final f in ['editor.js', 'geometry.js']) {
      expect(File('tool/badge_editor/$f').readAsStringSync().contains('</script'), isFalse, reason: f);
    }
  });
}
