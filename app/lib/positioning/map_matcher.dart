import 'dart:math' as math;

import '../models/campus_map.dart';
import 'position_sample.dart';

class MapMatchResult {
  final PositionSample position;
  final NavigationEdge? edge;
  final double distanceUnits;
  final double confidence;

  const MapMatchResult({
    required this.position,
    required this.edge,
    required this.distanceUnits,
    required this.confidence,
  });
}

class MapMatcher {
  const MapMatcher();

  MapMatchResult match({
    required CampusMap campus,
    required PositionSample sample,
  }) {
    final nodes = {for (final node in campus.nodes) node.id: node};
    NavigationEdge? nearestEdge;
    _PointOnSegment? nearest;

    for (final edge in campus.edges) {
      final from = nodes[edge.from];
      final to = nodes[edge.to];
      if (from == null || to == null) continue;
      if (from.floor != sample.floor || to.floor != sample.floor) continue;
      final point = _nearestPoint(
        sample.x,
        sample.y,
        from.x,
        from.y,
        to.x,
        to.y,
      );
      if (nearest == null || point.distance < nearest.distance) {
        nearest = point;
        nearestEdge = edge;
      }
    }

    if (nearest == null) {
      return MapMatchResult(
        position: sample,
        edge: null,
        distanceUnits: double.infinity,
        confidence: 0,
      );
    }

    final mapConfidence = (1 - nearest.distance / 14).clamp(0, 1).toDouble();
    return MapMatchResult(
      position: PositionSample(
        x: nearest.x,
        y: nearest.y,
        z: sample.z,
        floor: sample.floor,
        headingDegrees: sample.headingDegrees,
        accuracyMeters: math.max(sample.accuracyMeters, nearest.distance),
        confidence: (sample.confidence * .62 + mapConfidence * .38)
            .clamp(0, 1)
            .toDouble(),
        timestamp: sample.timestamp,
      ),
      edge: nearestEdge,
      distanceUnits: nearest.distance,
      confidence: mapConfidence,
    );
  }

  _PointOnSegment _nearestPoint(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    final t = lengthSquared <= .000001
        ? 0.0
        : (((px - ax) * dx + (py - ay) * dy) / lengthSquared)
              .clamp(0, 1)
              .toDouble();
    final x = ax + dx * t;
    final y = ay + dy * t;
    final distance = math.sqrt(math.pow(px - x, 2) + math.pow(py - y, 2));
    return _PointOnSegment(x: x, y: y, distance: distance);
  }
}

class _PointOnSegment {
  final double x;
  final double y;
  final double distance;

  const _PointOnSegment({
    required this.x,
    required this.y,
    required this.distance,
  });
}
