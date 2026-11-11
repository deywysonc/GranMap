import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/models/personal_data.dart';
import 'package:granmap/positioning/sensor_service.dart';
import 'package:granmap/positioning/sensor_snapshot.dart';
import 'package:granmap/screens/advanced_route_screen.dart';
import 'package:granmap/screens/route_screen.dart';
import 'package:granmap/services/local_store.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:granmap/widgets/campus_map_canvas.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SharedPreferencesAsyncPlatform.instance = null;
  });

  testWidgets('rota carrega favorito local e persiste cada mudança', (
    tester,
  ) async {
    final store = LocalStore();
    await store.saveFavoriteState('guest', const FavoriteState(ids: ['sala']));
    await _showRoute(tester);
    expect(find.byTooltip('Remover dos favoritos'), findsOneWidget);
    await tester.tap(find.byTooltip('Remover dos favoritos'));
    await tester.pumpAndSettle();
    expect((await store.readFavoriteState('guest')).ids, isEmpty);
    expect(find.byTooltip('Favoritar'), findsOneWidget);
    await tester.tap(find.byTooltip('Favoritar'));
    await tester.pumpAndSettle();
    expect((await store.readFavoriteState('guest')).ids, ['sala']);
    expect(
      find.text('Favorito marcado; a sincronização será tentada depois.'),
      findsNothing,
    );
    await _close(tester);
  });

  testWidgets(
    'controles 3D e AR ficam acima do painel sem modo Walk em 360x800',
    (tester) async {
      const cameraChannel = MethodChannel('plugins.flutter.io/camera');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        cameraChannel,
        (call) async => call.method == 'availableCameras' ? [] : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          cameraChannel,
          null,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _showRoute(tester, initialView: 1);
      final viewport = tester.getRect(
        find.byKey(const ValueKey('route-visual-viewport')),
      );
      final sheet = tester.getRect(
        find.byKey(const ValueKey('route-details-sheet')),
      );
      expect(viewport.height, greaterThan(180));
      expect(viewport.bottom, lessThanOrEqualTo(sheet.top));
      final reset = find.byTooltip('Restaurar visualização 3D');
      expect(viewport.contains(tester.getCenter(reset)), isTrue);
      final enlarge = find.byTooltip('Ampliar maquete');
      expect(viewport.contains(tester.getCenter(enlarge)), isTrue);
      await tester.tap(reset);
      await tester.tap(enlarge);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Ver dois pisos'));
      await tester.pumpAndSettle();
      expect(viewport.contains(tester.getCenter(find.byType(Slider))), isTrue);
      await tester.tap(find.byType(Slider));
      await tester.pump();

      expect(find.text('Walk'), findsNothing);

      await tester.tap(find.text('AR'));
      await tester.pump();
      final camera = find.text('Câmera real');
      expect(viewport.contains(tester.getCenter(camera)), isTrue);
      await tester.tap(camera);
      await tester.pumpAndSettle();
      expect(find.textContaining('não pôde ser iniciada'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    },
  );

  testWidgets('rota com modo legado 2 abre mapa 2D em vez de Street View', (
    tester,
  ) async {
    await _showRoute(tester, initialView: 2);
    expect(find.byType(CampusMapCanvas), findsOneWidget);
    expect(find.text('Walk'), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets(
    'passos opt-in não avançam com tempo, retomam e pausam no background',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sensors = _FakeSensors();
      await _showRoute(tester, sensors: sensors);
      expect(find.text('Iniciar navegação interna'), findsNothing);
      await tester.tap(find.text('Acompanhar passos'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Se trocar de piso, confirme sua localização'),
        findsOneWidget,
      );
      await tester.tap(find.text('Estou nesse ponto — acompanhar passos'));
      await tester.pumpAndSettle();
      expect(sensors.starts, 1);
      expect(_positionX(tester), 0);
      await tester.pump(const Duration(seconds: 4));
      expect(_positionX(tester), 0);
      sensors.emit(101);
      await tester.pumpAndSettle();
      expect(_positionX(tester), closeTo(.72, .01));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Pausar sensores'),
            )
            .onPressed,
        isNotNull,
        reason: 'início dos sensores deve liberar controles',
      );
      await tester.tap(find.text('Pausar sensores'));
      await _flushCancellation(tester);
      await tester.pumpAndSettle();
      await tester.pump();
      expect(sensors.stops, 1, reason: 'pausar deve liberar a fonte física');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Retomar sensores'),
            )
            .onPressed,
        isNotNull,
      );
      sensors.emit(120);
      await tester.tap(find.text('Retomar sensores'));
      await tester.pumpAndSettle();
      expect(sensors.starts, 2);
      expect(_positionX(tester), closeTo(.72, .01));
      sensors.emit(121);
      await tester.pumpAndSettle();
      expect(_positionX(tester), closeTo(1.44, .01));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _flushCancellation(tester);
      await tester.pump();
      sensors.emit(140);
      await tester.pump();
      expect(_positionX(tester), closeTo(1.44, .01));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(sensors.starts, 3);
      expect(_positionX(tester), closeTo(1.44, .01));
      sensors.emit(141);
      await tester.pumpAndSettle();
      expect(_positionX(tester), closeTo(2.16, .01));

      await tester.ensureVisible(find.text('Usar prévia animada'));
      await tester.tap(find.text('Usar prévia animada'));
      await _flushCancellation(tester);
      await tester.pump();
      expect(find.text('Prévia animada • movimento simulado'), findsOneWidget);
      expect(sensors.stops, 3);
      await _close(tester);
      await sensors.close();
    },
  );

  testWidgets(
    'modo técnico recria stream ao ativar, desativar e ativar sensores',
    (tester) async {
      final sensors = _FakeSensors();
      final campus = _campus();
      await tester.pumpWidget(
        MaterialApp(
          theme: GranMapTheme.dark,
          home: AdvancedRouteScreen(
            campus: campus,
            origin: campus.pois.first,
            destination: campus.pois.last,
            sensors: sensors,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sensors.starts, 0);
      await tester.ensureVisible(find.text('Usar sensores reais'));
      await tester.tap(find.text('Usar sensores reais'));
      await tester.pumpAndSettle();
      sensors.emit(101);
      await tester.pumpAndSettle();
      expect(_positionX(tester), closeTo(.72, .01));
      await tester.pump(const Duration(seconds: 3));
      expect(_positionX(tester), closeTo(.72, .01));
      await tester.ensureVisible(
        find.byKey(const ValueKey('advanced-sensor-toggle')),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('advanced-sensor-toggle')),
            )
            .onPressed,
        isNotNull,
        reason: 'ativação deve concluir',
      );
      await tester.tap(find.byKey(const ValueKey('advanced-sensor-toggle')));
      await _flushCancellation(tester);
      await tester.pumpAndSettle();
      await tester.pump();
      expect(sensors.stops, 1, reason: 'desativar deve liberar a fonte física');
      sensors.emit(200);
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('advanced-sensor-toggle'))),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar sensores reais'));
      await tester.pumpAndSettle();
      expect(_positionX(tester), 0);
      sensors.emit(201);
      await tester.pumpAndSettle();
      expect(_positionX(tester), closeTo(.72, .01));
      expect(sensors.starts, 2);
      expect(tester.takeException(), isNull);
      await _close(tester);
      await sensors.close();
    },
  );
}

