// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Schematic metro map layout generator for Seoul subway.
/// Reads existing stations.json/connections.json, computes new svgX/svgY
/// using: 2호선 rectangle → fixed anchors → force-directed → grid snap.

// ============================================================
// CONSTANTS
// ============================================================

const double gridSize = 60.0;
const double canvasW = 3000.0;
const double canvasH = 3000.0;
const double margin = 80.0;

// 2호선 rectangle bounds (larger for better spacing)
const double rectLeft = 900.0;
const double rectTop = 700.0;
const double rectWidth = 720.0;
const double rectHeight = 1080.0;
const double rectRight = rectLeft + rectWidth; // 1620
const double rectBottom = rectTop + rectHeight; // 1780

// ============================================================
// DATA STRUCTURES
// ============================================================

class Node {
  final String id;
  final String name;
  final String lineId;
  double x;
  double y;
  bool isFixed;
  final bool isTransfer;
  final List<String> transferLines;
  int labelDirection;
  final double latitude;
  final double longitude;

  Node({
    required this.id,
    required this.name,
    required this.lineId,
    required this.x,
    required this.y,
    this.isFixed = false,
    required this.isTransfer,
    required this.transferLines,
    this.labelDirection = 0,
    required this.latitude,
    required this.longitude,
  });
}

// ============================================================
// FILE I/O
// ============================================================

List<Node> readStations() {
  final json = jsonDecode(
    File('assets/json/stations.json').readAsStringSync(),
  );
  return (json as List)
      .map(
        (s) => Node(
          id: s['id'] as String,
          name: s['name'] as String,
          lineId: s['lineId'] as String,
          x: (s['svgX'] as num).toDouble(),
          y: (s['svgY'] as num).toDouble(),
          isTransfer: s['isTransfer'] as bool? ?? false,
          transferLines: List<String>.from(s['transferLines'] ?? []),
          latitude: (s['latitude'] as num).toDouble(),
          longitude: (s['longitude'] as num).toDouble(),
        ),
      )
      .toList();
}

List<Map<String, dynamic>> readConnections() {
  final json = jsonDecode(
    File('assets/json/connections.json').readAsStringSync(),
  );
  return List<Map<String, dynamic>>.from(json as List);
}

List<Map<String, dynamic>> readLines() {
  final json = jsonDecode(
    File('assets/json/lines.json').readAsStringSync(),
  );
  return List<Map<String, dynamic>>.from(json as List);
}

void writeOutput(List<Node> nodes) {
  // Read original JSON to preserve all fields
  final original = jsonDecode(
    File('assets/json/stations.json').readAsStringSync(),
  ) as List;

  final nodeMap = {for (final n in nodes) n.id: n};

  final updated = original.map((s) {
    final node = nodeMap[s['id']];
    if (node != null) {
      return {
        ...Map<String, dynamic>.from(s as Map),
        'svgX': (node.x * 10).roundToDouble() / 10,
        'svgY': (node.y * 10).roundToDouble() / 10,
        'labelDirection': node.labelDirection,
      };
    }
    return s;
  }).toList();

  final encoder = const JsonEncoder.withIndent('  ');
  File('assets/json/stations.json').writeAsStringSync(encoder.convert(updated));
}

// ============================================================
// ADJACENCY GRAPH
// ============================================================

Map<String, List<String>> buildAdjacency(List<Map<String, dynamic>> conns) {
  final adj = <String, List<String>>{};
  for (final c in conns) {
    if (c['isTransfer'] == true) continue;
    final from = c['fromStationId'] as String;
    final to = c['toStationId'] as String;
    adj.putIfAbsent(from, () => []).add(to);
    adj.putIfAbsent(to, () => []).add(from);
  }
  return adj;
}

// ============================================================
// PHASE 1: PLACE 2호선 RECTANGLE
// ============================================================

