// `assets/json/express_skip_edges.json` 산출물 드리프트 회귀 가드.
//
// 배경: 이 파일은 `tool/extract_express_skip_edges.py` 의 산출물인데, 과거
// 생성기 출력과 어긋난 채로 커밋돼 있었다(1호선 오산→평택 `861`, 재생성하면
// `798`). `861` 은 connections.json 의 해당 구간 완행 시간이 수기 갱신되기 전
// 값에 0.7 을 곱한 산출물로, 아무도 알아채지 못한 채 남아 재생성 불가 상태를
// 만들었다. 정답은 생성기의 `_CURATED_MANUAL_SECONDS` 로 옮겼지만, 그것만으로는
// **반대 방향(산출물을 다시 손으로 패치)** 을 막지 못한다. 이 테스트가 그 방어선이다.
//
// 잡는 것:
//   1) 실측 고정값이 붙은 1호선 경부선 급행 edge 의 값 자체 (수기 패치 감지)
//   2) 정차 패턴 — 급행이 실제로 통과하는 역만 skippedStationIds 에 들어가는지
//   3) 물리 불변식 — 급행 소요시간이 같은 구간 완행 합을 넘지 않는지
//
// 값의 근거는 `tool/extract_express_skip_edges.py` 의 `_CURATED_MANUAL_SECONDS`
// 주석 참조.
//
// ⚠ 경부선 급행은 **계통이 둘**이고, 이 파일도 둘을 따로 고정한다.
//   · A급행 — 청량리 착발, 전 구간 경부2선. 2019-12-30 개편으로 **금정 정차**.
//     캐시 etrnYn=Y 청량리 착발 47편성. 경부선 급행의 주력이다.
//   · B급행 — 지상 서울역 착발, 서울역~수원 경부1선. 일 3회(K1902·K1904·K1945).
//     경부1선에 승강장이 없어 **금정·신도림·구로 등 환승역까지 통과**한다.
//   두 계통이 공유하는 구간(금천구청→안양, 의왕→성균관대, 평택→성환, 두정→천안)은
//   pair 키가 하나뿐이라 B급행 실측값 하나로 공유된다 — 두 표에 같은 값이 나온다.
//
// ⚠ pin 범위는 **경부선 24개 edge 뿐**이다. 나머지 경인선 10개(영등포→구로,
// 구로→부천, 부천→송내, 송내→부평, 부평→백운, 백운→동암, 동암→간석,
// 간석→주안, 주안→제물포, 제물포→동인천)는 실측이 아니라 `0.7 × 완행 합`
// 근사값이라 일부러 고정하지 않는다 — connections.json 의 완행 시간이 정상
// 갱신될 때 함께 따라가야 하기 때문이다. 경인선은 이 캐시로 정차 패턴 검증이
// 불가하다(전 편성이 전 역 레코드 보유). 물리 불변식 검사만 적용된다.
// 급행 데이터를 의도적으로 바꿀 때는 생성기를 고쳐 재생성한 뒤 이 표도 갱신할 것 —
// 이 파일만 고치면 다음 재생성에 되돌아간다.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/data/local/local_data_source.dart';
import 'package:seoul_subway/domain/entities/connection.dart';
import 'package:seoul_subway/domain/entities/express_skip_edge.dart';

