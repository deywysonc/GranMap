import 'dart:math' as math;

import '../models/campus_map.dart';
import '../positioning/position_sample.dart';

class FieldWalkthrough {
  final String id;
  final String label;
  final List<int> floors;
  final List<String> anchorNodeIds;
  final List<String> assetPaths;
  final double activationRadius;

  const FieldWalkthrough({
    required this.id,
    required this.label,
    required this.floors,
    required this.anchorNodeIds,
    required this.assetPaths,
    this.activationRadius = 30,
  });

  double distanceTo(CampusMap campus, PositionSample position) {
    var nearest = double.infinity;
    for (final nodeId in anchorNodeIds) {
      final node = campus.nodeById(nodeId);
      if (node == null || node.floor != position.floor) continue;
      final distance = math.sqrt(
        math.pow(node.x - position.x, 2) + math.pow(node.y - position.y, 2),
      );
      nearest = math.min(nearest, distance);
    }
    return nearest;
  }
}

abstract final class FieldWalkthroughCatalog {
  static const all = <FieldWalkthrough>[
    FieldWalkthrough(
      id: 'entrada_gran',
      label: 'Entrada Gran',
      floors: [0],
      anchorNodeIds: ['ground_c1_start'],
      assetPaths: [
        'assets/walkthroughs/entrada_gran/frame_01.jpg',
        'assets/walkthroughs/entrada_gran/frame_02.jpg',
        'assets/walkthroughs/entrada_gran/frame_03.jpg',
        'assets/walkthroughs/entrada_gran/frame_04.jpg',
      ],
      activationRadius: 28,
    ),
    FieldWalkthrough(
      id: 'rampa_superior',
      label: 'Rampa para o piso superior',
      floors: [0, 1],
      anchorNodeIds: ['ground_spiral_ramp_landing', 'upper_spiral_ramp'],
      assetPaths: [
        'assets/walkthroughs/rampa_superior/frame_01.jpg',
        'assets/walkthroughs/rampa_superior/frame_02.jpg',
        'assets/walkthroughs/rampa_superior/frame_03.jpg',
        'assets/walkthroughs/rampa_superior/frame_04.jpg',
        'assets/walkthroughs/rampa_superior/frame_05.jpg',
        'assets/walkthroughs/rampa_superior/frame_06.jpg',
        'assets/walkthroughs/rampa_superior/frame_07.jpg',
        'assets/walkthroughs/rampa_superior/frame_08.jpg',
      ],
      activationRadius: 28,
    ),
    FieldWalkthrough(
      id: 'agronomia',
      label: 'Área de Agronomia',
      floors: [1],
      anchorNodeIds: ['upper_agronomy'],
      assetPaths: [
        'assets/walkthroughs/agronomia/frame_01.jpg',
        'assets/walkthroughs/agronomia/frame_02.jpg',
        'assets/walkthroughs/agronomia/frame_03.jpg',
      ],
      activationRadius: 24,
    ),
    FieldWalkthrough(
      id: 'entrada_tyto',
      label: 'Entrada Tyto/Gran + Secretaria',
      floors: [0],
      anchorNodeIds: ['ground_c2_start', 'ground_secretaria_door'],
      assetPaths: [
        'assets/walkthroughs/entrada_tyto/frame_01.jpg',
        'assets/walkthroughs/entrada_tyto/frame_02.jpg',
        'assets/walkthroughs/entrada_tyto/frame_03.jpg',
      ],
      activationRadius: 24,
    ),
  ];

  static FieldWalkthrough? nearest(CampusMap campus, PositionSample position) {
    FieldWalkthrough? selected;
    var selectedDistance = double.infinity;

    for (final capture in all) {
      if (!capture.floors.contains(position.floor)) continue;
      final distance = capture.distanceTo(campus, position);
      if (distance <= capture.activationRadius && distance < selectedDistance) {
        selected = capture;
        selectedDistance = distance;
      }
    }

    return selected;
  }
}
