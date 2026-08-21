import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../positioning/position_sample.dart';
import '../theme/granmap_theme.dart';

class CampusLensCanvas extends StatefulWidget {
  final CampusMap campus;
  final List<NavigationNode> route;
  final PositionSample position;
  final int segmentIndex;
  final CampusPoi destination;

  const CampusLensCanvas({
    super.key,
    required this.campus,
    required this.route,
    required this.position,
    required this.segmentIndex,
    required this.destination,
  });

  @override
  State<CampusLensCanvas> createState() => _CampusLensCanvasState();
}

class _CampusLensCanvasState extends State<CampusLensCanvas>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _starting = false;
  String? _cameraError;

  bool get _cameraReady => _camera?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    }
  }

  Future<void> _startCamera() async {
    if (_starting || _cameraReady) return;
    setState(() {
      _starting = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('Nenhuma câmera disponível.');
      final back = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final controller = CameraController(
        back.isNotEmpty ? back.first : cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (error) {
      if (mounted) {
        setState(() => _cameraError = _cameraMessage(error));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String _cameraMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('denied') || text.contains('permission')) {
      return 'Permissão da câmera não concedida.';
    }
    return 'A câmera real não pôde ser iniciada neste aparelho.';
  }

  Future<void> _disposeCamera() async {
    final controller = _camera;
    _camera = null;
    await controller?.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final confidence = (widget.position.confidence * 100).round();
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraReady) CameraPreview(_camera!),
                CustomPaint(
                  painter: _CampusLensPainter(
                    campus: widget.campus,
                    route: widget.route,
                    position: widget.position,
                    segmentIndex: widget.segmentIndex,
                    destination: widget.destination,
                    drawBackdrop: !_cameraReady,
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 13,
                  child: _LensBadge(
                    icon: Icons.videocam_rounded,
                    label: _cameraReady
                        ? 'GRAN LENS • CÂMERA REAL'
                        : 'GRAN LENS • AR DEMO',
                    color: GranMapColors.coral,
                  ),
                ),
                Positioned(
                  right: 14,
                  top: 13,
                  child: _LensBadge(
                    icon: Icons.center_focus_strong_rounded,
                    label: '$confidence% TRACKING',
                    color: GranMapColors.mint,
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11101C).withValues(alpha: .76),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .12),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: GranMapColors.sky,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _cameraReady
                                ? 'Câmera real • setas projetadas pela posição X/Y/Z e orientação.'
                                : 'Câmera simulada • rota e tracking usam a mesma posição X/Y/Z.',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              const Icon(Icons.camera_alt_outlined, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _cameraError ??
                      (_cameraReady
                          ? 'Câmera ativa. Reancore por QR para reduzir a deriva antes de navegar.'
                          : 'Ative a câmera quando quiser testar a sobreposição real.'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _starting
                    ? null
                    : (_cameraReady ? _disposeCamera : _startCamera),
                icon: Icon(
                  _cameraReady
                      ? Icons.videocam_off_outlined
                      : Icons.videocam_outlined,
                  size: 17,
                ),
                label: Text(
                  _starting
                      ? 'Abrindo…'
                      : (_cameraReady ? 'Desligar' : 'Câmera real'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }
}

class _LensBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _LensBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF11101C).withValues(alpha: .72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .92),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }
}

class _CampusLensPainter extends CustomPainter {
  final CampusMap campus;
  final List<NavigationNode> route;
  final PositionSample position;
  final int segmentIndex;
  final CampusPoi destination;
  final bool drawBackdrop;

  const _CampusLensPainter({
    required this.campus,
    required this.route,
    required this.position,
    required this.segmentIndex,
    required this.destination,
    this.drawBackdrop = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final horizon = size.height * .43;
    if (drawBackdrop) _paintCameraScene(canvas, rect, horizon);
    final projection = _LensProjection(
      size: size,
      position: position,
      headingRadians: position.headingDegrees * math.pi / 180,
      horizon: horizon,
    );
    _paintSpatialRoute(canvas, projection);
    _paintDestination(canvas, projection);
    _paintReticle(canvas, size);
  }

  void _paintCameraScene(Canvas canvas, Rect rect, double horizon) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF494452), Color(0xFF191A22), Color(0xFF302D35)],
        ).createShader(rect),
    );

    final vanishing = Offset(rect.center.dx, horizon);
    final wall = Paint()..color = Colors.white.withValues(alpha: .075);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(rect.width * .2, 0)
        ..lineTo(vanishing.dx - 34, vanishing.dy)
        ..lineTo(0, rect.height)
        ..close(),
      wall,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.width, 0)
        ..lineTo(rect.width * .8, 0)
        ..lineTo(vanishing.dx + 34, vanishing.dy)
        ..lineTo(rect.width, rect.height)
        ..close(),
      wall,
    );

    final floorPath = Path()
      ..moveTo(0, rect.height)
      ..lineTo(vanishing.dx - 34, vanishing.dy)
      ..lineTo(vanishing.dx + 34, vanishing.dy)
      ..lineTo(rect.width, rect.height)
      ..close();
    canvas.drawPath(
      floorPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF78727E).withValues(alpha: .45),
            const Color(0xFF15151D).withValues(alpha: .9),
          ],
        ).createShader(rect),
    );

    final structural = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..strokeWidth = 2;
    for (final side in [-1, 1]) {
      for (var index = 0; index < 5; index++) {
        final edgeX = side < 0 ? 0.0 : rect.width;
        final nearY = rect.height * (index / 5);
        canvas.drawLine(
          Offset(edgeX, nearY),
          Offset(vanishing.dx + side * (28 + index * 4), vanishing.dy - 8),
          structural,
        );
      }
    }

    final scan = Paint()
      ..color = GranMapColors.sky.withValues(alpha: .045)
      ..strokeWidth = 1;
    for (var y = 4.0; y < rect.height; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), scan);
    }
  }

  void _paintSpatialRoute(Canvas canvas, _LensProjection projection) {
    final projected = <_LensPoint>[];
    var fromX = position.x;
    var fromY = position.y;
    final start = math.min(segmentIndex + 1, route.length - 1);

    for (var nodeIndex = start; nodeIndex < route.length; nodeIndex++) {
      final node = route[nodeIndex];
      if (node.floor != position.floor) break;
      final length = math.sqrt(
        math.pow(node.x - fromX, 2) + math.pow(node.y - fromY, 2),
      );
      final steps = math.max(1, (length / 4).ceil());
      for (var step = 1; step <= steps; step++) {
        final t = step / steps;
        final point = projection.project(
          fromX + (node.x - fromX) * t,
          fromY + (node.y - fromY) * t,
        );
        if (point != null) projected.add(point);
      }
      fromX = node.x;
      fromY = node.y;
    }

    projected.sort((a, b) => b.depth.compareTo(a.depth));
    for (var index = 0; index < projected.length; index += 2) {
      final sample = projected[index];
      if (sample.depth < 1.5 || sample.depth > 80) continue;
      final scale = (1.45 - sample.depth / 80).clamp(.38, 1.25);
      final point = sample.point;
      final halo = Rect.fromCenter(
        center: point,
        width: 42 * scale,
        height: 19 * scale,
      );
      canvas.drawOval(
        halo,
        Paint()..color = GranMapColors.sky.withValues(alpha: .16),
      );
      final arrow = Path()
        ..moveTo(point.dx, point.dy - 12 * scale)
        ..lineTo(point.dx - 13 * scale, point.dy + 7 * scale)
        ..lineTo(point.dx - 4 * scale, point.dy + 4 * scale)
        ..lineTo(point.dx, point.dy + 10 * scale)
        ..lineTo(point.dx + 4 * scale, point.dy + 4 * scale)
        ..lineTo(point.dx + 13 * scale, point.dy + 7 * scale)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()
          ..shader = const LinearGradient(
            colors: [GranMapColors.sky, GranMapColors.violet],
          ).createShader(arrow.getBounds()),
      );
      canvas.drawPath(
        arrow,
        Paint()
          ..color = Colors.white.withValues(alpha: .72)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintDestination(Canvas canvas, _LensProjection projection) {
    if (destination.floor != position.floor) return;
    final destinationPoint = projection.project(destination.x, destination.y);
    if (destinationPoint == null) return;
    final point = destinationPoint.point - const Offset(0, 50);
    canvas.drawLine(
      point + const Offset(0, 15),
      destinationPoint.point,
      Paint()
        ..color = GranMapColors.coral
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      point,
      21,
      Paint()..color = GranMapColors.coral.withValues(alpha: .2),
    );
    canvas.drawCircle(point, 10, Paint()..color = GranMapColors.coral);
    canvas.drawCircle(point, 3, Paint()..color = Colors.white);

    final label = TextPainter(
      text: TextSpan(
        text: destination.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 150);
    final labelRect = Rect.fromLTWH(
      point.dx - label.width / 2 - 8,
      point.dy - 44,
      label.width + 16,
      label.height + 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(9)),
      Paint()..color = const Color(0xFF11101C).withValues(alpha: .78),
    );
    label.paint(canvas, Offset(labelRect.left + 8, labelRect.top + 5));
  }

  void _paintReticle(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .43);
    final paint = Paint()
      ..color = GranMapColors.mint.withValues(alpha: .7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 18, paint);
    for (final angle in [0.0, math.pi / 2, math.pi, math.pi * 1.5]) {
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * 23;
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * 29;
      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CampusLensPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.segmentIndex != segmentIndex ||
        oldDelegate.route != route ||
        oldDelegate.destination != destination ||
        oldDelegate.drawBackdrop != drawBackdrop;
  }
}

class _LensProjection {
  final Size size;
  final PositionSample position;
  final double headingRadians;
  final double horizon;

  const _LensProjection({
    required this.size,
    required this.position,
    required this.headingRadians,
    required this.horizon,
  });

  _LensPoint? project(double x, double y) {
    final dx = x - position.x;
    final dy = y - position.y;
    final forward =
        dx * math.cos(headingRadians) + dy * math.sin(headingRadians);
    if (forward <= .4) return null;
    final lateral =
        -dx * math.sin(headingRadians) + dy * math.cos(headingRadians);
    final focal = size.width * .76;
    final screenX = size.width / 2 + lateral / forward * focal;
    final screenY = horizon + (size.height * .18 / forward) * focal / 10;
    if (screenX < -120 || screenX > size.width + 120) return null;
    return _LensPoint(Offset(screenX, screenY), forward);
  }
}

class _LensPoint {
  final Offset point;
  final double depth;

  const _LensPoint(this.point, this.depth);
}
