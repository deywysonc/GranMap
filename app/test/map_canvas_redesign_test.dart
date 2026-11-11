import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/navigation/navigation_service.dart';
import 'package:granmap/positioning/position_sample.dart';
import 'package:granmap/widgets/campus_map_canvas.dart';
import 'package:granmap/widgets/map_scene_geometry.dart';

void main() {
  final campus = _campus();
  late CampusMap actualMap;
  setUpAll(() async {
    actualMap = CampusMap.fromJson(
      jsonDecode(
        await File('assets/maps/gran_tiete_floorplan_v12.json').readAsString(),
      ) as Map<String, dynamic>,
    );
    const fonts = String.fromEnvironment('GRANMAP_QA_FONT_DIR');
    if (fonts.isNotEmpty) {
      for (final font in {
        'GranMapQA': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final bytes = await File('$fonts/${font.value}').readAsBytes();
        await (FontLoader(
          font.key,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });

  test('projection preserves architectural aspect and is reversible', () {
    for (final size in [const Size(360, 800), const Size(1536, 900)]) {
      final geometry = MapSceneGeometry(
        campus: campus,
        floor: 0,
        viewport: size,
      );
      final origin = geometry.project(0, 0);
      final x = geometry.project(10, 0);
      final y = geometry.project(0, 10);
      expect((x - origin).distance, closeTo((y - origin).distance, .00001));
      expect(x.dx, greaterThan(origin.dx));
      expect(y.dy, lessThan(origin.dy));
      final raw = geometry.unproject(geometry.project(13.25, 4.5));
      expect(raw.dx, closeTo(13.25, .00001));
      expect(raw.dy, closeTo(4.5, .00001));
    }
  });

  test('hit testing uses room interior and rejects POIs on other floors', () {
    final geometry = MapSceneGeometry(
      campus: campus,
      floor: 0,
      viewport: const Size(360, 800),
    );
    expect(geometry.hitTestPoi(geometry.project(12, 7))?.id, 'room');
    expect(geometry.hitTestPoi(geometry.project(22, 7)), isNull);
  });

  test(
    'route remains contiguous without bridging an excursion to another floor',
    () {
      final segments = MapSceneGeometry.routeSegments([
        _node('a', 0, 0, 0),
        _node('b', 0, 10, 0),
        _node('upper', 1, 12, 5),
        _node('c', 0, 20, 0),
        _node('d', 0, 30, 0),
      ], 0);
      expect(segments.map((s) => s.map((n) => n.id).toList()).toList(), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    },
  );

  test('physical position is interpolated into display coordinates', () {
    final geometry = MapSceneGeometry(
      campus: campus,
      floor: 0,
      viewport: const Size(360, 800),
    );
    final display = geometry.displayPosition(
      PositionSample(
        x: 5,
        y: 0,
        z: 0,
        floor: 0,
        headingDegrees: 0,
        accuracyMeters: 3,
        confidence: .6,
        timestamp: DateTime(2026),
      ),
    );
    expect(display.dx, closeTo(10, .00001));
    expect(display.dy, closeTo(0, .00001));
  });

  for (final size in [const Size(360, 800), const Size(1536, 900)]) {
    testWidgets('floor plan controls and selection work at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      CampusPoi? selected;
      final mapKey = GlobalKey<CampusMapCanvasState>();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CampusMapCanvas(
                key: mapKey,
                campus: campus,
                floor: 0,
                fullBleed: true,
                onPoiSelected: (poi) => selected = poi,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final interactive = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final controller = interactive.transformationController!;
        final canvas = find.byKey(const ValueKey('granmap-floor-canvas'));
        final viewport = tester.getSize(canvas);
        final geometry = MapSceneGeometry(
          campus: campus,
          floor: 0,
          viewport: viewport,
          padding: EdgeInsets.fromLTRB(
            size.width < 500 ? 20 : 38,
            28,
            size.width < 500 ? 20 : 38,
            64,
          ),
        );
        final room = geometry.project(14, 8);
        await tester.tapAt(tester.getTopLeft(canvas) + room);
        await tester.pump();
        expect(selected?.id, 'room');
        expect(
          find.text('Sala exemplo'),
          findsNothing,
          reason: 'The screen callback owns its destination card',
        );
        await tester.tap(find.byTooltip('Ampliar mapa'));
        await tester.pumpAndSettle();
        expect(controller.value.getMaxScaleOnAxis(), closeTo(1.35, .0001));
        controller.value = Matrix4.identity()
          ..translateByDouble(22, -18, 0, 1)
          ..scaleByDouble(1.5, 1.5, 1, 1);
        await tester.pump();
        selected = null;
        final transformed = MatrixUtils.transformPoint(controller.value, room);
        await tester.tapAt(
          tester.getTopLeft(find.byType(InteractiveViewer)) + transformed,
        );
        await tester.pump();
        expect(selected?.id, 'room');
        await tester.tap(find.byTooltip('Enquadrar planta'));
        await tester.pumpAndSettle();
        expect(controller.value, Matrix4.identity());
        mapKey.currentState!.zoomBy(2);
        await tester.pump();
        expect(controller.value.getMaxScaleOnAxis(), closeTo(2, .0001));
        mapKey.currentState!.resetView();
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      }
    });
  }

  testWidgets('actual v12 floors render with routes without exceptions', (
    tester,
  ) async {
    final map = actualMap;
    const directory = String.fromEnvironment('GRANMAP_QA_DIR');
    final boundaryKey = GlobalKey();
    for (final floor in map.floors) {
      final route = const NavigationService().calculateRoute(
        campus: map,
        origin: map.poiById('entrada_gran')!,
        destination: map.poiById(floor.level == 0 ? 'biblioteca' : 'van_gogh')!,
      )!;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'GranMapQA',
              ),
            ),
            home: Scaffold(
              body: CampusMapCanvas(
                key: ValueKey(floor.level),
                campus: map,
                floor: floor.level,
                fullBleed: true,
                route: route.nodes,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ampliar mapa'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (directory.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: 2);
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/floor-${floor.level}-2d.png')
              .writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

NavigationNode _node(String id, int floor, double x, double y) =>
    NavigationNode(
      id: id,
      floor: floor,
      x: x,
      y: y,
      z: floor * 4,
      type: 'corridor',
      displayX: x * 2,
      displayY: y,
    );

CampusMap _campus() => CampusMap(
  building: const BuildingInfo(id: 'test', name: 'Gran Tietê', version: '12'),
  floors: const [
    CampusFloor(id: 'ground', name: 'Térreo', level: 0, elevation: 0),
    CampusFloor(id: 'upper', name: 'Superior', level: 1, elevation: 4),
  ],
  zones: const [
    CampusZone(
      id: 'room',
      name: 'Sala exemplo',
      type: 'classroom',
      floor: 0,
      x: 10,
      y: 4,
      width: 8,
      height: 8,
    ),
    CampusZone(
      id: 'corridor',
      name: 'Corredor',
      type: 'corridor_gran',
      floor: 0,
      x: 0,
      y: -2,
      width: 28,
      height: 4,
    ),
  ],
  pois: const [
    CampusPoi(
      id: 'room',
      name: 'Sala exemplo',
      type: 'classroom',
      floor: 0,
      x: 7,
      y: 8,
      z: 0,
      displayX: 14,
      displayY: 8,
      navigationNode: 'b',
    ),
    CampusPoi(
      id: 'upper',
      name: 'Outra sala',
      type: 'classroom',
      floor: 1,
      x: 11,
      y: 7,
      z: 4,
      displayX: 22,
      displayY: 7,
      navigationNode: 'upper',
    ),
  ],
  nodes: [_node('a', 0, 0, 0), _node('b', 0, 10, 0), _node('upper', 1, 11, 7)],
  edges: const [
    NavigationEdge(
      from: 'a',
      to: 'b',
      distance: 10,
      type: 'corridor',
      accessible: true,
    ),
  ],
);