void placeLine2Rectangle(List<Node> nodes, Map<String, Node> byId) {
  // 2호선 station IDs: 201-243, circular
  // Top side: 201→205 (4 gaps), Right: 205→216 (11 gaps)
  // Bottom: 216→226 (10 gaps), Left: 226→243→201 (18 gaps)
  final line2Ids = List.generate(43, (i) => (201 + i).toString());

  // Assign positions around rectangle
  final positions = <String, List<double>>{};

  // Top side: 201-205 (east direction)
  final topGap = rectWidth / 4;
  for (var i = 0; i <= 4; i++) {
    positions[line2Ids[i]] = [rectLeft + topGap * i, rectTop];
  }

  // Right side: 205-216 (south direction, 205 already placed)
  final rightGap = rectHeight / 11;
  for (var i = 1; i <= 11; i++) {
    positions[line2Ids[4 + i]] = [rectRight, rectTop + rightGap * i];
  }

  // Bottom side: 216-226 (west direction, 216 already placed)
  final bottomGap = rectWidth / 10;
  for (var i = 1; i <= 10; i++) {
    positions[line2Ids[15 + i]] = [rectRight - bottomGap * i, rectBottom];
  }

  // Left side: 226-243→201 (north direction, 226 already placed)
  final leftGap = rectHeight / 18;
  for (var i = 1; i <= 17; i++) {
    positions[line2Ids[25 + i]] = [rectLeft, rectBottom - leftGap * i];
  }
  // 201 is already placed at top-left

  // Apply positions
  for (final entry in positions.entries) {
    final node = byId[entry.key];
    if (node != null) {
      node.x = entry.value[0];
      node.y = entry.value[1];
      node.isFixed = true;
    }
  }
}

// ============================================================
// PHASE 2: PROPAGATE TRANSFERS & SET FIXED ANCHORS
// ============================================================

/// Fixed anchor positions for key transfer stations (by name).
/// These define the skeleton of the network outside 2호선.
/// Canvas: 3000x3000, Grid: 60px, Rectangle: (900,700)-(1620,1780)
final Map<String, List<double>> fixedAnchors = {
  // Interior of 2호선 rectangle (lines crossing through center)
  '종각': [1020, 640],
  '종로3가': [1140, 640],
  '종로5가': [1260, 640],
  '동대문': [1440, 640],
  '경복궁': [960, 580],
  '안국': [1140, 580],
  '광화문': [1020, 700],
  '서대문': [900, 700],
  '충무로': [1320, 760],
  '명동': [1260, 780],
  '회현': [1200, 820],
  '서울역': [840, 820],
  '숙대입구': [840, 880],
  '삼각지': [840, 940],
  '신용산': [840, 1000],
  '이촌': [780, 1060],
  '동대입구': [1320, 820],
  '약수': [1380, 880],
  '금호': [1440, 880],
  '옥수': [1500, 940],
  '한강진': [1380, 820],
  '버티고개': [1380, 760],
  '녹사평': [1320, 880],
  '이태원': [1380, 940],
  '효창공원앞': [900, 940],
  '동작': [720, 1120],

  // North of rectangle (wider spacing)
  '도봉산': [1500, 200],
  '창동': [1500, 400],
  '노원': [1620, 320],
  '석계': [1740, 460],
  '청량리': [1680, 580],
  '회기': [1680, 620],
  '태릉입구': [1860, 380],
  '상봉': [1920, 460],

  // South of rectangle
  '고속터미널': [1140, 1900],
  '남부터미널': [1140, 1960],
  '양재': [1260, 2020],
  '매봉': [1320, 2080],
  '도곡': [1380, 2140],
  '대치': [1440, 2140],
  '수서': [1560, 2200],
  '가락시장': [1680, 2020],
  '오금': [1800, 1960],

  '남태령': [900, 1840],
  '선바위': [900, 1900],
  '경마공원': [900, 1960],
  '대공원': [900, 2020],
  '과천': [960, 2080],
  '정부과천청사': [1020, 2140],
  '인덕원': [900, 2260],
  '평촌': [840, 2320],
  '범계': [720, 2320],
  '금정': [600, 2380],
  '산본': [540, 2440],

  '양재시민의숲': [1320, 2140],
  '청계산입구': [1380, 2260],
  '판교': [1440, 2440],
  '정자': [1560, 2560],

  // West of rectangle (wider spacing)
  '노량진': [720, 1060],
  '구로': [660, 1360],
  '가산디지털단지': [600, 1420],
  '온수': [360, 1360],
  '김포공항': [300, 700],
  '여의도': [660, 1120],
  '국회의사당': [660, 1060],
  '마포': [780, 1000],
  '공덕': [780, 940],
  '디지털미디어시티': [540, 700],
  '월드컵경기장': [600, 760],
  '마포구청': [660, 820],
  '망원': [720, 880],
  '연신내': [540, 460],
  '불광': [600, 520],
  '녹번': [660, 580],
  '홍제': [720, 640],
  '무악재': [780, 640],
  '독립문': [840, 640],

  // East of rectangle (wider spacing)
  '군자': [1800, 1120],
  '어린이대공원': [1740, 1180],
  '천호': [1980, 1580],
  '잠실나루': [1740, 1660],
  '강동': [2040, 1580],
  '암사': [1980, 1520],
  '모란': [1920, 2320],

  // Line 7 south
  '총신대입구(이수)': [960, 1840],
  '남성': [960, 1900],
  '숭실대입구': [900, 1900],
  '상도': [840, 1900],
  '장승배기': [780, 1840],
  '신대방삼거리': [720, 1780],
  '보라매': [660, 1720],
  '신풍': [660, 1660],
  '남구로': [600, 1420],
  '철산': [480, 1420],
  '광명사거리': [420, 1420],
  '천왕': [360, 1420],

  // Line 9 west
  '개화': [240, 640],
};

