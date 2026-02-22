import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/connection.dart';
import '../../../../domain/entities/station.dart';
import 'svg_web_view.dart';

/// 지하철 노선도 뷰어.
///
/// WebView 기반 SVG 렌더링으로 원본 SVG의 한국어 텍스트와 CSS를 완전히 지원한다.
class SubwayMapViewer extends ConsumerWidget {
  final List<Station> stations;
  final List<Connection> connections;
  final Set<String> routeStationIds;

  const SubwayMapViewer({
    super.key,
    required this.stations,
    required this.connections,
    this.routeStationIds = const {},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SvgWebView(
      stations: stations,
      connections: connections,
      routeStationIds: routeStationIds,
    );
  }
}
