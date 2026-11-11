import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/navigation/a_star.dart';
import 'package:granmap/widgets/map_scene_geometry.dart';

const _chemistryGroups = [
  (
    id: 'labs_quimica_entrada_gran',
    name: 'Laboratórios de Química na Entrada Gran',
    zoneId: 'zone_ground_labs_quimica_entrada',
    anchorId: 'ground_labs_quimica_entrada',
    rect: Rect.fromLTWH(4, 83, 22, 8),
    anchor: Offset(15, 84),
    navigation: Offset(7, 38),
    branch: [
      'ground_c1_start',
      'ground_labs_quimica_entry_approach',
      'ground_labs_quimica_entrada',
    ],
  ),
  (
    id: 'labs_quimica_sala_rampa',
    name: 'Laboratórios de Química próximos à sala com rampa',
    zoneId: 'zone_ground_labs_quimica_rampa',
    anchorId: 'ground_labs_quimica_rampa',
    rect: Rect.fromLTWH(0, 54, 13, 10),
    anchor: Offset(12, 59),
    navigation: Offset(4, 22),
    branch: [
      'ground_c1_turn',
      'ground_labs_quimica_ramp_corner',
      'ground_labs_quimica_ramp_approach',
      'ground_labs_quimica_rampa',
    ],
  ),
];