void propagateTransfersAndAnchors(
  List<Node> nodes,
  Map<String, Node> byId,
  Map<String, List<Node>> byName,
) {
  // 1. Apply fixed anchor positions (by name)
  for (final entry in fixedAnchors.entries) {
    final stationsWithName = byName[entry.key];
    if (stationsWithName == null) continue;
    for (final node in stationsWithName) {
      if (!node.isFixed) {
        node.x = entry.value[0];
        node.y = entry.value[1];
        node.isFixed = true;
      }
    }
  }

  // 2. Propagate positions from fixed transfer stations to their partners
  for (final entry in byName.entries) {
    final group = entry.value;
    if (group.length < 2) continue;

    // Find a fixed station in this group
    final fixedNode = group.where((n) => n.isFixed).firstOrNull;
    if (fixedNode == null) continue;

    // Copy position to all unfixed partners
    for (final node in group) {
      if (!node.isFixed) {
        node.x = fixedNode.x;
        node.y = fixedNode.y;
        node.isFixed = true;
      }
    }
  }
}

// ============================================================
// PHASE 3: INITIAL PLACEMENT FOR REMAINING STATIONS
// ============================================================

void placeRemainingStations(
  List<Node> nodes,
  Map<String, Node> byId,
  Map<String, List<String>> adjacency,
  List<Map<String, dynamic>> lines,
) {
  // For each line, place unplaced stations between placed anchors
  for (final line in lines) {
    final stationIds = List<String>.from(line['stationIds'] as List);
    _placeLineStations(stationIds, byId, adjacency);
  }

  // Any still-unplaced stations: use scaled geographic coordinates
  final placedNodes = nodes.where((n) => n.isFixed).toList();
  if (placedNodes.isEmpty) return;

  // Compute geographic centroid of placed nodes
  double avgLat = 0, avgLng = 0;
  for (final n in placedNodes) {
    avgLat += n.latitude;
    avgLng += n.longitude;
  }
  avgLat /= placedNodes.length;
  avgLng /= placedNodes.length;

  // Compute canvas centroid of placed nodes
  double avgX = 0, avgY = 0;
  for (final n in placedNodes) {
    avgX += n.x;
    avgY += n.y;
  }
  avgX /= placedNodes.length;
  avgY /= placedNodes.length;

  // Scale factor (geographic degrees to canvas pixels)
  const scaleX = 4500.0; // approx pixels per degree longitude
  const scaleY = -5000.0; // negative because lat increases up, y increases down

  for (final node in nodes) {
    if (node.isFixed) continue;
    node.x = avgX + (node.longitude - avgLng) * scaleX;
    node.y = avgY + (node.latitude - avgLat) * scaleY;
    // Clamp to canvas
    node.x = node.x.clamp(margin, canvasW - margin);
    node.y = node.y.clamp(margin, canvasH - margin);
  }
}

