import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/campus_map.dart';

class RouteMapPreview extends StatelessWidget {
  final List<NavigationNode> route;
  final int floor;
  final int activeIndex;

  const RouteMapPreview({
    super.key,
    required this.route,
    required this.floor,
    required this.activeIndex,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: CustomPaint(
        painter: _RoutePainter(
          route: route,
          floor: floor,
          activeIndex: activeIndex,
          colorScheme: Theme.of(context).colorScheme,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<NavigationNode> route;
  final int floor;
  final int activeIndex;
  final ColorScheme colorScheme;

  _RoutePainter({
    required this.route,
    required this.floor,
    required this.activeIndex,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final floorNodes = route.where((node) => node.floor == floor).toList();

    final background = Paint()..color = colorScheme.surfaceContainerHighest;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
      background,
    );

    if (floorNodes.isEmpty) return;

    final minX = floorNodes.map((e) => e.x).reduce(math.min);
    final maxX = floorNodes.map((e) => e.x).reduce(math.max);
    final minY = floorNodes.map((e) => e.y).reduce(math.min);
    final maxY = floorNodes.map((e) => e.y).reduce(math.max);

    const padding = 28.0;
    final drawWidth = math.max(1.0, size.width - padding * 2);
    final drawHeight = math.max(1.0, size.height - padding * 2);

    Offset project(NavigationNode node) {
      final xRange = math.max(1.0, maxX - minX);
      final yRange = math.max(1.0, maxY - minY);
      final px = padding + ((node.x - minX) / xRange) * drawWidth;
      final py = padding + ((node.y - minY) / yRange) * drawHeight;
      return Offset(px, py);
    }

    final floorRoute = route.where((node) => node.floor == floor).toList();
    final pathPaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (floorRoute.length > 1) {
      final path = Path()
        ..moveTo(project(floorRoute.first).dx, project(floorRoute.first).dy);
      for (final node in floorRoute.skip(1)) {
        final point = project(node);
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, pathPaint);
    }

    for (var i = 0; i < route.length; i++) {
      final node = route[i];
      if (node.floor != floor) continue;

      final point = project(node);
      final isActive = i == activeIndex;
      final paint = Paint()
        ..color = isActive ? colorScheme.tertiary : colorScheme.primary;
      canvas.drawCircle(point, isActive ? 9 : 5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.floor != floor ||
        oldDelegate.activeIndex != activeIndex;
  }
}
