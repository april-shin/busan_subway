import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 자식의 **높이**를 측정해, 값이 실제로 바뀔 때만 [onHeight] 로 알린다.
///
/// 홈 화면이 검색 카드 아래쪽 경계를 지도(JS)에 넘기는 데 쓴다. 카드 높이는
/// 태그 줄 유무·경유역 칸 수·화면 회전으로 바뀌므로 첫 레이아웃 뒤 한 번,
/// 이후 크기 변화마다 다시 측정한다. 측정은 프레임 끝(post-frame)에서 해
/// 빌드 중 상태 변경을 피한다.
class HeightReporter extends StatefulWidget {
  final Widget child;
  final ValueChanged<double> onHeight;

  const HeightReporter({
    super.key,
    required this.child,
    required this.onHeight,
  });

  @override
  State<HeightReporter> createState() => _HeightReporterState();
}

class _HeightReporterState extends State<HeightReporter> {
  double? _last;
  bool _scheduled = false;

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final h = box.size.height;
      if (h == _last) return;
      _last = h;
      widget.onHeight(h);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 초기 레이아웃은 알림이 오지 않으므로 build 마다 한 번 예약한다
    // (같은 값이면 위에서 걸러져 onHeight 는 호출되지 않는다).
    _schedule();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _schedule();
        return false;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}