/// 1호선 경부선 **B급행**(지상 서울역 착발·경부1선)의 실측 고정 구간.
///
/// 척도는 `다음역 trainArvlTm − 현재역 trainDptreTm`(dwell 제외)로 완행
/// `travelTimeSeconds` 와 같은 규약이다(2026-08 dwell 이중 가산 교정 때 전환).
/// 수원→세류·오산→진위·평택→성환은 실측 중앙값(210·210·420)이 완행 합을 넘어
/// 생성기의 "급행은 완행보다 느릴 수 없다" 상한에 걸린 결과값이다.
const _gyeongbuExpressB = <(String, String, int)>[
  ('134', '136', 270), // 서울역→용산 (남영 통과)
  ('136', '137', 120), // 용산→노량진 (arvl 결측 — dep→dep 150 − dwell 30 근사)
  ('137', '140', 210), // 노량진→영등포 (대방·신길 통과, 근사 240 − 30)
  ('140', '167', 480), // 영등포→금천구청 (신도림·구로·가산디지털단지·독산 통과)
  ('167', '170', 330), // 금천구청→안양 (석수·관악 통과)
  ('170', '172', 300), // 안양→군포 (명학·금정 통과)
  ('172', '174', 210), // 군포→의왕 (당정 통과)
  ('174', '175', 180), // 의왕→성균관대
  ('175', '176', 150), // 성균관대→화서
  ('176', '177', 150), // 화서→수원
  ('177', '178', 180), // 수원→세류 (완행 상한 적용: 실측 210)
  ('178', '179', 180), // 세류→병점
  ('179', '181', 120), // 병점→세마
  ('181', '182', 120), // 세마→오산대 (근사 150 − 30)
  ('182', '183', 180), // 오산대→오산
  ('183', '184', 180), // 오산→진위 (완행 상한 적용: 실측 210)
  ('184', '185', 120), // 진위→송탄 (근사 150 − 30)
  ('185', '186', 120), // 송탄→서정리
  ('186', '187', 210), // 서정리→평택지제
  ('187', '188', 240), // 평택지제→평택
  ('188', '189', 390), // 평택→성환 (완행 상한 적용: 실측 420)
  ('189', '190', 210), // 성환→직산
  ('190', '191', 240), // 직산→두정
  ('191', '192', 240), // 두정→천안
];

/// 1호선 경부선 **A급행**(청량리 착발·경부2선)의 실측 고정 구간.
///
/// 표본은 캐시의 etrnYn=Y 청량리 착발 47편성(하행만 `trainArvlTm` 이 채워져
/// n≈148 은 전부 하행). 정차역 목록의 출처와 교차검증 근거는
/// `tool/manual_express_stops.json` 의 A급행 `_comment` 참조.
///
/// 영등포~구로는 A급행도 전역 정차라 통과역 0개인 인접쌍이다 — 신도림·
/// 가산디지털단지에서 급행을 탈 수 있게 노드를 만들어 두는 것이 목적이다.
/// 금천구청→안양·의왕→성균관대·평택→성환·두정→천안은 B급행과 공유하는 pair 라
/// B 표와 같은 값이다.
const _gyeongbuExpressA = <(String, String, int)>[
  ('140', '141', 120), // 영등포→신도림 (인접)
  ('141', '142', 120), // 신도림→구로 (인접)
  ('142', '1425', 240), // 구로→가산디지털단지 (인접)
  ('1425', '167', 240), // 가산디지털단지→금천구청 (독산 통과)
  ('167', '170', 330), // 금천구청→안양 (석수·관악 통과) — B급행과 공유
  ('170', '1715', 210), // 안양→금정 (명학 통과)
  ('1715', '174', 330), // 금정→의왕 (군포·당정 통과)
  ('174', '175', 180), // 의왕→성균관대 — B급행과 공유
  ('175', '177', 270), // 성균관대→수원 (화서 통과)
  ('177', '179', 360), // 수원→병점 (세류 통과)
  ('179', '183', 420), // 병점→오산 (세마·오산대 통과)
  ('183', '186', 450), // 오산→서정리 (진위·송탄 통과)
  ('186', '188', 390), // 서정리→평택 (평택지제 통과)
  ('188', '189', 390), // 평택→성환 — B급행과 공유 (완행 상한 적용)
  ('189', '191', 420), // 성환→두정 (직산 통과)
  ('191', '192', 240), // 두정→천안 — B급행과 공유
];

/// A급행이 통과하는 역 — 금정은 여기 **없다**(2019-12-30 개편으로 정차).
const _gyeongbuSkippedA = <String>{
  '166', // 독산
  '168', // 석수
  '169', // 관악
  '171', // 명학
  '172', // 군포
  '173', // 당정
  '176', // 화서
  '178', // 세류
  '181', // 세마
  '182', // 오산대
  '184', // 진위
  '185', // 송탄
  '187', // 평택지제
  '190', // 직산
};