/// Place unplaced stations on a line by interpolating between placed anchors.
void _placeLineStations(
  List<String> stationIds,
  Map<String, Node> byId,
  Map<String, List<String>> adjacency,
) {
  // Find segments: [placed] ... [unplaced] ... [placed]
  final nodes = stationIds.map((id) => byId[id]).whereType<Node>().toList();
  if (nodes.length < 2) return;

  // Find indices of placed (fixed) stations
  final fixedIndices = <int>[];
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].isFixed) fixedIndices.add(i);
  }
  if (fixedIndices.isEmpty) return;

  // Interpolate between consecutive fixed stations
  for (var fi = 0; fi < fixedIndices.length - 1; fi++) {
    final startIdx = fixedIndices[fi];
    final endIdx = fixedIndices[fi + 1];
    final gaps = endIdx - startIdx;
    if (gaps <= 1) continue;

    final startNode = nodes[startIdx];
    final endNode = nodes[endIdx];

    for (var i = 1; i < gaps; i++) {
      final t = i / gaps;
      final node = nodes[startIdx + i];
      if (node.isFixed) continue;
      node.x = startNode.x + (endNode.x - startNode.x) * t;
      node.y = startNode.y + (endNode.y - startNode.y) * t;
    }
  }

  // Extend terminal segments (before first fixed, after last fixed)
  if (fixedIndices.isNotEmpty) {
    final firstFixed = fixedIndices.first;
    final lastFixed = fixedIndices.last;

    // Before first fixed: extend in reverse direction
    if (firstFixed > 0 && fixedIndices.length >= 2) {
      final anchor = nodes[firstFixed];
      final nextAnchor = nodes[fixedIndices[1]];
      final dx = anchor.x - nextAnchor.x;
      final dy = anchor.y - nextAnchor.y;
      final dist = sqrt(dx * dx + dy * dy);
      final ux = dist > 0 ? dx / dist : 0.0;
      final uy = dist > 0 ? dy / dist : -1.0;

      for (var i = firstFixed - 1; i >= 0; i--) {
        final step = (firstFixed - i).toDouble();
        final node = nodes[i];
        if (node.isFixed) continue;
        node.x = anchor.x + ux * gridSize * step;
        node.y = anchor.y + uy * gridSize * step;
      }
    } else if (firstFixed > 0) {
      // Only one anchor: use geographic direction
      final anchor = nodes[firstFixed];
      for (var i = firstFixed - 1; i >= 0; i--) {
        final node = nodes[i];
        if (node.isFixed) continue;
        final geoDir = _geoDirection(node, anchor);
        final step = (firstFixed - i).toDouble();
        node.x = anchor.x - geoDir[0] * gridSize * step;
        node.y = anchor.y - geoDir[1] * gridSize * step;
      }
    }

    // After last fixed: extend forward
    if (lastFixed < nodes.length - 1 && fixedIndices.length >= 2) {
      final anchor = nodes[lastFixed];
      final prevAnchor = nodes[fixedIndices[fixedIndices.length - 2]];
      final dx = anchor.x - prevAnchor.x;
      final dy = anchor.y - prevAnchor.y;
      final dist = sqrt(dx * dx + dy * dy);
      final ux = dist > 0 ? dx / dist : 0.0;
      final uy = dist > 0 ? dy / dist : 1.0;

      for (var i = lastFixed + 1; i < nodes.length; i++) {
        final step = (i - lastFixed).toDouble();
        final node = nodes[i];
        if (node.isFixed) continue;
        node.x = anchor.x + ux * gridSize * step;
        node.y = anchor.y + uy * gridSize * step;
      }
    } else if (lastFixed < nodes.length - 1) {
      final anchor = nodes[lastFixed];
      for (var i = lastFixed + 1; i < nodes.length; i++) {
        final node = nodes[i];
        if (node.isFixed) continue;
        final geoDir = _geoDirection(anchor, node);
        final step = (i - lastFixed).toDouble();
        node.x = anchor.x + geoDir[0] * gridSize * step;
        node.y = anchor.y + geoDir[1] * gridSize * step;
      }
    }
  }
}

/// Get normalized direction vector from geographic coordinates, snapped to 8 dirs.
List<double> _geoDirection(Node from, Node to) {
  final dlng = to.longitude - from.longitude;
  final dlat = to.latitude - from.latitude;
  var angle = atan2(-dlat, dlng); // negative because y increases downward
  if (angle < 0) angle += 2 * pi;

  // Snap to nearest 45-degree increment
  final sector = ((angle + pi / 8) / (pi / 4)).floor() % 8;
  const dirs = [
    [1.0, 0.0], // 0: right
    [0.707, 0.707], // 1: down-right
    [0.0, 1.0], // 2: down
    [-0.707, 0.707], // 3: down-left
    [-1.0, 0.0], // 4: left
    [-0.707, -0.707], // 5: up-left
    [0.0, -1.0], // 6: up
    [0.707, -0.707], // 7: up-right
  ];
  return dirs[sector];
}

