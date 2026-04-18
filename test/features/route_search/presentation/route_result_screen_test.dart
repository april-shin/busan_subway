import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:seoul_subway/domain/entities/route_result.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/domain/repositories/arrival_repository.dart';
import 'package:seoul_subway/features/arrival_info/presentation/providers/arrival_providers.dart';
import 'package:seoul_subway/features/route_search/presentation/screens/route_result_screen.dart';

class _MockArrivalRepository extends Mock implements ArrivalRepository {}

void main() {
  const station1 = Station(
    id: '901',
    name: '김포공항',
    lineId: '9',
    latitude: 37.56,
    longitude: 126.80,
  );
  const station2 = Station(
    id: '902',
    name: '공항시장',
    lineId: '9',
    latitude: 37.56,
    longitude: 126.81,
  );
  const station3 = Station(
    id: '903',
    name: '신방화',
    lineId: '9',
    latitude: 37.56,
    longitude: 126.82,
  );

  late _MockArrivalRepository mockRepo;

  setUp(() {
    mockRepo = _MockArrivalRepository();
    when(() => mockRepo.getArrivalInfo(any())).thenAnswer((_) async => []);
  });

  Widget buildApp(RouteResult route) {
    return ProviderScope(
      overrides: [
        arrivalRepositoryProvider.overrideWithValue(mockRepo),
      ],
      child: MaterialApp(
        home: RouteResultScreen(
          fastest: route,
          departureStationName: station1.name,
        ),
      ),
    );
  }

  /// 완행/급행 SegmentedButton을 렌더하는 데 필요한 최소 RouteResult
  RouteResult makeRoute({int? totalExpress, int? expressDuration}) {
    return RouteResult(
      segments: [
        RouteSegment(
          lineId: '9',
          lineName: '9호선',
          stations: const [station1, station2, station3],
          durationSeconds: 300,
          direction: '신방화 방면',
          expressDurationSeconds: expressDuration,
        ),
      ],
      totalTimeSeconds: 300,
      transferCount: 0,
      stationCount: 3,
      totalExpressTimeSeconds: totalExpress,
    );
  }

  testWidgets('급행 가능 경로에서 탭 렌더 + 급행이 왼쪽/기본 선택', (tester) async {
    final route = makeRoute(totalExpress: 180, expressDuration: 180);

    await tester.pumpWidget(buildApp(route));
    // AsyncValue 로딩 해소 대기
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('완행'), findsOneWidget);
    // 토글 라벨 '급행' + 세그먼트 헤더 '급행' 배지 두 개 존재
    expect(find.text('급행'), findsNWidgets(2));

    // 왼쪽이 급행, 오른쪽이 완행인지 레이아웃 순서 확인
    final expressPos = tester.getTopLeft(find.text('급행').first).dx;
    final localPos = tester.getTopLeft(find.text('완행')).dx;
    expect(expressPos, lessThan(localPos), reason: '급행 탭이 완행 탭보다 왼쪽에 위치');
  });

  testWidgets('totalExpressTimeSeconds가 null이면 토글 자체가 숨겨짐', (tester) async {
    final route = makeRoute(totalExpress: null, expressDuration: null);

    await tester.pumpWidget(buildApp(route));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('완행'), findsNothing);
    expect(find.text('급행'), findsNothing);
  });

  testWidgets('완행 클릭 시 _SegmentHeader 시간 표시가 완행 기준으로 변경된다',
      (tester) async {
    // 완행 5분(300초) / 급행 3분(180초). 기본값이 급행이라 초기 표시는 3분.
    final route = makeRoute(totalExpress: 180, expressDuration: 180);

    await tester.pumpWidget(buildApp(route));
    await tester.pump(const Duration(milliseconds: 50));

    // 급행 모드(기본): "3분 (2개역)" 표시 + 세그먼트 배지
    expect(find.textContaining('3분'), findsWidgets);

    // 완행 세그먼트 탭
    await tester.tap(find.text('완행'));
    await tester.pump(const Duration(milliseconds: 50));

    // 완행 모드: "5분 (2개역)" 표시
    expect(find.textContaining('5분'), findsWidgets);
  });

  testWidgets('급행 미지원 세그먼트는 급행 모드에서도 배지가 나타나지 않는다',
      (tester) async {
    // 세그먼트 expressDurationSeconds는 null이지만, 다른 세그먼트가 있어
    // totalExpressTimeSeconds는 non-null인 가상 시나리오 — 배지 미표시 확인
    final route = RouteResult(
      segments: const [
        RouteSegment(
          lineId: '2',
          lineName: '2호선',
          stations: [station1, station2],
          durationSeconds: 120,
          direction: '공항시장 방면',
          // expressDurationSeconds 미지정 → null
        ),
      ],
      totalTimeSeconds: 120,
      transferCount: 0,
      stationCount: 2,
      totalExpressTimeSeconds: 120, // 강제로 non-null 설정 (토글 활성화 목적)
    );

    await tester.pumpWidget(buildApp(route));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('급행'));
    await tester.pump(const Duration(milliseconds: 50));

    // 배지는 세그먼트에 직접 표시되지 않는다. 토글 라벨의 '급행'만 존재.
    // _SegmentHeader 배지가 있으면 텍스트 개수가 늘어나므로 개수 확인.
    final expressLabels = find.text('급행');
    expect(expressLabels, findsOneWidget);
  });
}

