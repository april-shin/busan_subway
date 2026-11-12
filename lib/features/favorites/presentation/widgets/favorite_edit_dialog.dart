import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/line_colors.dart';
import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../core/utils/same_station.dart';
import '../../../../domain/entities/favorite_route.dart';
import '../../../../domain/entities/station.dart';
import '../providers/favorite_routes_provider.dart';
import 'favorite_dialogs.dart';

/// 설정 화면의 즐겨찾기 추가/수정 다이얼로그.
///
/// [initial] 이 null 이면 추가, 아니면 수정이다. 출발·도착은 역 선택 화면을
/// `favorite-*` purpose 로 push 해 고른다 — 고른 역은 pop 결과로만 돌아오고
/// 홈의 현재 출발/도착(`selectedStationsProvider`)은 바뀌지 않는다.
///
/// 경유역은 이 화면에서 고를 수 없다(경유 즐겨찾기는 경로 결과의 별 버튼으로
/// 등록). 수정 시 출발·도착이 그대로면 기존 경유역을 유지하고, 둘 중 하나라도
/// 바꾸면 경유역을 지운다 — 옛 출발·도착 기준으로 고른 경유역이 새 경로에선
/// 엉뚱한 우회가 될 수 있어서다. 이 사실을 다이얼로그에 미리 안내한다.
///
/// [onSave] 가 [FavoriteSaveResult.success] 또는 `notFound` 를 돌려주면 닫고,
/// 그 밖의 결과(중복·가득 참)는 다이얼로그 안에 안내하고 머문다.
Future<void> showFavoriteEditDialog(
  BuildContext context, {
  ResolvedFavoriteRoute? initial,
  required Future<FavoriteSaveResult> Function(FavoriteRoute draft) onSave,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FavoriteEditDialog(initial: initial, onSave: onSave),
  );
}

class _FavoriteEditDialog extends StatefulWidget {
  final ResolvedFavoriteRoute? initial;
  final Future<FavoriteSaveResult> Function(FavoriteRoute draft) onSave;

  const _FavoriteEditDialog({required this.initial, required this.onSave});

  @override
  State<_FavoriteEditDialog> createState() => _FavoriteEditDialogState();
}

class _FavoriteEditDialogState extends State<_FavoriteEditDialog> {
  late final TextEditingController _alias = TextEditingController(
    text: widget.initial?.route.alias ?? '',
  );
  late Station? _departure = widget.initial?.departure;
  late Station? _arrival = widget.initial?.arrival;
  String? _error;
  bool _saving = false;

  FavoriteRoute? get _original => widget.initial?.route;

  /// 출발·도착이 원래 즐겨찾기와 같은지 — 같을 때만 경유역을 유지한다.
  bool get _keepsWaypoints {
    final original = _original;
    return original != null &&
        original.waypointIds.isNotEmpty &&
        _departure?.id == original.departureId &&
        _arrival?.id == original.arrivalId;
  }

  /// 유지할 경유 id — 현재 역 목록에서 찾지 못한 경유역은 뺀다.
  ///
  /// 죽은 경유 id 가 남으면 그 즐겨찾기는 계속 미완성이라 홈 태그에서 숨겨진다.
  /// 별칭만 고쳐도 홈에 다시 보이도록 저장할 때 걸러 낸다. (출발·도착이 죽은
  /// 항목은 저장 버튼이 막혀 있어 사용자가 다시 고르게 된다.)
  List<String> get _keptWaypointIds {
    if (!_keepsWaypoints) return const [];
    final ids = _original!.waypointIds;
    final resolved = widget.initial!.waypoints;
    return [
      for (var i = 0; i < ids.length; i++)
        if (i < resolved.length && resolved[i] != null) ids[i],
    ];
  }

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  Future<void> _pick(String purpose) async {
    final station = await context.push<Station>('/pick-station/$purpose');
    if (station == null || !mounted) return;
    setState(() {
      _error = null;
      if (purpose == 'favorite-departure') {
        _departure = station;
      } else {
        _arrival = station;
      }
    });
  }

  Future<void> _save() async {
    final departure = _departure;
    final arrival = _arrival;
    if (departure == null || arrival == null) return;
    if (isSamePhysicalStation(departure, arrival)) {
      setState(() => _error = '출발역과 도착역이 같아요');
      return;
    }
    final draft = FavoriteRoute(
      departureId: departure.id,
      arrivalId: arrival.id,
      waypointIds: _keptWaypointIds,
      alias: _alias.text.trim(),
    );
    setState(() => _saving = true);
    final result = await widget.onSave(draft);
    if (!mounted) return;
    switch (result) {
      case FavoriteSaveResult.success:
      case FavoriteSaveResult.notFound:
        Navigator.of(context).pop();
      case FavoriteSaveResult.duplicate:
      case FavoriteSaveResult.full:
      case FavoriteSaveResult.saveFailed:
        setState(() {
          _saving = false;
          _error = favoriteResultMessage(result);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final original = _original;
    final waypointNames = [
      for (final w in widget.initial?.waypoints ?? const <Station?>[])
        w?.name ?? '알 수 없는 역',
    ];
    final hasDeadWaypoint =
        widget.initial?.waypoints.any((w) => w == null) ?? false;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(original == null ? '즐겨찾기 추가' : '즐겨찾기 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FavoriteAliasField(
              controller: _alias,
              defaultLabel: _departure == null || _arrival == null
                  ? ''
                  : defaultFavoriteLabel(_departure, _arrival),
            ),
            const SizedBox(height: AppSpacing.space8),
            _StationPickRow(
              label: '출발',
              station: _departure,
              onTap: () => _pick('favorite-departure'),
            ),
            const SizedBox(height: AppSpacing.space8),
            _StationPickRow(
              label: '도착',
              station: _arrival,
              onTap: () => _pick('favorite-arrival'),
            ),
            if (waypointNames.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.space8),
              Text(
                _keepsWaypoints
                    ? '경유 ${waypointNames.join(', ')}\n출발·도착을 바꾸면 경유역은 빠져요'
                          '${hasDeadWaypoint ? '\n찾을 수 없는 경유역은 저장할 때 빠져요' : ''}'
                    : '출발·도착이 바뀌어 경유역(${waypointNames.join(', ')})은 빠져요',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.space8),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: _departure != null && _arrival != null && !_saving
              ? _save
              : null,
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 다이얼로그 안의 출발/도착 선택 칸. 탭하면 역 선택 화면으로 간다.
class _StationPickRow extends StatelessWidget {
  final String label;
  final Station? station;
  final VoidCallback onTap;

  const _StationPickRow({
    required this.label,
    required this.station,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final s = station;
    return Semantics(
      button: true,
      label: s == null ? '$label역 선택' : '$label역 ${s.name}, 바꾸기',
      excludeSemantics: true,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space12,
              vertical: AppSpacing.space12,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(label, style: textTheme.labelMedium),
                ),
                if (s != null) ...[
                  Icon(Icons.circle, size: 8, color: lineColorFor(s.lineId)),
                  const SizedBox(width: AppSpacing.space6),
                ],
                Expanded(
                  child: Text(
                    s?.name ?? '$label역을 선택하세요',
                    overflow: TextOverflow.ellipsis,
                    style: s != null
                        ? textTheme.labelLarge
                        : textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
