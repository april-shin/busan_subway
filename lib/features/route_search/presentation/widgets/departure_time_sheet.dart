import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../core/theme/tokens/app_radii.dart';
import '../../utils/departure_candidates.dart';
import '../../utils/departure_query_time.dart';

/// 요일 타입별 선택 가능한 출발시각 목록.
///
/// 값은 운영일 자정 기준 분이며, 비어 있으면 해당 요일에 역별 시간표 데이터가
/// 없다는 뜻이다(배차간격 추정치로 채우지 않는다).
@immutable
class DepartureOptions {
  final List<int> weekday;
  final List<int> weekend;

  const DepartureOptions({required this.weekday, required this.weekend});

  static const empty = DepartureOptions(weekday: [], weekend: []);

  List<int> forDayType(DepartureDayType type) =>
      type == DepartureDayType.weekday ? weekday : weekend;

  /// 어느 요일이든 고를 수 있는 시각이 하나라도 있는지.
  bool get hasAny => weekday.isNotEmpty || weekend.isNotEmpty;
}

/// 출발시각 선택 시트를 띄우고 사용자가 고른 값을 돌려준다.
/// 취소하면 null.
///
/// 호출측(결과 화면 요약 헤더)은 고를 수 있는 시각이 있을 때만 이 시트를 연다 —
/// 배차간격으로 추정한 시각을 고르게 하지 않기 위해서다.
Future<DepartureQueryTime?> showDepartureTimeSheet({
  required BuildContext context,
  required DepartureQueryTime query,
  required DepartureOptions options,
  required int referenceMinutes,
}) {
  return showModalBottomSheet<DepartureQueryTime>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DepartureTimeSheet(
      query: query,
      options: options,
      referenceMinutes: referenceMinutes,
    ),
  );
}

/// 역 시간표 그리드 시트 — 평일/주말 토글 + 시(hour) 행 × 분 칩.
class _DepartureTimeSheet extends StatefulWidget {
  final DepartureQueryTime query;
  final DepartureOptions options;

  /// 결과 화면에 실제로 떠 있는 출발 시각(자정 기준 분, 0~1439).
  /// 시트는 이 시각을 시간표 위에 짚어준다 — 화면과 시트가 다른 곳을 가리키면
  /// 사용자는 "내 열차가 어디 있지"를 다시 찾아야 한다.
  final int referenceMinutes;

  const _DepartureTimeSheet({
    required this.query,
    required this.options,
    required this.referenceMinutes,
  });

  @override
  State<_DepartureTimeSheet> createState() => _DepartureTimeSheetState();
}

class _DepartureTimeSheetState extends State<_DepartureTimeSheet> {
  late DepartureDayType _dayType = _initialDayType();
  final _scrollController = ScrollController();

  /// 시트를 열었을 때 보여줄 요일 타입.
  ///
  /// 기본은 현재 조회 요일이지만, 그쪽에 데이터가 없고 반대쪽에는 있으면 반대쪽을
  /// 연다. 경춘·수인분당은 주말 급행 시간표(`we.tE`)가 비어 있어서, 주말에 앱을
  /// 열면 시트가 빈 화면으로 뜨는 것을 막는다.
  DepartureDayType _initialDayType() {
    // "지금 출발" 상태에서는 query.dayType 이 계산에 쓰이지 않아 신뢰할 수 없다.
    // 이 경우 오늘 요일을 기준으로 연다.
    final preferred = widget.query.isNow
        ? dayTypeOf(DateTime.now())
        : widget.query.dayType;
    if (widget.options.forDayType(preferred).isNotEmpty) return preferred;

    final fallback = preferred == DepartureDayType.weekday
        ? DepartureDayType.weekend
        : DepartureDayType.weekday;
    return widget.options.forDayType(fallback).isNotEmpty ? fallback : preferred;
  }

  /// 시트를 열자마자 스크롤할 목표 행 index. 레이아웃 후 1회만 사용한다.
  int? _pendingScrollRow;

