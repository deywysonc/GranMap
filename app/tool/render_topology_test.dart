import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:granmap/widgets/campus_map_canvas.dart';

Future<CampusMap> _loadMap() async {
  final raw = await File('assets/maps/gran_tiete_user_corrected_v10.json')
      .readAsString();
  return CampusMap.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

Widget _frame(CampusMap campus, int floor) {
  return MaterialApp(
    theme: GranMapTheme.dark,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 1440,
          height: 900,
          child: RepaintBoundary(
            key: const ValueKey('topology-map'),
            child: CampusMapCanvas(campus: campus, floor: floor),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renderiza o térreo topológico', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final campus = (await tester.runAsync(_loadMap))!;
    await tester.pumpWidget(_frame(campus, 0));
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('topology-map')),
      matchesGoldenFile('goldens/mapa_corrigido_terreo_v10.png'),
    );
  }, timeout: const Timeout(Duration(seconds: 8)));

  testWidgets('renderiza o piso superior topológico', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final campus = (await tester.runAsync(_loadMap))!;
    await tester.pumpWidget(_frame(campus, 1));
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('topology-map')),
      matchesGoldenFile('goldens/mapa_corrigido_superior_v10.png'),
    );
  }, timeout: const Timeout(Duration(seconds: 8)));
}
