import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../models/campus_map.dart';
import '../positioning/position_sample.dart';
import 'map_scene_geometry.dart';

/// A floor plan, not the navigation graph. Graph edges supply route and door
/// connectivity, but are never drawn as a web of coloured lines in overview.
class CampusMapCanvas extends StatefulWidget {
  final CampusMap campus;
  final int floor;
  final List<NavigationNode> route;
  final String? activeNodeId;
  final PositionSample? userPosition;
  final bool fullBleed;
  final ValueChanged<CampusPoi>? onPoiSelected;
  final String? selectedPoiId;

  const CampusMapCanvas({
    super.key,
    required this.campus,
    required this.floor,
    this.route = const [],
    this.activeNodeId,
    this.userPosition,
    this.fullBleed = false,
    this.onPoiSelected,
    this.selectedPoiId,
  });

  @override
  CampusMapCanvasState createState() => CampusMapCanvasState();
}

class CampusMapCanvasState extends State<CampusMapCanvas> {
  final TransformationController _controller = TransformationController();
  Size _viewport = Size.zero;
  double _zoom = 1;
  String? _tappedPoiId;
  MapSceneGeometry? _cachedGeometry;
  bool? _cachedCompact;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(CampusMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.floor != widget.floor || oldWidget.campus != widget.campus) {
      _tappedPoiId = null;
      _cachedGeometry = null;
      resetView();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    if (!mounted) return;
    final nextZoom = _controller.value.getMaxScaleOnAxis();
    if ((nextZoom - _zoom).abs() >= 0.03 ||
        _zoomTier(nextZoom) != _zoomTier(_zoom)) {
      setState(() => _zoom = nextZoom);
    }
  }

  int _zoomTier(double z) {
    if (z >= 1.8) return 3;
    if (z >= 1.4) return 2;
    if (z >= 1.32) return 1;
    return 0;
  }

  MapSceneGeometry _geometryFor(Size viewport, bool compact) {
    final cached = _cachedGeometry;
    if (cached != null &&
        _cachedCompact == compact &&
        cached.campus == widget.campus &&
        cached.floor == widget.floor &&
        cached.viewport == viewport) {
      return cached;
    }
    final next = MapSceneGeometry(
      campus: widget.campus,
      floor: widget.floor,
      viewport: viewport,
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 38,
        28,
        compact ? 20 : 38,
        64,
      ),
    );
    _cachedGeometry = next;
    _cachedCompact = compact;
    return next;
  }

  /// Available to screen-level recenter controls through a GlobalKey.
  void resetView() => _controller.value = Matrix4.identity();

  /// Zoom around the viewport centre, preserving the selected area.
  void zoomBy(double factor) {
    final current = _controller.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(.8, 6.0);
    final ratio = target / current;
    final centre = Offset(_viewport.width / 2, _viewport.height / 2);
    final transform = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    _controller.value = transform * _controller.value;
  }

  void _selectPoi(CampusPoi poi) {
    setState(() => _tappedPoiId = poi.id);
    widget.onPoiSelected?.call(poi);
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 640.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : width / 1.6;
        _viewport = Size(width, height);
        final geometry = _geometryFor(_viewport, width < 500);
        final zoom = _controller.value.getMaxScaleOnAxis();
        _zoom = zoom;
        final selected = widget.campus.poiById(
          widget.selectedPoiId ?? _tappedPoiId ?? '',
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.fullBleed ? 0 : 20),
          child: ColoredBox(
            color: const Color(0xFF07111E),
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _controller,
                  minScale: .8,
                  maxScale: 6,
                  boundaryMargin: EdgeInsets.all(math.max(width, height) / 2),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final poi = geometry.hitTestPoi(
                        details.localPosition,
                        zoom: zoom,
                      );
                      if (poi != null) _selectPoi(poi);
                    },
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('granmap-floor-canvas'),
                          painter: _FloorPlanPainter(
                            geometry: geometry,
                            route: widget.route,
                            activeNodeId: widget.activeNodeId,
                            userPosition: widget.userPosition,
                            selectedPoiId: selected?.id,
                            zoom: zoom,
                            onPoiSelected: _selectPoi,
                            fontFamily: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.fontFamily,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _MapControls(
                    onZoomIn: () => zoomBy(1.35),
                    onZoomOut: () => zoomBy(1 / 1.35),
                    onReset: resetView,
                    compact: width < 500,
                  ),
                ),
                if (width >= 420 && height >= 160)
                  const Positioned(
                    left: 16,
                    bottom: 18,
                    child: IgnorePointer(child: _MapLegend()),
                  ),
                if (selected != null &&
                    selected.floor == widget.floor &&
                    widget.onPoiSelected == null)
                  Positioned(
                    left: 12,
                    right: width < 500 ? 12 : null,
                    bottom: 66,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(13, 9, 5, 9),
                        decoration: BoxDecoration(
                          color: const Color(0xF2142538),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF7A18)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.place_rounded,
                              color: Color(0xFFFF7A18),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                selected.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFF2F6FC),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Fechar nome do local',
                              icon: const Icon(Icons.close_rounded, size: 17),
                              color: const Color(0xFF9AAFC7),
                              onPressed: () =>
                                  setState(() => _tappedPoiId = null),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    return widget.fullBleed
        ? content
        : AspectRatio(aspectRatio: 1.6, child: content);
  }
}

