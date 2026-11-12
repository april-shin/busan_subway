import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../domain/entities/favorite_route.dart';
import '../providers/favorite_routes_provider.dart';
import 'favorite_dialogs.dart';
import 'favorite_edit_dialog.dart';

/// 설정 화면 "즐겨찾기" 섹션의 본문 — 목록(드래그로 순서 변경) + 추가 행.
///
/// 목록 순서가 곧 홈 태그 순서다. 현재 역 목록에서 못 찾는 역이 든 항목도
/// 지울 수 있도록 여기서는 숨기지 않고 "홈에 표시되지 않아요" 로 안내한다.
class FavoriteSettingsList extends ConsumerWidget {
  const FavoriteSettingsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value`: 변경 직후 재계산(AsyncLoading) 중에도 이전 목록을 유지해 목록이
    // 한 프레임 비었다 다시 생기는 깜빡임을 막는다.
    final favorites =
        ref.watch(resolvedFavoriteRoutesProvider).value ??
        const <ResolvedFavoriteRoute>[];
    // await(다이얼로그·저장) 뒤에 ref 를 쓰지 않도록 notifier 를 먼저 잡아 둔다.
    final notifier = ref.read(favoriteRoutesProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (favorites.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // 손잡이로만 끈다 — 행 탭(수정)·삭제 버튼과 제스처가 겹치지 않게.
              buildDefaultDragHandles: false,
              itemCount: favorites.length,
              // onReorderItem 의 newIndex 는 이미 "이동 후 목록" 기준 최종 위치다.
              onReorderItem: (oldIndex, newIndex) async {
                final result = await notifier.move(oldIndex, newIndex);
                if (!context.mounted) return;
                showFavoriteResultSnackBar(context, result);
              },
              // 다이얼로그·스낵바는 행이 아니라 이 섹션의 context 로 띄운다 —
              // 삭제되면 행 context 는 사라진다.
              itemBuilder: (_, index) {
                final favorite = favorites[index];
                return _FavoriteRow(
                  key: ValueKey(favorite.route),
                  index: index,
                  favorite: favorite,
                  onTap: () => showFavoriteEditDialog(
                    context,
                    initial: favorite,
                    onSave: (draft) => notifier.replace(favorite.route, draft),
                  ),
                  onDelete: () async {
                    final confirmed = await confirmDeleteFavorite(
                      context,
                      favorite.label,
                    );
                    if (!confirmed) return;
                    final result = await notifier.remove(favorite.route);
                    if (!context.mounted) return;
                    showFavoriteResultSnackBar(context, result);
                  },
                );
              },
            ),
          if (favorites.isNotEmpty) const Divider(height: 1, thickness: 0.5),
          _AddRow(
            count: favorites.length,
            onTap: () {
              if (favorites.length >= maxFavoriteRoutes) {
                showFavoriteSnackBar(context, favoriteLimitMessage);
                return;
              }
              showFavoriteEditDialog(context, onSave: notifier.add);
            },
          ),
        ],
      ),
    );
  }
}

class _FavoriteRow extends StatelessWidget {
  final int index;
  final ResolvedFavoriteRoute favorite;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _FavoriteRow({
    super.key,
    required this.index,
    required this.favorite,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final path = [
      favorite.departure,
      ...favorite.waypoints,
      favorite.arrival,
    ].map((s) => s?.name ?? '알 수 없는 역').join(' → ');

    // 드래그 중 떠오른 행도 배경이 비치지 않도록 Material 로 감싼다.
    return Material(
      color: colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.space20,
            top: AppSpacing.space8,
            bottom: AppSpacing.space8,
          ),
          child: Row(
            children: [
              Icon(Icons.star_rounded, size: 24, color: colorScheme.primary),
              const SizedBox(width: AppSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favorite.label,
                      // 테마의 bodyLarge 는 w700 — 다른 설정 행과 같은 굵기로.
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      path,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!favorite.isComplete)
                      Text(
                        '찾을 수 없는 역이 있어 홈에 표시되지 않아요',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '삭제',
                onPressed: onDelete,
              ),
              ReorderableDragStartListener(
                index: index,
                child: Semantics(
                  label: '순서 변경',
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.space4,
                      right: AppSpacing.space16,
                      top: AppSpacing.space12,
                      bottom: AppSpacing.space12,
                    ),
                    child: Icon(
                      Icons.drag_handle,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _AddRow({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space20,
          vertical: AppSpacing.space16,
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 24, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.space12),
            Expanded(
              child: Text(
                '즐겨찾기 추가',
                // 테마의 bodyLarge 는 w700 — 설정 화면의 다른 행(_SettingsTile)과
                // 같은 굵기로 맞춘다.
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Text(
              '$count/$maxFavoriteRoutes',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
