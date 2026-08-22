import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/navigation/a_star.dart';
import 'package:granmap/navigation/navigation_service.dart';

Future<CampusMap> loadCorrectedCampus() async {
  final raw = await File('assets/maps/gran_tiete_upper_floorplan_v11.json')
      .readAsString();
  return CampusMap.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  late CampusMap campus;

  setUpAll(() async {
    campus = await loadCorrectedCampus();
  });

  test('declara explicitamente que geometria e distâncias são provisórias', () {
    expect(campus.building.version, '0.11-upper-floorplan-v11');
    expect(campus.metadata.roomCatalogStatus, 'real');
    expect(campus.metadata.geometryStatus, 'floorplan_relative');
    expect(campus.metadata.distanceStatus, 'provisional');
    expect(campus.metadata.distanceUnit, 'conceptual_unit');
    expect(campus.metadata.hasValidatedMetricGeometry, isFalse);
    expect(
      campus.metadata.mapMode,
      'upper_floorplan_relative_with_navigation_topology',
    );
    expect(
      campus.metadata.surveyStatus,
      'upper_floorplan_pdf_plus_four_walkthroughs_and_author_corrections_v11',
    );
  });

  test('preserva o catálogo das 27 salas reais', () {
    const realRoomIds = {
      'alan_turing',
      'cora_coralina',
      'henry_ford',
      'albert_einstein',
      'socrates',
      'karl_marx',
      'peter_drucker',
      'paulo_freire',
      'carlos_drummond',
      'zilda_arns',
      'maria_lacerda',
      'rachel_de_queiroz',
      'lab_quimica',
      'lab_microscopia',
      'lab_informatica',
      'clinica_escola',
      'leonardo_da_vinci',
      'isaac_newton',
      'van_gogh',
      'cecilia_meireles',
      'lab_kaisen_machado_assis',
      'tarsila_do_amaral',
      'auditorio',
      'monteiro_lobato',
      'fayol',
      'ayrton_senna',
      'santos_dummont',
    };

    final ids = campus.pois.map((poi) => poi.id).toSet();
    expect(ids.containsAll(realRoomIds), isTrue);
    expect(realRoomIds.length, 27);
  });

  test('não possui referências órfãs nem IDs duplicados', () {
    final nodeIds = campus.nodes.map((node) => node.id).toSet();
    final poiIds = campus.pois.map((poi) => poi.id).toSet();

    expect(nodeIds.length, campus.nodes.length);
    expect(poiIds.length, campus.pois.length);

    for (final poi in campus.pois) {
      expect(nodeIds, contains(poi.navigationNode), reason: poi.id);
    }
    for (final edge in campus.edges) {
      expect(nodeIds, contains(edge.from), reason: '${edge.from} → ${edge.to}');
      expect(nodeIds, contains(edge.to), reason: '${edge.from} → ${edge.to}');
    }
  });

  test('posiciona os dois corredores paralelos na composição corrigida', () {
    final granStart = campus.nodeById('ground_c1_start')!;
    final granEnd = campus.nodeById('ground_c1_end')!;
    final tytoStart = campus.nodeById('ground_c2_start')!;
    final tytoEnd = campus.nodeById('ground_c2_end')!;

    expect(granStart.displayX, lessThan(granEnd.displayX));
    expect(granStart.displayY, closeTo(granEnd.displayY, 5));
    expect(tytoStart.displayX, lessThan(tytoEnd.displayX));
    expect(tytoStart.displayY, closeTo(tytoEnd.displayY, .1));
    expect(granStart.displayY, greaterThan(tytoStart.displayY));

    final observedZones = campus.zones
        .where((zone) => zone.verification == 'observed_video')
        .map((zone) => zone.id)
        .toSet();
    expect(observedZones, containsAll({'zone_ground_c1', 'zone_ground_c2'}));
  });

  test('distribui portas nos dois lados do corredor Tyto/Secretaria', () {
    final doorY = campus.nodes
        .where((node) => node.id.startsWith('ground_c2_door_'))
        .map((node) => node.displayY)
        .toList();

    expect(doorY.any((y) => y > 28), isTrue);
    expect(doorY.any((y) => y < 28), isTrue);
  });

  test('aplica as correções da curva e do lado das salas da Entrada Gran', () {
    final turn = campus.nodeById('ground_c1_turn')!;
    final roomRamp = campus.nodeById('ground_c1_room_ramp')!;
    final doors = campus.nodes.where(
      (node) => node.id.startsWith('ground_c1_door_'),
    );

    expect(roomRamp.displayX, greaterThan(turn.displayX));
    expect(roomRamp.displayY, greaterThan(turn.displayY));
    expect(doors.every((door) => door.displayY < 70), isTrue);
  });

  test(
    'coloca lanchonete e entrada da rampa juntas no fim do corredor Gran',
    () {
      final corridorEnd = campus.nodeById('ground_c1_end')!;
      final snack = campus.nodeById('ground_snack_bar')!;
      final upperAccess = campus.nodeById('ground_spiral_ramp_landing')!;

      expect(snack.displayX, greaterThan(corridorEnd.displayX));
      expect(upperAccess.displayX, greaterThan(snack.displayX));
      expect(upperAccess.displayY, closeTo(snack.displayY, .1));
      expect(upperAccess.displayX - snack.displayX, lessThanOrEqualTo(18));
    },
  );

  test('liga a quadra à frente dos dois corredores', () {
    bool hasConfirmedEdge(String from, String to) => campus.edges.any(
      (edge) =>
          edge.from == from &&
          edge.to == to &&
          edge.verification == 'user_confirmed',
    );

    expect(
      hasConfirmedEdge('ground_c1_end', 'ground_court_west_north'),
      isTrue,
    );
    expect(
      hasConfirmedEdge('ground_c2_end', 'ground_court_west_south'),
      isTrue,
    );

    final granEnd = campus.nodeById('ground_c1_end')!;
    final tytoEnd = campus.nodeById('ground_c2_end')!;
    final court = campus.poiById('quadra')!;
    expect(court.displayX, greaterThan(granEnd.displayX));
    expect(court.displayX, greaterThan(tytoEnd.displayX));
  });

  test('coloca biblioteca, financeiro e banheiros do outro lado da quadra', () {
    final court = campus.poiById('quadra')!;
    for (final id in ['biblioteca', 'financeiro', 'banheiros']) {
      expect(campus.poiById(id)!.displayX, greaterThan(court.displayX));
    }
  });

  test('Portão Superior pertence somente ao piso 1', () {
    final gate = campus.poiById('portao_superior')!;
    expect(gate.floor, 1);
    expect(gate.verification, 'user_confirmed');
    expect(gate.displayX, lessThan(48));

    final touchingGate = campus.edges.where(
      (edge) =>
          edge.from == gate.navigationNode || edge.to == gate.navigationNode,
    );
    for (final edge in touchingGate) {
      final otherId = edge.from == gate.navigationNode ? edge.to : edge.from;
      expect(campus.nodeById(otherId)!.floor, 1);
    }
    expect(
      touchingGate.any(
        (edge) =>
            edge.verification == 'user_confirmed' &&
            (edge.from == 'upper_spine_0' || edge.to == 'upper_spine_0'),
      ),
      isTrue,
    );
  });

  test('reproduz a sequência longitudinal da planta do piso superior', () {
    const orderedDoorIds = [
      'upper_door_0',
      'upper_door_1',
      'upper_door_2',
      'upper_door_3',
      'upper_door_4',
      'upper_door_5',
      'upper_door_6',
      'upper_door_7',
      'upper_door_8',
    ];
    final doors = orderedDoorIds.map((id) => campus.nodeById(id)!).toList();
    for (var index = 1; index < doors.length; index++) {
      expect(doors[index].displayX, greaterThan(doors[index - 1].displayX));
    }
    expect(doors.map((door) => door.displayY).toSet(), hasLength(1));

    final upperZoneIds = campus.zones
        .where((zone) => zone.floor == 1)
        .map((zone) => zone.id)
        .toSet();
    expect(
      upperZoneIds,
      containsAll({
        'zone_upper_corridor',
        'zone_upper_auditorio',
        'zone_upper_bwc_masc',
        'zone_upper_bwc_fem',
        'zone_upper_archive',
      }),
    );
  });

  test('posiciona a rampa no canto inferior esquerdo do piso superior', () {
    final ramp = campus.poiById('rampa_caracol')!;
    final upperDoors = campus.nodes.where(
      (node) => node.id.startsWith('upper_door_'),
    );

    expect(ramp.floor, 1);
    expect(ramp.displayX, lessThan(upperDoors.first.displayX));
    expect(ramp.displayY, lessThan(upperDoors.first.displayY));
    expect(campus.poiById('arquivo_superior'), isNotNull);
    expect(campus.poiById('bwc_masculino_superior'), isNotNull);
    expect(campus.poiById('bwc_feminino_superior'), isNotNull);
  });

  test('rota entre corredores preserva a demo sem fingir conexão filmada', () {
    final path = const AStar().findPath(
      campus: campus,
      startNodeId: campus.poiById('entrada_gran')!.navigationNode,
      goalNodeId: campus.poiById('secretaria')!.navigationNode,
    );

    expect(path, isNotNull);
    final ids = path!.nodes.map((node) => node.id).toSet();
    expect(ids, contains('ground_court_west_north'));
    expect(ids, contains('ground_court_west_mid'));
    expect(ids, contains('ground_court_west_south'));
    expect(
      path.edges.any((edge) => edge.verification == 'user_confirmed'),
      isTrue,
    );
    expect(path.edges.any((edge) => edge.verification == 'unlocated'), isFalse);
  });

  test('mudança de piso usa a rampa em lances observada nos vídeos', () {
    final path = const AStar().findPath(
      campus: campus,
      startNodeId: campus.poiById('entrada_gran')!.navigationNode,
      goalNodeId: campus.poiById('portao_superior')!.navigationNode,
    );

    expect(path, isNotNull);
    final ids = path!.nodes.map((node) => node.id).toSet();
    expect(ids, contains('ground_spiral_ramp_landing'));
    expect(ids, contains('ground_ramp_landing_mid'));
    expect(ids, contains('upper_ramp_run_2'));
    expect(ids, contains('upper_spiral_ramp'));
    expect(path.edges.any((edge) => edge.type == 'ramp'), isTrue);
    expect(
      path.edges
          .where((edge) => edge.type == 'ramp')
          .every((edge) => edge.verification == 'observed_video'),
      isTrue,
    );
  });

  test('separa coordenadas de navegação da composição visual corrigida', () {
    expect(
      campus.metadata.coordinateSystem,
      'navigation_conceptual_xyz_with_floorplan_display_xy',
    );
    expect(
      campus.nodes.any(
        (node) => node.x != node.displayX || node.y != node.displayY,
      ),
      isTrue,
    );
  });

  test('rotas conceituais não fingem métricas físicas', () {
    final route = const NavigationService().calculateRoute(
      campus: campus,
      origin: campus.poiById('entrada_gran')!,
      destination: campus.poiById('lab_quimica')!,
    );

    expect(route, isNotNull);
    expect(route!.hasPhysicalMetrics, isFalse);
    expect(route.distanceMeters, isNull);
    expect(route.estimatedDuration, isNull);
    expect(
      route.instructions.any(
        (instruction) => instruction.detail.contains(' m.'),
      ),
      isFalse,
    );
  });
}
