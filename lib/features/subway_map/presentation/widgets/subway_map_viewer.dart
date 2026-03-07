import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/entities/connection.dart';
import '../../../../domain/entities/station.dart';
import '../../../../domain/usecases/search_route.dart';
import '../providers/subway_map_providers.dart';
import 'svg_web_view.dart';

/// 지하철 노선도 뷰어.
///
/// WebView 기반 SVG 렌더링으로 원본 SVG의 한국어 텍스트와 CSS를 완전히 지원한다.
/// 출발+도착 모두 선택 시 경로를 탐색하여 경유 노선을 강조하고,
/// 출발역으로 카메라를 부드럽게 이동한다.
class SubwayMapViewer extends ConsumerStatefulWidget {
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
  ConsumerState<SubwayMapViewer> createState() => _SubwayMapViewerState();
}

class _SubwayMapViewerState extends ConsumerState<SubwayMapViewer> {
  Set<String> _highlightedLineIds = const {};
  ({double x, double y})? _panTarget;
  int _computeRevision = 0;

  @override
  void initState() {
    super.initState();
    _maybeComputeHighlightedLines();
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod 공식 패턴: build 내 ref.listen은 중복 구독 자동 방지
    ref.listen(selectedStationsProvider, (prev, next) {
      _onSelectedStationsChanged(next);
    });

    return SvgWebView(
      stations: widget.stations,
      connections: widget.connections,
      routeStationIds: widget.routeStationIds,
      highlightedLineIds: _highlightedLineIds,
      panTarget: _panTarget,
    );
  }

  void _onSelectedStationsChanged(SelectedStations selected) {
    if (!selected.isComplete) {
      if (_highlightedLineIds.isNotEmpty) {
        setState(() {
          _highlightedLineIds = const {};
          _panTarget = null;
        });
      }
      return;
    }
    _computeHighlightedLines(selected);
  }

  void _maybeComputeHighlightedLines() {
    final selected = ref.read(selectedStationsProvider);
    if (selected.isComplete) {
      _computeHighlightedLines(selected);
    }
  }

  Future<void> _computeHighlightedLines(SelectedStations selected) async {
    final revision = ++_computeRevision;
    final repo = ref.read(stationRepositoryProvider);
    final useCase = SearchRoute(stationRepository: repo);

    try {
      final (:fastest, :leastTransfer) = await useCase.executeAll(
        selected.departure!.id,
        selected.arrival!.id,
      );

      if (!mounted || revision != _computeRevision) return;

      final lineIds = <String>{};
      if (fastest != null) {
        for (final segment in fastest.segments) {
          lineIds.add(segment.lineId);
        }
      }
      if (leastTransfer != null) {
        for (final segment in leastTransfer.segments) {
          lineIds.add(segment.lineId);
        }
      }

      setState(() {
        _highlightedLineIds = lineIds;
        _panTarget = (
          x: selected.departure!.svgX,
          y: selected.departure!.svgY,
        );
      });
    } catch (_) {
      if (!mounted || revision != _computeRevision) return;
      setState(() {
        _highlightedLineIds = const {};
        _panTarget = null;
      });
    }
  }
}