  @override
  void initState() {
    super.initState();
    _scheduleInitialScroll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 화면의 출발 시각이 이 요일 시간표에 대응될 때만 위치를 짚는다.
  /// 다른 요일로 토글했다면 그 시각은 이 표와 무관하다.
  bool get _showsReference => _dayType == widget.query.dayType;

  /// 시간표에서 짚어줄 칩.
  ///
  /// 화면 출발 시각과 **같은 벽시계 시각**의 칩을 먼저 찾는다. 자정 넘김을
  /// 1440+ 로 담는 노선이 있어 `% 1440` 으로 맞춰 비교한다. 실시간 보정으로
  /// 시간표에 없는 시각이 나올 수도 있으므로, 없으면 그 이후 첫 열차로 폴백한다.
  int? get _referenceMinutes {
    if (!_showsReference) return null;
    final candidates = widget.options.forDayType(_dayType);
    for (final m in candidates) {
      if (m % 1440 == widget.referenceMinutes) return m;
    }
    return findUpcomingDeparture(candidates, widget.referenceMinutes);
  }

  /// 시트 상단에 기준 시각을 알리는 한 줄.
  String get _referenceCaption {
    final clock = formatOperatingMinutes(widget.referenceMinutes);
    if (!_showsReference) return '${_dayType.label} 시간표';
    return '현재 $clock 출발';
  }

  /// 기존 선택(없으면 화면 출발 시각)이 속한 시(hour) 행으로 스크롤을 예약한다.
  ///
  /// 행 높이가 가변(분 칩 줄바꿈)이라 오프셋을 정확히 계산할 수 없으므로,
  /// 첫 프레임 뒤 `Scrollable.ensureVisible` 로 해당 행을 화면에 들인다.
  void _scheduleInitialScroll() {
    final rows = groupDeparturesByHour(widget.options.forDayType(_dayType));
    final index = resolveInitialScrollRow(
      rows: rows,
      selectedMinutes: widget.query.minutes,
      upcomingMinutes: _referenceMinutes,
    );
    _pendingScrollRow = index < 0 ? null : index;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = groupDeparturesByHour(widget.options.forDayType(_dayType));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppPadding.screenHorizontal,
              ),
              child: Column(
                children: [
                  Text(
                    '출발 시각 선택',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  // 화면에 떠 있는 출발 시각. 아래 그리드에서 같은 칩에
                  // 테두리를 둘러 시간표 어디쯤인지 짚어준다.
                  Text(
                    _referenceCaption,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.hintColor),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space12),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppPadding.screenHorizontal,
              ),
              child: SegmentedButton<DepartureDayType>(
                segments: [
                  for (final type in DepartureDayType.values)
                    ButtonSegment(value: type, label: Text(type.label)),
                ],
                selected: {_dayType},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _dayType = selection.first);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.space8),
            ListTile(
              leading: const Icon(Icons.my_location, size: AppIconSize.md),
              title: const Text('지금 출발'),
              subtitle: const Text('실시간 도착정보 사용'),
              selected: widget.query.isNow,
              onTap: () => Navigator.of(context).pop(
                // 시트에서 토글한 요일은 넘기지 않는다 — "지금 출발"에서는
                // 의미가 없고, 남겨두면 다음 열람 때 그 요일로 열린다.
                DepartureQueryTime.nowAt(DateTime.now()),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: rows.isEmpty
                  ? _EmptyTimetable(dayType: _dayType)
                  : _TimetableGrid(
                      rows: rows,
                      scrollController: _scrollController,
                      selectedMinutes:
                          widget.query.dayType == _dayType
                              ? widget.query.minutes
                              : null,
                      upcomingMinutes: _referenceMinutes,
                      initialScrollRow: _pendingScrollRow,
                      onScrollHandled: () => _pendingScrollRow = null,
                      onSelected: (minutes) => Navigator.of(context).pop(
                        DepartureQueryTime(
                          minutes: minutes,
                          dayType: _dayType,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTimetable extends StatelessWidget {
  final DepartureDayType dayType;

  const _EmptyTimetable({required this.dayType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space32),
      child: Center(
        child: Text(
          '${dayType.label} 시간표 데이터가 없습니다',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// 시(hour) 행 × 분 칩 그리드. 종이 시간표와 같은 배치다.
class _TimetableGrid extends StatelessWidget {
  final List<({int hour, List<int> minutes})> rows;
  final ScrollController scrollController;
  final int? selectedMinutes;

  /// 현재 시각 이후 첫 출발 — 테두리로 "지금 여기"를 짚어준다.
  final int? upcomingMinutes;
  final int? initialScrollRow;
  final VoidCallback onScrollHandled;
  final ValueChanged<int> onSelected;

  const _TimetableGrid({
    required this.rows,
    required this.scrollController,
    required this.selectedMinutes,
    required this.upcomingMinutes,
    required this.initialScrollRow,
    required this.onScrollHandled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // 지연 빌드(`ListView.builder`)를 쓰지 않고 전 행을 한 번에 만든다.
    // 초기 스크롤이 `Scrollable.ensureVisible` 기반인데, 지연 빌드에서는 목표
    // 행이 viewport + cacheExtent 밖이면 아예 마운트되지 않아 스크롤이 조용히
    // 무시된다. 행 수는 운행 시간대(대략 05시~24시) 상한이라 20여 개뿐이므로
    // 전부 만들어도 시트 1회 오픈 비용으로 충분하다.
    return SingleChildScrollView(
      controller: scrollController,
      // 마지막 행(심야 열차)이 화면 맨 아래에 딱 붙으면 누르기 불편하므로
      // 아래쪽 여백을 넉넉히 준다.
      padding: const EdgeInsets.fromLTRB(
        AppPadding.screenHorizontal,
        AppSpacing.space8,
        AppPadding.screenHorizontal,
        AppSpacing.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            if (index == initialScrollRow)
              _EnsureVisibleOnce(
                onDone: onScrollHandled,
                child: _buildRow(context, rows[index]),
              )
            else
              _buildRow(context, rows[index]),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, ({int hour, List<int> minutes}) row) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppSpacing.space32,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space8),
              child: Text(
                (row.hour % 24).toString().padLeft(2, '0'),
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.space6,
              runSpacing: AppSpacing.space6,
              children: [
                for (final minutes in row.minutes)
                  _MinuteChip(
                    minutes: minutes,
                    selected: minutes == selectedMinutes,
                    isUpcoming: minutes == upcomingMinutes,
                    onTap: () => onSelected(minutes),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 첫 프레임 뒤 자기 자신을 화면에 들이는 1회성 래퍼.
class _EnsureVisibleOnce extends StatefulWidget {
  final Widget child;
  final VoidCallback onDone;

  const _EnsureVisibleOnce({required this.child, required this.onDone});

  @override
  State<_EnsureVisibleOnce> createState() => _EnsureVisibleOnceState();
}

class _EnsureVisibleOnceState extends State<_EnsureVisibleOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context, alignment: 0.1, duration: Duration.zero);
      widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MinuteChip extends StatelessWidget {
  final int minutes;
  final bool selected;

  /// 현재 시각 이후 첫 열차. 선택(채움)과 구분되도록 테두리로만 표시한다.
  final bool isUpcoming;
  final VoidCallback onTap;

  const _MinuteChip({
    required this.minutes,
    required this.selected,
    required this.isUpcoming,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: AppBorderRadius.sm,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space8,
          vertical: AppSpacing.space6,
        ),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: AppBorderRadius.sm,
          border: isUpcoming && !selected
              ? Border.all(color: scheme.primary, width: 1.5)
              : null,
        ),
        child: Text(
          // 시(hour)는 행 라벨이 담당하므로 칩은 분만 보여준다.
          (minutes % 60).toString().padLeft(2, '0'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: selected ? FontWeight.bold : null,
          ),
        ),
      ),
    );
  }
}
