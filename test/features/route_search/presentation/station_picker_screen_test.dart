import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seoul_subway/domain/entities/station.dart';
import 'package:seoul_subway/features/route_search/presentation/screens/station_picker_screen.dart';
import 'package:seoul_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

void main() {
  // 종합운동장(2/9호선 환승), 여의도(5/9호선 환승), 잠실새내(2호선 단일).
  // stations.json 의 실제 레코드 순서를 모사: 같은 이름 역은 lineId 오름차순.
  final testStations = <Station>[
    const Station(
      id: '217',
      name: '잠실새내',
      lineId: '2',
      latitude: 37.51,
      longitude: 127.09,
    ),
    const Station(
      id: '218',
      name: '종합운동장',
      lineId: '2',
      latitude: 37.51,
      longitude: 127.07,
      isTransfer: true,
      transferLines: ['2', '9'],
    ),
    const Station(
      id: '517',
      name: '여의도',
      lineId: '5',
      latitude: 37.52,
      longitude: 126.92,
      isTransfer: true,
      transferLines: ['5', '9'],
    ),
    const Station(
      id: '915',
      name: '여의도',
      lineId: '9',
      latitude: 37.52,
      longitude: 126.92,
      isTransfer: true,
      transferLines: ['5', '9'],
    ),
    const Station(
      id: '930',
      name: '종합운동장',
      lineId: '9',
      latitude: 37.51,
      longitude: 127.07,
      isTransfer: true,
      transferLines: ['2', '9'],
    ),
  ];

  Widget buildHarness() {
    return ProviderScope(
      overrides: [
        allStationsProvider.overrideWith((ref) async => testStations),
      ],
      child: const MaterialApp(
        home: StationPickerScreen(purpose: 'departure'),
      ),
    );
  }

  testWidgets('환승역은 중복 제거되어 1개만 표시된다', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    // 종합운동장은 2호선 + 9호선에 모두 등록되어 있지만 ListTile 1개만 보여야 함.
    expect(find.text('종합운동장'), findsOneWidget);
    expect(find.text('여의도'), findsOneWidget);
    expect(find.text('잠실새내'), findsOneWidget);
  });

  testWidgets('환승역에 소속 노선 뱃지가 모두 표시된다', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    // 종합운동장: 2호선 + 9호선 뱃지 둘 다 존재.
    expect(find.text('2호선'), findsWidgets);
    expect(find.text('9호선'), findsWidgets);
    // 여의도: 5호선 + 9호선 뱃지.
    expect(find.text('5호선'), findsWidgets);
  });

  testWidgets('환승역 탭 시 대표 Station이 selectedStations에 저장되고 '
      'transferLines가 보존된다', (tester) async {
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allStationsProvider.overrideWith((ref) async => testStations),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: StationPickerScreen(purpose: 'departure'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('종합운동장'));
    await tester.pumpAndSettle();

    final selected = container.read(selectedStationsProvider).departure;
    expect(selected, isNotNull);
    expect(selected!.name, '종합운동장');
    // transferLines 가 양쪽 노선을 모두 포함해야 이후 executeAll 에서
    // "양쪽 다 급행 지원 노선" 공유 판정이 가능하다.
    expect(selected.transferLines, containsAll(['2', '9']));
  });
}