/// Sync all transfer stations (same name) to the same position.
/// Uses the position of the first fixed station, or average if none fixed.
void _syncTransferPositions(Map<String, List<Node>> byName) {
  for (final group in byName.values) {
    if (group.length < 2) continue;

    // Find a fixed station, or use the first one
    final anchor = group.firstWhere((n) => n.isFixed, orElse: () => group.first);
    for (final n in group) {
      if (n.id != anchor.id) {
        n.x = anchor.x;
        n.y = anchor.y;
      }
    }
  }
}

// ============================================================
// PHASE 4: FORCE-DIRECTED REFINEMENT
// ============================================================

void forceDirectedLayout(
  List<Node> nodes,
  Map<String, List<String>> adjacency,
  Map<String, Node> byId,
) {
  // Group by name for transfer co-movement
  final byName = <String, List<Node>>{};
  for (final n in nodes) {
    byName.putIfAbsent(n.name, () => []).add(n);
  }

  final unfixedNodes = nodes.where((n) => !n.isFixed).toList();
  if (unfixedNodes.isEmpty) return;

  const iterations = 500;
  const repulsionK = 100.0; // repulsion constant (stronger)
  const attractionK = 0.003; // attraction spring constant
  const lineSpringK = 0.008; // stronger spring for same-line connections
  double temperature = 120.0;
  const coolingFactor = 0.97;
  const minDist = 50.0;

  for (var iter = 0; iter < iterations; iter++) {
    // Calculate forces for unfixed nodes
    for (final node in unfixedNodes) {
      double fx = 0, fy = 0;

      // Repulsion from ALL nearby nodes
      for (final other in nodes) {
        if (other.id == node.id) continue;
        final dx = node.x - other.x;
        final dy = node.y - other.y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < 1) continue;
        if (dist > repulsionK * 5) continue; // skip far nodes

        final force = repulsionK * repulsionK / dist;
        fx += (dx / dist) * force;
        fy += (dy / dist) * force;
      }

      // Attraction to connected nodes
      final neighbors = adjacency[node.id] ?? [];
      for (final neighborId in neighbors) {
        final neighbor = byId[neighborId];
        if (neighbor == null) continue;
        final dx = neighbor.x - node.x;
        final dy = neighbor.y - node.y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < 1) continue;

        // Determine spring strength
        final k = (neighbor.lineId == node.lineId) ? lineSpringK : attractionK;
        final idealDist = gridSize * 1.5;
        final force = k * (dist - idealDist);
        fx += (dx / dist) * force;
        fy += (dy / dist) * force;
      }

      // Apply force with temperature limit
      final forceMag = sqrt(fx * fx + fy * fy);
      if (forceMag > 0) {
        final scale = min(forceMag, temperature) / forceMag;
        node.x += fx * scale;
        node.y += fy * scale;
      }

      // Clamp to canvas
      node.x = node.x.clamp(margin, canvasW - margin);
      node.y = node.y.clamp(margin, canvasH - margin);

      // Sync co-located transfer stations (same name)
      final partners = byName[node.name];
      if (partners != null && partners.length > 1) {
        for (final p in partners) {
          if (p.id != node.id && !p.isFixed) {
            p.x = node.x;
            p.y = node.y;
          }
        }
      }
    }

    temperature *= coolingFactor;
    if (temperature < 1) break;
  }
}

// ============================================================
// PHASE 5: OCTILINEAR GRID SNAPPING
// ============================================================

