import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/positioning/sensor_service.dart';
import 'package:granmap/positioning/sensor_snapshot.dart';
import 'package:granmap/screens/advanced_route_screen.dart';
import 'package:granmap/screens/route_screen.dart';
import 'package:granmap/services/app_preferences.dart';
import 'package:granmap/services/granmap_api.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:granmap/widgets/campus_map_canvas.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await AppPreferences.instance.setAccessibleRoutes(false);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SharedPreferencesAsyncPlatform.instance = null;
  });

  testWidgets(
    'QR reancora o piso na própria rota simples e nos próximos passos',
    (tester) async {
      final sensors = _FakeSensors();
      final api = _AnchorApi();
      var scans = 0;
      await _showRoute(
        tester,
        sensors: sensors,
        api: api,
        scanAnchor: (_) async {
          scans++;
          return 'upper-qr';
        },
      );
      await _startPhysical(tester);
      expect(_map(tester).floor, 0);
      expect(_map(tester).userPosition!.x, 0);

      await tester.tap(find.byTooltip('Ferramentas de navegação'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ler placa QR'));
      await tester.pumpAndSettle();

      expect(scans, 1);
      expect(api.anchorRequests, 1);
      expect(find.byType(RouteScreen), findsOneWidget);
      expect(find.byType(AdvancedRouteScreen), findsNothing);
      expect(_map(tester).floor, 1);
      expect(_map(tester).userPosition!.floor, 1);
      expect(_map(tester).userPosition!.x, 10);
      expect(_map(tester).userPosition!.z, 3);
      sensors.emit(sensors.steps + 1);
      await tester.pumpAndSettle();
      expect(_map(tester).floor, 1);
      expect(_map(tester).userPosition!.x, closeTo(10.72, .01));
      expect(_map(tester).userPosition!.z, 3);
      expect(tester.takeException(), isNull);
      await _close(tester);
      await sensors.close();
      api.dispose();
    },
  );

  testWidgets('recalcular e acessibilidade preservam sensores pausados', (
    tester,
  ) async {
    final sensors = _FakeSensors();
    await _showRoute(tester, sensors: sensors);
    await _startPhysical(tester);
    sensors.emit(101);
    await tester.pumpAndSettle();
    expect(_map(tester).userPosition!.x, closeTo(.72, .01));
    await tester.tap(find.text('Pausar sensores'));
    await _flushCancellation(tester);
    await tester.pumpAndSettle();
    expect(sensors.starts, 1);
    expect(sensors.stops, 1);

    sensors.emit(120);
    await tester.ensureVisible(find.text('Recalcular'));
    await tester.tap(find.text('Recalcular'));
    await tester.pumpAndSettle();
    expect(find.text('Retomar sensores'), findsOneWidget);
    expect(sensors.starts, 1);
    expect(_map(tester).userPosition!.x, closeTo(.72, .01));
    await tester.pump(const Duration(seconds: 3));
    expect(_map(tester).userPosition!.x, closeTo(.72, .01));

    await tester.tap(find.byTooltip('Ferramentas de navegação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priorizar rota acessível'));
    await tester.pumpAndSettle();
    expect(AppPreferences.instance.accessibleRoutes, isTrue);
    expect(find.text('Retomar sensores'), findsOneWidget);
    expect(sensors.starts, 1);
    expect(_map(tester).userPosition!.x, closeTo(.72, .01));

    sensors.emit(130);
    await tester.ensureVisible(find.text('Retomar sensores'));
    await tester.tap(find.text('Retomar sensores'));
    await tester.pumpAndSettle();
    expect(sensors.starts, 2);
    expect(_map(tester).userPosition!.x, closeTo(.72, .01));
    sensors.emit(131);
    await tester.pumpAndSettle();
    expect(_map(tester).userPosition!.x, closeTo(1.44, .01));
    expect(_map(tester).floor, 0);
    expect(tester.takeException(), isNull);
    await _close(tester);
    await sensors.close();
  });

  testWidgets('confirmação manual atualiza o piso da própria rota simples', (
    tester,
  ) async {
    final sensors = _FakeSensors();
    await _showRoute(tester, sensors: sensors);
    await _startPhysical(tester);
    await tester.tap(find.byTooltip('Ferramentas de navegação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar posição manual'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GPS'), findsWidgets);
    expect(find.textContaining('Superior'), findsWidgets);
    expect(find.textContaining('manual é aproximada'), findsOneWidget);
    await tester.tap(find.text('Estou em Hall superior'));
    await tester.pumpAndSettle();

    expect(find.byType(RouteScreen), findsOneWidget);
    expect(find.byType(AdvancedRouteScreen), findsNothing);
    expect(_map(tester).floor, 1);
    expect(_map(tester).userPosition!.floor, 1);
    expect(_map(tester).userPosition!.x, 10);
    sensors.emit(sensors.steps + 1);
    await tester.pumpAndSettle();
    expect(_map(tester).userPosition!.x, closeTo(10.72, .01));
    expect(_map(tester).userPosition!.floor, 1);
    expect(tester.takeException(), isNull);
    await _close(tester);
    await sensors.close();
  });
}

Future<void> _showRoute(
  WidgetTester tester, {
  required SensorService sensors,
  GranMapApi? api,
  Future<String?> Function(BuildContext)? scanAnchor,
}) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final campus = _campus();
  await tester.pumpWidget(
    MaterialApp(
      theme: GranMapTheme.dark,
      home: RouteScreen(
        campus: campus,
        origin: campus.pois.first,
        destination: campus.pois.last,
        sensors: sensors,
        api: api,
        scanAnchor: scanAnchor,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _startPhysical(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Acompanhar passos'));
  await tester.tap(find.text('Acompanhar passos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Estou nesse ponto — acompanhar passos'));
  await tester.pumpAndSettle();
}

CampusMapCanvas _map(WidgetTester tester) =>
    tester.widget<CampusMapCanvas>(find.byType(CampusMapCanvas));

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flushCancellation(tester);
  await tester.pump(const Duration(seconds: 3));
  debugDefaultTargetPlatformOverride = null;
}

Future<void> _flushCancellation(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}

class _AnchorApi extends GranMapApi {
  int anchorRequests = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchPositioningAnchors() async {
    anchorRequests++;
    return [
      {
        'anchor_code': 'upper-qr',
        'x': 10,
        'y': 0,
        'z': 3,
        'floor': 1,
        'heading': 0,
      },
    ];
  }
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
  floors: [
    CampusFloor(id: 'f0', name: 'Térreo', level: 0, elevation: 0),
    CampusFloor(id: 'f1', name: 'Piso 1', level: 1, elevation: 3),
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
      navigationNode: 'ground_start',
    ),
    CampusPoi(
      id: 'hall_superior',
      name: 'Hall superior',
      type: 'entrance',
      floor: 1,
      x: 10,
      y: 0,
      z: 3,
      navigationNode: 'upper_start',
    ),
    CampusPoi(
      id: 'sala',
      name: 'Sala 10',
      type: 'room',
      floor: 1,
      x: 100,
      y: 0,
      z: 3,
      navigationNode: 'upper_end',
    ),
  ],
  nodes: [
    NavigationNode(
      id: 'ground_start',
      floor: 0,
      x: 0,
      y: 0,
      z: 0,
      type: 'corridor',
    ),
    NavigationNode(
      id: 'ground_lift',
      floor: 0,
      x: 10,
      y: 0,
      z: 0,
      type: 'elevator',
    ),
    NavigationNode(
      id: 'upper_start',
      floor: 1,
      x: 10,
      y: 0,
      z: 3,
      type: 'elevator',
    ),
    NavigationNode(
      id: 'upper_end',
      floor: 1,
      x: 100,
      y: 0,
      z: 3,
      type: 'corridor',
    ),
  ],
  edges: [
    NavigationEdge(
      from: 'ground_start',
      to: 'ground_lift',
      distance: 10,
      type: 'corridor',
      accessible: true,
    ),
    NavigationEdge(
      from: 'ground_lift',
      to: 'upper_start',
      distance: 3,
      type: 'elevator',
      accessible: true,
    ),
    NavigationEdge(
      from: 'upper_start',
      to: 'upper_end',
      distance: 90,
      type: 'corridor',
      accessible: true,
    ),
  ],
);
