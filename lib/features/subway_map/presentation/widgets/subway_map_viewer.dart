import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/entities/station.dart';
import '../../../../domain/entities/connection.dart';
import '../providers/subway_map_providers.dart';
import 'station_marker.dart';
import 'station_tooltip.dart';
import 'subway_map_painter.dart';

/// Returns label offset based on direction (0=right, 1=bottom-right, ..., 7=top-right).
Offset _labelOffset(int direction) {
  const d = 12.0;
  switch (direction) {
    case 0: return const Offset(d, -6);       // right
    case 1: return const Offset(d, d - 6);    // bottom-right
    case 2: return const Offset(-4, d);        // bottom
    case 3: return const Offset(-50, d - 6);   // bottom-left
    case 4: return const Offset(-50, -6);      // left
    case 5: return const Offset(-50, -18);     // top-left
    case 6: return const Offset(-4, -18);      // top
    case 7: return const Offset(d, -18);       // top-right
    default: return const Offset(d, -6);
  }
}

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

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();

    // Center initial view on the 2호선 rectangle area after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerOnLine2Rectangle();
    });
  }

  void _centerOnLine2Rectangle() {
    final viewSize = context.size;
    if (viewSize == null) return;

    // 2호선 rectangle center: approximately (1260, 1240)
    const centerX = 1260.0;
    const centerY = 1240.0;
    const initialScale = 0.25;

    final matrix = Matrix4.identity()
      ..scale(initialScale)
      ..translate(
        -(centerX - viewSize.width / (2 * initialScale)),
        -(centerY - viewSize.height / (2 * initialScale)),
      );

    _transformController.value = matrix;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedStations = ref.watch(selectedStationsProvider);
    final tappedStation = ref.watch(tappedStationProvider);

    // Calculate canvas size from station positions
    double maxX = 2000;
    double maxY = 2000;
    for (final s in widget.stations) {
      maxX = max(maxX, s.svgX + 120);
      maxY = max(maxY, s.svgY + 120);
    }

    final canvasSize = Size(maxX, maxY);

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
              CustomPaint(
                size: canvasSize,
                painter: SubwayMapPainter(
                  stations: widget.stations,
                  connections: widget.connections,
                  routeStationIds: widget.routeStationIds,
                ),
              ),
              ...widget.stations.map((station) {
                final isDeparture =
                    selectedStations.departure?.id == station.id;
                final isArrival = selectedStations.arrival?.id == station.id;
                final isOnRoute = widget.routeStationIds.contains(station.id);

                return Positioned(
                  left: station.svgX - 7,
                  top: station.svgY - 7,
                  child: StationMarker(
                    station: station,
                    isSelected: tappedStation?.id == station.id,
                    isDeparture: isDeparture,
                    isArrival: isArrival,
                    isOnRoute: isOnRoute,
                    onTap: () {
                      ref.read(tappedStationProvider.notifier).state = station;
                    },
                  ),
                );
              }),
              ...widget.stations.map((station) {
                final labelOffset = _labelOffset(station.labelDirection);
                return Positioned(
                  left: station.svgX + labelOffset.dx,
                  top: station.svgY + labelOffset.dy,
                  child: Text(
                    station.name,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: station.isTransfer
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: Colors.black87,
                    ),
                  ),
                );
              }),
              if (tappedStation != null)
                Positioned(
                  left: (tappedStation.svgX - 60)
                      .clamp(0, canvasSize.width - 120),
                  top: (tappedStation.svgY - 100).clamp(0, canvasSize.height),
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