void main() {
  late CampusMap campus;

  setUpAll(() async {
    campus = CampusMap.fromJson(
      jsonDecode(
        await File('assets/maps/gran_tiete_floorplan_v12.json').readAsString(),
      ) as Map<String, dynamic>,
    );
  });

  test('registra os novos grupos de Química como posições aproximadas', () {
    for (final group in _chemistryGroups) {
      final poi = campus.poiById(group.id)!;
      final zone = _zone(campus, group.zoneId);
      final anchor = campus.nodeById(group.anchorId)!;

      expect(poi.name, group.name);
      expect(zone.name, group.name);
      expect(RegExp(r'\d').hasMatch(poi.name), isFalse);
      expect(poi.type, 'laboratory');
      expect(zone.type, 'laboratory');
      expect(poi.floor, 0);
      expect(zone.floor, 0);
      expect(poi.verification, 'user_reported_approximate');
      expect(zone.verification, 'user_reported_approximate');
      expect(_rect(zone), group.rect);
      expect(poi.navigationNode, group.anchorId);
      expect(Offset(poi.displayX, poi.displayY), group.anchor);
      expect(Offset(anchor.displayX, anchor.displayY), group.anchor);
      expect(Offset(anchor.x, anchor.y), group.navigation);
      expect(anchor.type, isNot('door'));
    }
  });

  test('mantém acessos provisórios ortogonais sem inventar portas', () {
    for (final group in _chemistryGroups) {
      final path = const AStar().findPath(
        campus: campus,
        startNodeId: group.branch.first,
        goalNodeId: group.anchorId,
      );
      expect(path, isNotNull, reason: group.id);
      expect(path!.nodes.map((node) => node.id), group.branch);
      expect(path.edges, hasLength(group.branch.length - 1));
      for (final edge in path.edges) {
        expect(edge.type, 'provisional_access');
        expect(edge.verification, 'access_unverified');
        expect(edge.accessible, isFalse);
      }
      for (var i = 0; i < path.nodes.length - 1; i++) {
        final from = path.nodes[i];
        final to = path.nodes[i + 1];
        expect(
          from.displayX == to.displayX || from.displayY == to.displayY,
          isTrue,
          reason: '${from.id} → ${to.id}',
        );
      }
    }
    final nearRamp = _zone(campus, 'zone_ground_labs_quimica_rampa');
    final rampedRoom = _zone(campus, 'zone_ground_ramped_room');
    expect(nearRamp.x + nearRamp.width, lessThan(rampedRoom.x));
  });

  test('preserva o laboratório de Química que já existia no catálogo', () {
    final poi = campus.poiById('lab_quimica')!;
    final node = campus.nodeById('ground_c1_door_0')!;
    final zone = _zone(campus, 'zone_ground_lab_quimica');

    expect(poi.name, 'Laboratório de Química');
    expect(poi.navigationNode, 'ground_c1_door_0');
    expect(poi.verification, 'user_reported');
    expect([poi.x, poi.y, poi.z], [28, 42, 0]);
    expect(Offset(poi.displayX, poi.displayY), const Offset(40, 76));
    expect(Offset(node.displayX, node.displayY), const Offset(40, 76));
    expect(_rect(zone), const Rect.fromLTWH(34.25, 74, 11.5, 18));
    expect(zone.verification, 'user_reported');
  });

  for (final origin in ['entrada_gran', 'entrada_tyto_gran']) {
    for (final group in _chemistryGroups) {
      test('$origin alcança ${group.id} sem atravessar outros ambientes', () {
        final path = _route(campus, origin, group.id);
        expect(path.nodes.last.id, group.anchorId);
        expect(
          path.edges.any((edge) => edge.verification == 'access_unverified'),
          isTrue,
        );
        _expectClearOfOtherInteriors(campus, path, allowedZoneId: group.zoneId);
      });
    }
  }

  test('coloca cantina e rampa lado a lado diante da quadra', () {
    final snack = _zone(campus, 'zone_ground_snack');
    final ramp = _zone(campus, 'zone_ground_upper_access');
    final court = _zone(campus, 'zone_ground_court');
    final poi = campus.poiById('lanchonete')!;
    final anchor = campus.nodeById('ground_snack_bar')!;

    expect(_rect(snack), const Rect.fromLTWH(115, 77, 10, 15));
    expect(_rect(ramp), const Rect.fromLTWH(126, 77, 11, 15));
    expect(ramp.x - (snack.x + snack.width), closeTo(1, .0001));
    expect(snack.x, court.x);
    expect(ramp.x + ramp.width, court.x + court.width);
    expect(snack.y - (court.y + court.height), 13);
    expect(poi.navigationNode, 'ground_snack_bar');
    expect([poi.x, poi.y, poi.z], [96, 39, 0]);
    expect([anchor.x, anchor.y, anchor.z], [96, 39, 0]);
    expect(Offset(poi.displayX, poi.displayY), const Offset(120, 78));
    expect(Offset(anchor.displayX, anchor.displayY), const Offset(120, 78));
    expect(
      Offset(
        campus.nodeById('ground_spiral_ramp_landing')!.displayX,
        campus.nodeById('ground_spiral_ramp_landing')!.displayY,
      ),
      const Offset(131.5, 78),
    );
  });

  for (final origin in ['entrada_gran', 'entrada_tyto_gran']) {
    test('$origin sobe pela rampa sem cortar a cantina ou salas', () {
      final path = _route(campus, origin, 'van_gogh');
      expect(
        path.nodes.map((node) => node.id),
        containsAll([
          'ground_ramp_access_corner',
          'ground_spiral_ramp_landing',
          'ground_ramp_run_1',
          'ground_ramp_landing_mid',
          'upper_ramp_run_2',
          'upper_spiral_ramp',
        ]),
      );
      final corner = campus.nodeById('ground_ramp_access_corner')!;
      expect(Offset(corner.displayX, corner.displayY), const Offset(131.5, 70));
      for (final stage in [
        (id: 'ground_ramp_run_1', y: 83.0),
        (id: 'ground_ramp_landing_mid', y: 88.0),
      ]) {
        final node = campus.nodeById(stage.id)!;
        expect(Offset(node.displayX, node.displayY), Offset(131.5, stage.y));
      }
      _expectClearOfOtherInteriors(
        campus,
        path,
        allowedZoneId: 'zone_upper_van_gogh',
      );
    });
  }

  test('posiciona Agronomia à esquerda da rampa e abaixo da galeria', () {
    final agronomy = _zone(campus, 'zone_upper_agronomy');
    final ramp = _zone(campus, 'zone_upper_ramp');
    final gallery = _zone(campus, 'zone_upper_corridor');
    final agronomyPoi = campus.poiById('area_agronomia')!;
    final rampPoi = campus.poiById('rampa_caracol')!;

    expect(_rect(agronomy), const Rect.fromLTWH(84, 1, 25, 16));
    expect(_rect(ramp), const Rect.fromLTWH(117, 1, 27, 16));
    expect(agronomy.x + agronomy.width, lessThan(ramp.x));
    expect(agronomy.y + agronomy.height, lessThan(gallery.y));
    expect(ramp.y + ramp.height, lessThan(gallery.y));
    expect(agronomyPoi.floor, 1);
    expect(rampPoi.floor, 1);
    expect(agronomyPoi.navigationNode, 'upper_agronomy');
    expect(rampPoi.navigationNode, 'upper_spiral_ramp');
    expect([agronomyPoi.x, agronomyPoi.y, agronomyPoi.z], [110, 30, 1]);
    expect([rampPoi.x, rampPoi.y, rampPoi.z], [124, 8, 1]);
    expect(
      Offset(agronomyPoi.displayX, agronomyPoi.displayY),
      const Offset(96.5, 16),
    );
    expect(Offset(rampPoi.displayX, rampPoi.displayY), const Offset(130.5, 5));
    for (final stage in [
      (id: 'upper_ramp_run_2', navigation: [124, 14, .75], y: 14.0),
      (id: 'upper_ramp_approach', navigation: [108, 18, 1], y: 20.0),
    ]) {
      final node = campus.nodeById(stage.id)!;
      expect([node.x, node.y, node.z], stage.navigation);
      expect(Offset(node.displayX, node.displayY), Offset(130.5, stage.y));
    }
  });

  for (final destination in [
    (id: 'area_agronomia', zoneId: 'zone_upper_agronomy'),
    (id: 'rampa_caracol', zoneId: 'zone_upper_ramp'),
  ]) {
    test('Portão Superior acessa ${destination.id} pela circulação comum', () {
      final path = _route(campus, 'portao_superior', destination.id);
      expect(
        path.nodes.any((node) => node.id.startsWith('upper_open_')),
        isTrue,
        reason: 'A circulação aberta oferece acesso além do antigo corredor.',
      );
      _expectClearOfOtherInteriors(
        campus,
        path,
        allowedZoneId: destination.zoneId,
      );
    });
  }

  test('toque no centro de cada novo grupo escolhe seu próprio destino', () {
    final geometry = MapSceneGeometry(
      campus: campus,
      floor: 0,
      viewport: const Size(360, 800),
    );
    for (final group in _chemistryGroups) {
      final center = geometry.zoneRect(_zone(campus, group.zoneId)).center;
      expect(geometry.hitTestPoi(center)?.id, group.id, reason: group.id);
    }
  });
}

