// CSV(`data/transfer_guides.csv`)를 읽어 `assets/json/transfer_guides.json`으로
// 변환하는 빌드 도구.
//
// 사용법:
//   dart run tool/import_transfer_guides.dart
//
// CSV 포맷 (v2 — destination_direction 컬럼 추가):
//   station,arrival_line,direction,destination_line,destination_direction,door_side,car,door,note
//   - direction: "up" | "down"  (환승역에 **도착할 때** 타고 온 노선의 방향)
//   - destination_direction: "up" | "down" | (빈 값)
//       환승 후 타는 노선의 방향. 빈 값이면 "방향 무관"으로 4-tuple 폴백 키에
//       기록된다. 값이 있으면 5-tuple 구체 키로 기록되어 런타임 2단 조회에서
//       폴백보다 우선한다. 사당 4호선→2호선처럼 목적 노선 방향에 따라 빠른환승
//       칸이 갈리는 환승만 값을 채운다.
//   - door_side: "left" | "right" | (빈 값)
//   - car, door: 정수 또는 빈 값
//   - note: 한글/영문 주석 또는 빈 값
//
// 동작:
//   - 4가지 데이터 필드(door_side, car, door, note) 중 하나라도 값이 있는 행만 JSON에 기록
//   - 모든 값이 비어 있는 행은 무시 (템플릿 기본 상태)
//   - 키 조립은 `lib/core/utils/transfer_guide_key.dart`의 `buildTransferGuideKey`를
//     **그대로 호출**한다. 과거 이 파일이 키를 직접 문자열 조립하던 중복이
//     런타임과의 스키마 불일치 버그를 낳았으므로 다시 복제하지 말 것.
//   - 유효하지 않은 행(필수 필드 누락, 잘못된 enum 값 등)은 경고 출력 후 건너뜀
//
// 런타임의 `LocalDataSource.loadTransferGuides`는 개별 엔트리 파싱 실패를
// 무시하도록 설계되어 있으나, 빌드 타임에 사전 검증함으로써 더 나은 DX를 제공한다.

import 'dart:convert';
import 'dart:io';

import 'package:busan_subway/core/utils/transfer_guide_key.dart';

const _csvPath = 'data/transfer_guides.csv';
const _jsonPath = 'assets/json/transfer_guides.json';

const _expectedHeader = [
  'station',
  'arrival_line',
  'direction',
  'destination_line',
  'destination_direction',
  'door_side',
  'car',
  'door',
  'note',
];