/// B급행이 실제로 통과하는 역 (getTrainSch 실측 — 이 12개가 전부다).
///
/// ⚠ 구로 이남 역 ID 재배정(2026-08)으로 독산 167→166, 석수 169→168,
///   관악 168→169 로 바뀌었다. **금천구청은 167** 이고 급행 정차역이므로 여기
///   들어오면 안 된다(아래 별도 테스트가 고정한다).
/// ⚠ 같은 작업에서 가산디지털단지 1호선 노드(1425)를 신설했고, 급행 3편성
///   (K1902·K1904·K1945)에 그 역 레코드가 없어 통과역 목록에 합류했다.
const _gyeongbuSkippedB = <String>{
  '135', // 남영
  '138', // 대방
  '139', // 신길
  '141', // 신도림
  '142', // 구로
  '1425', // 가산디지털단지
  '166', // 독산
  '168', // 석수
  '169', // 관악
  '171', // 명학
  // 금정 — 1호선 노드가 신설되면서 통과역 목록에 합류했다(같은 실측 기준:
  // 급행 3편성 K1902·K1904·K1945 레코드가 `data/timetables/1_금정_*.json` 에
  // 하나도 없다). 이 매핑을 만든 시점엔 1호선 금정 레코드가 없어 빠져 있었다.
  '1715', // 금정
  '173', // 당정
};

/// 운행 시간대 창이 붙은 edge — B급행 **전용** 구간뿐이어야 한다.
///
/// A급행과 함께 서는 구간(금천구청→안양·의왕→성균관대·평택→성환·두정→천안)과
/// 경인선 급행이 먼저 claim 한 구간(용산→노량진·노량진→영등포)은 상시 운행이라
/// 창이 없다. 생성기가 상시 운행 계통을 먼저 처리해 그 pair 를 claim 하게 하는
/// 순서에 의존하므로, 여기 목록이 늘어나면 그 순서가 깨졌다는 뜻이다.
const _windowedPairs = <(String, String)>{
  ('134', '136'), // 서울역→용산
  ('140', '167'), // 영등포→금천구청
  ('170', '172'), // 안양→군포
  ('172', '174'), // 군포→의왕
  ('175', '176'), // 성균관대→화서
  ('176', '177'), // 화서→수원
  ('177', '178'), // 수원→세류
  ('178', '179'), // 세류→병점
  ('179', '181'), // 병점→세마
  ('181', '182'), // 세마→오산대
  ('182', '183'), // 오산대→오산
  ('183', '184'), // 오산→진위
  ('184', '185'), // 진위→송탄
  ('185', '186'), // 송탄→서정리
  ('186', '187'), // 서정리→평택지제
  ('187', '188'), // 평택지제→평택
  ('189', '190'), // 성환→직산
  ('190', '191'), // 직산→두정
};

