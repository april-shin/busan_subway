import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/usecases/search_route.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';
import '../providers/timetable_providers.dart';

/// 현재 선택된 출발/도착역으로 경로를 계산해 결과 화면(`/route-result`)으로
/// 이동한다.
///
/// 홈 검색 버튼과 역 선택 화면의 "최근 검색" 탭이 공유하는 로직이다. 선택이
/// 완료되지 않았으면 아무 것도 하지 않는다. 계산 중 로딩 다이얼로그를 띄우고,
/// 무경로/예외 시 스낵바로 알린다. `context.mounted` 로 async 경계 이후 안전을
/// 보장한다.
Future<void> searchAndNavigateToResult(
  BuildContext context,
  WidgetRef ref,
) async {
  final selected = ref.read(selectedStationsProvider);
  if (!selected.isComplete) return;

  final repo = ref.read(stationRepositoryProvider);
  final timetableSource = ref.read(timetableDataSourceProvider);
  final useCase = SearchRoute(
    stationRepository: repo,
    timetableDataSource: timetableSource,
  );

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final (
      :fastest,
      :leastTransfer,
      :fastestExpress,
      :fastestLocal,
    ) = await useCase.executeAll(
      selected.departure!.id,
      selected.arrival!.id,
      viaStationIds: selected.waypointStationIds,
    );

    if (!context.mounted) return;
    Navigator.of(context).pop();

    if (fastest != null) {
      context.go('/route-result', extra: (
        fastest: fastest,
        leastTransfer: leastTransfer,
        fastestExpress: fastestExpress,
        fastestLocal: fastestLocal,
        departureStationName: selected.departure!.name,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('경로를 찾을 수 없습니다')),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('경로 검색 실패: $e')),
    );
  }
}
