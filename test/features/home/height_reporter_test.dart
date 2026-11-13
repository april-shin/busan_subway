// HeightReporter: 검색 카드 높이를 지도(mapSafeTopProvider)에 알리는 로직 가드.
// 높이가 바뀌면 새 값이 전달되고, 안 바뀌면 재전달하지 않아야 한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busan_subway/features/home/presentation/widgets/height_reporter.dart';
import 'package:busan_subway/features/subway_map/presentation/providers/subway_map_providers.dart';

void main() {
  testWidgets('첫 레이아웃 높이를 보고하고, 같은 높이로 리빌드하면 재보고하지 않는다', (tester) async {
    final reported = <double>[];
    final h = ValueNotifier<double>(100);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<double>(
        valueListenable: h,
        builder: (_, v, _) => Align(
          alignment: Alignment.topCenter,
          child: HeightReporter(
            onHeight: reported.add,
            child: SizedBox(height: v, width: 50),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(reported, [100.0]);

    // 높이 유지 리빌드 → 재전달 없음.
    h.value = 100;
    await tester.pump();
    await tester.pump();
    expect(reported, [100.0]);

    // 높이 증가(태그 줄/경유역 칸 추가) → 새 값 전달.
    h.value = 142;
    await tester.pump();
    await tester.pump();
    expect(reported, [100.0, 142.0]);

    // 감소(제거) → 새 값 전달.
    h.value = 100;
    await tester.pump();
    await tester.pump();
    expect(reported, [100.0, 142.0, 100.0]);
  });

  testWidgets('provider 에 기록되고 listen 측은 변경 때만 알림을 받는다', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seen = <double>[];
    container.listen<double>(mapSafeTopProvider, (_, n) => seen.add(n));
    expect(container.read(mapSafeTopProvider), 0);

    final h = ValueNotifier<double>(120);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: h,
          builder: (_, v, _) => Align(
            alignment: Alignment.topCenter,
            child: Consumer(
              builder: (context, ref, _) => HeightReporter(
                onHeight: (x) =>
                    ref.read(mapSafeTopProvider.notifier).state = x,
                child: SizedBox(height: v, width: 50),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(container.read(mapSafeTopProvider), 120);
    h.value = 120;
    await tester.pump();
    await tester.pump();
    expect(seen, [120.0]);
  });

  testWidgets('자식이 스스로 setState 로 크기를 바꿔도(리빌드 없는 경로) 새 높이를 보고한다',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seen = <double>[];
    container.listen<double>(mapSafeTopProvider, (_, n) => seen.add(n));
    final key = GlobalKey<_GrowingBoxState>();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          // HeightReporter 는 이 트리에서 리빌드되지 않는다(const 부모).
          child: Consumer(
            builder: (context, ref, child) => HeightReporter(
              onHeight: (x) => ref.read(mapSafeTopProvider.notifier).state = x,
              child: _GrowingBox(key: key),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(seen, [100.0]);

    // 태그 줄이 생기는 상황: 자식만 setState.
    key.currentState!.setHeight(142);
    await tester.pump();
    await tester.pump();
    expect(seen, [100.0, 142.0]);

    key.currentState!.setHeight(100);
    await tester.pump();
    await tester.pump();
    expect(seen, [100.0, 142.0, 100.0]);
  });
}

class _GrowingBox extends StatefulWidget {
  const _GrowingBox({super.key});

  @override
  State<_GrowingBox> createState() => _GrowingBoxState();
}

class _GrowingBoxState extends State<_GrowingBox> {
  double _h = 100;

  void setHeight(double h) => setState(() => _h = h);

  @override
  Widget build(BuildContext context) => SizedBox(height: _h, width: 50);
}
