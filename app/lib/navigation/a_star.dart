import 'dart:math' as math;

import '../models/campus_map.dart';

class AStarPath {
  final List<NavigationNode> nodes;
  final List<NavigationEdge> edges;
  final double cost;

  const AStarPath({
    required this.nodes,
    required this.edges,
    required this.cost,
  });
}

class AStar {
  const AStar();

  AStarPath? findPath({
    required CampusMap campus,
    required String startNodeId,
    required String goalNodeId,
    bool accessibleOnly = false,
    Set<String> blockedEdgeIds = const {},
  }) {
    final nodesById = {for (final node in campus.nodes) node.id: node};

    final start = nodesById[startNodeId];
    final goal = nodesById[goalNodeId];

    if (start == null || goal == null) return null;
    if (start.id == goal.id) {
      return AStarPath(nodes: [start], edges: const [], cost: 0);
    }

    final heuristicScale = _heuristicScale(campus, nodesById);

    final adjacency = <String, List<NavigationEdge>>{};

    for (final edge in campus.edges) {
      if (accessibleOnly && !edge.accessible) continue;
      final id = '${edge.from}__${edge.to}';
      if (blockedEdgeIds.contains(id)) continue;

      adjacency.putIfAbsent(edge.from, () => []).add(edge);
      adjacency
          .putIfAbsent(edge.to, () => [])
          .add(
            NavigationEdge(
              from: edge.to,
              to: edge.from,
              distance: edge.distance,
              type: edge.type,
              accessible: edge.accessible,
              verification: edge.verification,
              evidenceCaptureIds: edge.evidenceCaptureIds,
            ),
          );
    }

    final openSet = <String>{start.id};
    final cameFrom = <String, String>{};
    final cameByEdge = <String, NavigationEdge>{};
    final gScore = <String, double>{start.id: 0};
    final fScore = <String, double>{
      start.id: _heuristic(start, goal) * heuristicScale,
    };

    while (openSet.isNotEmpty) {
      final currentId = openSet.reduce((a, b) {
        final scoreA = fScore[a] ?? double.infinity;
        final scoreB = fScore[b] ?? double.infinity;
        return scoreA <= scoreB ? a : b;
      });

      if (currentId == goal.id) {
        return _reconstruct(
          currentId: currentId,
          nodesById: nodesById,
          cameFrom: cameFrom,
          cameByEdge: cameByEdge,
          cost: gScore[currentId] ?? 0,
        );
      }

      openSet.remove(currentId);

      for (final edge in adjacency[currentId] ?? const <NavigationEdge>[]) {
        final neighbor = nodesById[edge.to];
        if (neighbor == null) continue;

        final tentativeScore =
            (gScore[currentId] ?? double.infinity) + edge.distance;

        if (tentativeScore < (gScore[neighbor.id] ?? double.infinity)) {
          cameFrom[neighbor.id] = currentId;
          cameByEdge[neighbor.id] = edge;
          gScore[neighbor.id] = tentativeScore;
          fScore[neighbor.id] =
              tentativeScore + _heuristic(neighbor, goal) * heuristicScale;
          openSet.add(neighbor.id);
        }
      }
    }

    return null;
  }

  double _heuristic(NavigationNode a, NavigationNode b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  double _heuristicScale(
    CampusMap campus,
    Map<String, NavigationNode> nodesById,
  ) {
    var scale = 1.0;
    for (final edge in campus.edges) {
      final from = nodesById[edge.from];
      final to = nodesById[edge.to];
      if (from == null || to == null) continue;
      final coordinateDistance = _heuristic(from, to);
      if (coordinateDistance <= 0) continue;
      scale = math.min(scale, edge.distance / coordinateDistance);
    }
    return scale.clamp(0.0, 1.0).toDouble();
  }

  AStarPath _reconstruct({
    required String currentId,
    required Map<String, NavigationNode> nodesById,
    required Map<String, String> cameFrom,
    required Map<String, NavigationEdge> cameByEdge,
    required double cost,
  }) {
    final nodeIds = <String>[currentId];
    final edges = <NavigationEdge>[];

    var cursor = currentId;
    while (cameFrom.containsKey(cursor)) {
      final edge = cameByEdge[cursor];
      if (edge != null) edges.add(edge);
      cursor = cameFrom[cursor]!;
      nodeIds.add(cursor);
    }

    final nodes = nodeIds.reversed
        .map((id) => nodesById[id]!)
        .toList(growable: false);

    return AStarPath(
      nodes: nodes,
      edges: edges.reversed.toList(growable: false),
      cost: cost,
    );
  }
}
