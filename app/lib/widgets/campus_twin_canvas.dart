import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../positioning/position_sample.dart';
import '../theme/granmap_theme.dart';

/// Relative-scale architectural view of the same geometry used for routing.
/// This does not claim to be a surveyed, metric digital twin.
class CampusTwinCanvas extends StatefulWidget {
  final CampusMap campus;
  final int focusFloor;
  final List<NavigationNode> route;
  final PositionSample? userPosition;
  final ValueChanged<CampusPoi>? onPoiSelected;
  final String? selectedPoiId;

  const CampusTwinCanvas({
    super.key,
    required this.campus,
    required this.focusFloor,
    this.route = const [],
    this.userPosition,
    this.onPoiSelected,
    this.selectedPoiId,
  });

  @override
  State<CampusTwinCanvas> createState() => _CampusTwinCanvasState();
}

class _CampusTwinCanvasState extends State<CampusTwinCanvas> {
  double _rotation = 0;
  double _explosion = .65;
  double _zoom = 1;
  double _gestureZoom = 1;
  bool _showBothFloors = false;

  void _resetView() => setState(() {
    _rotation = 0;
    _zoom = 1;
  });

  @override
  void didUpdateWidget(covariant CampusTwinCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusFloor != widget.focusFloor ||
        oldWidget.campus != widget.campus) {
      _zoom = 1;
    }
  }

  _TwinProjection _projection(Size size) => _TwinProjection(
    campus: widget.campus,
    size: size,
    focusFloor: widget.focusFloor,
    showBothFloors: _showBothFloors,
    rotation:
        _rotation +
        (size.width < 600 && size.height > size.width ? -.88 : -.44),
    explosion: _explosion,
    zoom: _zoom,
    zoomTarget: _zoomTarget,
  );

  Offset? get _zoomTarget {
    final selected = widget.selectedPoiId == null
        ? null
        : widget.campus.poiById(widget.selectedPoiId!);
    if (selected?.floor == widget.focusFloor) {
      return Offset(selected!.displayX, selected.displayY);
    }
    final destination = widget.route.lastOrNull;
    return destination?.floor == widget.focusFloor
        ? Offset(destination!.displayX, destination.displayY)
        : null;
  }

  void _selectPoi(Offset tap, _TwinProjection projection) {
    final callback = widget.onPoiSelected;
    if (callback == null) return;
    CampusPoi? closest;
    var distance = 28.0;
    for (final poi in widget.campus.pois) {
      if (!projection.includesFloor(poi.floor)) continue;
      final point = projection.project(poi.displayX, poi.displayY, poi.floor);
      final candidate = math.min(
        (point - tap).distance,
        (point - const Offset(0, 13) - tap).distance,
      );
      if (candidate < distance) {
        closest = poi;
        distance = candidate;
      }
    }
    if (closest != null) callback(closest);
  }

  @override
  Widget build(BuildContext context) {
    final floorName = widget.campus.floors
        .where((floor) => floor.level == widget.focusFloor)
        .map((floor) => floor.name)
        .firstOrNull;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final projection = _projection(
                  Size(constraints.maxWidth, constraints.maxHeight),
                );
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Semantics(
                        label:
                            'Maquete 3D: ${_showBothFloors ? 'dois pisos' : floorName ?? 'piso ${widget.focusFloor}'}. Escala relativa.',
                        value: widget.selectedPoiId == null
                            ? (widget.route.isEmpty
                                  ? null
                                  : 'Rota com destino destacado')
                            : widget.campus
                                  .poiById(widget.selectedPoiId!)
                                  ?.name,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) =>
                              _selectPoi(details.localPosition, projection),
                          onDoubleTap: _resetView,
                          onScaleStart: (_) => _gestureZoom = _zoom,
                          onScaleUpdate: (details) => setState(() {
                            _zoom = (_gestureZoom * details.scale).clamp(
                              .7,
                              2.8,
                            );
                            _rotation += details.focalPointDelta.dx * .008;
                          }),
                          child: CustomPaint(
                            key: const ValueKey('campus-twin-drawing'),
                            painter: _CampusTwinPainter(
                              campus: widget.campus,
                              focusFloor: widget.focusFloor,
                              route: widget.route,
                              userPosition: widget.userPosition,
                              selectedPoiId: widget.selectedPoiId,
                              projection: projection,
                              fontFamily: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontFamily,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.layers_rounded,
                              size: 16,
                              color: GranMapColors.sky,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _showBothFloors
                                    ? 'Dois pisos • ${floorName ?? 'piso ${widget.focusFloor}'} em foco'
                                    : floorName ?? 'Piso ${widget.focusFloor}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFDDEAF5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'MAQUETE',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.3,
                                color: Color(0xFF94AFC5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _control(
                'Girar para a esquerda',
                Icons.rotate_left_rounded,
                () => setState(() => _rotation -= .22),
              ),
              _control(
                'Diminuir maquete',
                Icons.remove_rounded,
                () => setState(() => _zoom = (_zoom / 1.2).clamp(.7, 2.8)),
              ),
              _control(
                'Restaurar visualização 3D',
                Icons.center_focus_strong_rounded,
                _resetView,
              ),
              _control(
                'Ampliar maquete',
                Icons.add_rounded,
                () => setState(() => _zoom = (_zoom * 1.2).clamp(.7, 2.8)),
              ),
              _control(
                'Girar para a direita',
                Icons.rotate_right_rounded,
                () => setState(() => _rotation += .22),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Arraste para girar • pinça para ampliar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showBothFloors = !_showBothFloors),
                icon: Icon(
                  _showBothFloors
                      ? Icons.filter_1_rounded
                      : Icons.layers_rounded,
                  size: 16,
                ),
                label: Text(
                  _showBothFloors ? 'Só este piso' : 'Ver dois pisos',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        if (_showBothFloors)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Text(
                  'Separação',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Expanded(
                  child: Slider(
                    value: _explosion,
                    semanticFormatterCallback: (value) =>
                        'Separação dos pisos ${(value * 100).round()}%',
                    onChanged: (value) => setState(() => _explosion = value),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _control(String tooltip, IconData icon, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      );
}

class _CampusTwinPainter extends CustomPainter {
  final CampusMap campus;
  final int focusFloor;
  final List<NavigationNode> route;
  final PositionSample? userPosition;
  final String? selectedPoiId;
  final _TwinProjection projection;
  final String? fontFamily;
  // Bounds of actually painted text, also used to enforce collision-free LOD.
  final List<Rect> labelBounds = [];
  final List<_TwinLabel> _pendingLabels = [];

  _CampusTwinPainter({
    required this.campus,
    required this.focusFloor,
    required this.route,
    required this.userPosition,
    required this.selectedPoiId,
    required this.projection,
    required this.fontFamily,
  });

  @override
  void paint(Canvas canvas, Size size) {
    labelBounds.clear();
    _pendingLabels.clear();
    final background = Offset.zero & size;
    canvas.drawRect(
      background,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102234), Color(0xFF071321)],
        ).createShader(background),
    );
    canvas.save();
    canvas.clipRect(background);
    for (var x = 20.0; x < size.width; x += 28) {
      for (var y = 52.0; y < size.height; y += 28) {
        canvas.drawCircle(
          Offset(x, y),
          .7,
          Paint()..color = const Color(0xFF274054),
        );
      }
    }
    for (final floor in projection.floors) {
      final zones = campus.zones.where((zone) => zone.floor == floor).toList()
        ..sort((a, b) {
          if (_isCirculation(a.type) != _isCirculation(b.type)) {
            return _isCirculation(a.type) ? -1 : 1;
          }
          return projection
              .project(a.x + a.width / 2, a.y + a.height / 2, floor)
              .dy
              .compareTo(
                projection
                    .project(b.x + b.width / 2, b.y + b.height / 2, floor)
                    .dy,
              );
        });
      for (final zone in zones) {
        _paintZone(canvas, zone, floor == focusFloor ? 1 : .58);
      }
      _paintCirculationGraph(canvas, floor);
      _paintPois(canvas, floor);
    }
    _paintRoute(canvas);
    _paintUser(canvas);
    _paintSelection(canvas);
    _pendingLabels.sort((a, b) => b.priority.compareTo(a.priority));
    for (final label in _pendingLabels) {
      _label(
        canvas,
        label.text,
        label.center,
        maxWidth: label.width,
        fontSize: label.fontSize,
        background: label.background,
        allowPlacement: label.background,
      );
    }
    canvas.restore();
  }

  void _paintZone(Canvas canvas, CampusZone zone, double opacity) {
    final corners = _corners(zone);
    final circulation = _isCirculation(zone.type);
    final outdoor = zone.type == 'court' || zone.type == 'agronomy';
    final depth = circulation ? 2.0 : (outdoor ? 4.0 : 13.0);
    final top = corners.map((point) => point - Offset(0, depth)).toList();
    final color = _zoneColor(zone.type);
    canvas.drawPath(
      _polygon(corners.map((point) => point + const Offset(3, 6)).toList()),
      Paint()..color = Colors.black.withValues(alpha: .3 * opacity),
    );
    final sides = List<int>.generate(4, (index) => index)
      ..sort(
        (a, b) => ((corners[a].dy + corners[(a + 1) % 4].dy) / 2).compareTo(
          (corners[b].dy + corners[(b + 1) % 4].dy) / 2,
        ),
      );
    for (final index in sides) {
      final next = (index + 1) % 4;
      canvas.drawPath(
        _polygon([corners[index], corners[next], top[next], top[index]]),
        Paint()
          ..color = Color.lerp(
            color,
            const Color(0xFF04101B),
            .43,
          )!.withValues(alpha: opacity),
      );
    }
    canvas.drawPath(
      _polygon(top),
      Paint()..color = color.withValues(alpha: opacity),
    );
    // Shared circulation rectangles form one open floor, not separate rooms.
    if (zone.type != 'open_area') {
      canvas.drawPath(
        _polygon(top),
        Paint()
          ..color = const Color(0xFFC5DBE7)
              .withValues(alpha: (circulation ? .4 : .72) * opacity)
          ..strokeWidth = circulation ? .8 : 1.6
          ..style = PaintingStyle.stroke,
      );
    }
    if (zone.type == 'court') _paintCourt(canvas, zone, depth, opacity);
    if (zone.type == 'agronomy') _paintAgronomy(canvas, zone, depth, opacity);
    if (zone.floor != focusFloor) return;
    // Overview stays quiet. Names of individual rooms are revealed on zoom,
    // only when their projected footprint can hold two complete text lines.
    final overview = projection.size.width < 600 && projection.zoom < 1.55;
    if (overview || circulation) return;
    final center =
        projection.project(
          zone.x + zone.width / 2,
          zone.y + zone.height / 2,
          zone.floor,
        ) -
        Offset(0, depth);
    final bounds = _bounds(top);
    final labelWidth = math.min(bounds.width - 12, 110.0);
    if (labelWidth < 52 || bounds.height < 32) return;
    _pendingLabels.add(
      _TwinLabel(
        _shortName(zone.name),
        center,
        labelWidth,
        fontSize: 10,
        priority: outdoor ? 2 : 0,
      ),
    );
  }

  void _paintCourt(
    Canvas canvas,
    CampusZone zone,
    double lift,
    double opacity,
  ) {
    Offset point(double x, double y) =>
        projection.project(
          zone.x + zone.width * x,
          zone.y + zone.height * y,
          zone.floor,
        ) -
        Offset(0, lift);
    final line = Paint()
      ..color = const Color(0xFFE4F4E8).withValues(alpha: .68 * opacity)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      _polygon([
        point(.08, .08),
        point(.92, .08),
        point(.92, .92),
        point(.08, .92),
      ]),
      line,
    );
    canvas.drawLine(point(.08, .5), point(.92, .5), line);
    final circle = Path();
    for (var index = 0; index <= 32; index++) {
      final angle = index / 32 * math.pi * 2;
      final p = point(.5 + math.cos(angle) * .16, .5 + math.sin(angle) * .085);
      if (index == 0) {
        circle.moveTo(p.dx, p.dy);
      } else {
        circle.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(circle, line);
  }

  void _paintAgronomy(
    Canvas canvas,
    CampusZone zone,
    double lift,
    double opacity,
  ) {
    for (var row = 0; row < 3; row++) {
      final start =
          projection.project(
            zone.x + zone.width * .13,
            zone.y + zone.height * (.2 + row * .28),
            zone.floor,
          ) -
          Offset(0, lift);
      final end =
          projection.project(
            zone.x + zone.width * .87,
            zone.y + zone.height * (.2 + row * .28),
            zone.floor,
          ) -
          Offset(0, lift);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = const Color(0xFF8BCBA9).withValues(alpha: .55 * opacity)
          ..strokeWidth = 2,
      );
    }
  }

  void _paintCirculationGraph(Canvas canvas, int floor) {
    final paint = Paint()
      ..color = const Color(0xFF95C3E1)
          .withValues(alpha: floor == focusFloor ? .32 : .15)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final edge in campus.edges) {
      // The routing mesh is not a physical feature of a walkable plaza.
      // The active route is drawn separately, including these shortcuts.
      if (edge.type == 'open_area') continue;
      final from = campus.nodeById(edge.from);
      final to = campus.nodeById(edge.to);
      if (from == null ||
          to == null ||
          from.floor != floor ||
          to.floor != floor) {
        continue;
      }
      if (from.type == 'poi' || to.type == 'poi') continue;
      canvas.drawLine(
        projection.project(from.displayX, from.displayY, floor) -
            const Offset(0, 3),
        projection.project(to.displayX, to.displayY, floor) -
            const Offset(0, 3),
        paint,
      );
    }
  }

  void _paintPois(Canvas canvas, int floor) {
    for (final poi in campus.pois.where((poi) => poi.floor == floor)) {
      final point =
          projection.project(poi.displayX, poi.displayY, floor) -
          const Offset(0, 13);
      canvas.drawCircle(
        point,
        _isLandmark(poi.type) ? 3.5 : 2.2,
        Paint()
          ..color =
              (_isLandmark(poi.type)
                      ? const Color(0xFFFFA65C)
                      : const Color(0xFFBCDCE9))
                  .withValues(alpha: floor == focusFloor ? 1 : .55),
      );
      if (floor == focusFloor && _isOverviewLandmark(poi.type)) {
        _pendingLabels.add(
          _TwinLabel(
            _shortName(poi.name),
            point - const Offset(0, 15),
            120,
            priority: poi.type == 'entrance' || poi.type == 'upper_entrance'
                ? 3
                : 2,
            background: true,
          ),
        );
      }
    }
  }

  void _paintRoute(Canvas canvas) {
    if (route.isEmpty) return;
    final path = Path();
    var previousVisible = false;
    for (final node in route) {
      if (!projection.includesFloor(node.floor)) {
        previousVisible = false;
        continue;
      }
      final point =
          projection.project(node.displayX, node.displayY, node.floor) -
          const Offset(0, 16);
      if (!previousVisible) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      previousVisible = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF03101B)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF8D36)
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    final destination = route.last;
    if (!projection.includesFloor(destination.floor)) {
      final visible = route
          .where((node) => node.floor == focusFloor)
          .lastOrNull;
      if (visible != null) {
        _label(
          canvas,
          'Continua no ${destination.floor == 0 ? 'térreo' : 'piso ${destination.floor}'}',
          projection.project(
                visible.displayX,
                visible.displayY,
                visible.floor,
              ) -
              const Offset(0, 30),
          maxWidth: 150,
          color: const Color(0xFFFFBA82),
        );
      }
      return;
    }
    final poi = campus.pois
        .where((poi) => poi.navigationNode == destination.id)
        .firstOrNull;
    _paintPin(
      canvas,
      projection.project(
        destination.displayX,
        destination.displayY,
        destination.floor,
      ),
      const Color(0xFFFF8D36),
      poi?.name ?? 'Destino',
      destination: true,
    );
  }

  void _paintSelection(Canvas canvas) {
    final poi = selectedPoiId == null ? null : campus.poiById(selectedPoiId!);
    if (poi == null || !projection.includesFloor(poi.floor)) return;
    if (route.isNotEmpty && route.last.id == poi.navigationNode) return;
    _paintPin(
      canvas,
      projection.project(poi.displayX, poi.displayY, poi.floor),
      const Color(0xFF62C8F2),
      poi.name,
    );
  }

  void _paintPin(
    Canvas canvas,
    Offset point,
    Color color,
    String name, {
    bool destination = false,
  }) {
    final top = point - const Offset(0, 25);
    canvas.drawCircle(
      point - const Offset(0, 13),
      11,
      Paint()..color = color.withValues(alpha: .22),
    );
    canvas.drawLine(
      point - const Offset(0, 11),
      top,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(top, 7, Paint()..color = color);
    canvas.drawCircle(top, 2.5, Paint()..color = const Color(0xFF071321));
    _label(
      canvas,
      '${destination ? 'DESTINO · ' : ''}${_shortName(name)}',
      top - const Offset(0, 20),
      maxWidth: math.min(180, projection.size.width - 24),
      color: color,
      allowPlacement: true,
      mandatory: true,
    );
  }

  void _paintUser(Canvas canvas) {
    final position = userPosition;
    if (position == null || !projection.includesFloor(position.floor)) return;
    NavigationNode? nearest;
    var bestDistanceSquared = double.infinity;
    for (final node in campus.nodes.where(
      (node) => node.floor == position.floor,
    )) {
      final dx = node.x - position.x;
      final dy = node.y - position.y;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistanceSquared) {
        bestDistanceSquared = distance;
        nearest = node;
      }
    }
    final point =
        projection.project(
          nearest?.displayX ?? position.x,
          nearest?.displayY ?? position.y,
          position.floor,
        ) -
        const Offset(0, 16);
    canvas.drawCircle(
      point,
      13,
      Paint()..color = GranMapColors.sky.withValues(alpha: .2),
    );
    canvas.drawCircle(point, 6, Paint()..color = GranMapColors.sky);
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset center, {
    required double maxWidth,
    Color color = const Color(0xFFE5F0F6),
    double fontSize = 10,
    bool background = true,
    bool allowPlacement = false,
    bool mandatory = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    )..layout(maxWidth: math.max(1, maxWidth));
    if (painter.didExceedMaxLines && !mandatory) return;
    final base = center - Offset(painter.width / 2, painter.height / 2);
    Offset? origin;
    final placements = allowPlacement
        ? const [
            Offset.zero,
            Offset(0, -28),
            Offset(0, 28),
            Offset(0, -56),
            Offset(0, 56),
            Offset(-44, 0),
            Offset(44, 0),
          ]
        : const [Offset.zero];
    for (final placement in placements) {
      var candidate = base + placement;
      if (background) {
        candidate = Offset(
          candidate.dx.clamp(
            10,
            math.max(10, projection.size.width - painter.width - 10),
          ),
          candidate.dy.clamp(
            43,
            math.max(43, projection.size.height - painter.height - 10),
          ),
        );
      }
      final bounds = (candidate & painter.size).inflate(background ? 6 : 3);
      if (bounds.left < 0 ||
          bounds.top < 40 ||
          bounds.right > projection.size.width ||
          bounds.bottom > projection.size.height) {
        continue;
      }
      if (labelBounds.any((occupied) => occupied.overlaps(bounds))) continue;
      origin = candidate;
      labelBounds.add(bounds);
      break;
    }
    if (origin == null) return;
    if (background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (origin & painter.size).inflate(5),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFF06111F).withValues(alpha: .94),
      );
    }
    painter.paint(canvas, origin);
  }

  List<Offset> _corners(CampusZone zone) => [
    projection.project(zone.x, zone.y, zone.floor),
    projection.project(zone.x + zone.width, zone.y, zone.floor),
    projection.project(zone.x + zone.width, zone.y + zone.height, zone.floor),
    projection.project(zone.x, zone.y + zone.height, zone.floor),
  ];

  @override
  bool shouldRepaint(covariant _CampusTwinPainter oldDelegate) => true;
}