void snapToGrid(List<Node> nodes) {
  // Group by name so transfer stations (same name) share the same grid point
  final byName = <String, List<Node>>{};
  for (final n in nodes) {
    byName.putIfAbsent(n.name, () => []).add(n);
  }

  final occupied = <String, String>{}; // gridKey -> station name (allows co-location)
  String gridKey(double x, double y) =>
      '${(x / gridSize).round()},${(y / gridSize).round()}';

  // First pass: snap fixed station groups
  final processedNames = <String>{};
  for (final node in nodes) {
    if (!node.isFixed) continue;
    if (processedNames.contains(node.name)) continue;

    final gx = (node.x / gridSize).round() * gridSize;
    final gy = (node.y / gridSize).round() * gridSize;
    final key = gridKey(gx, gy);

    // Allow co-location for same-name stations (transfers)
    if (!occupied.containsKey(key) || occupied[key] == node.name) {
      final group = byName[node.name] ?? [node];
      for (final n in group) {
        n.x = gx;
        n.y = gy;
      }
      occupied[key] = node.name;
      processedNames.add(node.name);
    }
  }

  // Second pass: snap unfixed nodes
  for (final node in nodes) {
    if (processedNames.contains(node.name)) continue;

    final gx = (node.x / gridSize).round() * gridSize;
    final gy = (node.y / gridSize).round() * gridSize;
    final key = gridKey(gx, gy);

    if (!occupied.containsKey(key) || occupied[key] == node.name) {
      // Snap all same-name stations together
      final group = byName[node.name] ?? [node];
      for (final n in group) {
        n.x = gx;
        n.y = gy;
      }
      occupied[key] = node.name;
      processedNames.add(node.name);
    } else {
      // Find nearest unoccupied grid point (spiral search)
      var placed = false;
      for (var radius = 1; radius <= 10 && !placed; radius++) {
        for (var dx = -radius; dx <= radius && !placed; dx++) {
          for (var dy = -radius; dy <= radius && !placed; dy++) {
            if (dx.abs() != radius && dy.abs() != radius) continue;
            final nx = gx + dx * gridSize;
            final ny = gy + dy * gridSize;
            if (nx < margin || nx > canvasW - margin) continue;
            if (ny < margin || ny > canvasH - margin) continue;
            final nk = gridKey(nx, ny);
            if (!occupied.containsKey(nk)) {
              final group = byName[node.name] ?? [node];
              for (final n in group) {
                n.x = nx;
                n.y = ny;
              }
              occupied[nk] = node.name;
              processedNames.add(node.name);
              placed = true;
            }
          }
        }
      }
    }
  }
}

// ============================================================
// PHASE 6: LINE STRAIGHTENING
// ============================================================

void straightenLines(
  List<Node> nodes,
  Map<String, Node> byId,
  List<Map<String, dynamic>> lines,
) {
  final occupied = <String>{};
  for (final n in nodes) {
    occupied.add('${(n.x / gridSize).round()},${(n.y / gridSize).round()}');
  }

  for (var pass = 0; pass < 5; pass++) {
    var improved = false;

    for (final line in lines) {
      final stationIds = List<String>.from(line['stationIds'] as List);
      final lineNodes =
          stationIds.map((id) => byId[id]).whereType<Node>().toList();

      for (var i = 1; i < lineNodes.length - 1; i++) {
        final prev = lineNodes[i - 1];
        final curr = lineNodes[i];
        final next = lineNodes[i + 1];

        if (curr.isFixed) continue;

        // Check if prev-curr-next forms an 8-directional path
        final dx1 = (curr.x - prev.x);
        final dy1 = (curr.y - prev.y);
        final dx2 = (next.x - curr.x);
        final dy2 = (next.y - curr.y);

        // Try to align: move curr so that prev→curr→next uses 8-directions
        final midX = (prev.x + next.x) / 2;
        final midY = (prev.y + next.y) / 2;
        final snapX = (midX / gridSize).round() * gridSize;
        final snapY = (midY / gridSize).round() * gridSize;

        final key =
            '${(snapX / gridSize).round()},${(snapY / gridSize).round()}';
        final oldKey =
            '${(curr.x / gridSize).round()},${(curr.y / gridSize).round()}';

        if (key != oldKey && !occupied.contains(key)) {
          // Check if new position creates better alignment
          final oldBend = _bendAngle(prev, curr, next);
          final tempX = curr.x;
          final tempY = curr.y;
          curr.x = snapX;
          curr.y = snapY;
          final newBend = _bendAngle(prev, curr, next);

          if (_isOctilinear(newBend) && !_isOctilinear(oldBend)) {
            occupied.remove(oldKey);
            occupied.add(key);
            improved = true;
          } else {
            curr.x = tempX;
            curr.y = tempY;
          }
        }
      }
    }

    if (!improved) break;
  }
}