/// B급행 운행 시간대 실측 — 캐시의 3편성이 노선 위에 있는 시각 범위.
/// 상행 05:44~08:09(K1902 시발 ~ K1904 종착), 하행 18:32~20:02(K1945).
const _bWindows = <ExpressServiceWindow>[
  ExpressServiceWindow(isDown: false, startMinute: 344, endMinute: 489),
  ExpressServiceWindow(isDown: true, startMinute: 1112, endMinute: 1202),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ExpressSkipEdge> line1Edges;
  late List<ExpressSkipEdge> allEdges;
  late Map<String, Connection> line1Local;

  setUpAll(() async {
    final source = LocalDataSource();
    allEdges = await source.loadExpressSkipEdges();
    line1Edges = allEdges.where((e) => e.lineId == '1').toList();

    // 1호선 완행 connection — 양방향 조회용 (`from|to` 키).
    final raw = await rootBundle.loadString('assets/json/connections.json');
    line1Local = {};
    for (final json in jsonDecode(raw) as List<dynamic>) {
      final c = Connection.fromJson(json as Map<String, dynamic>);
      if (c.lineId != '1' || c.isTransfer) continue;
      line1Local['${c.fromStationId}|${c.toStationId}'] = c;
      line1Local['${c.toStationId}|${c.fromStationId}'] = c;
    }
  });

  ExpressSkipEdge? find(String from, String to) {
    for (final e in line1Edges) {
      if (e.fromStationId == from && e.toStationId == to) return e;
      if (e.fromStationId == to && e.toStationId == from) return e;
    }
    return null;
  }

  group('express_skip_edges.json — 1호선 경부선 B급행 실측값 고정', () {
    for (final (from, to, seconds) in _gyeongbuExpressB) {
      test('$from → $to 는 $seconds초', () {
        final edge = find(from, to);
        expect(
          edge,
          isNotNull,
          reason: '$from→$to 급행 edge 가 사라졌다. '
              'tool/manual_express_stops.json 의 경부선 stops 를 확인할 것.',
        );
        expect(
          edge!.seconds,
          seconds,
          reason: '실측 고정값과 다르다. assets/json 을 손으로 고쳤다면 되돌리고, '
              'tool/extract_express_skip_edges.py 의 _CURATED_MANUAL_SECONDS 를 '
              '고친 뒤 재생성할 것.',
        );
      });
    }

    test('오산→평택 직결 edge 는 존재하지 않는다 (A·B 모두 서정리에 정차)', () {
      // 과거 `861`(그리고 재생성 시 `798`) 이 붙어 있던 허구의 skip edge.
      // getTrainSch 실측상 급행 3편성 모두 진위·송탄·서정리·평택지제에 정차한다.
      expect(find('183', '188'), isNull);
    });
  });

  group('express_skip_edges.json — 1호선 경부선 A급행 실측값 고정', () {
    for (final (from, to, seconds) in _gyeongbuExpressA) {
      test('$from → $to 는 $seconds초', () {
        final edge = find(from, to);
        expect(
          edge,
          isNotNull,
          reason: '$from→$to A급행 edge 가 사라졌다. '
              'tool/manual_express_stops.json 의 A급행 stops 를 확인할 것.',
        );
        expect(
          edge!.seconds,
          seconds,
          reason: '실측 고정값과 다르다. assets/json 을 손으로 고쳤다면 되돌리고, '
              'tool/extract_express_skip_edges.py 의 _CURATED_MANUAL_SECONDS 를 '
              '고친 뒤 재생성할 것.',
        );
      });
    }

    test('금정은 A급행 정차역이다 (2019-12-30 개편)', () {
      // 회귀 가드: A급행 매핑이 빠지면 금정이 다시 통과역으로만 남는다.
      // B급행(안양→군포)은 여전히 금정을 통과하므로, "어떤 edge 도 금정을
      // 통과하지 않는다"로는 검사할 수 없다 — A급행 쪽 정차를 직접 고정한다.
      expect(
        find('170', '1715'),
        isNotNull,
        reason: '안양→금정 A급행 edge 가 없다',
      );
      expect(
        find('1715', '174'),
        isNotNull,
        reason: '금정→의왕 A급행 edge 가 없다',
      );
    });
  });

  group('express_skip_edges.json — B급행 운행 시간대 창', () {
    test('창이 붙은 edge 는 B급행 전용 구간뿐이다', () {
      final windowed = {
        for (final e in line1Edges)
          if (e.serviceWindows.isNotEmpty)
            (e.fromStationId, e.toStationId),
      };
      expect(windowed, _windowedPairs);
    });

    test('창 값은 캐시 실측 그대로다 (상행 344~489 / 하행 1112~1202)', () {
      for (final e in line1Edges) {
        if (e.serviceWindows.isEmpty) continue;
        expect(
          e.serviceWindows,
          _bWindows,
          reason: '${e.fromStationId}→${e.toStationId} 의 창이 실측과 다르다',
        );
      }
    });

    test('A급행 구간에는 창이 없다 (낮에도 급행이 남아야 한다)', () {
      for (final (from, to, _) in _gyeongbuExpressA) {
        final edge = find(from, to)!;
        expect(
          edge.serviceWindows,
          isEmpty,
          reason: '$from→$to 에 창이 붙으면 A급행이 시간대 밖에서 사라진다',
        );
      }
    });

    test('1호선 말고는 창을 쓰는 노선이 없다', () {
      for (final e in allEdges.where((e) => e.lineId != '1')) {
        expect(e.serviceWindows, isEmpty, reason: '${e.lineId} 에 창이 생겼다');
      }
    });
  });

  group('express_skip_edges.json — 정차 패턴·물리 불변식', () {
    test('경부선 B급행 통과역은 실측 12개역뿐이다', () {
      final skipped = <String>{};
      for (final (from, to, _) in _gyeongbuExpressB) {
        final edge = find(from, to);
        expect(edge, isNotNull, reason: '$from→$to B급행 edge 가 없다');
        skipped.addAll(edge!.skippedStationIds);
      }
      expect(skipped, _gyeongbuSkippedB);
    });

    test('경부선 A급행 통과역은 14개역이며 금정을 포함하지 않는다', () {
      final skipped = <String>{};
      for (final (from, to, _) in _gyeongbuExpressA) {
        final edge = find(from, to);
        expect(edge, isNotNull, reason: '$from→$to A급행 edge 가 없다');
        skipped.addAll(edge!.skippedStationIds);
      }
      expect(skipped, _gyeongbuSkippedA);
      expect(skipped, isNot(contains('1715')));
    });

    test('군포는 B급행 정차역이다 (B급행 edge 가 통과역으로 분류하지 않는다)', () {
      // `trainArvlTm` 채움률 4.6% 를 근거로 통과역으로 오인됐던 역.
      // ⚠ A급행은 군포를 **실제로 통과**하므로(금정→의왕) 전 edge 대상으로
      //   검사하면 안 된다 — B급행 표에 한정한다.
      for (final (from, to, _) in _gyeongbuExpressB) {
        final edge = find(from, to)!;
        expect(
          edge.skippedStationIds,
          isNot(contains('172')),
          reason: '$from→$to 가 군포(172)를 통과역으로 분류했다',
        );
      }
    });

    test('금천구청은 어느 급행도 통과하지 않는다', () {
      // 종전 매핑에서 통과역으로 잘못 분류돼 있던 역. A급행은 출퇴근 13회만
      // 정차하지만, 정차역으로 모델링했으므로 통과 목록에 들어오면 안 된다.
      //
      // ⚠ 금천구청 ID 는 구로 이남 순서 교정으로 166 → 167 이 됐다. 166 은 이제
      //   독산(= 실제 통과역)이므로, 이 단정을 166 으로 되돌리면 검사가 뒤집힌다.
      for (final edge in line1Edges) {
        expect(
          edge.skippedStationIds,
          isNot(contains('167')),
          reason: '${edge.fromStationId}→${edge.toStationId} 가 '
              '금천구청(167)을 통과역으로 분류했다',
        );
      }
    });

    // "1호선 급행의 유일 소스는 skip edges" 검사는 여기 있었지만, 구 급행 모델이
    // 전 노선에서 제거되면서(`Connection.expressTimeSeconds` 필드 자체가 삭제)
    // 엔티티로는 표현할 수 없게 됐다. 에셋에 그 키가 되살아나지 않는지는
    // `test/data/connections_no_express_asset_test.dart` 가 원본 JSON 을 직접
    // 읽어 **전 노선**에 대해 검사한다 — 1호선만 보던 이 검사보다 강하다.

    test('모든 1호선 급행 edge 는 같은 구간 완행 합을 넘지 않는다', () {
      for (final edge in line1Edges) {
        final chain = [
          edge.fromStationId,
          ...edge.skippedStationIds,
          edge.toStationId,
        ];
        var localSum = 0;
        for (var i = 0; i < chain.length - 1; i++) {
          final c = line1Local['${chain[i]}|${chain[i + 1]}'];
          expect(
            c,
            isNotNull,
            reason: 'skippedStationIds 가 완행 경로와 어긋난다: '
                '${edge.fromStationId}→${edge.toStationId} '
                '(${chain[i]}→${chain[i + 1]} 연결 없음)',
          );
          localSum += c!.travelTimeSeconds;
        }
        expect(
          edge.seconds,
          lessThanOrEqualTo(localSum),
          reason: '급행이 완행보다 느리다: '
              '${edge.fromStationId}→${edge.toStationId}',
        );
      }
    });
  });
}
