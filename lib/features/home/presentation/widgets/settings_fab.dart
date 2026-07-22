import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 지도 위에 떠 있는(floating) 설정 진입 버튼.
///
/// 홈 화면 좌측 하단에 배치되며, 지도의 줌/팬 영역을 최소로만 가리도록
/// 원형 아이콘 버튼(48dp) 크기로 제한한다.
class SettingsFab extends StatelessWidget {
  const SettingsFab({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 검색바와 톤을 맞춘 하단 그림자 이중 레이어를 위해 DecoratedBox 로
    // 감싼다. Material.elevation 은 0 으로 두어 그림자가 중복되지 않게 함.
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.go('/settings'),
          child: Tooltip(
            message: '설정',
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.settings_outlined,
                color: colorScheme.onSurface,
                size: 24,
                semanticLabel: '설정',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
