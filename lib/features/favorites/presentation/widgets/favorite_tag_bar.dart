import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../domain/entities/favorite_route.dart';
import '../../../../domain/entities/station.dart';
import '../../../subway_map/presentation/providers/subway_map_providers.dart';
import '../providers/favorite_routes_provider.dart';
import 'favorite_dialogs.dart';

/// 홈 검색바의 도착역 칸 아래에 붙는 즐겨찾기 태그 줄(한 줄 가로 스크롤).
///
/// 자체 [ConsumerWidget] 이라 즐겨찾기 변경은 이 줄만 다시 그린다 — 지도
/// (`SubwayMapScreen`)의 리빌드를 유발하지 않는다.
///
/// 현재 역 목록에서 못 찾는 역이 든 즐겨찾기는 탭해도 경로를 만들 수 없으므로
/// 숨긴다. 보여 줄 태그가 없으면(없음/로딩/에러) 자리도 차지하지 않는다.
class FavoriteTagBar extends ConsumerWidget {
  const FavoriteTagBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(resolvedFavoriteRoutesProvider).value;
    final favorites = [
      for (final f in all ?? const <ResolvedFavoriteRoute>[])
        if (f.isComplete) f,
    ];
    if (favorites.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < favorites.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.space6),
              _FavoriteTag(
                label: favorites[i].label,
                onTap: () => _select(ref, favorites[i]),
                onLongPress: () => _confirmDelete(context, ref, favorites[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 출발·경유·도착을 한 번에 채우는 데까지만 한다. 선택이 완성되면 지도가
  /// 경로를 그려 주므로, 경로 결과 화면으로는 보내지 않는다(사용자 결정
  /// 2026-11-11) — 결과 화면은 검색 버튼이나 지도의 '경로 검색결과' 로 간다.
  void _select(WidgetRef ref, ResolvedFavoriteRoute favorite) {
    ref
        .read(selectedStationsProvider.notifier)
        .setRoute(
          favorite.departure!,
          favorite.arrival!,
          waypoints: [for (final w in favorite.waypoints) w as Station],
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ResolvedFavoriteRoute favorite,
  ) async {
    // 확인 다이얼로그(await) 뒤에 ref 를 쓰지 않도록 notifier 를 먼저 잡아 둔다.
    final notifier = ref.read(favoriteRoutesProvider.notifier);
    final confirmed = await confirmDeleteFavorite(context, favorite.label);
    if (!confirmed) return;
    final result = await notifier.remove(favorite.route);
    if (!context.mounted) return;
    showFavoriteResultSnackBar(context, result);
  }
}

class _FavoriteTag extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FavoriteTag({
    required this.label,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 길게 누르기가 삭제라 Tooltip(길게 눌러 표시)은 쓰지 않고, 스크린리더용
    // 힌트를 Semantics 로 준다.
    return Semantics(
      button: true,
      label: '즐겨찾기 $label',
      onTapHint: '경로 검색',
      onLongPressHint: '삭제',
      excludeSemantics: true,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            // 손가락으로 누르기 충분한 높이.
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 해시태그 모양 — '#' 을 이름 바로 앞에 붙인다.
                  Text(
                    '#',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
