import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_info.dart';
import '../../../../core/theme/tokens/app_dimensions.dart';
import '../providers/home_station_provider.dart';
import '../widgets/feedback_tile.dart';

/// iOS-native 스타일의 flat 리스트형 설정 화면.
///
/// - 배경: 옅은 회색 (`surfaceContainerLowest` 계열)
/// - 섹션: 회색 라벨 헤더 + 흰 배경 리스트 그룹 (카드 컨테이너 없이 divider 로만 구분)
/// - 아이템: 좌측 아이콘 + 텍스트 + (탭 가능 시) chevron
/// - 하단: 저작권 + 크레딧
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final homeStationAsync = ref.watch(homeStationProvider);
    final homeStation = homeStationAsync.value;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: colorScheme.surfaceContainerLow,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.space32),
        children: [
          const SizedBox(height: AppSpacing.space8),

          // ─── 지도 ─────────────────────────────
          const _SectionHeader('지도'),
          _SectionGroup(
            children: [
              _SettingsTile(
                icon: Icons.my_location_outlined,
                title: '지도 시작점',
                trailingText: homeStation?.name ?? '서울역 (기본)',
                onTap: () => context.go('/pick-station/home'),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.space20),

          // ─── 지원 ─────────────────────────────
          const _SectionHeader('지원'),
          const _SectionGroup(
            children: [
              FeedbackTile(),
            ],
          ),

          const SizedBox(height: AppSpacing.space20),

          // ─── 앱 정보 (버전 + 데이터 제공) ─────────────
          const _SectionHeader('앱 정보'),
          _SectionGroup(
            children: [
              _SettingsTile(
                icon: Icons.info_outline,
                title: AppInfo.versionLabel,
              ),
              _SettingsTile(
                icon: Icons.train_outlined,
                title: '실시간 열차 도착 정보',
                trailingText: '서울 열린데이터광장',
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.space32),

          // ─── 하단 크레딧 ─────────────────────────────
          const _Footer(),
        ],
      ),
    );
  }
}

/// 카드 밖에 뜨는 작은 회색 섹션 라벨.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space20,
        AppSpacing.space16,
        AppSpacing.space20,
        AppSpacing.space8,
      ),
      child: Text(
        title,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 하나의 섹션에 속하는 리스트 아이템 그룹. 흰 배경 + 아이템 사이 divider.
class _SectionGroup extends StatelessWidget {
  final List<Widget> children;
  const _SectionGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _intersperse(children),
      ),
    );
  }

  static List<Widget> _intersperse(List<Widget> items) {
    if (items.length <= 1) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        result.add(const _RowDivider());
      }
      result.add(items[i]);
    }
    return result;
  }
}

/// 아이콘 폭만큼 들여쓴 얇은 구분선.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 아이콘(24) + 좌측 패딩(20) + 아이콘-텍스트 간격(12) 만큼 들여쓰기.
      padding: const EdgeInsets.only(left: 56),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: Theme.of(context).dividerColor,
      ),
    );
  }
}

/// 단일 리스트 아이템. iOS UITableViewCell 스타일.
///
/// - `onTap` 이 주어지면 우측에 chevron 표시.
/// - `trailingText` 는 chevron 대신 값 표기(예: 설정된 언어) 용도로 사용.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final String? trailingText;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space20,
          vertical: AppSpacing.space16,
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.space12),
            Expanded(
              child: Text(
                title,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (onTap != null) const SizedBox(width: AppSpacing.space4),
            ],
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }
}

/// 화면 하단 저작권 + 크레딧.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space20,
        vertical: AppSpacing.space16,
      ),
      child: Column(
        children: [
          Text(
            '© 2026 April',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            '공공 데이터 기반이며 실제 운행과 차이가 있을 수 있습니다.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