double _bendAngle(Node a, Node b, Node c) {
  final dx1 = b.x - a.x;
  final dy1 = b.y - a.y;
  final dx2 = c.x - b.x;
  final dy2 = c.y - b.y;
  final angle1 = atan2(dy1, dx1);
  final angle2 = atan2(dy2, dx2);
  var diff = (angle2 - angle1).abs();
  if (diff > pi) diff = 2 * pi - diff;
  return diff;
}

bool _isOctilinear(double angle) {
  // Check if angle is close to 0, 45, 90, 135, or 180 degrees
  const tolerance = 0.15; // ~8.6 degrees
  for (var i = 0; i <= 4; i++) {
    if ((angle - i * pi / 4).abs() < tolerance) return true;
  }
  return false;
}

// ============================================================
// PHASE 7: CROSSING MINIMIZATION
// ============================================================

void minimizeCrossings(
  List<Node> nodes,
  Map<String, Node> byId,
  List<Map<String, dynamic>> connections,
) {
  // Build edge list (non-transfer connections only)
  final edges = <List<Node>>[];
  for (final c in connections) {
    if (c['isTransfer'] == true) continue;
    final from = byId[c['fromStationId'] as String];
    final to = byId[c['toStationId'] as String];
    if (from != null && to != null) edges.add([from, to]);
  }

  // Count initial crossings
  var crossings = _countCrossings(edges);
  print('  Initial crossings: $crossings');

  // Try to reduce crossings by swapping unfixed nodes
  final unfixed = nodes.where((n) => !n.isFixed).toList();
  final rng = Random(42);

  for (var iter = 0; iter < 50; iter++) {
    var improved = false;

    for (final node in unfixed) {
      final origX = node.x;
      final origY = node.y;

      // Try small perturbations
      for (final offset in [
        [gridSize, 0.0],
        [-gridSize, 0.0],
        [0.0, gridSize],
        [0.0, -gridSize],
        [gridSize, gridSize],
        [-gridSize, -gridSize],
        [gridSize, -gridSize],
        [-gridSize, gridSize],
      ]) {
        node.x = origX + offset[0];
        node.y = origY + offset[1];

        if (node.x < margin || node.x > canvasW - margin) {
          node.x = origX;
          node.y = origY;
          continue;
        }
        if (node.y < margin || node.y > canvasH - margin) {
          node.x = origX;
          node.y = origY;
          continue;
        }

        final newCrossings = _countCrossings(edges);
        if (newCrossings < crossings) {
          crossings = newCrossings;
          improved = true;
          break; // accept first improvement
        }
        node.x = origX;
        node.y = origY;
      }
    }

    if (!improved) break;
  }

  print('  Final crossings: $crossings');
}

int _countCrossings(List<List<Node>> edges) {
  var count = 0;
  for (var i = 0; i < edges.length; i++) {
    for (var j = i + 1; j < edges.length; j++) {
      if (_segmentsIntersect(
        edges[i][0].x, edges[i][0].y, edges[i][1].x, edges[i][1].y,
        edges[j][0].x, edges[j][0].y, edges[j][1].x, edges[j][1].y,
      )) {
        count++;
      }
    }
  }
  return count;
}

bool _segmentsIntersect(
  double x1, double y1, double x2, double y2,
  double x3, double y3, double x4, double y4,
) {
  // Skip if segments share an endpoint
  if ((x1 == x3 && y1 == y3) || (x1 == x4 && y1 == y4)) return false;
  if ((x2 == x3 && y2 == y3) || (x2 == x4 && y2 == y4)) return false;

  final d1 = _cross(x3, y3, x4, y4, x1, y1);
  final d2 = _cross(x3, y3, x4, y4, x2, y2);
  final d3 = _cross(x1, y1, x2, y2, x3, y3);
  final d4 = _cross(x1, y1, x2, y2, x4, y4);

  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  return false;
}

