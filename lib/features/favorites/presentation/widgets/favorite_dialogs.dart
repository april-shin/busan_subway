import 'package:flutter/material.dart';

import '../providers/favorite_routes_provider.dart';

/// 가득 찬 상태에서 등록을 시도했을 때의 안내.
const String favoriteLimitMessage = '즐겨찾기는 최대 $maxFavoriteRoutes개까지예요';

/// 같은 경로가 이미 있을 때의 안내.
const String favoriteDuplicateMessage = '이미 같은 경로의 즐겨찾기가 있어요';

/// 기기 저장소에 쓰지 못했을 때의 안내.
const String favoriteSaveFailedMessage = '즐겨찾기를 저장하지 못했어요';

/// 실패 결과를 사용자 안내 문구로. 안내할 것이 없으면(success·notFound) null.
String? favoriteResultMessage(FavoriteSaveResult result) => switch (result) {
  FavoriteSaveResult.full => favoriteLimitMessage,
  FavoriteSaveResult.duplicate => favoriteDuplicateMessage,
  FavoriteSaveResult.saveFailed => favoriteSaveFailedMessage,
  FavoriteSaveResult.success || FavoriteSaveResult.notFound => null,
};

/// [result] 가 실패면 스낵바로 알린다. [context] 가 이미 떠났으면 무시.
void showFavoriteResultSnackBar(
  BuildContext context,
  FavoriteSaveResult result,
) {
  final message = favoriteResultMessage(result);
  if (message == null || !context.mounted) return;
  showFavoriteSnackBar(context, message);
}

/// 현재 화면에 짧은 스낵바를 띄운다(앞선 스낵바는 바로 걷는다).
void showFavoriteSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 별칭 입력칸 — 최대 [maxFavoriteAliasLength]자, 비우면 [defaultLabel] 로 표시됨을
/// 힌트로 알린다. 경로 결과의 등록 다이얼로그와 설정의 수정 다이얼로그가 공유한다.
class FavoriteAliasField extends StatelessWidget {
  final TextEditingController controller;
  final String defaultLabel;
  final bool autofocus;

  const FavoriteAliasField({
    super.key,
    required this.controller,
    required this.defaultLabel,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLength: maxFavoriteAliasLength,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        // 예시("ex) 출근길")만 보통 굵기·작은 글씨 — 라벨 기본 스타일은 테마를 따른다.
        label: const Text.rich(
          TextSpan(
            text: '경로 이름 ',
            children: [
              TextSpan(
                text: 'ex) 출근길',
                style: TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
              ),
            ],
          ),
        ),
        // 비워 두면 쓰일 기본 이름을 힌트로만 보여 준다(역을 아직 안 골랐으면 없음).
        hintText: defaultLabel.isEmpty ? null : defaultLabel,
      ),
    );
  }
}

/// 별칭을 입력받는 등록 다이얼로그. 취소하면 null, 등록하면 trim 한 별칭
/// (빈 문자열 가능)을 돌려준다.
Future<String?> showFavoriteAliasDialog(
  BuildContext context, {
  required String defaultLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FavoriteAliasDialog(defaultLabel: defaultLabel),
  );
}

class _FavoriteAliasDialog extends StatefulWidget {
  final String defaultLabel;

  const _FavoriteAliasDialog({required this.defaultLabel});

  @override
  State<_FavoriteAliasDialog> createState() => _FavoriteAliasDialogState();
}

class _FavoriteAliasDialogState extends State<_FavoriteAliasDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('즐겨찾기 추가'),
      content: FavoriteAliasField(
        controller: _controller,
        defaultLabel: widget.defaultLabel,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('추가'),
        ),
      ],
    );
  }
}

/// 즐겨찾기 삭제 확인. 삭제를 고르면 true.
Future<bool> confirmDeleteFavorite(BuildContext context, String label) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('즐겨찾기 삭제'),
      content: Text('"$label" 즐겨찾기를 삭제할까요?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
