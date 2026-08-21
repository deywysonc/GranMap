import '../models/campus_map.dart';

class RouteInstruction {
  final String title;
  final String detail;
  final String type;

  const RouteInstruction({
    required this.title,
    required this.detail,
    required this.type,
  });
}

class RouteResult {
  final List<NavigationNode> nodes;
  final List<NavigationEdge> edges;
  final List<RouteInstruction> instructions;
  final double routeCost;
  final double? distanceMeters;
  final Duration? estimatedDuration;

  const RouteResult({
    required this.nodes,
    required this.edges,
    required this.instructions,
    required this.routeCost,
    this.distanceMeters,
    this.estimatedDuration,
  });

  bool get hasPhysicalMetrics =>
      distanceMeters != null && estimatedDuration != null;
}
