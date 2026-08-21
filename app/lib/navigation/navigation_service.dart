import '../models/campus_map.dart';
import 'a_star.dart';
import 'route_result.dart';

class NavigationService {
  final AStar _aStar;

  const NavigationService({this._aStar = const AStar()});

  RouteResult? calculateRoute({
    required CampusMap campus,
    required CampusPoi origin,
    required CampusPoi destination,
    bool accessibleOnly = false,
    Set<String> blockedEdgeIds = const {},
  }) {
    return calculateRouteFromNode(
      campus: campus,
      startNodeId: origin.navigationNode,
      destination: destination,
      accessibleOnly: accessibleOnly,
      blockedEdgeIds: blockedEdgeIds,
    );
  }

  RouteResult? calculateRouteFromNode({
    required CampusMap campus,
    required String startNodeId,
    required CampusPoi destination,
    bool accessibleOnly = false,
    Set<String> blockedEdgeIds = const {},
  }) {
    final path = _aStar.findPath(
      campus: campus,
      startNodeId: startNodeId,
      goalNodeId: destination.navigationNode,
      accessibleOnly: accessibleOnly,
      blockedEdgeIds: blockedEdgeIds,
    );

    if (path == null) return null;

    final hasPhysicalMetrics = campus.metadata.hasValidatedMetricGeometry;
    const walkingSpeedMetersPerSecond = 1.25;
    final seconds = hasPhysicalMetrics
        ? (path.cost <= 0
              ? 0
              : (path.cost / walkingSpeedMetersPerSecond).ceil())
        : null;

    return RouteResult(
      nodes: path.nodes,
      edges: path.edges,
      instructions: _buildInstructions(
        nodes: path.nodes,
        edges: path.edges,
        destination: destination,
        hasPhysicalMetrics: hasPhysicalMetrics,
      ),
      routeCost: path.cost,
      distanceMeters: hasPhysicalMetrics ? path.cost : null,
      estimatedDuration: seconds == null ? null : Duration(seconds: seconds),
    );
  }

  List<RouteInstruction> _buildInstructions({
    required List<NavigationNode> nodes,
    required List<NavigationEdge> edges,
    required CampusPoi destination,
    required bool hasPhysicalMetrics,
  }) {
    if (nodes.length <= 1) {
      return [
        RouteInstruction(
          title: 'Você já está no destino',
          detail: destination.name,
          type: 'arrival',
        ),
      ];
    }

    final result = <RouteInstruction>[];

    for (var i = 0; i < edges.length; i++) {
      final edge = edges[i];
      final current = nodes[i];
      final next = nodes[i + 1];

      if (edge.type == 'ramp' ||
          edge.type == 'stairs' ||
          current.floor != next.floor) {
        final usesRamp = edge.type == 'ramp';
        result.add(
          RouteInstruction(
            title: next.floor > current.floor
                ? 'Suba para o piso superior'
                : 'Desça para o térreo',
            detail: usesRamp
                ? 'Siga pelos lances da rampa para mudar de piso.'
                : 'Use a conexão vertical indicada no mapa.',
            type: usesRamp ? 'ramp' : 'stairs',
          ),
        );
      } else {
        result.add(_instructionForEdge(edge, hasPhysicalMetrics));
      }
    }

    result.add(
      RouteInstruction(
        title: 'Destino alcançado',
        detail: destination.name,
        type: 'arrival',
      ),
    );

    return result;
  }

  RouteInstruction _instructionForEdge(
    NavigationEdge edge,
    bool hasPhysicalMetrics,
  ) {
    switch (edge.type) {
      case 'opening':
        return const RouteInstruction(
          title: 'Entre na área aberta da quadra',
          detail: 'Use a abertura localizada no fim do corredor.',
          type: 'opening',
        );
      case 'open_area':
        return const RouteInstruction(
          title: 'Contorne a área da quadra',
          detail: 'Siga pelo caminho indicado ao redor da área aberta.',
          type: 'open_area',
        );
      case 'service_access':
        return const RouteInstruction(
          title: 'Siga para o setor de serviços',
          detail: 'Continue pelo acesso ao lado da quadra.',
          type: 'service',
        );
      case 'ramp_access':
        return const RouteInstruction(
          title: 'Siga até a rampa',
          detail: 'Acompanhe o acesso destacado no mapa.',
          type: 'ramp',
        );
      case 'door':
        return const RouteInstruction(
          title: 'Acesse o ambiente indicado',
          detail: 'Use a porta conectada ao corredor.',
          type: 'door',
        );
      default:
        return RouteInstruction(
          title: 'Continue pelo corredor',
          detail: hasPhysicalMetrics
              ? 'Siga por ${edge.distance.toStringAsFixed(0)} m.'
              : 'Avance pelo trecho indicado no mapa conceitual.',
          type: 'walk',
        );
    }
  }
}
