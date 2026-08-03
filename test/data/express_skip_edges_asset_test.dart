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
// 주석 참조 (getTrainSch 캐시의 급행 편성 K1902·K1904·K1945 실측).
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

/// 1호선 경부선 급행의 실측 고정 구간 — `from → to : seconds`.
///
/// 척도는 `다음역 trainArvlTm − 현재역 trainDptreTm`(dwell 제외)로 완행
/// `travelTimeSeconds` 와 같은 규약이다(2026-08 dwell 이중 가산 교정 때 전환).
/// 수원→세류·오산→진위·평택→성환은 실측 중앙값(210·210·420)이 완행 합을 넘어
/// 생성기의 "급행은 완행보다 느릴 수 없다" 상한에 걸린 결과값이다.
const _gyeongbuExpress = <(String, String, int)>[
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

/// 경부선 급행이 실제로 통과하는 역 (getTrainSch 실측 — 이 12개가 전부다).
///
/// ⚠ 구로 이남 역 ID 재배정(2026-08)으로 독산 167→166, 석수 169→168,
///   관악 168→169 로 바뀌었다. **금천구청은 167** 이고 급행 정차역이므로 여기
///   들어오면 안 된다(아래 별도 테스트가 고정한다).
/// ⚠ 같은 작업에서 가산디지털단지 1호선 노드(1425)를 신설했고, 급행 3편성
///   (K1902·K1904·K1945)에 그 역 레코드가 없어 통과역 목록에 합류했다.
const _gyeongbuSkipped = <String>{
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ExpressSkipEdge> line1Edges;
  late Map<String, Connection> line1Local;

  setUpAll(() async {
    final source = LocalDataSource();
    line1Edges = (await source.loadExpressSkipEdges())
        .where((e) => e.lineId == '1')
        .toList();

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

  group('express_skip_edges.json — 1호선 경부선 급행 실측값 고정', () {
    for (final (from, to, seconds) in _gyeongbuExpress) {
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

    test('오산→평택 직결 edge 는 존재하지 않는다 (급행도 4개 역 모두 정차)', () {
      // 과거 `861`(그리고 재생성 시 `798`) 이 붙어 있던 허구의 skip edge.
      // getTrainSch 실측상 급행 3편성 모두 진위·송탄·서정리·평택지제에 정차한다.
      expect(find('183', '188'), isNull);
    });
  });

  group('express_skip_edges.json — 정차 패턴·물리 불변식', () {
    test('경부선 급행 통과역은 실측 12개역뿐이다', () {
      final skipped = <String>{};
      for (final (from, to, _) in _gyeongbuExpress) {
        final edge = find(from, to);
        expect(edge, isNotNull, reason: '$from→$to 급행 edge 가 없다');
        skipped.addAll(edge!.skippedStationIds);
      }
      expect(skipped, _gyeongbuSkipped);
    });

    test('군포·금천구청은 급행 정차역이다 (통과역으로 분류되지 않는다)', () {
      // 군포: `trainArvlTm` 채움률 4.6% 를 근거로 통과역으로 오인됐던 역.
      // 금천구청: 종전 매핑에서 통과역으로 잘못 분류돼 있던 역.
      //
      // ⚠ 금천구청 ID 는 구로 이남 순서 교정으로 166 → 167 이 됐다. 166 은 이제
      //   독산(= 실제 통과역)이므로, 이 단정을 166 으로 되돌리면 검사가 뒤집힌다.
      for (final edge in line1Edges) {
        final where = '${edge.fromStationId}→${edge.toStationId}';
        expect(
          edge.skippedStationIds,
          isNot(contains('172')),
          reason: '$where 가 군포(172)를 통과역으로 분류했다',
        );
        expect(
          edge.skippedStationIds,
          isNot(contains('167')),
          reason: '$where 가 금천구청(167)을 통과역으로 분류했다',
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