Future<void> _showRoute(
  WidgetTester tester, {
  int initialView = 0,
  SensorService? sensors,
}) async {
  final campus = _campus();
  await tester.pumpWidget(
    MaterialApp(
      theme: GranMapTheme.dark,
      home: RouteScreen(
        campus: campus,
        origin: campus.pois.first,
        destination: campus.pois.last,
        initialView: initialView,
        sensors: sensors,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _positionX(WidgetTester tester) => tester
    .widget<CampusMapCanvas>(find.byType(CampusMapCanvas))
    .userPosition!
    .x;

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flushCancellation(tester);
  await tester.pump(const Duration(seconds: 3));
  debugDefaultTargetPlatformOverride = null;
}

Future<void> _flushCancellation(WidgetTester tester) async {
  // Stream cancellation can complete in the root zone rather than the test's
  // fake clock. Allow that completion before issuing the next sensor command.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}

class _FakeSensors implements SensorService {
  final controller = StreamController<SensorSnapshot>.broadcast(sync: true);
  int steps = 100;
  int starts = 0;
  int stops = 0;
  @override
  Stream<SensorSnapshot> get snapshots => controller.stream;
  void emit(int value) {
    steps = value;
    controller.add(
      SensorSnapshot(
        accelerationX: 0,
        accelerationY: 0,
        accelerationZ: 0,
        gyroscopeZ: 0,
        magneticField: 0,
        headingDegrees: 0,
        stepCount: value,
        confidence: .6,
        source: 'test',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> start() async {
    starts++;
    emit(steps);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> reset() async {
    steps = 0;
  }

  Future<void> close() => controller.close();
}

CampusMap _campus() => const CampusMap(
  building: BuildingInfo(id: 'gran', name: 'Gran Tietê', version: 'test'),
  floors: [CampusFloor(id: 'f0', name: 'Térreo', level: 0, elevation: 0)],
  zones: [
    CampusZone(
      id: 'z0',
      name: 'Corredor',
      type: 'corridor',
      floor: 0,
      x: 0,
      y: 0,
      width: 100,
      height: 5,
    ),
  ],
  pois: [
    CampusPoi(
      id: 'entrada',
      name: 'Entrada Gran',
      type: 'entrance',
      floor: 0,
      x: 0,
      y: 0,
      z: 0,
      navigationNode: 'ground_c1_start',
    ),
    CampusPoi(
      id: 'sala',
      name: 'Sala 10',
      type: 'room',
      floor: 0,
      x: 100,
      y: 0,
      z: 0,
      navigationNode: 'end',
    ),
  ],
  nodes: [
    NavigationNode(
      id: 'ground_c1_start',
      floor: 0,
      x: 0,
      y: 0,
      z: 0,
      type: 'corridor',
    ),
    NavigationNode(id: 'end', floor: 0, x: 100, y: 0, z: 0, type: 'corridor'),
  ],
  edges: [
    NavigationEdge(
      from: 'ground_c1_start',
      to: 'end',
      distance: 100,
      type: 'corridor',
      accessible: true,
    ),
  ],
);
