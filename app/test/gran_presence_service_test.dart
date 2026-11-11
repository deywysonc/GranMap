import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:granmap/positioning/gran_presence_service.dart';

void main() {
  group('ciclo de vida da presença', () {
    late GeolocatorPlatform original;
    late _FakeGeolocator platform;
    late GranPresenceService service;

    setUp(() {
      original = GeolocatorPlatform.instance;
      platform = _FakeGeolocator();
      GeolocatorPlatform.instance = platform;
      service = GranPresenceService.forTesting();
    });

    tearDown(() async {
      await service.stop();
      service.dispose();
      await platform.stream.close();
      GeolocatorPlatform.instance = original;
    });

    test('parar durante início assíncrono não abre stream depois', () async {
      platform.enabledGate = Completer<bool>();
      final starting = service.start();
      await Future<void>.delayed(Duration.zero);
      await service.stop();
      platform.enabledGate!.complete(true);
      await starting;
      expect(platform.streamStarts, 0);
      expect(service.running, isFalse);
    });

    test(
      'background cancela início e permite nova geração ao voltar',
      () async {
        platform.lastGate = Completer<Position?>();
        final starting = service.start();
        await Future<void>.delayed(Duration.zero);
        await service.setForeground(false);
        platform.lastGate!.complete(_fix(DateTime.now()));
        await starting;
        expect(platform.streamStarts, 0);
        await service.setForeground(true);
        expect(platform.streamStarts, 1);
        expect(platform.stream.hasListener, isTrue);
        await service.setForeground(false);
        expect(platform.stream.hasListener, isFalse);
        final before = service.snapshot;
        platform.fresh.complete(_fix(DateTime.now(), away: true));
        await Future<void>.delayed(Duration.zero);
        expect(service.snapshot, same(before));
      },
    );

    test(
      'leitura pontual antiga não substitui posição recente do stream',
      () async {
        await service.start();
        final latest = DateTime.now();
        platform.stream.add(_fix(latest));
        await Future<void>.delayed(Duration.zero);
        platform.fresh.complete(
          _fix(latest.subtract(const Duration(seconds: 20)), away: true),
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.snapshot.status, GranPresenceStatus.inside);
        expect(service.snapshot.updatedAt, latest);
      },
    );

    test('leitura pontual depois de stop não altera estado', () async {
      await service.start();
      platform.stream.add(_fix(DateTime.now()));
      await Future<void>.delayed(Duration.zero);
      await service.stop();
      final before = service.snapshot;
      platform.fresh.complete(_fix(DateTime.now(), away: true));
      await Future<void>.delayed(Duration.zero);
      expect(service.snapshot, same(before));
      expect(platform.stream.hasListener, isFalse);
    });
  });
  group('prazos das leituras de presença', () {
    const deadline = Duration(milliseconds: 20);
    const pastDeadline = Duration(milliseconds: 25);
    late GeolocatorPlatform original;
    late _FakeGeolocator platform;
    late GranPresenceService service;

    setUp(() {
      original = GeolocatorPlatform.instance;
      platform = _FakeGeolocator();
      GeolocatorPlatform.instance = platform;
      service = GranPresenceService.forTesting(
        setupTimeout: deadline,
        permissionTimeout: deadline,
        lastKnownTimeout: deadline,
        freshFixTimeout: deadline,
      );
    });

    tearDown(() async {
      await service.stop();
      service.dispose();
      await platform.stream.close();
      GeolocatorPlatform.instance = original;
    });

    testWidgets('serviço GPS pendente encerra a verificação', (tester) async {
      platform.enabledGate = Completer<bool>();
      final starting = service.start();
      await tester.pump();
      expect(platform.enabledChecks, 1);
      await tester.pump(pastDeadline);
      await starting;

      expect(service.snapshot.status, GranPresenceStatus.unavailable);
      expect(service.snapshot.detail, isNotEmpty);
      expect(service.snapshot.updatedAt, isNull);
      expect(platform.streamStarts, 0);
      expect(platform.freshRequests, 0);

      final timedOut = service.snapshot;
      platform.enabledGate!.complete(true);
      await tester.pump();
      expect(service.snapshot, same(timedOut));
      expect(platform.permissionChecks, 0);
      expect(platform.streamStarts, 0);
    });

    testWidgets('consulta de permissão pendente tem prazo de setup', (
      tester,
    ) async {
      platform.checkPermissionGate = Completer<LocationPermission>();
      final starting = service.start();
      await tester.pump();
      expect(platform.permissionChecks, 1);
      await tester.pump(pastDeadline);
      await starting;

      expect(service.snapshot.status, GranPresenceStatus.unavailable);
      expect(service.snapshot.needsPermission, isFalse);
      expect(service.snapshot.detail, isNotEmpty);
      expect(platform.permissionRequests, 0);
      expect(platform.streamStarts, 0);

      final timedOut = service.snapshot;
      platform.checkPermissionGate!.complete(LocationPermission.deniedForever);
      await tester.pump();
      expect(service.snapshot, same(timedOut));
    });

    testWidgets('permissão pendente permite tentar novamente e ignora atraso', (
      tester,
    ) async {
      platform.permission = LocationPermission.denied;
      final oldPermission = Completer<LocationPermission>();
      platform.requestPermissionGate = oldPermission;
      final starting = service.start();
      await tester.pump();
      expect(platform.permissionRequests, 1);
      await tester.pump(pastDeadline);
      await starting;

      expect(service.snapshot.status, GranPresenceStatus.uncertain);
      expect(service.snapshot.needsPermission, isFalse);
      expect(service.snapshot.detail, isNotEmpty);
      expect(platform.streamStarts, 0);

      platform.requestPermissionGate = null;
      final retrying = service.refresh();
      await tester.pump();
      await retrying;
      expect(platform.permissionChecks, 2);
      expect(platform.permissionRequests, 2);
      expect(platform.streamStarts, 1);
      expect(platform.freshRequests, 1);
      final latest = DateTime.now();
      platform.fresh.complete(_fix(latest));
      await tester.pump();
      expect(service.snapshot.status, GranPresenceStatus.inside);
      final retried = service.snapshot;

      oldPermission.complete(LocationPermission.deniedForever);
      await tester.pump();
      expect(service.snapshot, same(retried));
      expect(service.snapshot.updatedAt, latest);
      expect(platform.streamStarts, 1);
    });

    testWidgets('posição anterior pendente segue para stream e leitura atual', (
      tester,
    ) async {
      platform.lastGate = Completer<Position?>();
      final starting = service.start();
      await tester.pump();
      expect(platform.lastRequests, 1);
      expect(platform.streamStarts, 0);
      await tester.pump(pastDeadline);
      await starting;

      expect(platform.streamStarts, 1);
      expect(platform.stream.hasListener, isTrue);
      expect(platform.freshRequests, 1);
      final latest = DateTime.now();
      platform.fresh.complete(_fix(latest));
      await tester.pump();
      expect(service.snapshot.status, GranPresenceStatus.inside);
      final current = service.snapshot;

      platform.lastGate!.complete(
        _fix(latest.subtract(const Duration(seconds: 1)), away: true),
      );
      await tester.pump();
      expect(service.snapshot, same(current));
    });

    testWidgets('prazo externo encerra leitura atual que ignora timeLimit', (
      tester,
    ) async {
      final starting = service.start();
      await tester.pump();
      await starting;
      expect(platform.freshRequests, 1);
      expect(platform.freshSettings?.timeLimit, deadline);
      expect(service.snapshot.status, GranPresenceStatus.checking);

      await tester.pump(pastDeadline);
      expect(service.snapshot.status, GranPresenceStatus.uncertain);
      expect(service.snapshot.detail, isNotEmpty);
      expect(service.snapshot.updatedAt, isNull);
      final timedOut = service.snapshot;

      platform.fresh.complete(_fix(DateTime.now(), away: true));
      await tester.pump();
      expect(service.snapshot, same(timedOut));

      platform.stream.add(_fix(DateTime.now()));
      await tester.pump();
      expect(service.snapshot.status, GranPresenceStatus.inside);
    });

    testWidgets('erro da leitura atual sai do estado de verificação', (
      tester,
    ) async {
      final starting = service.start();
      await tester.pump();
      await starting;
      platform.fresh.completeError(StateError('fresh failed'));
      await tester.pump();

      expect(service.snapshot.status, GranPresenceStatus.unavailable);
      expect(service.snapshot.detail, isNotEmpty);
      expect(service.snapshot.updatedAt, isNull);
      expect(platform.stream.hasListener, isTrue);
    });

    for (final timesOut in [false, true]) {
      final failure = timesOut ? 'timeout' : 'erro';
      testWidgets('$failure de setup preserva a última posição válida', (
        tester,
      ) async {
        final starting = service.start();
        await tester.pump();
        await starting;
        platform.fresh.complete(_fix(DateTime.now()));
        await tester.pump();
        final previous = service.snapshot;
        expect(previous.status, GranPresenceStatus.inside);

        for (var attempt = 0; attempt < 2; attempt++) {
          platform.enabledGate = Completer<bool>();
          final refreshing = service.refresh();
          await tester.pump();
          expect(platform.enabledChecks, attempt + 2);
          if (timesOut) {
            await tester.pump(pastDeadline);
          } else {
            platform.enabledGate!.completeError(StateError('setup failed'));
            await tester.pump();
          }
          await refreshing;

          _expectPreservedFix(service.snapshot, previous);
        }
        expect(platform.streamStarts, 1);
        expect(platform.freshRequests, 1);
      });

      testWidgets('$failure da leitura atual preserva a posição anterior', (
        tester,
      ) async {
        platform.lastGate = Completer<Position?>()
          ..complete(_fix(DateTime.now()));
        final starting = service.start();
        await tester.pump();
        await starting;
        final previous = service.snapshot;
        expect(previous.status, GranPresenceStatus.inside);

        if (timesOut) {
          await tester.pump(pastDeadline);
        } else {
          platform.fresh.completeError(StateError('fresh failed'));
          await tester.pump();
        }

        _expectPreservedFix(service.snapshot, previous);
      });

      testWidgets('$failure pontual não degrada nova posição do stream', (
        tester,
      ) async {
        final starting = service.start();
        await tester.pump();
        await starting;
        platform.stream.add(_fix(DateTime.now()));
        await tester.pump();
        final current = service.snapshot;
        expect(current.status, GranPresenceStatus.inside);

        if (timesOut) {
          await tester.pump(pastDeadline);
        } else {
          platform.fresh.completeError(StateError('fresh failed'));
          await tester.pump();
        }

        expect(service.snapshot, same(current));
      });
    }

    testWidgets('timeout de permissão preserva coordenadas e instante', (
      tester,
    ) async {
      final starting = service.start();
      await tester.pump();
      await starting;
      platform.fresh.complete(_fix(DateTime.now()));
      await tester.pump();
      final previous = service.snapshot;

      platform.permission = LocationPermission.denied;
      platform.requestPermissionGate = Completer<LocationPermission>();
      final refreshing = service.refresh();
      await tester.pump();
      expect(platform.permissionRequests, 1);
      await tester.pump(pastDeadline);
      await refreshing;

      _expectPreservedFix(service.snapshot, previous);
      expect(service.snapshot.needsPermission, isFalse);
    });

    testWidgets(
      'leitura pontual de geração anterior ignora posição mais nova',
      (tester) async {
        final starting = service.start();
        await tester.pump();
        await starting;
        final oldFresh = platform.fresh;
        platform.fresh = Completer<Position>();
        final refreshing = service.refresh();
        await tester.pump();
        await refreshing;
        expect(platform.streamStarts, 2);
        expect(platform.freshRequests, 2);

        final latest = DateTime.now();
        platform.fresh.complete(_fix(latest));
        await tester.pump();
        final current = service.snapshot;
        expect(current.status, GranPresenceStatus.inside);
        oldFresh.complete(
          _fix(latest.add(const Duration(seconds: 1)), away: true),
        );
        await tester.pump();

        expect(service.snapshot, same(current));
        expect(service.snapshot.updatedAt, latest);
      },
    );
  });
  group('GranGeofence', () {
    test('reconhece uma leitura confiável dentro da Gran Tietê', () {
      final result = GranGeofence.classify(
        latitude: GranGeofence.latitude,
        longitude: GranGeofence.longitude,
        accuracyMeters: 8,
      );

      expect(result.status, GranPresenceStatus.inside);
      expect(result.distanceMeters, closeTo(0, .01));
    });

    test('distingue proximidade de uma posição distante', () {
      final nearby = GranGeofence.classify(
        latitude: GranGeofence.latitude + .0045,
        longitude: GranGeofence.longitude,
        accuracyMeters: 12,
      );
      final outside = GranGeofence.classify(
        latitude: GranGeofence.latitude + 1,
        longitude: GranGeofence.longitude,
        accuracyMeters: 12,
      );

      expect(nearby.status, GranPresenceStatus.nearby);
      expect(outside.status, GranPresenceStatus.outside);
    });

    test('não afirma presença quando o GPS é impreciso', () {
      final result = GranGeofence.classify(
        latitude: GranGeofence.latitude + .0045,
        longitude: GranGeofence.longitude,
        accuracyMeters: 250,
      );

      expect(result.status, GranPresenceStatus.uncertain);
    });

    test('não usa uma posição antiga como se fosse atual', () {
      final result = GranGeofence.classify(
        latitude: GranGeofence.latitude,
        longitude: GranGeofence.longitude,
        accuracyMeters: 8,
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(result.status, GranPresenceStatus.uncertain);
      expect(result.detail, contains('desatualizada'));
    });

    test('calcula distância geográfica em metros', () {
      final distance = GranGeofence.distanceBetween(0, 0, 0, 1);
      expect(distance, closeTo(111195, 100));
    });
  });
}

class _FakeGeolocator extends GeolocatorPlatform {
  final stream = StreamController<Position>.broadcast();
  Completer<Position>? _fresh;
  Completer<bool>? enabledGate;
  Completer<LocationPermission>? checkPermissionGate;
  Completer<LocationPermission>? requestPermissionGate;
  Completer<Position?>? lastGate;
  LocationPermission permission = LocationPermission.whileInUse;
  int enabledChecks = 0;
  int permissionChecks = 0;
  int permissionRequests = 0;
  int lastRequests = 0;
  int streamStarts = 0;
  int freshRequests = 0;
  LocationSettings? freshSettings;

  Completer<Position> get fresh => _fresh ??= Completer<Position>();
  set fresh(Completer<Position> value) => _fresh = value;

  @override
  Future<bool> isLocationServiceEnabled() async {
    enabledChecks++;
    return enabledGate == null ? true : await enabledGate!.future;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    permissionChecks++;
    return checkPermissionGate == null
        ? permission
        : await checkPermissionGate!.future;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return requestPermissionGate == null
        ? LocationPermission.whileInUse
        : await requestPermissionGate!.future;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    lastRequests++;
    return lastGate == null ? null : await lastGate!.future;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamStarts++;
    return stream.stream;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    freshRequests++;
    freshSettings = locationSettings;
    return fresh.future;
  }
}

void _expectPreservedFix(
  GranPresenceSnapshot snapshot,
  GranPresenceSnapshot previous,
) {
  expect(snapshot.status, GranPresenceStatus.uncertain);
  expect(snapshot.latitude, previous.latitude);
  expect(snapshot.longitude, previous.longitude);
  expect(snapshot.accuracyMeters, previous.accuracyMeters);
  expect(snapshot.distanceMeters, previous.distanceMeters);
  expect(snapshot.updatedAt, previous.updatedAt);
  expect(snapshot.detail, isNotEmpty);
}

Position _fix(DateTime timestamp, {bool away = false}) => Position(
  longitude: GranGeofence.longitude,
  latitude: GranGeofence.latitude + (away ? 1 : 0),
  timestamp: timestamp,
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
