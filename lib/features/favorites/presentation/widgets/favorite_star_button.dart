import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/favorite_route.dart';
import '../../../../domain/entities/station.dart';
import '../providers/favorite_routes_provider.dart';
import 'favorite_dialogs.dart';

/// 경로 결과 화면 AppBar 의 즐겨찾기 별 버튼.
///
/// 이 결과의 출발·경유·도착과 같은 즐겨찾기가 있으면 채워진 별(탭 = 해제),
/// 없으면 빈 별(탭 = 별칭 입력 후 등록). 가득 찼으면 다이얼로그를 띄우기 전에
/// 막고 안내한다 — 별칭을 다 입력한 뒤에 거절당하지 않게.
class FavoriteStarButton extends ConsumerWidget {
  final Station departure;
  final Station arrival;
  final List<Station> waypoints;

  const FavoriteStarButton({
    super.key,
    required this.departure,
    required this.arrival,
    this.waypoints = const [],
  });

  FavoriteRoute get _route => FavoriteRoute(
    departureId: departure.id,
    arrivalId: arrival.id,
    waypointIds: [for (final w in waypoints) w.id],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteRoutesProvider).asData?.value;
    // 로딩/에러 중에는 상태를 단정할 수 없으므로 버튼을 그리지 않는다.
    if (favorites == null) return const SizedBox.shrink();

    final route = _route;
    final isFavorite = favorites.any(route.hasSameRouteAs);
    return IconButton(
      icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded),
      tooltip: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
      onPressed: () => isFavorite
          ? _remove(context, ref, route)
          : _add(context, ref, favorites.length),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    FavoriteRoute route,
  ) async {
    final result = await ref
        .read(favoriteRoutesProvider.notifier)
        .remove(route);
    if (!context.mounted) return;
    showFavoriteResultSnackBar(context, result);
  }

  Future<void> _add(BuildContext context, WidgetRef ref, int count) async {
    if (count >= maxFavoriteRoutes) {
      showFavoriteSnackBar(context, favoriteLimitMessage);
      return;
    }
    // 다이얼로그(await) 뒤에 ref 를 쓰지 않도록 notifier 를 먼저 잡아 둔다.
    final notifier = ref.read(favoriteRoutesProvider.notifier);
    final alias = await showFavoriteAliasDialog(
      context,
      defaultLabel: defaultFavoriteLabel(departure, arrival),
    );
    if (alias == null) return;
    final result = await notifier.add(_route.copyWith(alias: alias));
    if (!context.mounted) return;
    showFavoriteResultSnackBar(context, result);
  }
}