class _MapControls extends StatelessWidget {
  final VoidCallback onZoomIn, onZoomOut, onReset;
  final bool compact;
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.compact,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xF215263A),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF344861)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.remove_rounded, 'Diminuir mapa', onZoomOut),
          _button(Icons.add_rounded, 'Ampliar mapa', onZoomIn),
          const SizedBox(height: 22, child: VerticalDivider(width: 1)),
          _button(Icons.fit_screen_rounded, 'Enquadrar planta', onReset),
        ],
      ),
    ),
  );
  Widget _button(IconData icon, String tooltip, VoidCallback callback) =>
      SizedBox(
        width: compact ? 42 : 44,
        height: 42,
        child: IconButton(
          tooltip: tooltip,
          onPressed: callback,
          icon: Icon(icon, color: const Color(0xFFE8EFF8), size: 21),
          padding: EdgeInsets.zero,
        ),
      );
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _LegendItem(Color(0xFF335171), 'Salas'),
      SizedBox(width: 14),
      _LegendItem(Color(0xFF4A8E8D), 'Serviços'),
      SizedBox(width: 14),
      _LegendItem(Color(0xFFFF7A18), 'Rota'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFF91A5BF)),
      ),
    ],
  );
}

class _FloorPlanPainter extends CustomPainter {
  final MapSceneGeometry geometry;
  final List<NavigationNode> route;
  final String? activeNodeId;
  final PositionSample? userPosition;
  final String? selectedPoiId;
  final double zoom;
  final ValueChanged<CampusPoi> onPoiSelected;
  final String? fontFamily;
  _FloorPlanPainter({
    required this.geometry,
    required this.route,
    required this.activeNodeId,
    required this.userPosition,
    required this.selectedPoiId,
    required this.zoom,
    required this.onPoiSelected,
    required this.fontFamily,
  });

