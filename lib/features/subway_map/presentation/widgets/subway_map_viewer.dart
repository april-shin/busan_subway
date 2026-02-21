import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/entities/station.dart';
import '../../../../domain/entities/connection.dart';
import '../providers/subway_map_providers.dart';
import 'route_highlight_painter.dart';
import 'station_selection_indicator.dart';
import 'station_tooltip.dart';

/// SVG 기반 지하철 노선도 뷰어.
///
/// 필터링된 SVG 파일을 배경으로 렌더링하고, 그 위에
/// 경로 하이라이트, 선택 표시, 탭 감지 레이어, 툴팁을 오버레이한다.
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
  late TransformationController _transformController;

  /// SVG viewBox와 동일한 캔버스 크기.
  static const _canvasWidth = 2416.0;
  static const _canvasHeight = 1560.0;

  /// 역 탭 감지 반경 (제곱값으로 비교).
  static const _tapHitRadius = 12.0;
  static const _tapHitRadiusSq = _tapHitRadius * _tapHitRadius;

  /// 2호선 순환 구간 시각적 중심 (SVG 좌표계 기준).
  static const _initialFocusCenterX = 1260.0;
  static const _initialFocusCenterY = 1240.0;
  static const _initialScale = 0.25;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerOnLine2Rectangle();
    });
  }

  void _centerOnLine2Rectangle() {
    final viewSize = context.size;
    if (viewSize == null) return;

    final tx = -(_initialFocusCenterX -
        viewSize.width / (2 * _initialScale));
    final ty = -(_initialFocusCenterY -
        viewSize.height / (2 * _initialScale));

    final matrix = Matrix4.identity()
      ..scaleByDouble(_initialScale, _initialScale, 1, 1)
      ..translateByDouble(tx, ty, 0, 0);

    _transformController.value = matrix;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// labelDirection(0-7)에 따른 라벨 오프셋을 반환한다.
  /// 0=오른쪽, 1=우하, 2=아래, 3=좌하, 4=왼쪽, 5=좌상, 6=위, 7=우상.
  static Offset _labelOffset(int direction) {
    const d = 10.0;
    switch (direction) {
      case 0:
        return const Offset(d, -4);
      case 1:
        return const Offset(d, d);
      case 2:
        return const Offset(-4, d);
      case 3:
        return Offset(-d - 30, d);
      case 4:
        return Offset(-d - 30, -4);
      case 5:
        return Offset(-d - 30, -d - 6);
      case 6:
        return const Offset(-4, -d - 6);
      case 7:
        return Offset(d, -d - 6);
      default:
        return const Offset(d, -4);
    }
  }

  Station? _findNearestStation(Offset tapPosition) {
    Station? closest;
    var closestDistSq = double.infinity;

    for (final station in widget.stations) {
      final dx = station.svgX - tapPosition.dx;
      final dy = station.svgY - tapPosition.dy;
      final distSq = dx * dx + dy * dy;
      if (distSq < closestDistSq && distSq < _tapHitRadiusSq) {
        closestDistSq = distSq;
        closest = station;
      }
    }

    return closest;
  }

  @override
  Widget build(BuildContext context) {
    final selectedStations = ref.watch(selectedStationsProvider);
    final tappedStation = ref.watch(tappedStationProvider);
    const canvasSize = Size(_canvasWidth, _canvasHeight);
    const offset = StationSelectionIndicator.indicatorOffset;

    return GestureDetector(
      onTap: () {
        if (tappedStation != null) {
          ref.read(tappedStationProvider.notifier).state = null;
        }
      },
      child: InteractiveViewer(
        transformationController: _transformController,
        boundaryMargin: const EdgeInsets.all(200),
        minScale: 0.1,
        maxScale: 5.0,
        constrained: false,
        child: SizedBox(
          width: canvasSize.width,
          height: canvasSize.height,
          child: Stack(
            children: [
              // 레이어 1: SVG 지도 (노선, 역 마커)
              RepaintBoundary(
                child: SvgPicture.asset(
                  'assets/svg/seoul_subway_map_filtered.svg',
                  width: canvasSize.width,
                  height: canvasSize.height,
                ),
              ),

              // 레이어 2: 역명 라벨 (SVG에서 텍스트 제거 → Flutter 위젯으로 표시)
              ...widget.stations.map((station) {
                final labelOff = _labelOffset(station.labelDirection);
                return Positioned(
                  left: station.svgX + labelOff.dx,
                  top: station.svgY + labelOff.dy,
                  child: Text(
                    station.name,
                    style: const TextStyle(
                      fontSize: 7,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }),

              // 레이어 3: 경로 하이라이트 오버레이
              if (widget.routeStationIds.isNotEmpty)
                CustomPaint(
                  size: canvasSize,
                  painter: RouteHighlightPainter(
                    stations: widget.stations,
                    connections: widget.connections,
                    routeStationIds: widget.routeStationIds,
                  ),
                ),

              // 레이어 4: 출발/도착 선택 표시
              if (selectedStations.departure != null)
                Positioned(
                  left: selectedStations.departure!.svgX - offset,
                  top: selectedStations.departure!.svgY - offset,
                  child: StationSelectionIndicator(
                    station: selectedStations.departure!,
                    isDeparture: true,
                  ),
                ),
              if (selectedStations.arrival != null)
                Positioned(
                  left: selectedStations.arrival!.svgX - offset,
                  top: selectedStations.arrival!.svgY - offset,
                  child: StationSelectionIndicator(
                    station: selectedStations.arrival!,
                    isDeparture: false,
                  ),
                ),

              // 레이어 5: 역 탭 감지 (단일 GestureDetector, 최근접 역 탐색)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    final station = _findNearestStation(details.localPosition);
                    if (station != null) {
                      ref.read(tappedStationProvider.notifier).state = station;
                    }
                  },
                  child: const SizedBox.expand(),
                ),
              ),

              // 레이어 6: 툴팁
              if (tappedStation != null)
                Positioned(
                  left: (tappedStation.svgX - 60)
                      .clamp(0, canvasSize.width - 120),
                  top: max(0, tappedStation.svgY - 100),
                  child: StationTooltip(
                    station: tappedStation,
                    onSetDeparture: () {
                      ref
                          .read(selectedStationsProvider.notifier)
                          .setDeparture(tappedStation);
                      ref.read(tappedStationProvider.notifier).state = null;
                    },
                    onSetArrival: () {
                      ref
                          .read(selectedStationsProvider.notifier)
                          .setArrival(tappedStation);
                      ref.read(tappedStationProvider.notifier).state = null;
                    },
                    onViewArrivalInfo: () {
                      ref.read(tappedStationProvider.notifier).state = null;
                      context.go('/arrivals/${tappedStation.name}');
                    },
                    onDismiss: () {
                      ref.read(tappedStationProvider.notifier).state = null;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
