import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:granmap/widgets/campus_twin_canvas.dart';

void main() {
  late CampusMap campus;
  setUpAll(() async {
    campus = CampusMap.fromJson(
      jsonDecode(
        await File('assets/maps/gran_tiete_floorplan_v12.json').readAsString(),
      ) as Map<String, dynamic>,
    );
  });

  Future<void> show(
    WidgetTester tester, {
    int floor = 1,
    List<NavigationNode> route = const [],
    String? selected,
    ValueChanged<CampusPoi>? onSelect,
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: GranMapTheme.dark,
        home: Scaffold(
          body: CampusTwinCanvas(
            campus: campus,
            focusFloor: floor,
            route: route,
            selectedPoiId: selected,
            onPoiSelected: onSelect,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  dynamic projection(WidgetTester tester) =>
      (tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('campus-twin-drawing')),
                  )
                  .painter
              as dynamic)
          .projection;

  dynamic painter(WidgetTester tester) => tester
      .widget<CustomPaint>(find.byKey(const ValueKey('campus-twin-drawing')))
      .painter;

  void expectNoLabelCollision(WidgetTester tester) {
    final labels = List<Rect>.from(painter(tester).labelBounds as List);
    for (var first = 0; first < labels.length; first++) {
      for (var second = first + 1; second < labels.length; second++) {
        expect(
          labels[first].overlaps(labels[second]),
          isFalse,
          reason: 'Labels $first and $second must not overlap',
        );
      }
    }
  }

  void expectFitted(WidgetTester tester) {
    final dynamic geometry = projection(tester);
    final rect = tester.getRect(
      find.byKey(const ValueKey('campus-twin-drawing')),
    );
    for (final zone in campus.zones.where(
      (zone) => geometry.includesFloor(zone.floor) as bool,
    )) {
      for (final x in [zone.x, zone.x + zone.width]) {
        for (final y in [zone.y, zone.y + zone.height]) {
          final point = geometry.project(x, y, zone.floor) as Offset;
          expect(point.dx, inInclusiveRange(23.9, rect.width - 23.9));
          expect(point.dy, inInclusiveRange(73.9, rect.height - 21.9));
        }
      }
    }
  }

  testWidgets(
    'maquete mostra apenas o piso em foco e controles cabem no celular',
    (tester) async {
      await show(tester);
      expect(projection(tester).floors, [1]);
      expect(find.text('Separação'), findsNothing);
      for (final tooltip in [
        'Girar para a esquerda',
        'Diminuir maquete',
        'Restaurar visualização 3D',
        'Ampliar maquete',
        'Girar para a direita',
      ]) {
        final rect = tester.getRect(find.byTooltip(tooltip));
        expect(rect.bottom, lessThanOrEqualTo(800));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
      }
      expectFitted(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('enquadramento mantém a planta inteira após girar uma volta', (
    tester,
  ) async {
    await show(tester);
    for (var step = 0; step < 30; step++) {
      await tester.tap(find.byTooltip('Girar para a direita'));
      await tester.pump();
      expectFitted(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'orientação Y-up coincide com a planta 2D sem espelhar os corredores',
    (tester) async {
      await show(tester, floor: 0);
      // Four explicit turns cancel the portrait -.88 rad view angle.
      for (var turn = 0; turn < 4; turn++) {
        await tester.tap(find.byTooltip('Girar para a direita'));
        await tester.pump();
      }
      final dynamic geometry = projection(tester);
      expect(geometry.rotation as double, closeTo(0, .000001));
      final gran = campus.poiById('entrada_gran')!;
      final tyto = campus.poiById('entrada_tyto_gran')!;
      final granPoint =
          geometry.project(gran.displayX, gran.displayY, 0) as Offset;
      final tytoPoint =
          geometry.project(tyto.displayX, tyto.displayY, 0) as Offset;
      expect(granPoint.dy, lessThan(tytoPoint.dy));
      final north = geometry.project(50.0, 74.0, 0) as Offset;
      final south = geometry.project(50.0, 28.0, 0) as Offset;
      expect(north.dy, lessThan(south.dy));
      expect(north.dx, closeTo(south.dx, .000001));
      expectFitted(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dois pisos são opcionais, separados e ainda enquadrados', (
    tester,
  ) async {
    await show(tester, floor: 0);
    await tester.tap(find.text('Ver dois pisos'));
    await tester.pumpAndSettle();
    expect(projection(tester).floors, [0, 1]);
    expect(find.text('Separação'), findsOneWidget);
    expectFitted(tester);
    await tester.tap(find.text('Só este piso'));
    await tester.pumpAndSettle();
    expect(projection(tester).floors, [0]);
    expectFitted(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toque seleciona local e mantém destino acessível na maquete', (
    tester,
  ) async {
    final poi = campus.poiById('auditorio')!;
    CampusPoi? selection;
    await show(
      tester,
      selected: poi.id,
      route: [campus.nodeById(poi.navigationNode)!],
      onSelect: (value) => selection = value,
    );
    final rect = tester.getRect(
      find.byKey(const ValueKey('campus-twin-drawing')),
    );
    final point = projection(
      tester,
    ).project(poi.displayX, poi.displayY, poi.floor) as Offset;
    await tester.tapAt(rect.topLeft + point - const Offset(0, 13));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(selection?.id, poi.id);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.value == poi.name,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ampliar e restaurar retorna ao enquadramento inicial', (
    tester,
  ) async {
    await show(tester);
    final initial = projection(tester).project(0.0, 0.0, 1) as Offset;
    await tester.tap(find.byTooltip('Ampliar maquete'));
    await tester.pump();
    expect(projection(tester).project(0.0, 0.0, 1), isNot(initial));
    await tester.tap(find.byTooltip('Restaurar visualização 3D'));
    await tester.pump();
    expect(projection(tester).project(0.0, 0.0, 1), initial);
    expectFitted(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview mobile tem rótulos poucos, completos e sem colisões', (
    tester,
  ) async {
    final destination = campus.poiById('auditorio')!;
    await show(
      tester,
      selected: 'rampa_caracol',
      route: [campus.nodeById(destination.navigationNode)!],
      size: const Size(390, 844),
    );
    expect(projection(tester).rotation as double, -.88);
    final labels = List<Rect>.from(painter(tester).labelBounds as List);
    expect(labels.length, inInclusiveRange(2, 8));
    expectNoLabelCollision(tester);
    for (var turn = 0; turn < 12; turn++) {
      await tester.tap(find.byTooltip('Girar para a direita'));
      await tester.pump();
      expectNoLabelCollision(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'zoom revela nomes sem colisão e centraliza o local selecionado',
    (tester) async {
      final selected = campus.poiById('auditorio')!;
      await show(tester, selected: selected.id);
      for (var zoom = 0; zoom < 3; zoom++) {
        await tester.tap(find.byTooltip('Ampliar maquete'));
        await tester.pump();
      }
      expectNoLabelCollision(tester);
      final rect = tester.getRect(
        find.byKey(const ValueKey('campus-twin-drawing')),
      );
      final point = projection(
        tester,
      ).project(selected.displayX, selected.displayY, selected.floor) as Offset;
      expect(point.dx, closeTo(rect.width / 2, .001));
      expect(point.dy, closeTo(rect.height / 2 + 26, .001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop mantém ângulo mais aberto e textos sem sobreposição', (
    tester,
  ) async {
    await show(tester, size: const Size(900, 600));
    expect(projection(tester).rotation as double, -.44);
    expectNoLabelCollision(tester);
    expectFitted(tester);
    expect(tester.takeException(), isNull);
  });
}