double _cross(double ax, double ay, double bx, double by, double cx, double cy) {
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

// ============================================================
// PHASE 8: LABEL DIRECTION CALCULATION
// ============================================================

void calculateLabelDirections(
  List<Node> nodes,
  Map<String, List<String>> adjacency,
  Map<String, Node> byId,
) {
  // Direction offsets: 0=right, 1=bottom-right, 2=bottom, 3=bottom-left,
  //                    4=left, 5=top-left, 6=top, 7=top-right
  for (final node in nodes) {
    final neighbors = adjacency[node.id] ?? [];
    if (neighbors.isEmpty) {
      node.labelDirection = 0; // default: right
      continue;
    }

    // Calculate angles to all adjacent nodes
    final occupiedDirs = <int>{};
    for (final nid in neighbors) {
      final neighbor = byId[nid];
      if (neighbor == null) continue;
      final dx = neighbor.x - node.x;
      final dy = neighbor.y - node.y;
      var angle = atan2(dy, dx);
      if (angle < 0) angle += 2 * pi;
      final sector = ((angle + pi / 8) / (pi / 4)).floor() % 8;
      occupiedDirs.add(sector);
    }

    // Find the direction farthest from any occupied direction
    var bestDir = 0;
    var bestMinDist = -1;
    for (var dir = 0; dir < 8; dir++) {
      var minDist = 8;
      for (final occ in occupiedDirs) {
        var d = (dir - occ).abs();
        if (d > 4) d = 8 - d;
        minDist = min(minDist, d);
      }
      if (minDist > bestMinDist) {
        bestMinDist = minDist;
        bestDir = dir;
      }
    }

    node.labelDirection = bestDir;
  }
}

// ============================================================
// MAIN
// ============================================================

void main() {
  print('=== Seoul Subway Schematic Layout Generator ===\n');

  // Load data
  print('Loading data...');
  final nodes = readStations();
  final connections = readConnections();
  final lines = readLines();

  final byId = {for (final n in nodes) n.id: n};
  final byName = <String, List<Node>>{};
  for (final n in nodes) {
    byName.putIfAbsent(n.name, () => []).add(n);
  }
  final adjacency = buildAdjacency(connections);

  print('  ${nodes.length} stations, ${connections.length} connections\n');

  // Phase 1: Place 2호선 rectangle
  print('Phase 1: Placing Line 2 rectangle...');
  placeLine2Rectangle(nodes, byId);
  final fixedCount1 = nodes.where((n) => n.isFixed).length;
  print('  Fixed stations: $fixedCount1\n');

  // Phase 2: Propagate transfers & set anchors
  print('Phase 2: Setting anchor positions...');
  propagateTransfersAndAnchors(nodes, byId, byName);
  final fixedCount2 = nodes.where((n) => n.isFixed).length;
  print('  Fixed stations: $fixedCount2\n');

  // Phase 3: Place remaining stations
  print('Phase 3: Placing remaining stations...');
  placeRemainingStations(nodes, byId, adjacency, lines);
  // Sync transfer stations after placement (same name = same position)
  _syncTransferPositions(byName);
  print('  All stations positioned\n');

  // Phase 4: Force-directed refinement
  print('Phase 4: Force-directed refinement...');
  forceDirectedLayout(nodes, adjacency, byId);
  // Re-sync after force-directed
  _syncTransferPositions(byName);
  print('  Done\n');

  // Phase 5: Grid snapping
  print('Phase 5: Snapping to grid...');
  snapToGrid(nodes);
  _syncTransferPositions(byName);
  print('  Done\n');

  // Phase 6: Line straightening
  print('Phase 6: Straightening lines...');
  straightenLines(nodes, byId, lines);
  _syncTransferPositions(byName);
  print('  Done\n');

  // Phase 7: Crossing minimization
  print('Phase 7: Minimizing crossings...');
  minimizeCrossings(nodes, byId, connections);
  _syncTransferPositions(byName);
  print('  Done\n');

  // Phase 8: Label directions
  print('Phase 8: Calculating label directions...');
  calculateLabelDirections(nodes, adjacency, byId);
  print('  Done\n');

  // Output
  print('Writing output...');
  writeOutput(nodes);

  // Stats
  final xs = nodes.map((n) => n.x);
  final ys = nodes.map((n) => n.y);
  print('  Canvas used: ${xs.reduce(min).round()}-${xs.reduce(max).round()} x '
      '${ys.reduce(min).round()}-${ys.reduce(max).round()}');
  print('\n=== Done! ===');
}