class _TwinProjection {
  final CampusMap campus;
  final Size size;
  final int focusFloor;
  final bool showBothFloors;
  final double rotation;
  final double explosion;
  final double zoom;
  final Offset? zoomTarget;
  late final List<int> floors;
  late final double _centerX;
  late final double _centerY;
  late final double _floorGap;
  late final double _scale;
  late final Offset _rawCenter;
  late final Offset _screenCenter;

  _TwinProjection({
    required this.campus,
    required this.size,
    required this.focusFloor,
    required this.showBothFloors,
    required this.rotation,
    required this.explosion,
    required this.zoom,
    this.zoomTarget,
  }) {
    floors = showBothFloors
        ? (campus.floors.map((floor) => floor.level).toList()..sort())
        : [focusFloor];
    final zones = campus.zones
        .where((zone) => includesFloor(zone.floor))
        .toList();
    final pois = campus.pois.where((poi) => includesFloor(poi.floor)).toList();
    final points = <Offset>[
      for (final zone in zones) ...[
        Offset(zone.x, zone.y),
        Offset(zone.x + zone.width, zone.y + zone.height),
      ],
      for (final poi in pois) Offset(poi.displayX, poi.displayY),
    ];
    final mapBounds = points.isEmpty
        ? const Rect.fromLTWH(0, 0, 100, 100)
        : _bounds(points);
    _centerX = mapBounds.center.dx;
    _centerY = mapBounds.center.dy;
    _floorGap = math.max(30, mapBounds.height * (.48 + explosion * .6));
    // Fit each floor's actual projected corners, not a duplicated global slab.
    final projected = <Offset>[
      for (final zone in zones)
        for (final x in [zone.x, zone.x + zone.width])
          for (final y in [zone.y, zone.y + zone.height])
            _raw(x, y, zone.floor),
      for (final poi in pois) _raw(poi.displayX, poi.displayY, poi.floor),
    ];
    final rawBounds = projected.isEmpty
        ? const Rect.fromLTWH(-50, -50, 100, 100)
        : _bounds(projected);
    const sidePadding = 24.0;
    const topPadding = 74.0; // badge, walls and destination pin
    const bottomPadding = 22.0;
    final availableWidth = math.max(1, size.width - sidePadding * 2);
    final availableHeight = math.max(
      1,
      size.height - topPadding - bottomPadding,
    );
    _scale =
        math.min(
          availableWidth / math.max(1, rawBounds.width),
          availableHeight / math.max(1, rawBounds.height),
        ) *
        zoom;
    final anchor = zoomTarget == null
        ? rawBounds.center
        : _raw(zoomTarget!.dx, zoomTarget!.dy, focusFloor);
    _rawCenter = Offset.lerp(
      rawBounds.center,
      anchor,
      ((zoom - 1) * 1.5).clamp(0, 1),
    )!;
    _screenCenter = Offset(size.width / 2, topPadding + availableHeight / 2);
  }

