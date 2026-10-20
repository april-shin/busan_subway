import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/core/utils/line_direction.dart';

/// 우이신설 도착 환승 가이드의 방향 키가 앱 `isDownBetween` 과 같은 방향을 가리키는지.
///
/// 환승 가이드(`transfer_guides.json`)의 방향 키(`up`/`down`)는 **생성 시점의**
/// `isDownBetween` 으로 정해진다(`tool/import_official_transfer_guides.dart`). 그래서
/// 방향 규칙을 바꾸면(2026-10-20 우이신설 API 라벨 반전) 가이드도 재생성하지 않으면
/// **같은 규칙이 데이터와 런타임에서 갈라져** 칸-문 안내가 반대 방향 값이 된다.
///
/// 공식 데이터의 "하차 열차 방면"은 **바로 옆 역 이름**이다(진행 방향). 예) 성신여대입구에서
/// "정릉 방면" 하차 = 정릉(W10) 쪽으로 가는 열차 = 북한산우이행 = API 하행.
void main() {
  late Map<String, dynamic> guides;

  setUpAll(() {
    guides = jsonDecode(File('assets/json/transfer_guides.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  String dir(String from, String to) =>
      isDownBetween(from, to, '우이신설') ? 'down' : 'up';

  // (환승역, 우이신설 역ID, 진행 방향 옆역 ID, 목적 노선, 공식 CSV 의 칸-문, 설명)
  const rows = <(String, String, String, String, (int, int), String)>[
    // 공식 CSV 984/986: 성신여대입구 우이신설 "정릉 방면" 하차 → 4호선 환승 1-2 (두 목적 방면 동일)
    ('성신여대입구', 'W11', 'W10', '4', (1, 2), '정릉 방면(북한산우이행)'),
    // 공식 CSV 983/985: "보문 방면" 하차 → 2-1
    ('성신여대입구', 'W11', 'W12', '4', (2, 1), '보문 방면(신설동행)'),
    // 공식 CSV 988/989: 보문 우이신설 "성신여대입구 방면" 하차 → 6호선 2-2
    ('보문', 'W12', 'W11', '6', (2, 2), '성신여대입구 방면(북한산우이행)'),
    // 공식 CSV 987/990: "신설동 방면" 하차 → 1-1
    ('보문', 'W12', 'W13', '6', (1, 1), '신설동 방면(신설동행)'),
  ];

  for (final (station, from, next, destLine, (car, door), desc) in rows) {
    test('$station 우이신설 $desc → $destLine호선 $car-$door', () {
      final key = '${station}_우이신설_${dir(from, next)}_$destLine';
      final entry = guides[key] as Map<String, dynamic>?;
      expect(entry, isNotNull, reason: '$key 없음');
      expect((entry!['car'], entry['door']), (car, door),
          reason: '$key — 방향 키가 생성 시점 규칙과 어긋나면(규칙만 고치고 가이드를 '
              '재생성하지 않으면) 반대 방향 칸-문이 나온다');
    });
  }

  test('북한산우이행(=API 하행)은 항상 down 키', () {
    expect(dir('W11', 'W10'), 'down');
    expect(dir('W12', 'W11'), 'down');
    expect(dir('W11', 'W12'), 'up');
  });
}
