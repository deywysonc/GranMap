import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../positioning/position_sample.dart';

class CampusMapCanvas extends StatelessWidget {
  final CampusMap campus;
  final int floor;
  final List<NavigationNode> route;
  final String? activeNodeId;
  final PositionSample? userPosition;
  final bool fullBleed;

  const CampusMapCanvas({
    super.key,
    required this.campus,
    required this.floor,
    this.route = const [],
    this.activeNodeId,
    this.userPosition,
    this.fullBleed = false,
  });

  @override
  Widget build(BuildContext context) {
    final map = CustomPaint(
      painter: _CampusPainter(
        campus: campus,
        floor: floor,
        route: route,
        activeNodeId: activeNodeId,
        userPosition: userPosition,
        colorScheme: Theme.of(context).colorScheme,
      ),
    );
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(80),
      child: fullBleed
          ? SizedBox.expand(child: map)
          : AspectRatio(aspectRatio: 16 / 10, child: map),
    );
  }
}

class _CampusPainter extends CustomPainter {
  final CampusMap campus;
  final int floor;
  final List<NavigationNode> route;
  final String? activeNodeId;
  final PositionSample? userPosition;
  final ColorScheme colorScheme;

  _CampusPainter({
    required this.campus,
    required this.floor,
    required this.route,
    required this.activeNodeId,
    required this.userPosition,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final floorNodes = campus.nodes.where((n) => n.floor == floor).toList();
    if (floorNodes.isEmpty) return;
    final floorZones = campus.zones.where((z) => z.floor == floor).toList();
    final floorPois = campus.pois.where((p) => p.floor == floor).toList();

    final backgroundRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.surface,
          colorScheme.primaryContainer.withValues(alpha: .2),
        ],
      ).createShader(backgroundRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(backgroundRect, const Radius.circular(24)),
      bgPaint,
    );

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: .28)
      ..strokeWidth = 1;
    const gridGap = 28.0;
    for (var x = gridGap; x < size.width; x += gridGap) {
      for (var y = gridGap; y < size.height; y += gridGap) {
        canvas.drawCircle(Offset(x, y), 1.1, gridPaint);
      }
    }

    final allX = <double>[
      ...floorNodes.map((node) => node.displayX),
      ...floorPois.map((poi) => poi.displayX),
      ...floorZones.expand((zone) => [zone.x, zone.x + zone.width]),
    ];
    final allY = <double>[
      ...floorNodes.map((node) => node.displayY),
      ...floorPois.map((poi) => poi.displayY),
      ...floorZones.expand((zone) => [zone.y, zone.y + zone.height]),
    ];

    final minX = allX.reduce(math.min);
    final maxX = allX.reduce(math.max);
    final minY = allY.reduce(math.min);
    final maxY = allY.reduce(math.max);

    const padding = 44.0;
    final drawWidth = math.max(1.0, size.width - padding * 2);
    final drawHeight = math.max(1.0, size.height - padding * 2);

    Offset projectCoordinates(double x, double y) {
      final xRange = math.max(1.0, maxX - minX);
      final yRange = math.max(1.0, maxY - minY);
      final px = padding + ((x - minX) / xRange) * drawWidth;
      final py = size.height - (padding + ((y - minY) / yRange) * drawHeight);
      return Offset(px, py);
    }

    Offset project(NavigationNode node) =>
        projectCoordinates(node.displayX, node.displayY);

    for (final zone in floorZones) {
      final topLeft = projectCoordinates(zone.x, zone.y + zone.height);
      final bottomRight = projectCoordinates(zone.x + zone.width, zone.y);
      final rect = Rect.fromPoints(topLeft, bottomRight);
      final zoneColor = _zoneColor(zone.type);
      final isUnlocated = zone.verification == 'unlocated';

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()..color = zoneColor.withValues(alpha: isUnlocated ? .03 : .075),
      );
      final zoneOutline = Paint()
        ..color = zoneColor.withValues(alpha: isUnlocated ? .34 : .58)
        ..strokeWidth = isUnlocated ? 1.2 : 1.6
        ..style = PaintingStyle.stroke;
      if (!isUnlocated) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
          zoneOutline,
        );
      } else {
        _drawDashedRRect(
          canvas,
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
          zoneOutline,
          dash: isUnlocated ? 4 : 7,
        );
      }
      final zoneLabel = TextPainter(
        text: TextSpan(
          text: zone.name,
          style: TextStyle(
            color: zoneColor,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: math.max(50.0, rect.width - 12));
      zoneLabel.paint(
        canvas,
        Offset(rect.center.dx - zoneLabel.width / 2, rect.top + 6),
      );
    }

    final nodeById = {for (final node in campus.nodes) node.id: node};
    final showNavigationGraph =
        route.isNotEmpty || activeNodeId != null || userPosition != null;

    for (final edge in campus.edges) {
      final from = nodeById[edge.from];
      final to = nodeById[edge.to];
      if (from == null || to == null) continue;
      if (from.floor != floor || to.floor != floor) continue;
      final isUnlocated = edge.verification == 'unlocated';
      final graphAlpha = showNavigationGraph
          ? (isUnlocated ? .42 : .78)
          : edge.type == 'door'
          ? .18
          : (isUnlocated ? .22 : .44);
      final edgePaint = Paint()
        ..color = _edgeColor(edge.type).withValues(alpha: graphAlpha)
        ..strokeWidth = showNavigationGraph ? 2.8 : 1.9
        ..strokeCap = StrokeCap.round;
      if (!isUnlocated) {
        canvas.drawLine(project(from), project(to), edgePaint);
      } else {
        _drawDashedLine(
          canvas,
          project(from),
          project(to),
          edgePaint,
          dash: edge.verification == 'unlocated' ? 3.5 : 7,
        );
      }
    }

    final routeNodes = route.where((n) => n.floor == floor).toList();
    if (routeNodes.length > 1) {
      final routeHaloPaint = Paint()
        ..color = colorScheme.surface.withValues(alpha: .82)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final routePaint = Paint()
        ..color = colorScheme.primary
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (var index = 0; index < routeNodes.length - 1; index++) {
        final from = project(routeNodes[index]);
        final to = project(routeNodes[index + 1]);
        _drawDashedLine(canvas, from, to, routeHaloPaint, dash: 10);
        _drawDashedLine(canvas, from, to, routePaint, dash: 10);
      }
    }

    if (showNavigationGraph) {
      for (final node in floorNodes) {
        final point = project(node);
        final isActive = node.id == activeNodeId;
        final paint = Paint()
          ..color = isActive ? colorScheme.tertiary : _nodeColor(node.type);
        if (isActive) {
          canvas.drawCircle(
            point,
            14,
            Paint()..color = colorScheme.tertiary.withValues(alpha: .2),
          );
          canvas.drawCircle(point, 7, Paint()..color = colorScheme.surface);
        }
        canvas.drawCircle(point, isActive ? 5 : 3.2, paint);
      }
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final showAllLabels = size.width >= 620;
    final orderedPois = [...floorPois]
      ..sort((a, b) {
        final aLandmark = _isLandmark(a.type) ? 0 : 1;
        final bLandmark = _isLandmark(b.type) ? 0 : 1;
        return aLandmark.compareTo(bLandmark);
      });
    final occupiedLabels = <Rect>[];
    for (final poi in orderedPois) {
      final point = projectCoordinates(poi.displayX, poi.displayY);
      final isLandmark = _isLandmark(poi.type);
      canvas.drawCircle(
        point,
        isLandmark ? 4.8 : 3.1,
        Paint()
          ..color = isLandmark
              ? _nodeColor(poi.type)
              : colorScheme.primary.withValues(alpha: .72),
      );
      if (!showAllLabels && !isLandmark) continue;
      textPainter.text = TextSpan(
        text: poi.verification == 'unlocated' ? '${poi.name} · ?' : poi.name,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: isLandmark ? 10 : 8.5,
          fontWeight: isLandmark ? FontWeight.w700 : FontWeight.w600,
        ),
      );
      textPainter.layout(maxWidth: isLandmark ? 100 : 76);

      var labelOffset = Offset(
        (point.dx - textPainter.width / 2)
            .clamp(4, size.width - textPainter.width - 4)
            .toDouble(),
        (point.dy - textPainter.height - 5)
            .clamp(4, size.height - textPainter.height - 4)
            .toDouble(),
      );
      var labelRect = (labelOffset & textPainter.size).inflate(2.5);
      if (occupiedLabels.any((used) => used.overlaps(labelRect))) {
        if (!isLandmark) continue;
        labelOffset = Offset(
          labelOffset.dx,
          (point.dy + 6)
              .clamp(4, size.height - textPainter.height - 4)
              .toDouble(),
        );
        labelRect = (labelOffset & textPainter.size).inflate(2.5);
      }
      occupiedLabels.add(labelRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        Paint()..color = colorScheme.surface.withValues(alpha: .92),
      );
      textPainter.paint(canvas, labelOffset);
    }

    final position = userPosition;
    if (position != null && position.floor == floor) {
      _paintUserMarker(
        canvas,
        projectCoordinates(
          _displayPosition(position, floorNodes).dx,
          _displayPosition(position, floorNodes).dy,
        ),
        position,
      );
    }
  }

  Offset _displayPosition(
    PositionSample position,
    List<NavigationNode> floorNodes,
  ) {
    final nodesById = {for (final node in floorNodes) node.id: node};
    Offset? bestPoint;
    var bestDistanceSquared = double.infinity;
    for (final edge in campus.edges) {
      final from = nodesById[edge.from];
      final to = nodesById[edge.to];
      if (from == null || to == null) continue;
      final segmentX = to.x - from.x;
      final segmentY = to.y - from.y;
      final segmentLengthSquared = segmentX * segmentX + segmentY * segmentY;
      final t = segmentLengthSquared == 0
          ? 0.0
          : (((position.x - from.x) * segmentX +
                        (position.y - from.y) * segmentY) /
                    segmentLengthSquared)
                .clamp(0.0, 1.0)
                .toDouble();
      final projectedX = from.x + segmentX * t;
      final projectedY = from.y + segmentY * t;
      final dx = projectedX - position.x;
      final dy = projectedY - position.y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestPoint = Offset(
          from.displayX + (to.displayX - from.displayX) * t,
          from.displayY + (to.displayY - from.displayY) * t,
        );
      }
    }
    if (bestPoint != null) return bestPoint;

    NavigationNode? nearest;
    for (final node in floorNodes) {
      final dx = node.x - position.x;
      final dy = node.y - position.y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        nearest = node;
      }
    }
    return nearest == null
        ? Offset(position.x, position.y)
        : Offset(nearest.displayX, nearest.displayY);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dash = 7,
  }) {
    final delta = to - from;
    final distance = delta.distance;
    if (distance == 0) return;
    final direction = delta / distance;
    const gap = 5.0;
    var cursor = 0.0;
    while (cursor < distance) {
      final end = math.min(cursor + dash, distance);
      canvas.drawLine(from + direction * cursor, from + direction * end, paint);
      cursor += dash + gap;
    }
  }

  void _drawDashedRRect(
    Canvas canvas,
    RRect rrect,
    Paint paint, {
    double dash = 7,
  }) {
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var cursor = 0.0;
      while (cursor < metric.length) {
        final end = math.min(cursor + dash, metric.length);
        canvas.drawPath(metric.extractPath(cursor, end), paint);
        cursor += dash + 5;
      }
    }
  }

  void _paintUserMarker(Canvas canvas, Offset point, PositionSample position) {
    final confidence = position.confidence.clamp(0, 1).toDouble();
    final uncertaintyRadius = 18 + (1 - confidence) * 22;

    canvas.drawCircle(
      point,
      uncertaintyRadius,
      Paint()
        ..color = const Color(0xFF55B9FF).withValues(alpha: .13)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      point,
      uncertaintyRadius,
      Paint()
        ..color = const Color(0xFF55B9FF).withValues(alpha: .48)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(-position.headingDegrees * math.pi / 180);

    final direction = Path()
      ..moveTo(19, 0)
      ..lineTo(7, -6)
      ..lineTo(9, 0)
      ..lineTo(7, 6)
      ..close();
    canvas.drawPath(
      direction,
      Paint()
        ..color = const Color(0xFF55B9FF)
        ..style = PaintingStyle.fill,
    );
    canvas.restore();

    canvas.drawCircle(
      point,
      11,
      Paint()
        ..color = colorScheme.surface
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      point,
      8,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF55B9FF), Color(0xFF6558F5)],
        ).createShader(Rect.fromCircle(center: point, radius: 8)),
    );
    canvas.drawCircle(
      Offset(point.dx, point.dy - 2.2),
      2.5,
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(point.dx, point.dy + 3.2),
          width: 6.5,
          height: 4.5,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white,
    );

    final label = TextPainter(
      text: TextSpan(
        text: 'VOCÊ',
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelOffset = Offset(
      point.dx - label.width / 2,
      point.dy + uncertaintyRadius + 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (labelOffset & label.size).inflate(3),
        const Radius.circular(5),
      ),
      Paint()..color = colorScheme.surface.withValues(alpha: .94),
    );
    label.paint(canvas, labelOffset);
  }

  Color _zoneColor(String type) {
    switch (type) {
      case 'corridor_gran':
        return const Color(0xFF1D4ED8);
      case 'corridor_tyto':
      case 'upper_walkway':
      case 'court':
      case 'agronomy':
        return const Color(0xFF15803D);
      case 'services':
        return const Color(0xFF6D28D9);
      case 'cafeteria':
      case 'ramp':
        return const Color(0xFFD97706);
      case 'upper_entrance':
        return const Color(0xFFF59E0B);
      case 'construction':
        return const Color(0xFFDC2626);
      case 'unlocated_group':
        return const Color(0xFF8A8FA8);
      default:
        return colorScheme.primary;
    }
  }

  Color _edgeColor(String type) {
    switch (type) {
      case 'opening':
        return const Color(0xFFDC2626);
      case 'ramp':
      case 'ramp_access':
        return const Color(0xFF7C3AED);
      case 'service_access':
        return const Color(0xFF6D28D9);
      case 'open_area':
        return const Color(0xFF15803D);
      case 'restricted_access':
        return const Color(0xFFDC2626);
      default:
        return colorScheme.outline;
    }
  }

  Color _nodeColor(String type) {
    switch (type) {
      case 'entrance':
        return const Color(0xFF1D4ED8);
      case 'ramp':
        return const Color(0xFF7C3AED);
      case 'service':
        return const Color(0xFF6D28D9);
      case 'open_area':
      case 'outdoor':
        return const Color(0xFF15803D);
      case 'opening':
        return const Color(0xFFDC2626);
      default:
        return colorScheme.secondary;
    }
  }

  bool _isLandmark(String type) {
    return const {
      'entrance',
      'upper_entrance',
      'administration',
      'cafeteria',
      'court',
      'library',
      'finance',
      'restroom',
      'construction',
      'agronomy',
      'ramp',
    }.contains(type);
  }

  @override
  bool shouldRepaint(covariant _CampusPainter oldDelegate) {
    return oldDelegate.floor != floor ||
        oldDelegate.route != route ||
        oldDelegate.activeNodeId != activeNodeId ||
        oldDelegate.userPosition != userPosition ||
        oldDelegate.campus != campus;
  }
}
