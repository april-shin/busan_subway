import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_info.dart';
import '../../../../core/theme/tokens/app_dimensions.dart';
import '../../../../core/theme/tokens/app_radii.dart';
import '../providers/feedback_provider.dart';

/// 설정 화면의 "개발자에게 의견보내기" 확장형 tile.
///
/// tile 을 탭하면 아래로 확장되어 TextField + 전송 버튼이 나타난다. 전송
/// 성공 시 SnackBar 알림 + 필드 초기화 + 접힘 상태로 복귀한다.
///
/// 로컬 상태(expanded/입력값/전송중)는 이 위젯 안에서만 완결되므로 프로바이더
/// 없이 `ConsumerStatefulWidget` 으로 유지한다. 데이터 소스만 프로바이더에서
/// 주입받는다.
class FeedbackTile extends ConsumerStatefulWidget {
  const FeedbackTile({super.key});

  @override
  ConsumerState<FeedbackTile> createState() => _FeedbackTileState();
}

class _FeedbackTileState extends ConsumerState<FeedbackTile> {
  final _controller = TextEditingController();
  bool _expanded = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 텍스트 변경 시 전송 버튼 활성 상태를 재계산해야 하므로 리스너 등록.
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // rebuild 트리거만 필요. setState 로 아무것도 안 바꿔도 OK.
    setState(() {});
  }

  bool get _canSend => !_sending && _controller.text.trim().isNotEmpty;

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dataSource = ref.read(slackFeedbackDataSourceProvider);
      await dataSource.sendFeedback(
        message: message,
        appVersion: AppInfo.versionLabel,
        platform: _platformLabel(),
        osVersion: _osVersion(),
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _sending = false;
        _expanded = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('의견이 전송되었습니다. 감사합니다!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('전송에 실패했어요. 잠시 후 다시 시도해 주세요.'),
        ),
      );
    }
  }

  String _platformLabel() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  /// OS 버전 문자열. 웹 등 `Platform` 접근 불가한 환경에서는 fallback.
  String _osVersion() {
    if (kIsWeb) return 'Web';
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return 'unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 헤더: 아이콘 + 제목 + chevron ──
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space20,
              vertical: AppSpacing.space16,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 24,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.space12),
                Expanded(
                  child: Text(
                    '개발자에게 의견보내기',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 22,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
        // ── 확장 영역: TextField + 전송 버튼 ──
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.space20,
                    0,
                    AppSpacing.space20,
                    AppSpacing.space16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TextField(
                        controller: _controller,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 500,
                        enabled: !_sending,
                        decoration: InputDecoration(
                          hintText: '버그 신고, 개선 아이디어 등을 자유롭게 남겨주세요.',
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: AppBorderRadius.md,
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.all(AppSpacing.space12),
                        ),
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.space8),
                      FilledButton.icon(
                        onPressed: _canSend ? _send : null,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send, size: 16),
                        label: Text(_sending ? '전송 중...' : '전송'),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
