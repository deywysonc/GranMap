import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/navigation/a_star.dart';

void main() {
  test('A* encontra caminho com mudança de piso', () {
    final campus = CampusMap(
      building: const BuildingInfo(id: 'b', name: 'B', version: '1'),
      floors: const [
        CampusFloor(id: 'f0', name: 'Térreo', level: 0, elevation: 0),
        CampusFloor(id: 'f1', name: 'Superior', level: 1, elevation: 3.2),
      ],
      pois: const [],
      nodes: const [
        NavigationNode(id: 'a', floor: 0, x: 0, y: 0, z: 0, type: 'corridor'),
        NavigationNode(id: 'b', floor: 0, x: 1, y: 0, z: 0, type: 'stairs'),
        NavigationNode(id: 'c', floor: 1, x: 1, y: 0, z: 3.2, type: 'stairs'),
        NavigationNode(id: 'd', floor: 1, x: 2, y: 0, z: 3.2, type: 'corridor'),
      ],
      edges: const [
        NavigationEdge(
          from: 'a',
          to: 'b',
          distance: 1,
          type: 'corridor',
          accessible: true,
        ),
        NavigationEdge(
          from: 'b',
          to: 'c',
          distance: 4,
          type: 'stairs',
          accessible: false,
        ),
        NavigationEdge(
          from: 'c',
          to: 'd',
          distance: 1,
          type: 'corridor',
          accessible: true,
        ),
      ],
    );

    final result = const AStar().findPath(
      campus: campus,
      startNodeId: 'a',
      goalNodeId: 'd',
    );

    expect(result, isNotNull);
    expect(result!.nodes.map((e) => e.id).toList(), ['a', 'b', 'c', 'd']);
    expect(result.cost, 6);
  });

  test('A* desvia de uma Edge bloqueada pela operação do campus', () {
    final campus = CampusMap(
      building: const BuildingInfo(id: 'b', name: 'B', version: '1'),
      floors: const [
        CampusFloor(id: 'f0', name: 'Térreo', level: 0, elevation: 0),
      ],
      pois: const [],
      nodes: const [
        NavigationNode(id: 'a', floor: 0, x: 0, y: 0, z: 0, type: 'corridor'),
        NavigationNode(id: 'b', floor: 0, x: 1, y: 0, z: 0, type: 'corridor'),
        NavigationNode(id: 'c', floor: 0, x: 1, y: 1, z: 0, type: 'corridor'),
        NavigationNode(id: 'd', floor: 0, x: 2, y: 0, z: 0, type: 'corridor'),
      ],
      edges: const [
        NavigationEdge(
          from: 'a',
          to: 'b',
          distance: 1,
          type: 'corridor',
          accessible: true,
        ),
        NavigationEdge(
          from: 'b',
          to: 'd',
          distance: 1,
          type: 'corridor',
          accessible: true,
        ),
        NavigationEdge(
          from: 'a',
          to: 'c',
          distance: 2,
          type: 'corridor',
          accessible: true,
        ),
        NavigationEdge(
          from: 'c',
          to: 'd',
          distance: 2,
          type: 'corridor',
          accessible: true,
        ),
      ],
    );

    final result = const AStar().findPath(
      campus: campus,
      startNodeId: 'a',
      goalNodeId: 'd',
      blockedEdgeIds: const {'a__b'},
    );

    expect(result, isNotNull);
    expect(result!.nodes.map((node) => node.id), ['a', 'c', 'd']);
    expect(result.cost, 4);
  });
}