void main() {
  final csvFile = File(_csvPath);
  if (!csvFile.existsSync()) {
    stderr.writeln('오류: $_csvPath 파일이 없습니다. 먼저 CSV 템플릿을 생성하세요.');
    exit(1);
  }

  final lines = csvFile.readAsLinesSync();
  if (lines.isEmpty) {
    stderr.writeln('오류: $_csvPath 이 비어 있습니다.');
    exit(1);
  }

  // 헤더 검증
  final header = _parseCsvLine(lines.first);
  if (header.length != _expectedHeader.length ||
      !_listEquals(header, _expectedHeader)) {
    stderr.writeln('오류: CSV 헤더가 예상과 다릅니다.');
    stderr.writeln('  기대: ${_expectedHeader.join(",")}');
    stderr.writeln('  실제: ${header.join(",")}');
    exit(1);
  }

  final result = <String, Map<String, dynamic>>{};
  var skippedEmpty = 0;
  var skippedInvalid = 0;
  var imported = 0;

  for (var i = 1; i < lines.length; i++) {
    final rawLine = lines[i].trim();
    if (rawLine.isEmpty) continue;

    final cols = _parseCsvLine(rawLine);
    if (cols.length != _expectedHeader.length) {
      stderr.writeln('경고: $i번 행의 컬럼 수가 맞지 않음: "$rawLine"');
      skippedInvalid++;
      continue;
    }

    final station = cols[0].trim();
    final arrivalLine = cols[1].trim();
    final direction = cols[2].trim();
    final destinationLine = cols[3].trim();
    final destDirectionRaw = cols[4].trim();
    final doorSideRaw = cols[5].trim();
    final carRaw = cols[6].trim();
    final doorRaw = cols[7].trim();
    final note = cols[8].trim();

    // 값이 하나도 없으면 템플릿 빈 행 → 스킵
    if (doorSideRaw.isEmpty &&
        carRaw.isEmpty &&
        doorRaw.isEmpty &&
        note.isEmpty) {
      skippedEmpty++;
      continue;
    }

    // 필수 필드 검증
    if (station.isEmpty ||
        arrivalLine.isEmpty ||
        destinationLine.isEmpty ||
        (direction != 'up' && direction != 'down')) {
      stderr.writeln(
          '경고: $i번 행 필수 필드 오류 (station/arrival_line/destination_line/direction): "$rawLine"');
      skippedInvalid++;
      continue;
    }

    // destination_direction 검증 — 빈 값은 "방향 무관"(4-tuple 폴백 키)으로 허용.
    bool? destIsDown;
    if (destDirectionRaw.isNotEmpty) {
      if (destDirectionRaw != 'up' && destDirectionRaw != 'down') {
        stderr.writeln(
            '경고: $i번 행 destination_direction 값 오류 ("$destDirectionRaw"): up/down 또는 빈 값만 허용');
        skippedInvalid++;
        continue;
      }
      destIsDown = destDirectionRaw == 'down';
    }

    // door_side 검증
    String? doorSide;
    if (doorSideRaw.isNotEmpty) {
      if (doorSideRaw != 'left' && doorSideRaw != 'right') {
        stderr.writeln(
            '경고: $i번 행 door_side 값 오류 ("$doorSideRaw"): left/right 만 허용');
        skippedInvalid++;
        continue;
      }
      doorSide = doorSideRaw;
    }

    // car, door 파싱
    int? car;
    if (carRaw.isNotEmpty) {
      car = int.tryParse(carRaw);
      if (car == null || car <= 0) {
        stderr.writeln('경고: $i번 행 car 값 오류 ("$carRaw"): 양의 정수 필요');
        skippedInvalid++;
        continue;
      }
    }

    int? door;
    if (doorRaw.isNotEmpty) {
      door = int.tryParse(doorRaw);
      if (door == null || door <= 0) {
        stderr.writeln('경고: $i번 행 door 값 오류 ("$doorRaw"): 양의 정수 필요');
        skippedInvalid++;
        continue;
      }
    }

    // 키 조립은 런타임과 공유하는 단일 진입점을 사용한다(문자열 직접 조립 금지).
    final key = buildTransferGuideKey(
      stationName: station,
      arrivalLineId: arrivalLine,
      isDown: direction == 'down',
      destinationLineId: destinationLine,
      destIsDown: destIsDown,
    );

    // 중복 체크
    if (result.containsKey(key)) {
      stderr.writeln('경고: 중복 키 "$key" — 이전 값을 덮어씁니다.');
    }

    result[key] = {
      'doorSide': doorSide,
      'car': car,
      'door': door,
      'note': note.isEmpty ? null : note,
    };
    imported++;
  }

  // 정렬된 출력으로 diff 안정성 확보
  final sortedKeys = result.keys.toList()..sort();
  final sortedMap = <String, Map<String, dynamic>>{
    for (final k in sortedKeys) k: result[k]!,
  };

  final jsonFile = File(_jsonPath);
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(sortedMap),
    encoding: utf8,
  );

  stdout.writeln('✓ $_jsonPath 에 $imported개 엔트리를 기록했습니다.');
  stdout.writeln('  (빈 행 스킵: $skippedEmpty, 오류 행 스킵: $skippedInvalid)');
}

// 간단한 CSV 파서 — 큰따옴표 이스케이프 지원.
// 복잡한 케이스(쉼표 포함 값)도 처리하되, 이 프로젝트의 데이터는 단순하므로
// RFC 4180을 완전히 구현할 필요는 없다.
List<String> _parseCsvLine(String line) {
  final result = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (c == ',' && !inQuotes) {
      result.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(c);
    }
  }
  result.add(buffer.toString());
  return result;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