  static const wall = Color(0xFF7C94B0);
  static const corridorFill = Color(0xFF24364A);
  static const orange = Color(0xFFFF7A18);
  double get unit => 1 / zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final campus = geometry.campus;
    final floor = geometry.floor;
    final zones = campus.zones.where((zone) => zone.floor == floor).toList();
    final pois = campus.pois.where((poi) => poi.floor == floor).toList();
    final nodeById = {for (final node in campus.nodes) node.id: node};
    final grid = Paint()..color = const Color(0xFF1B2B3D);
    for (var x = 18.0; x < size.width; x += 24) {
      for (var y = 18.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), .7 * unit, grid);
      }
    }
    final ordered = [...zones]
      ..sort((a, b) {
        final ca = MapSceneGeometry.isCorridor(a.type) ? 0 : 1;
        final cb = MapSceneGeometry.isCorridor(b.type) ? 0 : 1;
        return ca.compareTo(cb);
      });
    for (final zone in ordered) {
      final rect = geometry.zoneRect(zone);
      final type = zone.type;
      final poi = geometry.poiForZone(zone);
      final selected = poi?.id == selectedPoiId && poi != null;
      if (MapSceneGeometry.isCorridor(type)) {
        _paintCorridor(canvas, rect, openArea: type == 'open_area');
        continue;
      }
      if (type == 'court') {
        _paintCourt(canvas, rect);
      } else if (type == 'agronomy') {
        _paintAgronomy(canvas, rect);
      } else {
        _paintRoom(canvas, rect, type, selected);
        if (type == 'ramp') _paintRamp(canvas, rect);
        if (type == 'upper_entrance' || type == 'entrance') {
          _paintGate(canvas, rect);
        }
      }
    }
    // Only genuine door leaves/openings, not ordinary graph links.
    for (final edge in campus.edges) {
      if (!{'door', 'service_access', 'ramp_access'}.contains(edge.type)) {
        continue;
      }
      final from = nodeById[edge.from];
      final to = nodeById[edge.to];
      if (from == null ||
          to == null ||
          from.floor != floor ||
          to.floor != floor) {
        continue;
      }
      for (final zone in zones) {
        if (MapSceneGeometry.isCorridor(zone.type) ||
            {'court', 'agronomy'}.contains(zone.type)) {
          continue;
        }
        final rect = geometry.zoneRect(zone);
        final a = geometry.project(from.displayX, from.displayY);
        final b = geometry.project(to.displayX, to.displayY);
        if (rect.contains(a) == rect.contains(b)) continue;
        _paintDoor(
          canvas,
          rect,
          rect.contains(a) ? a : b,
          rect.contains(a) ? b : a,
        );
      }
    }
    _paintRoute(canvas);
    final occupied = <Rect>[];
    final labeledPoiIds = <String>{};
    for (final zone in ordered) {
      if (MapSceneGeometry.isCorridor(zone.type)) {
        _labelCorridor(canvas, zone, occupied);
        continue;
      }
      final poi = geometry.poiForZone(zone);
      if (poi != null) labeledPoiIds.add(poi.id);
      _labelZone(canvas, zone, poi, occupied);
    }
    final unzoned =
        pois.where((poi) => !labeledPoiIds.contains(poi.id)).toList()..sort(
          (a, b) => _isLandmark(a.type) == _isLandmark(b.type)
              ? 0
              : _isLandmark(a.type)
              ? -1
              : 1,
        );
    for (final poi in unzoned) {
      _paintPoi(canvas, poi, occupied);
    }
    if (userPosition case final position? when position.floor == floor) {
      final display = geometry.displayPosition(position);
      _paintUser(canvas, geometry.project(display.dx, display.dy), position);
    } else if (activeNodeId != null) {
      final active = nodeById[activeNodeId];
      if (active != null && active.floor == floor) {
        _paintActive(
          canvas,
          geometry.project(active.displayX, active.displayY),
        );
      }
    }
  }

  void _paintRoom(Canvas canvas, Rect rect, String type, bool selected) {
    canvas.drawRect(rect, Paint()..color = _roomFill(type));
    canvas.drawRect(
      rect,
      Paint()
        ..color = selected ? orange : wall
        ..strokeWidth = (selected ? 2.6 : 1.35) * unit
        ..style = PaintingStyle.stroke,
    );
    if (rect.width * zoom > 23 && rect.height * zoom > 22) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + 2 * unit,
          rect.top + 2 * unit,
          math.max(0, rect.width - 4 * unit),
          2.5 * unit,
        ),
        Paint()..color = _accent(type).withValues(alpha: .75),
      );
    }
  }

  void _paintCorridor(Canvas canvas, Rect rect, {bool openArea = false}) {
    canvas.drawRect(rect, Paint()..color = corridorFill);
    // A shared open floor has no corridor centre line or artificial seams
    // between its component rectangles. Only the selected route guides it.
    if (openArea) return;
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF3E536C)
        ..strokeWidth = unit
        ..style = PaintingStyle.stroke,
    );
    final paint = Paint()
      ..color = const Color(0xFF344A61)
      ..strokeWidth = .65 * unit;
    if (rect.width > rect.height) {
      _dashes(
        canvas,
        Offset(rect.left + 4 * unit, rect.center.dy),
        Offset(rect.right - 4 * unit, rect.center.dy),
        paint,
        3 * unit,
        5 * unit,
      );
    } else {
      _dashes(
        canvas,
        Offset(rect.center.dx, rect.top + 4 * unit),
        Offset(rect.center.dx, rect.bottom - 4 * unit),
        paint,
        3 * unit,
        5 * unit,
      );
    }
  }

  void _paintCourt(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFF14342F));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF568577)
        ..strokeWidth = 1.2 * unit
        ..style = PaintingStyle.stroke,
    );
    final court = rect.deflate(math.min(rect.shortestSide * .11, 8 * unit));
    final lines = Paint()
      ..color = const Color(0xFF90B8A5).withValues(alpha: .65)
      ..strokeWidth = .9 * unit
      ..style = PaintingStyle.stroke;
    canvas.drawRect(court, lines);
    canvas.drawCircle(court.center, court.shortestSide * .19, lines);
    if (court.height > court.width) {
      canvas.drawLine(
        Offset(court.left, court.center.dy),
        Offset(court.right, court.center.dy),
        lines,
      );
      for (final y in [court.top, court.bottom - court.height * .18]) {
        canvas.drawRect(
          Rect.fromLTWH(
            court.left + court.width * .23,
            y,
            court.width * .54,
            court.height * .18,
          ),
          lines,
        );
      }
    } else {
      canvas.drawLine(
        Offset(court.center.dx, court.top),
        Offset(court.center.dx, court.bottom),
        lines,
      );
      for (final x in [court.left, court.right - court.width * .18]) {
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            court.top + court.height * .23,
            court.width * .18,
            court.height * .54,
          ),
          lines,
        );
      }
    }
  }

  void _paintAgronomy(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = const Color(0xFF173B32));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF527F6B)
        ..strokeWidth = 1.2 * unit
        ..style = PaintingStyle.stroke,
    );
    final rowPaint = Paint()
      ..color = const Color(0xFF315D43)
      ..strokeWidth = 3 * unit;
    final gap = math.max(6 * unit, rect.height / 6);
    for (var y = rect.top + gap; y < rect.bottom - gap / 2; y += gap) {
      canvas.drawLine(
        Offset(rect.left + rect.width * .12, y),
        Offset(rect.right - rect.width * .12, y),
        rowPaint,
      );
    }
  }

  void _paintRamp(Canvas canvas, Rect rect) {
    final narrow = math.min(rect.width, rect.height);
    final paint = Paint()
      ..color = const Color(0xFF7D644A)
      ..strokeWidth = .8 * unit;
    if (rect.height > rect.width) {
      for (
        var y = rect.top + 5 * unit;
        y < rect.bottom - 2 * unit;
        y += math.max(5 * unit, narrow / 6)
      ) {
        canvas.drawLine(
          Offset(rect.left + 3 * unit, y),
          Offset(rect.right - 3 * unit, y),
          paint,
        );
      }
    } else {
      for (
        var x = rect.left + 5 * unit;
        x < rect.right - 2 * unit;
        x += math.max(5 * unit, narrow / 6)
      ) {
        canvas.drawLine(
          Offset(x, rect.top + 3 * unit),
          Offset(x, rect.bottom - 3 * unit),
          paint,
        );
      }
    }
  }

  void _paintGate(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFF9AAFCA)
      ..strokeWidth = 1.1 * unit;
    final vertical = rect.height > rect.width;
    for (var i = 1; i < 5; i++) {
      final t = i / 5;
      canvas.drawLine(
        vertical
            ? Offset(rect.left, rect.top + rect.height * t)
            : Offset(rect.left + rect.width * t, rect.top),
        vertical
            ? Offset(rect.right, rect.top + rect.height * t)
            : Offset(rect.left + rect.width * t, rect.bottom),
        paint,
      );
    }
  }

  void _paintDoor(Canvas canvas, Rect rect, Offset inside, Offset outside) {
    final delta = outside - inside;
    double best = double.infinity;
    Offset? hit;
    bool horizontal = false;
    for (final side in [rect.left, rect.right]) {
      if (delta.dx.abs() < .0001) continue;
      final t = (side - inside.dx) / delta.dx;
      final y = inside.dy + delta.dy * t;
      if (t >= 0 && t <= 1 && y >= rect.top && y <= rect.bottom && t < best) {
        best = t;
        hit = Offset(side, y);
        horizontal = false;
      }
    }
    for (final side in [rect.top, rect.bottom]) {
      if (delta.dy.abs() < .0001) continue;
      final t = (side - inside.dy) / delta.dy;
      final x = inside.dx + delta.dx * t;
      if (t >= 0 && t <= 1 && x >= rect.left && x <= rect.right && t < best) {
        best = t;
        hit = Offset(x, side);
        horizontal = true;
      }
    }
    if (hit == null) return;
    final doorWidth = math.min(8 * unit, rect.shortestSide * .42);
    final along = horizontal
        ? Offset(doorWidth / 2, 0)
        : Offset(0, doorWidth / 2);
    canvas.drawLine(
      hit - along,
      hit + along,
      Paint()
        ..color = corridorFill
        ..strokeWidth = 3.2 * unit,
    );
    final hinge = hit - along;
    final direction = (inside - hit) / math.max(.001, (inside - hit).distance);
    canvas.drawLine(
      hinge,
      hinge + direction * doorWidth,
      Paint()
        ..color = const Color(0xFF99AEC6)
        ..strokeWidth = .9 * unit,
    );
  }

  void _paintRoute(Canvas canvas) {
    for (final segment in MapSceneGeometry.routeSegments(
      route,
      geometry.floor,
    )) {
      if (segment.length < 2) continue;
      final path = Path();
      for (var i = 0; i < segment.length; i++) {
        final point = geometry.project(
          segment[i].displayX,
          segment[i].displayY,
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF07111E).withValues(alpha: .8)
          ..strokeWidth = 7.5 * unit
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = orange
          ..strokeWidth = 3.5 * unit
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    if (route.isEmpty) return;
    final destination = route.last;
    if (destination.floor == geometry.floor) {
      final point = geometry.project(
        destination.displayX,
        destination.displayY,
      );
      canvas.drawCircle(
        point,
        7 * unit,
        Paint()..color = const Color(0xFF07111E),
      );
      canvas.drawCircle(point, 5 * unit, Paint()..color = orange);
      canvas.drawCircle(point, 1.8 * unit, Paint()..color = Colors.white);
    }
  }

  void _labelZone(
    Canvas canvas,
    CampusZone zone,
    CampusPoi? poi,
    List<Rect> occupied,
  ) {
    final rect = geometry.zoneRect(zone);
    final screenWidth = rect.width * zoom, screenHeight = rect.height * zoom;
    if (screenWidth < 16 || screenHeight < 17) return;
    if (screenWidth < 24) {
      _drawIcon(
        canvas,
        _icon(zone.type),
        rect.center,
        math.min(12 * unit, rect.shortestSide * .6),
        _accent(zone.type),
      );
      return;
    }
    final selected = poi?.id == selectedPoiId && poi != null;
    var font =
        (screenWidth >= 62
            ? 11.0
            : screenWidth >= 40
            ? 9.5
            : 8.5) *
        unit;
    final title = zoom < 1.8
        ? _overviewName(poi?.name ?? zone.name)
        : _shortName(poi?.name ?? zone.name);
    final availableWidth = math.max(1.0, rect.width - 8 * unit);
    // TextPainter otherwise breaks a long word between individual letters.
    // Fit the longest word first; at tiny overview widths use its icon instead.
    for (final word in title.split(RegExp(r'\s+'))) {
      final measure = TextPainter(
        text: TextSpan(
          text: word,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: font,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (measure.width > availableWidth) {
        font *= availableWidth / measure.width;
      }
    }
    if (font * zoom < 7) {
      _drawIcon(
        canvas,
        _icon(zone.type),
        rect.center,
        12 * unit,
        _accent(zone.type),
      );
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: selected ? const Color(0xFFFFAA6B) : const Color(0xFFD7E3F1),
          fontSize: font,
          fontFamily: fontFamily,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: screenHeight >= 42 ? 3 : 2,
      ellipsis: '…',
    )..layout(maxWidth: availableWidth);
    final showIcon = screenHeight > 58 && screenWidth > 26;
    final blockHeight = painter.height + (showIcon ? 21 * unit : 0);
    final top = rect.center.dy - blockHeight / 2 + (showIcon ? 21 * unit : 0);
    final label = Rect.fromLTWH(
      rect.center.dx - painter.width / 2,
      top,
      painter.width,
      painter.height,
    ).inflate(2 * unit);
    if (label.height > rect.height - 6 * unit ||
        occupied.any((r) => r.overlaps(label))) {
      return;
    }
    canvas.save();
    canvas.clipRect(rect.deflate(2 * unit));
    if (showIcon) {
      _drawIcon(
        canvas,
        _icon(zone.type),
        Offset(rect.center.dx, top - 13 * unit),
        15 * unit,
        _accent(zone.type),
      );
    }
    if ({'court', 'agronomy', 'ramp'}.contains(zone.type)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(label, Radius.circular(3 * unit)),
        Paint()..color = const Color(0xFF10221D).withValues(alpha: .87),
      );
    }
    painter.paint(canvas, label.topLeft + Offset(2 * unit, 2 * unit));
    canvas.restore();
    occupied.add(label);
  }

  void _labelCorridor(Canvas canvas, CampusZone zone, List<Rect> occupied) {
    final rect = geometry.zoneRect(zone);
    if (rect.width * zoom < 100 || rect.height * zoom < 28) return;
    final text = zone.type == 'corridor_gran'
        ? 'CORREDOR GRAN'
        : zone.type == 'corridor_tyto'
        ? 'CORREDOR TYTO'
        : zone.type == 'open_area'
        ? (rect.height * zoom >= 100 ? 'ÁREA DE CIRCULAÇÃO' : 'CIRCULAÇÃO')
        : 'CORREDOR';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 8.5 * unit,
          fontFamily: fontFamily,
          color: const Color(0xFF8096AE),
          fontWeight: FontWeight.w600,
          letterSpacing: .8 * unit,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 8 * unit);
    final label = Rect.fromCenter(
      center: zone.type == 'open_area' && rect.height * zoom >= 100
          ? rect.center
          : Offset(rect.center.dx, rect.top + 7 * unit),
      width: painter.width,
      height: painter.height,
    );
    if (occupied.any((used) => used.overlaps(label.inflate(3 * unit)))) return;
    canvas.drawRect(label.inflate(3 * unit), Paint()..color = corridorFill);
    painter.paint(canvas, label.topLeft);
    occupied.add(label.inflate(3 * unit));
  }

  void _paintPoi(Canvas canvas, CampusPoi poi, List<Rect> occupied) {
    final point = geometry.project(poi.displayX, poi.displayY);
    final landmark = _isLandmark(poi.type), selected = poi.id == selectedPoiId;
    final accent = selected ? orange : _accent(poi.type);
    canvas.drawCircle(
      point,
      (landmark ? 7.5 : 3.3) * unit,
      Paint()..color = const Color(0xFF102239),
    );
    if (landmark) {
      _drawIcon(canvas, _icon(poi.type), point, 11.5 * unit, accent);
    } else {
      canvas.drawCircle(point, 2.2 * unit, Paint()..color = accent);
    }
    if (!landmark && geometry.scale * zoom < 4 && !selected) return;
    final painter = TextPainter(
      text: TextSpan(
        text: _shortName(poi.name),
        style: TextStyle(
          fontSize: (landmark ? 9.5 : 9.0) * unit,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          color: selected ? orange : const Color(0xFFE4ECF7),
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 94 * unit);
    for (final dy in [-painter.height - 11 * unit, 11 * unit]) {
      final label = Rect.fromLTWH(
        point.dx - painter.width / 2,
        point.dy + dy,
        painter.width,
        painter.height,
      ).inflate(3 * unit);
      if (label.left < 0 ||
          label.top < 0 ||
          label.right > geometry.viewport.width ||
          label.bottom > geometry.viewport.height ||
          occupied.any((used) => used.overlaps(label))) {
        continue;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(label, Radius.circular(4 * unit)),
        Paint()..color = const Color(0xFF07111E).withValues(alpha: .94),
      );
      painter.paint(canvas, label.topLeft + Offset(3 * unit, 3 * unit));
      occupied.add(label);
      break;
    }
  }

  void _paintActive(Canvas canvas, Offset point) {
    canvas.drawCircle(
      point,
      12 * unit,
      Paint()..color = const Color(0xFF4BABFF).withValues(alpha: .16),
    );
    canvas.drawCircle(point, 7 * unit, Paint()..color = Colors.white);
    canvas.drawCircle(
      point,
      5 * unit,
      Paint()..color = const Color(0xFF4BABFF),
    );
  }

  void _paintUser(Canvas canvas, Offset point, PositionSample position) {
    final radius = (17 + (1 - position.confidence.clamp(0, 1)) * 17) * unit;
    canvas.drawCircle(
      point,
      radius,
      Paint()..color = const Color(0xFF4BABFF).withValues(alpha: .12),
    );
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..color = const Color(0xFF4BABFF).withValues(alpha: .35)
        ..strokeWidth = unit
        ..style = PaintingStyle.stroke,
    );
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(-position.headingDegrees * math.pi / 180);
    final arrow = Path()
      ..moveTo(19 * unit, 0)
      ..lineTo(8 * unit, -6 * unit)
      ..lineTo(8 * unit, 6 * unit)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFF4BABFF));
    canvas.restore();
    _paintActive(canvas, point);
  }

  void _drawIcon(
    Canvas canvas,
    IconData icon,
    Offset centre,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _dashes(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double dash,
    double gap,
  ) {
    final delta = b - a;
    if (delta.distance < .001) return;
    final direction = delta / delta.distance;
    for (var cursor = 0.0; cursor < delta.distance; cursor += dash + gap) {
      canvas.drawLine(
        a + direction * cursor,
        a + direction * math.min(cursor + dash, delta.distance),
        paint,
      );
    }
  }

  static Color _roomFill(String type) => switch (type) {
    'ramp' => const Color(0xFF302A26),
    'restroom' => const Color(0xFF252B43),
    'auditorium' => const Color(0xFF282C45),
    'laboratory' || 'project_laboratory' => const Color(0xFF163340),
    'cafeteria' => const Color(0xFF332B24),
    'services' ||
    'library' ||
    'finance' ||
    'administration' => const Color(0xFF1C343B),
    'archive' => const Color(0xFF29323F),
    _ => const Color(0xFF192D43),
  };
  static Color _accent(String type) => switch (type) {
    'ramp' || 'cafeteria' => const Color(0xFFDDA36D),
    'entrance' || 'upper_entrance' => const Color(0xFF7BC4B3),
    'restroom' || 'auditorium' => const Color(0xFFAAACDC),
    'court' || 'agronomy' => const Color(0xFF87B99D),
    'laboratory' || 'project_laboratory' => const Color(0xFF70B9CB),
    'library' ||
    'finance' ||
    'administration' ||
    'services' => const Color(0xFF7BBDB6),
    _ => const Color(0xFF8BAECD),
  };
  static IconData _icon(String type) => switch (type) {
    'court' => Icons.sports_soccer_rounded,
    'agronomy' => Icons.spa_outlined,
    'ramp' => Icons.trending_up_rounded,
    'cafeteria' => Icons.local_cafe_outlined,
    'library' => Icons.menu_book_rounded,
    'finance' => Icons.account_balance_wallet_outlined,
    'restroom' => Icons.wc_rounded,
    'administration' || 'services' => Icons.support_agent_rounded,
    'laboratory' || 'project_laboratory' => Icons.science_outlined,
    'auditorium' => Icons.theater_comedy_outlined,
    'entrance' || 'upper_entrance' => Icons.login_rounded,
    'archive' => Icons.inventory_2_outlined,
    _ => Icons.meeting_room_outlined,
  };
  static bool _isLandmark(String type) => !{
    'classroom',
    'laboratory',
    'project_laboratory',
    'clinic',
    'staff_room',
  }.contains(type);
  static String _shortName(String value) => value
      .replaceAll('Laboratório de ', 'Lab. ')
      .replaceAll('Laboratório ', 'Lab. ')
      .replaceAll(' (Machado de Assis)', '')
      .replaceAll(' (Informática)', '')
      .replaceAll(' (Professores)', '')
      .replaceAll('Entrada Tyto/Gran + Secretaria', 'Entrada Tyto')
      .replaceAll('Rampa de acesso a uma sala', 'Sala com rampa')
      .replaceAll('Entrada da rampa para o piso superior', 'Rampa • 1º piso')
      .replaceAll('Rampa para o térreo', 'Rampa • térreo')
      .replaceAll(RegExp(r' —.*'), '');

  static String _overviewName(String value) => switch (value) {
    'Laboratório de Química' => 'Química',
    'Laboratório de Microscopia' => 'Lab. Micro',
    'Laboratório de Informática' => 'Informática',
    'Laboratório Kaisen (Machado de Assis)' => 'Lab. Kaisen',
    'Alan Turing (Informática)' => 'Alan Turing',
    'Cora Coralina (Professores)' => 'Cora Coralina',
    'BWC Feminino' => 'BWC F',
    'BWC Masculino' => 'BWC M',
    _ => _shortName(value),
  };

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final poi in geometry.campus.pois.where(
          (p) => p.floor == geometry.floor,
        ))
          CustomPainterSemantics(
            rect: Rect.fromCenter(
              center: geometry.project(poi.displayX, poi.displayY),
              width: 28 * unit,
              height: 28 * unit,
            ),
            properties: SemanticsProperties(
              label: poi.name,
              textDirection: TextDirection.ltr,
              button: true,
              onTap: () => onPoiSelected(poi),
            ),
          ),
      ];
  @override
  bool shouldRebuildSemantics(covariant _FloorPlanPainter oldDelegate) =>
      oldDelegate.geometry != geometry;
  @override
  bool shouldRepaint(covariant _FloorPlanPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.zoom != zoom ||
      oldDelegate.route != route ||
      oldDelegate.activeNodeId != activeNodeId ||
      oldDelegate.selectedPoiId != selectedPoiId ||
      oldDelegate.userPosition != userPosition;
}