  bool includesFloor(int floor) => floors.contains(floor);

  Offset project(double x, double y, int floor) =>
      _screenCenter + (_raw(x, y, floor) - _rawCenter) * _scale;

  Offset _raw(double x, double y, int floor) {
    final dx = x - _centerX;
    final dy = y - _centerY;
    final rotatedX = dx * math.cos(rotation) - dy * math.sin(rotation);
    final rotatedY = dx * math.sin(rotation) + dy * math.cos(rotation);
    final lift = showBothFloors ? (floor - floors.first) * _floorGap : 0.0;
    // Campus display coordinates use Y-up, just like the 2D map. Canvas uses
    // Y-down: preserve that orientation before applying the floor elevation.
    return Offset(rotatedX, -rotatedY * .58 - lift);
  }
}

class _TwinLabel {
  final String text;
  final Offset center;
  final double width;
  final double fontSize;
  final int priority;
  final bool background;
  const _TwinLabel(
    this.text,
    this.center,
    this.width, {
    this.fontSize = 10,
    this.priority = 0,
    this.background = false,
  });
}

Path _polygon(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  return path..close();
}

Rect _bounds(List<Offset> points) => Rect.fromLTRB(
  points.map((point) => point.dx).reduce(math.min),
  points.map((point) => point.dy).reduce(math.min),
  points.map((point) => point.dx).reduce(math.max),
  points.map((point) => point.dy).reduce(math.max),
);