CampusZone _zone(CampusMap campus, String id) =>
    campus.zones.singleWhere((zone) => zone.id == id);

Rect _rect(CampusZone zone) =>
    Rect.fromLTWH(zone.x, zone.y, zone.width, zone.height);

AStarPath _route(CampusMap campus, String origin, String destination) {
  final path = const AStar().findPath(
    campus: campus,
    startNodeId: campus.poiById(origin)!.navigationNode,
    goalNodeId: campus.poiById(destination)!.navigationNode,
  );
  expect(path, isNotNull, reason: '$origin → $destination');
  return path!;
}

void _expectClearOfOtherInteriors(
  CampusMap campus,
  AStarPath path, {
  required String allowedZoneId,
}) {
  const interiorTypes = {
    'classroom',
    'laboratory',
    'project_laboratory',
    'clinic',
    'administration',
    'staff_room',
    'library',
    'finance',
    'restroom',
    'auditorium',
    'archive',
    'agronomy',
    'court',
    'cafeteria',
  };
  final blocked = campus.zones.where(
    (zone) => zone.id != allowedZoneId && interiorTypes.contains(zone.type),
  );
  for (var i = 0; i < path.nodes.length - 1; i++) {
    final from = path.nodes[i];
    final to = path.nodes[i + 1];
    if (from.floor != to.floor) continue;
    final dx = (to.displayX - from.displayX).abs();
    final dy = (to.displayY - from.displayY).abs();
    final sampleCount = ((dx > dy ? dx : dy) * 4).ceil().clamp(1, 1000);
    for (var step = 0; step <= sampleCount; step++) {
      final t = step / sampleCount;
      final x = from.displayX + (to.displayX - from.displayX) * t;
      final y = from.displayY + (to.displayY - from.displayY) * t;
      for (final zone in blocked.where((zone) => zone.floor == from.floor)) {
        expect(
          x > zone.x + .0001 &&
              x < zone.x + zone.width - .0001 &&
              y > zone.y + .0001 &&
              y < zone.y + zone.height - .0001,
          isFalse,
          reason: '${from.id} → ${to.id} atravessa ${zone.id} em ($x, $y)',
        );
      }
    }
  }
}
