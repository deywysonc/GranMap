import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../positioning/position_sample.dart';
import '../theme/granmap_theme.dart';

class CampusTwinCanvas extends StatefulWidget {
  final CampusMap campus;
  final int focusFloor;
  final List<NavigationNode> route;
  final PositionSample? userPosition;

  const CampusTwinCanvas({
    super.key,
    required this.campus,
    required this.focusFloor,
    this.route = const [],
    this.userPosition,
  });

  @override
  State<CampusTwinCanvas> createState() => _CampusTwinCanvasState();
}

class _CampusTwinCanvasState extends State<CampusTwinCanvas> {
  double _rotation = -.48;
  double _explosion = .72;
  double _zoom = 1;
  double _gestureZoom = 1;

  void _resetView() {
    setState(() {
      _rotation = -.48;
      _explosion = .72;
      _zoom = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _resetView,
            onScaleStart: (_) {
              _gestureZoom = _zoom;
            },
            onScaleUpdate: (details) {
              setState(() {
                _zoom = (_gestureZoom * details.scale).clamp(.72, 2.4);
                _rotation += details.focalPointDelta.dx * .012;
              });
            },
            child: SizedBox.expand(
              child: CustomPaint(
                painter: _CampusTwinPainter(
                  campus: widget.campus,
                  focusFloor: widget.focusFloor,
                  route: widget.route,
                  userPosition: widget.userPosition,
                  rotation: _rotation,
                  explosion: _explosion,
                  zoom: _zoom,
                  colorScheme: Theme.of(context).colorScheme,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.view_in_ar_rounded, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Arraste para girar • pinça para ampliar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Restaurar visualização 3D',
                onPressed: _resetView,
                icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
              ),
              SizedBox(
                width: 92,
                child: Slider(
                  value: _explosion,
                  onChanged: (value) => setState(() => _explosion = value),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CampusTwinPainter extends CustomPainter {
  final CampusMap campus;
  final int focusFloor;
  final List<NavigationNode> route;
  final PositionSample? userPosition;
  final double rotation;
  final double explosion;
  final double zoom;
  final ColorScheme colorScheme;

  _CampusTwinPainter({
    required this.campus,
    required this.focusFloor,
    required this.route,
    required this.userPosition,
    required this.rotation,
    required this.explosion,
    required this.zoom,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final zones = campus.zones;
    if (zones.isEmpty) return;

    final background = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(24)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface,
            colorScheme.primaryContainer.withValues(alpha: .24),
          ],
        ).createShader(background),
    );

    final minX = zones.map((zone) => zone.x).reduce(math.min);
    final maxX = zones.map((zone) => zone.x + zone.width).reduce(math.max);
    final minY = zones.map((zone) => zone.y).reduce(math.min);
    final maxY = zones.map((zone) => zone.y + zone.height).reduce(math.max);
    final projection = _TwinProjection(
      size: size,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      floors: campus.floors.map((floor) => floor.level).toList(),
      rotation: rotation,
      explosion: explosion,
      zoom: zoom,
    );

    for (final floor in campus.floors) {
      final opacity = floor.level == focusFloor ? 1.0 : .28;
      final slab = <Offset>[
        projection.project(minX, minY, floor.level),
        projection.project(maxX, minY, floor.level),
        projection.project(maxX, maxY, floor.level),
        projection.project(minX, maxY, floor.level),
      ];
      _paintExtrudedPolygon(
        canvas,
        slab,
        colorScheme.surfaceContainerHighest.withValues(alpha: .72 * opacity),
        depth: 10,
      );
      canvas.drawPath(
        _polygon(slab),
        Paint()
          ..color = colorScheme.primary.withValues(alpha: .32 * opacity)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );

      final floorZones = zones.where((zone) => zone.floor == floor.level);
      for (final zone in floorZones) {
        final evidenceOpacity =
            zone.verification == 'observed_video' ||
                zone.verification == 'user_confirmed'
            ? 1.0
            : .34;
        final corners = <Offset>[
          projection.project(zone.x, zone.y, floor.level),
          projection.project(zone.x + zone.width, zone.y, floor.level),
          projection.project(
            zone.x + zone.width,
            zone.y + zone.height,
            floor.level,
          ),
          projection.project(zone.x, zone.y + zone.height, floor.level),
        ];
        final tone = _zoneColor(zone.type);
        _paintExtrudedPolygon(
          canvas,
          corners,
          tone.withValues(alpha: .28 * opacity * evidenceOpacity),
          depth:
              zone.verification == 'observed_video' ||
                  zone.verification == 'user_confirmed'
              ? (floor.level == focusFloor ? 8 : 4)
              : 2,
        );
        canvas.drawPath(
          _polygon(corners),
          Paint()
            ..color = tone.withValues(alpha: .72 * opacity * evidenceOpacity)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        );
      }

      _paintFloorLabel(canvas, projection, floor, minX, maxY, opacity);
    }

    _paintRoute(canvas, projection);
    _paintPois(canvas, projection);
    _paintUser(canvas, projection);
  }

  void _paintExtrudedPolygon(
    Canvas canvas,
    List<Offset> top,
    Color color, {
    required double depth,
  }) {
    final lowered = top.map((point) => point + Offset(0, depth)).toList();
    final side = <Offset>[top[1], top[2], lowered[2], lowered[1]];
    final front = <Offset>[top[2], top[3], lowered[3], lowered[2]];
    canvas.drawPath(
      _polygon(side),
      Paint()..color = Color.lerp(color, Colors.black, .24)!,
    );
    canvas.drawPath(
      _polygon(front),
      Paint()..color = Color.lerp(color, Colors.black, .34)!,
    );
    canvas.drawPath(_polygon(top), Paint()..color = color);
  }

  void _paintRoute(Canvas canvas, _TwinProjection projection) {
    if (route.length < 2) return;
    final path = Path();
    for (var index = 0; index < route.length; index++) {
      final node = route[index];
      final point =
          projection.project(node.displayX, node.displayY, node.floor) -
          const Offset(0, 7);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colorScheme.surface
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = GranMapColors.violet
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintPois(Canvas canvas, _TwinProjection projection) {
    for (final poi in campus.pois.where((item) => _isLandmark(item.type))) {
      final opacity = poi.floor == focusFloor ? 1.0 : .35;
      final point =
          projection.project(poi.displayX, poi.displayY, poi.floor) -
          const Offset(0, 8);
      canvas.drawLine(
        point,
        point - const Offset(0, 11),
        Paint()
          ..color = _zoneColor(poi.type).withValues(alpha: opacity)
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        point - const Offset(0, 13),
        4.5,
        Paint()..color = _zoneColor(poi.type).withValues(alpha: opacity),
      );
    }
  }

  void _paintUser(Canvas canvas, _TwinProjection projection) {
    final position = userPosition;
    if (position == null) return;
    final floorNodes = campus.nodes
        .where((node) => node.floor == position.floor)
        .toList(growable: false);
    NavigationNode? nearest;
    var bestDistanceSquared = double.infinity;
    for (final node in floorNodes) {
      final dx = node.x - position.x;
      final dy = node.y - position.y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        nearest = node;
      }
    }
    final point = projection.project(
      nearest?.displayX ?? position.x,
      nearest?.displayY ?? position.y,
      position.floor,
    );
    canvas.drawCircle(
      point - const Offset(0, 11),
      12,
      Paint()..color = GranMapColors.sky.withValues(alpha: .18),
    );
    canvas.drawCircle(
      point - const Offset(0, 11),
      6,
      Paint()..color = GranMapColors.sky,
    );
    canvas.drawLine(
      point - const Offset(0, 5),
      point - const Offset(0, 17),
      Paint()
        ..color = GranMapColors.sky
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintFloorLabel(
    Canvas canvas,
    _TwinProjection projection,
    CampusFloor floor,
    double minX,
    double maxY,
    double opacity,
  ) {
    final point = projection.project(minX, maxY, floor.level);
    final painter = TextPainter(
      text: TextSpan(
        text: floor.level == 0 ? 'TÉRREO' : 'PISO ${floor.level}',
        style: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: opacity),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, point + const Offset(5, 8));
  }

  Path _polygon(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  Color _zoneColor(String type) {
    return switch (type) {
      'corridor_gran' => GranMapColors.sky,
      'corridor_tyto' ||
      'upper_walkway' ||
      'court' ||
      'agronomy' => GranMapColors.mint,
      'services' ||
      'library' ||
      'finance' ||
      'restroom' => const Color(0xFF9A67EA),
      'cafeteria' => GranMapColors.coral,
      'ramp' => const Color(0xFF9A67EA),
      'upper_entrance' => const Color(0xFFF59E0B),
      'construction' => const Color(0xFFE85B65),
      'unlocated_group' => const Color(0xFF8A8FA8),
      _ => GranMapColors.violet,
    };
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
  bool shouldRepaint(covariant _CampusTwinPainter oldDelegate) {
    return oldDelegate.campus != campus ||
        oldDelegate.focusFloor != focusFloor ||
        oldDelegate.route != route ||
        oldDelegate.userPosition != userPosition ||
        oldDelegate.rotation != rotation ||
        oldDelegate.explosion != explosion ||
        oldDelegate.zoom != zoom ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _TwinProjection {
  final Size size;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final List<int> floors;
  final double rotation;
  final double explosion;
  final double zoom;

  late final double _scale;
  late final double _minRawX;
  late final double _minRawY;
  late final double _offsetX;
  late final double _offsetY;

  _TwinProjection({
    required this.size,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.floors,
    required this.rotation,
    required this.explosion,
    required this.zoom,
  }) {
    final rawPoints = <Offset>[
      for (final floor in floors)
        for (final x in [minX, maxX])
          for (final y in [minY, maxY]) _raw(x, y, floor),
    ];
    _minRawX = rawPoints.map((point) => point.dx).reduce(math.min);
    final maxRawX = rawPoints.map((point) => point.dx).reduce(math.max);
    _minRawY = rawPoints.map((point) => point.dy).reduce(math.min);
    final maxRawY = rawPoints.map((point) => point.dy).reduce(math.max);
    const padding = 24.0;
    final rawWidth = math.max(1, maxRawX - _minRawX);
    final rawHeight = math.max(1, maxRawY - _minRawY);
    final availableWidth = math.max(1, size.width - padding * 2);
    final availableHeight = math.max(1, size.height - padding * 2);
    _scale = math.min(
          availableWidth / rawWidth,
          availableHeight / rawHeight,
        ) *
        zoom;
    _offsetX = (size.width - rawWidth * _scale) / 2;
    _offsetY = (size.height - rawHeight * _scale) / 2;
  }

  Offset project(double x, double y, int floor) {
    final raw = _raw(x, y, floor);
    return Offset(
      _offsetX + (raw.dx - _minRawX) * _scale,
      _offsetY + (raw.dy - _minRawY) * _scale,
    );
  }

  Offset _raw(double x, double y, int floor) {
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final dx = x - cx;
    final dy = y - cy;
    final rotatedX = dx * math.cos(rotation) - dy * math.sin(rotation);
    final rotatedY = dx * math.sin(rotation) + dy * math.cos(rotation);
    final floorLift = floor * (24 + explosion * 36);
    return Offset(rotatedX, rotatedY * .46 - floorLift);
  }
}
