import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/screens/home_screen.dart';
import 'package:granmap/screens/map_screen.dart';
import 'package:granmap/screens/route_screen.dart';
import 'package:granmap/screens/search_screen.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:granmap/widgets/granmap_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  testWidgets('GranMapSurface preserva tinta e interação de ListTile', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: GranMapTheme.dark,
        home: Scaffold(
          body: GranMapSurface(
            child: ListTile(
              title: const Text('Minha grade'),
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Minha grade'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mapa 3D ocupa a área e modos Walk e AR respondem ao toque', (
    tester,
  ) async {
    var requestedView = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: GranMapTheme.dark,
        home: Scaffold(
          body: MapScreen(
            campus: _campus(),
            onRouteModeRequested: (view) => requestedView = view,
          ),
        ),
      ),
    );

    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Arraste para girar'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Walk'));
    await tester.pump();
    expect(requestedView, 2);

    await tester.tap(find.text('AR'));
    await tester.pump();
    expect(requestedView, 3);
  });

  testWidgets('card de destino abre a rota sem esperar o histórico', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final observer = _RecordingNavigatorObserver();
      await tester.pumpWidget(
        MaterialApp(
          theme: GranMapTheme.dark,
          navigatorObservers: [observer],
          home: Scaffold(body: SearchScreen(campus: _campus())),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Entrada Gran'));
      await tester.pump(const Duration(seconds: 1));

      expect(observer.pushes, hasLength(2));
      expect(find.byType(RouteScreen, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('visitante não vê carregamento acadêmico infinito', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: GranMapTheme.dark,
          home: Scaffold(body: HomeScreen(campus: _campus())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Entre para ver sua próxima aula'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes.add(route);
    super.didPush(route, previousRoute);
  }
}

CampusMap _campus() => const CampusMap(
  building: BuildingInfo(id: 'gran', name: 'Gran Tietê', version: 'test'),
  floors: [
    CampusFloor(id: 'f0', name: 'Térreo', level: 0, elevation: 0),
    CampusFloor(id: 'f1', name: 'Superior', level: 1, elevation: 3),
  ],
  zones: [
    CampusZone(
      id: 'z0',
      name: 'Corredor térreo',
      type: 'corridor_gran',
      floor: 0,
      x: 0,
      y: 0,
      width: 20,
      height: 5,
      verification: 'observed_video',
    ),
    CampusZone(
      id: 'z1',
      name: 'Corredor superior',
      type: 'upper_walkway',
      floor: 1,
      x: 2,
      y: 2,
      width: 16,
      height: 4,
      verification: 'user_confirmed',
    ),
  ],
  pois: [
    CampusPoi(
      id: 'entrada_gran',
      name: 'Entrada Gran',
      type: 'entrance',
      floor: 0,
      x: 0,
      y: 2,
      z: 0,
      navigationNode: 'n0',
    ),
  ],
  nodes: [
    NavigationNode(id: 'n0', floor: 0, x: 0, y: 2, z: 0, type: 'entrance'),
  ],
  edges: [],
);
