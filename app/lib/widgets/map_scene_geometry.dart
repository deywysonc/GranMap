import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/campus_map.dart';
import '../positioning/position_sample.dart';

/// One uniform, reversible transform for drawing and tapping a floor plan.
/// Display coordinates use Y pointing up; Flutter canvas coordinates point down.
class MapSceneGeometry {
  final CampusMap campus;
  final int floor;
  final Size viewport;
  final Rect bounds;
  final double scale;
  final Offset origin;

  MapSceneGeometry._({
    required this.campus,
    required this.floor,
    required this.viewport,
    required this.bounds,
    required this.scale,
    required this.origin,
  });

  factory MapSceneGeometry({
    required CampusMap campus,
    required int floor,
    required Size viewport,
    EdgeInsets padding = const EdgeInsets.fromLTRB(24, 28, 24, 66),
  }) {
    final points = <Offset>[
      for (final node in campus.nodes.where((n) => n.floor == floor))
        Offset(node.displayX, node.displayY),
      for (final poi in campus.pois.where((p) => p.floor == floor))
        Offset(poi.displayX, poi.displayY),
      for (final zone in campus.zones.where((z) => z.floor == floor)) ...[
        Offset(zone.x, zone.y),
        Offset(zone.x + zone.width, zone.y + zone.height),
      ],
    ];
    final minX = points.isEmpty
        ? 0.0
        : points.map((p) => p.dx).reduce(math.min);
    final maxX = points.isEmpty
        ? 1.0
        : points.map((p) => p.dx).reduce(math.max);
    final minY = points.isEmpty
        ? 0.0
        : points.map((p) => p.dy).reduce(math.min);
    final maxY = points.isEmpty
        ? 1.0
        : points.map((p) => p.dy).reduce(math.max);
    final bounds = Rect.fromLTWH(
      minX,
      minY,
      math.max(1.0, maxX - minX),
      math.max(1.0, maxY - minY),
    );
    final usableWidth = math.max(1.0, viewport.width - padding.horizontal);
    final usableHeight = math.max(1.0, viewport.height - padding.vertical);
    final scale = math.min(
      usableWidth / bounds.width,
      usableHeight / bounds.height,
    );
    final origin = Offset(
      padding.left + (usableWidth - bounds.width * scale) / 2,
      padding.top + (usableHeight - bounds.height * scale) / 2,
    );
    return MapSceneGeometry._(
      campus: campus,
      floor: floor,
      viewport: viewport,
      bounds: bounds,
      scale: scale,
      origin: origin,
    );
  }

  Offset project(double x, double y) => Offset(
    origin.dx + (x - bounds.left) * scale,
    origin.dy + (bounds.bottom - y) * scale,
  );

  Offset unproject(Offset point) => Offset(
    bounds.left + (point.dx - origin.dx) / scale,
    bounds.bottom - (point.dy - origin.dy) / scale,
  );

  Rect zoneRect(CampusZone zone) => Rect.fromPoints(
    project(zone.x, zone.y + zone.height),
    project(zone.x + zone.width, zone.y),
  );

  CampusPoi? poiForZone(CampusZone zone) {
    final candidates = campus.pois.where((poi) => poi.floor == floor);
    final name = _normalise(zone.name);
    for (final poi in candidates) {
      if (_normalise(poi.name) == name) return poi;
    }
    final rect = Rect.fromLTWH(zone.x, zone.y, zone.width, zone.height);
    CampusPoi? closest;
    var distance = double.infinity;
    for (final poi in candidates) {
      final point = Offset(poi.displayX, poi.displayY);
      if (!rect.contains(point)) continue;
      final next = (point - rect.center).distanceSquared;
      if (next < distance) {
        distance = next;
        closest = poi;
      }
    }
    return closest;
  }

  /// Takes an untransformed scene point. Room interiors are tap targets too.
  CampusPoi? hitTestPoi(Offset point, {double zoom = 1}) {
    final zones =
        campus.zones
            .where((zone) => zone.floor == floor && !isCorridor(zone.type))
            .toList()
          ..sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));
    for (final zone in zones) {
      if (zoneRect(zone).contains(point)) {
        final poi = poiForZone(zone);
        if (poi != null) return poi;
      }
    }
    CampusPoi? closest;
    var distance = math.pow(22 / math.max(.8, zoom), 2).toDouble();
    for (final poi in campus.pois.where((poi) => poi.floor == floor)) {
      final next =
          (project(poi.displayX, poi.displayY) - point).distanceSquared;
      if (next <= distance) {
        distance = next;
        closest = poi;
      }
    }
    return closest;
  }

  /// Filtering first would create false lines if a route leaves and returns.
  static List<List<NavigationNode>> routeSegments(
    List<NavigationNode> route,
    int floor,
  ) {
    final segments = <List<NavigationNode>>[];
    List<NavigationNode>? current;
    for (final node in route) {
      if (node.floor != floor) {
        current = null;
        continue;
      }
      if (current == null) {
        current = [];
        segments.add(current);
      }
      current.add(node);
    }
    return segments;
  }

  Offset displayPosition(PositionSample position) {
    final nodes = {
      for (final node in campus.nodes.where((n) => n.floor == position.floor))
        node.id: node,
    };
    Offset? best;
    var distance = double.infinity;
    for (final edge in campus.edges) {
      final from = nodes[edge.from];
      final to = nodes[edge.to];
      if (from == null || to == null) continue;
      final delta = Offset(to.x - from.x, to.y - from.y);
      final offset = Offset(position.x - from.x, position.y - from.y);
      final t = delta.distanceSquared == 0
          ? 0.0
          : ((offset.dx * delta.dx + offset.dy * delta.dy) /
                    delta.distanceSquared)
                .clamp(0.0, 1.0);
      final projected = Offset(from.x, from.y) + delta * t;
      final next = (projected - Offset(position.x, position.y)).distanceSquared;
      if (next < distance) {
        distance = next;
        best = Offset(
          from.displayX + (to.displayX - from.displayX) * t,
          from.displayY + (to.displayY - from.displayY) * t,
        );
      }
    }
    if (best != null) return best;
    NavigationNode? nearest;
    for (final node in nodes.values) {
      final next = (Offset(node.x, node.y) - Offset(position.x, position.y))
          .distanceSquared;
      if (next < distance) {
        distance = next;
        nearest = node;
      }
    }
    return nearest == null
        ? Offset(position.x, position.y)
        : Offset(nearest.displayX, nearest.displayY);
  }

  static bool isCorridor(String type) =>
      type.startsWith('corridor') ||
      type == 'upper_walkway' ||
      type == 'open_area';
  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'—.*|·.*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapSceneGeometry &&
          campus == other.campus &&
          floor == other.floor &&
          viewport == other.viewport &&
          scale == other.scale &&
          origin == other.origin &&
          bounds == other.bounds;

  @override
  int get hashCode =>
      Object.hash(campus, floor, viewport, scale, origin, bounds);
}
