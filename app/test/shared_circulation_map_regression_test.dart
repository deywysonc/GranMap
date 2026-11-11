import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/navigation/a_star.dart';
import 'package:granmap/widgets/map_scene_geometry.dart';

void main() {
  late CampusMap campus;
  setUpAll(() async {
    campus = CampusMap.fromJson(
      jsonDecode(
        await File('assets/maps/gran_tiete_floorplan_v12.json').readAsString(),
      ) as Map<String, dynamic>,
    );
  });

  test('espaço amplo substitui as faixas sem incorporar ambientes', () {
    final area = campus.zones.singleWhere(
      (zone) => zone.id == 'zone_upper_south_access',
    );
    expect(area.type, 'open_area');
    expect(_rect(area), const Rect.fromLTWH(4, 17, 147.9, 31.8));
    expect(area.verification, 'user_reported_approximate');
    expect(
      campus.zones.any((zone) => zone.id == 'zone_upper_south_crosslink'),
      isFalse,
    );
    for (final zone in campus.zones.where(
      (zone) => zone.floor == 1 && !MapSceneGeometry.isCorridor(zone.type),
    )) {
      expect(_rect(area).overlaps(_rect(zone)), isFalse, reason: zone.id);
    }
  });

  test('malha nova permanece sobre chão caminhável e não garante acesso', () {
    final newEdges = campus.edges.where(
      (edge) =>
          edge.type == 'open_area' && edge.verification == 'access_unverified',
    );
    expect(newEdges, hasLength(17));
    for (final edge in newEdges) {
      expect(edge.accessible, isFalse);
      expect(edge.verification, 'access_unverified');
      final from = campus.nodeById(edge.from)!;
      final to = campus.nodeById(edge.to)!;
      expect(from.floor, to.floor);
      final surfaces = campus.zones.where(
        (zone) =>
            zone.floor == from.floor && MapSceneGeometry.isCorridor(zone.type),
      );
      for (var sample = 0; sample <= 100; sample++) {
        final t = sample / 100;
        final point = Offset(
          from.displayX + (to.displayX - from.displayX) * t,
          from.displayY + (to.displayY - from.displayY) * t,
        );
        expect(
          surfaces.any((zone) => _rect(zone).inflate(.00001).contains(point)),
          isTrue,
          reason: '${edge.from} → ${edge.to}: $point',
        );
      }
    }
  });

  test('espaço vazio do superior não se comporta como uma sala clicável', () {
    final geometry = MapSceneGeometry(
      campus: campus,
      floor: 1,
      viewport: const Size(360, 800),
    );
    for (final point in const [
      Offset(30, 35),
      Offset(70, 35),
      Offset(115, 35),
    ]) {
      expect(geometry.hitTestPoi(geometry.project(point.dx, point.dy)), isNull);
    }
  });

  test('lanchonete é destino terminal, nunca passagem para outro piso', () {
    final anchor = campus.poiById('lanchonete')!.navigationNode;
    expect(
      campus.edges.where((edge) => edge.from == anchor || edge.to == anchor),
      hasLength(1),
    );
    for (final originId in ['entrada_gran', 'entrada_tyto_gran']) {
      final origin = campus.poiById(originId)!;
      for (final destination in campus.pois.where((poi) => poi.floor == 1)) {
        final path = const AStar().findPath(
          campus: campus,
          startNodeId: origin.navigationNode,
          goalNodeId: destination.navigationNode,
        );
        expect(path, isNotNull);
        expect(
          path!.nodes.any((node) => node.id == anchor),
          isFalse,
          reason: '$originId → ${destination.id}',
        );
      }
    }
  });

  test('fachadas da lanchonete e rampa se voltam à mesma frente da quadra', () {
    CampusZone zone(String id) => campus.zones.singleWhere((z) => z.id == id);
    final court = zone('zone_ground_court');
    final front = zone('zone_ground_court_north');
    final snack = zone('zone_ground_snack');
    final ramp = zone('zone_ground_upper_access');
    expect(front.type, 'open_area');
    expect(front.y, court.y + court.height);
    expect(snack.y, front.y + front.height);
    expect(ramp.y, snack.y);
    expect(snack.x, court.x);
    expect(ramp.x + ramp.width, court.x + court.width);
    expect(snack.x + snack.width, lessThan(ramp.x));
    expect(campus.nodeById('ground_snack_front')!.displayY, lessThan(snack.y));
    expect(
      campus.nodeById('ground_ramp_access_corner')!.displayY,
      lessThan(ramp.y),
    );
  });
}

Rect _rect(CampusZone zone) =>
    Rect.fromLTWH(zone.x, zone.y, zone.width, zone.height);