bool _isCirculation(String type) =>
    type.startsWith('corridor') ||
    type == 'upper_walkway' ||
    type == 'walkway' ||
    type == 'open_area';

Color _zoneColor(String type) => switch (type) {
  'court' => const Color(0xFF276851),
  'agronomy' => const Color(0xFF3C6A4E),
  'cafeteria' || 'upper_entrance' => const Color(0xFF9C6635),
  'ramp' => const Color(0xFF427B88),
  'services' ||
  'library' ||
  'finance' ||
  'restroom' ||
  'administration' ||
  'staff_room' => const Color(0xFF536981),
  'laboratory' || 'project_laboratory' || 'clinic' => const Color(0xFF32758A),
  'auditorium' => const Color(0xFF4E6C91),
  'construction' => const Color(0xFF8C5B51),
  'archive' => const Color(0xFF566A76),
  'classroom' => const Color(0xFF42688B),
  _ => _isCirculation(type) ? const Color(0xFF243F56) : const Color(0xFF42688B),
};

bool _isLandmark(String type) => const {
  'entrance',
  'upper_entrance',
  'administration',
  'cafeteria',
  'court',
  'library',
  'finance',
  'restroom',
  'agronomy',
  'ramp',
}.contains(type);

bool _isOverviewLandmark(String type) => const {
  'entrance',
  'upper_entrance',
  'court',
  'ramp',
  'cafeteria',
  'agronomy',
}.contains(type);

String _shortName(String name) => name
    .replaceAll('Laboratório de ', 'Lab. ')
    .replaceAll('Laboratório ', 'Lab. ')
    .replaceAll('Corredor de ', '')
    .replaceAll('Corredor ', '')
    .replaceAll(' (Machado de Assis)', '')
    .replaceAll('Entrada Tyto/Gran + Secretaria', 'Entrada Tyto / Secretaria')
    .replaceAll('Rampa de acesso a uma sala', 'Acesso à sala')
    .replaceAll('Área de agronomia', 'Agronomia');
