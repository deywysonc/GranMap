import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/field_walkthrough_catalog.dart';
import '../models/campus_map.dart';
import '../positioning/position_sample.dart';
import '../theme/granmap_theme.dart';

class WalkViewCanvas extends StatefulWidget {
  final CampusMap campus;
  final List<NavigationNode> route;
  final PositionSample position;
  final int segmentIndex;
  final CampusPoi destination;

  const WalkViewCanvas({
    super.key,
    required this.campus,
    required this.route,
    required this.position,
    required this.segmentIndex,
    required this.destination,
  });

  @override
  State<WalkViewCanvas> createState() => _WalkViewCanvasState();
}

class _WalkViewCanvasState extends State<WalkViewCanvas> {
  double _lookOffsetDegrees = 0;
  final Map<String, int> _fieldFrameIndexes = {};

  void _changeFieldFrame(FieldWalkthrough capture, int delta) {
    final current = _fieldFrameIndexes[capture.id] ?? 0;
    setState(() {
      _fieldFrameIndexes[capture.id] = (current + delta).clamp(
        0,
        capture.assetPaths.length - 1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final fieldCapture = FieldWalkthroughCatalog.nearest(
      widget.campus,
      widget.position,
    );
    final fieldFrameIndex = fieldCapture == null
        ? 0
        : (_fieldFrameIndexes[fieldCapture.id] ?? 0).clamp(
            0,
            fieldCapture.assetPaths.length - 1,
          );

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: fieldCapture == null
                ? (details) {
                    setState(() {
                      _lookOffsetDegrees =
                          (_lookOffsetDegrees - details.delta.dx * .24)
                              .clamp(-58, 58)
                              .toDouble();
                    });
                  }
                : null,
            onHorizontalDragEnd: fieldCapture == null
                ? null
                : (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 100) return;
                    _changeFieldFrame(fieldCapture, velocity < 0 ? 1 : -1);
                  },
            onDoubleTap: fieldCapture == null
                ? () => setState(() => _lookOffsetDegrees = 0)
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (fieldCapture != null)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: Image.asset(
                      fieldCapture.assetPaths[fieldFrameIndex],
                      key: ValueKey('${fieldCapture.id}_$fieldFrameIndex'),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                CustomPaint(
                  painter: _WalkViewPainter(
                    campus: widget.campus,
                    route: widget.route,
                    position: widget.position,
                    segmentIndex: widget.segmentIndex,
                    destination: widget.destination,
                    lookOffsetDegrees: fieldCapture == null
                        ? _lookOffsetDegrees
                        : 0,
                    fieldCaptureLabel: fieldCapture?.label,
                    colorScheme: Theme.of(context).colorScheme,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 9),
          child: fieldCapture == null
              ? Row(
                  children: [
                    const Icon(Icons.swipe_rounded, size: 18),
                    const SizedBox(width: 7),
                    Text(
                      'Arraste para olhar • toque duplo para centralizar',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const Spacer(),
                    if (_lookOffsetDegrees.abs() > 1)
                      TextButton(
                        onPressed: () => setState(() => _lookOffsetDegrees = 0),
                        child: const Text('Recentralizar'),
                      ),
                  ],
                )
              : Row(
                  children: [
                    IconButton(
                      tooltip: 'Quadro anterior',
                      visualDensity: VisualDensity.compact,
                      onPressed: fieldFrameIndex > 0
                          ? () => _changeFieldFrame(fieldCapture, -1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            fieldCapture.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Captura real • quadro ${fieldFrameIndex + 1}/${fieldCapture.assetPaths.length}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Próximo quadro',
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          fieldFrameIndex < fieldCapture.assetPaths.length - 1
                          ? () => _changeFieldFrame(fieldCapture, 1)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _WalkViewPainter extends CustomPainter {
  final CampusMap campus;
  final List<NavigationNode> route;
  final PositionSample position;
  final int segmentIndex;
  final CampusPoi destination;
  final double lookOffsetDegrees;
  final String? fieldCaptureLabel;
  final ColorScheme colorScheme;

  _WalkViewPainter({
    required this.campus,
    required this.route,
    required this.position,
    required this.segmentIndex,
    required this.destination,
    required this.lookOffsetDegrees,
    required this.fieldCaptureLabel,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final horizon = size.height * .41;
    final heading =
        (position.headingDegrees + lookOffsetDegrees) * math.pi / 180;

    if (fieldCaptureLabel == null) {
      _paintWorld(canvas, rect, horizon);
      _paintCorridorDetails(canvas, size, horizon);
    } else {
      _paintFieldOverlay(canvas, rect);
    }

    final projection = _PerspectiveProjection(
      size: size,
      position: position,
      headingRadians: heading,
      horizon: horizon,
    );
    _paintRoute(canvas, projection);
    _paintPois(canvas, projection);
    _paintDestination(canvas, projection);
    _paintHud(canvas, size);
  }

  void _paintFieldOverlay(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: .24),
            Colors.transparent,
            Colors.black.withValues(alpha: .42),
          ],
          stops: const [0, .48, 1],
        ).createShader(rect),
    );
  }

  void _paintWorld(Canvas canvas, Rect rect, double horizon) {
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.top, rect.right, horizon),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF171429), Color(0xFF30284D)],
        ).createShader(Rect.fromLTRB(rect.left, rect.top, rect.right, horizon)),
    );
    canvas.drawRect(
      Rect.fromLTRB(rect.left, horizon, rect.right, rect.bottom),
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2D2940), Color(0xFF14131F)],
            ).createShader(
              Rect.fromLTRB(rect.left, horizon, rect.right, rect.bottom),
            ),
    );

    final glowRect = Rect.fromCircle(
      center: Offset(rect.center.dx, horizon),
      radius: rect.width * .34,
    );
    canvas.drawCircle(
      Offset(rect.center.dx, horizon),
      rect.width * .34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            GranMapColors.violet.withValues(alpha: .22),
            Colors.transparent,
          ],
        ).createShader(glowRect),
    );
  }

  void _paintCorridorDetails(Canvas canvas, Size size, double horizon) {
    final vanishing = Offset(size.width / 2, horizon);
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: .075)
      ..strokeWidth = 1;
    for (final fraction in const [.08, .22, .36, .64, .78, .92]) {
      canvas.drawLine(
        Offset(size.width * fraction, size.height),
        vanishing,
        linePaint,
      );
    }
    for (var index = 1; index <= 7; index++) {
      final t = index / 8;
      final curved = t * t;
      final y = horizon + (size.height - horizon) * curved;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final wallPaint = Paint()
      ..color = Colors.white.withValues(alpha: .045)
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width * .13, 0)
        ..lineTo(size.width * .41, horizon)
        ..lineTo(0, size.height * .74)
        ..close(),
      wallPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width, 0)
        ..lineTo(size.width * .87, 0)
        ..lineTo(size.width * .59, horizon)
        ..lineTo(size.width, size.height * .74)
        ..close(),
      wallPaint,
    );

    for (final side in [-1, 1]) {
      for (var index = 0; index < 4; index++) {
        final near = index / 4;
        final x = side < 0
            ? size.width * (.02 + near * .09)
            : size.width * (.98 - near * .09);
        final top = size.height * (.16 + near * .055);
        final width = size.width * (.075 - near * .012);
        final doorRect = Rect.fromLTWH(
          side < 0 ? x : x - width,
          top,
          width,
          size.height * (.38 - near * .05),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(doorRect, const Radius.circular(4)),
          Paint()
            ..color = Colors.black.withValues(alpha: .2)
            ..style = PaintingStyle.fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(doorRect, const Radius.circular(4)),
          Paint()
            ..color = GranMapColors.violet.withValues(alpha: .13)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  void _paintRoute(Canvas canvas, _PerspectiveProjection projection) {
    final samples = <_ProjectedPoint>[];
    var fromX = position.x;
    var fromY = position.y;
    final start = math.min(segmentIndex + 1, route.length - 1);

    for (var nodeIndex = start; nodeIndex < route.length; nodeIndex++) {
      final node = route[nodeIndex];
      if (node.floor != position.floor) break;
      final distance = math.sqrt(
        math.pow(node.x - fromX, 2) + math.pow(node.y - fromY, 2),
      );
      final steps = math.max(1, (distance / 3.5).ceil());
      for (var step = 1; step <= steps; step++) {
        final t = step / steps;
        final projected = projection.project(
          fromX + (node.x - fromX) * t,
          fromY + (node.y - fromY) * t,
        );
        if (projected != null) samples.add(projected);
      }
      fromX = node.x;
      fromY = node.y;
    }

    if (samples.length > 1) {
      final visible = samples.where((point) => point.depth < 85).toList();
      if (visible.length > 1) {
        final path = Path()
          ..moveTo(visible.first.point.dx, visible.first.point.dy);
        for (final sample in visible.skip(1)) {
          path.lineTo(sample.point.dx, sample.point.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.black.withValues(alpha: .34)
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
        canvas.drawPath(
          path,
          Paint()
            ..shader = const LinearGradient(
              colors: [GranMapColors.sky, GranMapColors.violet],
            ).createShader(Offset.zero & projection.size)
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }

      for (var index = 0; index < samples.length; index += 2) {
        final sample = samples[index];
        if (sample.depth < 2 || sample.depth > 70) continue;
        final scale = (1.35 - sample.depth / 95).clamp(.35, 1.1);
        final point = sample.point;
        final chevron = Path()
          ..moveTo(point.dx, point.dy - 7 * scale)
          ..lineTo(point.dx - 7 * scale, point.dy + 5 * scale)
          ..lineTo(point.dx, point.dy + 1 * scale)
          ..lineTo(point.dx + 7 * scale, point.dy + 5 * scale)
          ..close();
        canvas.drawPath(
          chevron,
          Paint()..color = Colors.white.withValues(alpha: .88),
        );
      }
    }

    final nextNodeIndex = math.min(segmentIndex + 1, route.length - 1);
    final next = route[nextNodeIndex];
    if (next.floor != position.floor) {
      _paintPortal(canvas, projection.size, next.floor);
    }
  }

  void _paintPortal(Canvas canvas, Size size, int targetFloor) {
    final portal = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .43),
      width: 74,
      height: 98,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(portal, const Radius.circular(18)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            GranMapColors.violet.withValues(alpha: .5),
            GranMapColors.sky.withValues(alpha: .16),
          ],
        ).createShader(portal),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(portal, const Radius.circular(18)),
      Paint()
        ..color = Colors.white.withValues(alpha: .62)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: 'PISO $targetFloor',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(portal.center.dx - painter.width / 2, portal.center.dy - 7),
    );
  }

  void _paintPois(Canvas canvas, _PerspectiveProjection projection) {
    final visible = <({CampusPoi poi, _ProjectedPoint point})>[];
    for (final poi in campus.pois.where(
      (item) => item.floor == position.floor,
    )) {
      final projected = projection.project(poi.x, poi.y);
      if (projected == null || projected.depth > 55) continue;
      visible.add((poi: poi, point: projected));
    }
    visible.sort((a, b) => b.point.depth.compareTo(a.point.depth));

    for (final item in visible.take(7)) {
      final point = item.point.point - const Offset(0, 18);
      final opacity = (1 - item.point.depth / 75).clamp(.28, .92);
      final label = TextPainter(
        text: TextSpan(
          text: item.poi.name,
          style: TextStyle(
            color: Colors.white.withValues(alpha: opacity),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 108);
      final labelRect = Rect.fromLTWH(
        point.dx - label.width / 2 - 6,
        point.dy - label.height / 2 - 4,
        label.width + 12,
        label.height + 8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(8)),
        Paint()..color = const Color(0xFF171526).withValues(alpha: .72),
      );
      label.paint(
        canvas,
        Offset(point.dx - label.width / 2, point.dy - label.height / 2),
      );
    }
  }

  void _paintDestination(Canvas canvas, _PerspectiveProjection projection) {
    if (destination.floor != position.floor) return;
    final point = projection.project(destination.x, destination.y);
    if (point == null || point.depth > 95) return;
    final pin = point.point - const Offset(0, 42);
    canvas.drawCircle(
      pin,
      23,
      Paint()..color = GranMapColors.coral.withValues(alpha: .18),
    );
    canvas.drawCircle(pin, 12, Paint()..color = GranMapColors.coral);
    canvas.drawCircle(pin, 4, Paint()..color = Colors.white);
  }

  void _paintHud(Canvas canvas, Size size) {
    final hasFieldCapture = fieldCaptureLabel != null;
    final badge = RRect.fromRectAndRadius(
      Rect.fromLTWH(16, 15, hasFieldCapture ? 184 : 146, 34),
      const Radius.circular(13),
    );
    canvas.drawRRect(
      badge,
      Paint()..color = const Color(0xFF15142B).withValues(alpha: .72),
    );
    final painter = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(
            text: 'WALK VIEW  ',
            style: TextStyle(
              color: GranMapColors.sky,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(
            text: hasFieldCapture
                ? 'REAL • PISO ${position.floor}'
                : 'PISO ${position.floor}',
            style: TextStyle(color: Colors.white.withValues(alpha: .8)),
          ),
        ],
        style: const TextStyle(fontSize: 10, letterSpacing: .8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, const Offset(29, 27));

    final crosshair = Offset(size.width / 2, size.height * .41);
    final crosshairPaint = Paint()
      ..color = Colors.white.withValues(alpha: .3)
      ..strokeWidth = 1;
    canvas.drawLine(
      crosshair - const Offset(9, 0),
      crosshair + const Offset(9, 0),
      crosshairPaint,
    );
    canvas.drawLine(
      crosshair - const Offset(0, 9),
      crosshair + const Offset(0, 9),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WalkViewPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.segmentIndex != segmentIndex ||
        oldDelegate.route != route ||
        oldDelegate.destination != destination ||
        oldDelegate.lookOffsetDegrees != lookOffsetDegrees ||
        oldDelegate.fieldCaptureLabel != fieldCaptureLabel ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _PerspectiveProjection {
  final Size size;
  final PositionSample position;
  final double headingRadians;
  final double horizon;

  const _PerspectiveProjection({
    required this.size,
    required this.position,
    required this.headingRadians,
    required this.horizon,
  });

  _ProjectedPoint? project(double x, double y) {
    final dx = x - position.x;
    final dy = y - position.y;
    final forward =
        dx * math.cos(headingRadians) + dy * math.sin(headingRadians);
    if (forward <= .45) return null;
    final lateral =
        -dx * math.sin(headingRadians) + dy * math.cos(headingRadians);
    final focal = size.width * .72;
    final screenX = size.width / 2 + lateral / forward * focal;
    final screenY = horizon + (size.height * .17 / forward) * focal / 10;
    if (screenX < -140 || screenX > size.width + 140) return null;
    return _ProjectedPoint(Offset(screenX, screenY), forward);
  }
}

class _ProjectedPoint {
  final Offset point;
  final double depth;

  const _ProjectedPoint(this.point, this.depth);
}
