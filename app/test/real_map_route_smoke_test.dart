import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/screens/route_screen.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late CampusMap campus;
  setUpAll(() async {
    final raw = await File('assets/maps/gran_tiete_floorplan_v12.json')
        .readAsString();
    campus = CampusMap.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    const fonts = String.fromEnvironment('GRANMAP_QA_FONT_DIR');
    if (fonts.isNotEmpty) {
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final bytes = await File('$fonts/${font.value}').readAsBytes();
        await (FontLoader(
          font.key,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    }
  });
  testWidgets(
    'mapa completo abre rota entre pisos e modos em tela de celular',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await tester.binding.setSurfaceSize(const Size(360, 800));
      final origin = campus.poiById('entrada_gran')!;
      final destination = campus.pois.firstWhere((p) => p.floor == 1);
      final boundaryKey = GlobalKey();
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: GranMapTheme.dark,
              home: RouteScreen(
                campus: campus,
                origin: origin,
                destination: destination,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('route-visual-viewport')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, boundaryKey, 'route-2d.png');
        await tester.tap(find.text('3D'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Restaurar visualização 3D'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, boundaryKey, 'route-3d.png');
        expect(find.text('Walk'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
        SharedPreferencesAsyncPlatform.instance = null;
      }
    },
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  const directory = String.fromEnvironment('GRANMAP_QA_DIR');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 2);
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name').writeAsBytes(data!.buffer.asUint8List());
    picture.dispose();
  });
}
