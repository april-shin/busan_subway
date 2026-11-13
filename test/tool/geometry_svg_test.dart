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
  final svg = File('assets/svg/busan_metro_map.svg').readAsStringSync();
  final stations = jsonDecode(File('assets/json/stations.json').readAsStringSync()) as List<dynamic>;
  final doc = GeometryDoc.parse(svg);

  group('파싱', () {
    test('실제 SVG: path 6(노선당 1개) · rect 12(환승 물리 역 12곳), 전부 M/L 폴리라인', () {
      expect(doc.paths.length, 6);
      expect(doc.paths.map((p) => p.code).toSet(), {'B1', 'B2', 'B3', 'B4', 'DH', 'BG'});
      expect(doc.rects.length, 12);
      for (final p in doc.paths) {
        expect(p.points.length, greaterThanOrEqualTo(2), reason: 'path #${p.index}');
      }
    });

    test('부산 SVG 에는 흰색 이중선이 없다 — 6개 path 모두 편집 가능한 본체', () {
      expect(doc.paths.where((p) => p.isWhite), isEmpty);
      for (final p in doc.paths) {
        expect(doc.isEditablePath(p.index), isTrue, reason: p.code);
        expect(doc.twinsOf(p.index), isEmpty, reason: p.code);
      }
    });

    test('이중선 로직은 합성 SVG 로 계속 검증한다 — 본체 `X` 와 같은 d 의 흰 `X-1` 은 본체가 거느린다', () {
      const body = '<path d="M 10.0 10.0 L 100.0 10.0 L 100.0 60.0" fill="none" stroke="#ff0000" stroke-width="3" data-line="X" />';
      const white = '<path d="M 10.0 10.0 L 100.0 10.0 L 100.0 60.0" fill="none" stroke="#ffffff" stroke-width="1" data-line="X-1" />';
      final d = GeometryDoc.parse('<svg viewBox="0 0 2416.0 1560.0">$body$white</svg>');
      expect(d.paths[1].isWhite, isTrue);
      expect(d.isEditablePath(1), isFalse);
      expect(d.twinsOf(0), [1]);
      final out = applyGeometryEdits(d, pathEdits: {
        0: [(10.0, 10.0), (100.0, 10.0), (100.0, 70.0)],
      });
      final re = GeometryDoc.parse(out);
      expect(re.paths[0].points.last, (100.0, 70.0));
      expect(re.paths[1].points.last, (100.0, 70.0), reason: '흰 이중선도 같이 움직인다');
      expect(re.paths[1].d, re.paths[0].d);
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

    test('정점 하나만 옮기면 본체(+있다면 흰 이중선) 태그만 바뀌고 나머지는 바이트 동일', () {
      // 4호선 본체(B4).
      final body = doc.paths.firstWhere((p) => p.code == 'B4' && !p.isWhite);
      final twins = doc.twinsOf(body.index);
      expect(twins, isEmpty, reason: '부산에는 흰 이중선이 없다');
      final pts = [...body.points];
      pts[3] = (pts[3].$1 + 8, pts[3].$2 - 4);
      final out = applyGeometryEdits(doc, pathEdits: {body.index: pts});

      final redoc = GeometryDoc.parse(out);
      expect(redoc.paths[body.index].points[3], pts[3]);
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
      // 사용자가 지도를 고치면 테스트가 깨진다. 원본 `d` 에서 안 바뀐 정점의
      // 토큰을 그대로 뽑아 비교한다.
      final origTokens = body.d.split(' L ');
      expect(redoc.paths[body.index].d, contains(origTokens[1]),
          reason: '안 바뀐 정점(${origTokens[1]})은 원본 토큰 서식 그대로여야 한다');
    });

    test('정점 수가 다르거나 이중선을 직접 편집하거나 캔버스 밖이면 거부', () {
      final body = doc.paths.firstWhere((p) => p.code == 'B2' && !p.isWhite);
      expect(() => applyGeometryEdits(doc, pathEdits: {body.index: body.points.sublist(1)}), throwsArgumentError);
      expect(() => applyGeometryEdits(doc, pathEdits: {body.index: [...body.points, (1.0, 1.0)]}), throwsArgumentError);
      const withWhite =
          '<svg viewBox="0 0 2416.0 1560.0"><path d="M 1.0 1.0 L 9.0 1.0" stroke="#ffffff" data-line="X-1" /></svg>';
      final wd = GeometryDoc.parse(withWhite);
      expect(() => applyGeometryEdits(wd, pathEdits: {0: wd.paths[0].points}), throwsArgumentError,
          reason: '흰 이중선은 직접 편집할 수 없다');
      expect(() => applyGeometryEdits(doc, pathEdits: {999: body.points}), throwsArgumentError);
      final off = [...body.points]..[0] = (5000.0, 10.0);
      expect(() => applyGeometryEdits(doc, pathEdits: {body.index: off}), throwsArgumentError);
      final nan = [...body.points]..[0] = (double.nan, 10.0);
      expect(() => applyGeometryEdits(doc, pathEdits: {body.index: nan}), throwsArgumentError);
    });

    test('마커: 이동·방향·길이 변경은 그 rect 태그만 바꾼다', () {
      final r = doc.rects.firstWhere((r) => r.w == 8 && r.h == 24);
      // 세로 8×24 → 가로 24×8, 중심 유지.
      final cx = r.x + r.w / 2, cy = r.y + r.h / 2;
      final out = applyGeometryEdits(doc, rectEdits: {r.index: RectEdit(cx - 12, cy - 4, 24, 8)});
      final re = GeometryDoc.parse(out).rects[r.index];
      expect((re.x, re.y, re.w, re.h), (cx - 12, cy - 4, 24.0, 8.0));
      expect(out.replaceRange(re.start, re.end, ''), svg.replaceRange(r.start, r.end, ''));
      expect(re.tag, contains('rx="4" ry="4"'), reason: 'rx/ry/style 은 건드리지 않는다');
    });

    test('마커: 규격 밖 크기·캔버스 밖 거부, 기존 비규격 마커는 크기를 안 바꾸면 이동 가능', () {
      final r = doc.rects.first;
      expect(() => applyGeometryEdits(doc, rectEdits: {r.index: RectEdit(r.x, r.y, 13, 8)}), throwsArgumentError);
      expect(() => applyGeometryEdits(doc, rectEdits: {r.index: RectEdit(-1, r.y, r.w, r.h)}), throwsArgumentError);
      expect(() => applyGeometryEdits(doc, rectEdits: {500: RectEdit(1, 1, 8, 8)}), throwsArgumentError);
      final odd = doc.rects.firstWhere((r) => !isStandardMarkerSize(r.w, r.h)); // 부전 알약 44×8
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

  // ⚠️ 이 그룹의 첫 테스트가 "역이 선로 위" CI 가드다. 선분을 옮긴 뒤 커밋하면 이 테스트가 깨지는 구조이므로,
  // 허용 집합(현재 비어 있음)을 늘리는 것은 그 가드를 푸는 일이다.
  group('선로 이탈 가드 — 12px 하드 (브랜치 station_svg_coords_test 와 같은 계산)', () {
    test('현재 SVG: 선로에서 12px 넘게 벗어난 역은 하나도 없다 (부산 158개 레코드)', () {
      expect(stations.length, 158);
      final off = findOffLineStations(polylinesByCode(doc), stations);
      // 이 목록이 생기면 SVG 나 stations.json 이 어긋난 것이다.
      expect(off, isEmpty, reason: off.map((o) => o.toJson()).toString());
    });

    test('현재 SVG: 4px 넘는 소프트 이탈도 없다 — 역 좌표가 전부 선 위에 있다', () {
      final t = findOffLineTiers(polylinesByCode(doc), stations);
      expect(t.hard, isEmpty);
      expect(t.soft, isEmpty, reason: t.soft.map((o) => o.toJson()).toString());
    });

    test('선을 멀리 옮기면 그 노선 역들이 이탈로 잡힌다', () {
      final body = doc.paths.firstWhere((p) => p.code == 'B2' && !p.isWhite && p.points.length > 20);
      final moved = [for (final q in body.points) (q.$1, q.$2 + 40)];
      final off = findOffLineStations(polylinesByCode(doc, {body.index: moved}), stations);
      expect(off.where((o) => o.lineId == '2'), isNotEmpty);
      expect(off.first.dist, greaterThanOrEqualTo(off.last.dist), reason: '거리 내림차순');
    });

    test('경계: 12px 이내는 통과, 넘으면 이탈', () {
      final line = <String, List<List<Pt>>>{
        'B2': [
          [(0.0, 0.0), (100.0, 0.0)],
        ],
      };
      List<dynamic> st(double y) => [
            {'name': 'A', 'lineId': '2', 'svgX': 50, 'svgY': y},
          ];
      expect(findOffLineStations(line, st(12)), isEmpty);
      expect(findOffLineStations(line, st(12.1)), hasLength(1));
    });
  });

  group('선로 이탈 가드 — 4px 소프트 층(12px 하드는 그대로)', () {
    final line = <String, List<List<Pt>>>{
      'B2': [
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

    test('핵심 시나리오: 2호선(B2)을 위로 8px 올리면 2호선 역들이 4~12px 소프트 대역에 들어온다 — 하드는 침묵, 소프트가 잡는다', () {
      final b2 = doc.paths.where((p) => p.code == 'B2' && !p.isWhite).toList();
      expect(b2, isNotEmpty);
      final edits = {
        for (final p in b2) p.index: [for (final q in p.points) (q.$1, q.$2 - 8)],
      };
      final before = findOffLineTiers(polylinesByCode(doc), stations);
      final after = findOffLineTiers(polylinesByCode(doc, edits), stations);
      expect(after.hard.map((o) => o.key).toSet(), before.hard.map((o) => o.key).toSet(),
          reason: '하드(12px)는 새로 걸리지 않는다 — 이 구멍이 소프트 층의 존재 이유');
      expect(before.soft, isEmpty, reason: '편집 전엔 역이 선 위 — 소프트도 아님');
      expect(after.soft, isNotEmpty);
      expect(after.soft.every((o) => o.lineId == '2'), isTrue);
      expect(after.soft.map((o) => o.dist).reduce(math.max), closeTo(8.0, 1e-6));
    });
  });

  group('환승 마커 ↔ stations.json 좌표 드리프트', () {
    SvgRect rectAt(double cx, double cy) =>
        doc.rects.firstWhere((r) => (r.x + r.w / 2 - cx).abs() < 1e-6 && (r.y + r.h / 2 - cy).abs() < 1e-6);
    RectEdit moved(SvgRect r, double dx, double dy) => RectEdit(r.x + dx, r.y + dy, r.w, r.h);

    // ⚠️ 이 테스트가 "마커를 옮겨 커밋하면 stations.json 도 같이 고치라"를 강제하는 **영속 가드**다(편집기 세션 경고는
    // 저장 시점 1회뿐이고 앵커 반경 밖으로 크게 옮기면 침묵한다). 이전 버전은 항등 편집(원래 값 그대로)을 넣어 d1 == d0 이라
    // 어떤 데이터에서도 통과하는 공허한 검사였다 — 아래는 실제 거리를 센다.
    test('실측 전제: 12개 마커 중 11개는 역 좌표와 정확히 일치(≤0.5px), 나머지 1개는 부전 알약(36×8, 12px)', () {
      expect(doc.rects.length, 12);
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
      expect((exact, loose), (11, 1), reason: '마커를 옮기거나 stations.json 좌표를 바꿨다면 둘을 같이 맞출 것');
      // 중심이 역 좌표와 다른 마커는 부전 알약(36×8, 중심 (1110,746)) 하나다. 1호선 부전(1122,746)과 동해선
      // 부전(1098,746) 두 역을 한 칸에 묶는 넓은 마커라 각 역이 중심에서 12px 떨어진다 — 앵커 반경(14px) 안이
      // 되도록 tool/build_busan_data.py 의 CANVAS_OVERRIDES 로 동해선 부전을 당겨 둔 값이다.
      expect(far, 0);
      expect(nearest[rectAt(1110, 746).index], closeTo(12.0, 0.01), reason: '부전 알약 ↔ 가장 가까운 역');
    });

    test('앵커 없는 마커 0건 — 전 마커가 앵커 역을 갖는다', () {
      final anchors = markerAnchors(doc.rects, stations);
      expect(orphanMarkers(doc.rects, stations), isEmpty, reason: '앵커 없는 마커 = SVG ↔ stations.json 드리프트(또는 넓은 마커 오탐)');
      expect(anchors.length, doc.rects.length);
      for (final e in anchors.entries) {
        for (final a in e.value) {
          // 부전만 넓은 알약이라 두 역이 중심에서 12px 씩 떨어진다(위 테스트 참조).
          expect(a.d0, a.name == '부전' ? closeTo(12.0, 0.01) : lessThanOrEqualTo(0.5),
              reason: '${a.name}|${a.lineId}');
        }
      }
    });

    test('가드가 공허하지 않다: 마커를 앵커 반경(14px) 밖으로 옮겨 저장한 SVG 는 고아 마커로 잡힌다(findMarkerDrift 는 침묵)', () {
      for (final dist in [8.0, 16.0, 32.0, 200.0]) {
        final r = rectAt(1122, 816); // 서면 캡슐(역 레코드 2개가 앵커)
        final movedSvg = applyGeometryEdits(doc, rectEdits: {r.index: moved(r, dist, 0)});
        final reloaded = GeometryDoc.parse(movedSvg); // 새 세션: 디스크 SVG 를 다시 읽는다
        final orphans = orphanMarkers(reloaded.rects, stations);
        // 기준선: 부전 알약(넓은 마커)이 이미 고아로 잡혀 있다(위 '앵커 없는 마커 0건' 참조).
        final baseline = orphanMarkers(doc.rects, stations);
        if (dist <= kMarkerAnchorRadius) {
          // 반경 안이면 환승역이라 여전히 앵커 — 이 대역은 저장 시점 findMarkerDrift 가 맡는다.
          expect(orphans, baseline, reason: '${dist}px');
        } else {
          expect(orphans, ([...baseline, r.index]..sort()), reason: '${dist}px 옮겨 저장한 뒤 새 세션에서도 고아로 잡혀야 한다');
          // 이동량 기준 경고는 새 세션에서 옮긴 마커를 더 옮겨도 침묵한다(앵커 소실) — 영속 신호가 따로 있는 이유.
          final r2 = reloaded.rects[r.index];
          expect(findMarkerDrift(reloaded.rects, {r2.index: moved(r2, 32, 0)}, stations), isEmpty);
        }
      }
    });

    test('nearestStation — 고아 마커 안내용(가장 가까운 역)', () {
      final n = nearestStation(1122, 816, stations)!;
      expect(n['name'], '서면');
      expect(n['dist'], 0.0);
      expect(nearestStation(0, 0, const []), isNull);
    });

    test('서면 마커를 16px 옮기면 그 마커에 앵커된 역들이 어긋남으로 잡힌다', () {
      final r = rectAt(1122, 816);
      final d = findMarkerDrift(doc.rects, {r.index: moved(r, 16, 0)}, stations);
      expect(d, hasLength(1));
      expect(d.single.index, r.index);
      expect(d.single.dist, closeTo(16, 1e-6));
      expect(d.single.shared, isFalse, reason: '부산에는 12px 선로 가드가 면제하는 공유 캡슐이 없다');
      expect(d.single.stations.map((s) => s.name).toSet(), {'서면'});
      expect(d.single.stations.map((s) => s.lineId), containsAll(['1', '2']));
    });

    test('길이·방향 변경은 중심을 보존하므로 어긋나지 않는다(서면 8×24 → 24×8)', () {
      final a = rectAt(1122, 816); // 8×24 → 24×8 중심 보존
      final edits = {
        a.index: RectEdit(1122 - 12, 816 - 4, 24, 8),
      };
      expect(findMarkerDrift(doc.rects, edits, stations), isEmpty);
    });

    test('0.25px 이하의 미세 이동은 허용 오차로 무시, 그 이상은 보고', () {
      final r = rectAt(1122, 816);
      expect(findMarkerDrift(doc.rects, {r.index: moved(r, 0.25, 0)}, stations), isEmpty);
      expect(findMarkerDrift(doc.rects, {r.index: moved(r, 0.5, 0)}, stations), hasLength(1));
    });

    test('편집하지 않은 마커·없는 index 는 결과에 없다', () {
      final r = rectAt(1122, 816);
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
