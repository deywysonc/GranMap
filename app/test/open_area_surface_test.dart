import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/widgets/campus_map_canvas.dart';
import 'package:granmap/widgets/map_scene_geometry.dart';

const _viewport = Size(800, 480);
const _padding = EdgeInsets.fromLTRB(38, 28, 38, 64);
const _canvasKey = ValueKey('granmap-floor-canvas');

void main() {
  for (final size in [const Size(20, 12), const Size(12, 40)]) {
    testWidgets(
      'áreas abertas $size têm chão contínuo sem eixo ou parede na emenda',
      (tester) async {
        final campus = _campus(areaSize: size);
        await _mount(tester, campus);
        final paint = tester.widget<CustomPaint>(find.byKey(_canvasKey));
        final geometry = _geometry(campus);
        final raster = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          paint.painter!.paint(Canvas(recorder), _viewport);
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            _viewport.width.toInt(),
            _viewport.height.toInt(),
          );
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return _Raster(
              image.width,
              Uint8List.fromList(
                bytes!.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              ),
            );
          } finally {
            image.dispose();
            picture.dispose();
          }
        });
        expect(raster, isNotNull);
        final reference = raster!.at(
          geometry.project(size.width * .2, size.height * .2),
        );
        expect(
          reference & 0xff,
          255,
          reason: 'O piso precisa estar preenchido.',
        );

        for (final zone in campus.zones) {
          final rect = geometry.zoneRect(zone);
          // Stay near an end of the old corridor axis, away from the area
          // label at its centre. Scan several dash/gap periods and the
          // neighbouring pixels so antialiasing cannot hide a centre line.
          final axisPatch = rect.width > rect.height
              ? Rect.fromLTWH(rect.left + 8, rect.center.dy - 2, 28, 5)
              : Rect.fromLTWH(rect.center.dx - 2, rect.top + 8, 5, 28);
          _expectFloor(raster, axisPatch, reference, 'eixo de ${zone.id}');
        }

        final seam = geometry.project(size.width, size.height * .25);
        _expectFloor(
          raster,
          Rect.fromCenter(center: seam, width: 5, height: 24),
          reference,
          'emenda entre duas partes do mesmo piso aberto',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'área ampla vazia não captura POI e sala vizinha mantém alvo interior',
    () {
      final campus = _campus(withRoom: true);
      final geometry = _geometry(campus);
      for (final x in [1.0, 7.0, 15.0, 20.0, 25.0, 33.0, 39.0]) {
        for (final y in [1.0, 4.0, 8.0, 11.0]) {
          expect(
            geometry.hitTestPoi(geometry.project(x, y)),
            isNull,
            reason: 'Chão vazio ($x, $y) não representa a sala vizinha.',
          );
        }
      }
      expect(
        geometry.hitTestPoi(geometry.project(44, 1))?.id,
        'neighbor-room',
        reason: 'O interior da sala continua clicável longe do marcador.',
      );
    },
  );

  testWidgets('toques no piso aberto não selecionam a sala real vizinha', (
    tester,
  ) async {
    final campus = _campus(withRoom: true);
    final geometry = _geometry(campus);
    final selections = <String>[];
    await _mount(tester, campus, onSelected: (poi) => selections.add(poi.id));
    final origin = tester.getTopLeft(find.byKey(_canvasKey));
    for (final point in [
      const Offset(5, 3),
      const Offset(20, 6),
      const Offset(35, 9),
    ]) {
      await tester.tapAt(origin + geometry.project(point.dx, point.dy));
      await tester.pump();
    }
    expect(selections, isEmpty);
    await tester.tapAt(origin + geometry.project(44, 1));
    await tester.pump();
    expect(selections, ['neighbor-room']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _mount(
  WidgetTester tester,
  CampusMap campus, {
  ValueChanged<CampusPoi>? onSelected,
}) async {
  await tester.binding.setSurfaceSize(_viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CampusMapCanvas(
          campus: campus,
          floor: 0,
          fullBleed: true,
          onPoiSelected: onSelected,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.getSize(find.byKey(_canvasKey)), _viewport);
}

MapSceneGeometry _geometry(CampusMap campus) => MapSceneGeometry(
  campus: campus,
  floor: 0,
  viewport: _viewport,
  padding: _padding,
);

void _expectFloor(_Raster raster, Rect patch, int floor, String reason) {
  for (var y = patch.top.ceil(); y < patch.bottom.floor(); y++) {
    for (var x = patch.left.ceil(); x < patch.right.floor(); x++) {
      expect(
        raster.at(Offset(x.toDouble(), y.toDouble())),
        floor,
        reason: '$reason: pixel ($x, $y) deve ter a mesma cor do chão livre.',
      );
    }
  }
}

class _Raster {
  const _Raster(this.width, this.bytes);
  final int width;
  final Uint8List bytes;

  int at(Offset position) {
    final offset = (position.dy.floor() * width + position.dx.floor()) * 4;
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}

CampusMap _campus({
  Size areaSize = const Size(20, 12),
  bool withRoom = false,
}) => CampusMap(
  building: const BuildingInfo(id: 'test', name: 'GranMap', version: 'test'),
  floors: const [
    CampusFloor(id: 'ground', name: 'Térreo', level: 0, elevation: 0),
  ],
  zones: [
    for (var index = 0; index < 2; index++)
      CampusZone(
        id: 'open-$index',
        name: 'Área aberta',
        type: 'open_area',
        floor: 0,
        x: index * areaSize.width,
        y: 0,
        width: areaSize.width,
        height: areaSize.height,
      ),
    if (withRoom)
      const CampusZone(
        id: 'neighbor-zone',
        name: 'Sala vizinha',
        type: 'classroom',
        floor: 0,
        x: 43,
        y: 0,
        width: 10,
        height: 12,
      ),
  ],
  pois: [
    if (withRoom)
      const CampusPoi(
        id: 'neighbor-room',
        name: 'Sala vizinha',
        type: 'classroom',
        floor: 0,
        x: 48,
        y: 6,
        z: 0,
        navigationNode: 'room-node',
      ),
  ],
  nodes: [
    if (withRoom)
      const NavigationNode(
        id: 'room-node',
        floor: 0,
        x: 48,
        y: 6,
        z: 0,
        type: 'classroom',
      ),
  ],
  edges: const [],
);
