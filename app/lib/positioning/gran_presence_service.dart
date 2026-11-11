import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GranPresenceStatus {
  checking,
  inside,
  nearby,
  outside,
  uncertain,
  permissionDenied,
  servicesDisabled,
  unavailable,
}

@immutable
class GranPresenceSnapshot {
  final GranPresenceStatus status;
  final double? distanceMeters;
  final double? accuracyMeters;
  final double? latitude;
  final double? longitude;
  final DateTime? updatedAt;
  final String? detail;

  const GranPresenceSnapshot({
    required this.status,
    this.distanceMeters,
    this.accuracyMeters,
    this.latitude,
    this.longitude,
    this.updatedAt,
    this.detail,
  });

  static const checking = GranPresenceSnapshot(
    status: GranPresenceStatus.checking,
  );

  bool get isAtGran => status == GranPresenceStatus.inside;
  bool get isAway =>
      status == GranPresenceStatus.nearby ||
      status == GranPresenceStatus.outside;
  bool get needsPermission => status == GranPresenceStatus.permissionDenied;

  String get distanceLabel {
    final value = distanceMeters;
    if (value == null) return 'distância indisponível';
    if (value < 1000) return '${value.round()} m';
    final km = value / 1000;
    return '${km < 10 ? km.toStringAsFixed(1) : km.round()} km';
  }
}

/// Referência geográfica provisória da Gran Tietê.
///
/// O endereço público atual é Av. 15 de Novembro, 170, Centro, Barra
/// Bonita/SP. O centro pode ser recalibrado sem recompilar por dart-define
/// depois de uma medição de campo nas entradas.
class GranGeofence {
  const GranGeofence._();

  static final latitude =
      double.tryParse(
        const String.fromEnvironment(
          'GRANMAP_GRAN_LATITUDE',
          defaultValue: '-22.4940526',
        ),
      ) ??
      -22.4940526;
  static final longitude =
      double.tryParse(
        const String.fromEnvironment(
          'GRANMAP_GRAN_LONGITUDE',
          defaultValue: '-48.5578322',
        ),
      ) ??
      -48.5578322;
  static final insideRadiusMeters =
      double.tryParse(
        const String.fromEnvironment(
          'GRANMAP_GRAN_RADIUS_METERS',
          defaultValue: '180',
        ),
      ) ??
      180;
  static const nearbyRadiusMeters = 1500.0;
  static const address = 'Av. 15 de Novembro, 170, Centro, Barra Bonita - SP';

  static GranPresenceSnapshot classify({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    DateTime? timestamp,
  }) {
    final distance = distanceBetween(
      latitude,
      longitude,
      GranGeofence.latitude,
      GranGeofence.longitude,
    );
    final accuracy = accuracyMeters.isFinite
        ? accuracyMeters.clamp(0, 5000).toDouble()
        : 5000.0;
    final tolerance = math.min(accuracy, 50);
    final measuredAt = timestamp ?? DateTime.now();
    final stale =
        DateTime.now().difference(measuredAt).abs() >
        const Duration(minutes: 15);

    late final GranPresenceStatus status;
    if (stale) {
      status = GranPresenceStatus.uncertain;
    } else if (distance <= insideRadiusMeters + tolerance && accuracy <= 120) {
      status = GranPresenceStatus.inside;
    } else if (distance > nearbyRadiusMeters + accuracy) {
      status = GranPresenceStatus.outside;
    } else if (accuracy > 120) {
      status = GranPresenceStatus.uncertain;
    } else {
      status = GranPresenceStatus.nearby;
    }

    return GranPresenceSnapshot(
      status: status,
      distanceMeters: distance,
      accuracyMeters: accuracy,
      latitude: latitude,
      longitude: longitude,
      updatedAt: measuredAt,
      detail: stale ? 'A última posição disponível está desatualizada.' : null,
    );
  }

  static double distanceBetween(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = latitudeA * math.pi / 180;
    final lat2 = latitudeB * math.pi / 180;
    final deltaLat = (latitudeB - latitudeA) * math.pi / 180;
    final deltaLon = (longitudeB - longitudeA) * math.pi / 180;
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

/// Mantém a presença geográfica atualizada somente enquanto o app está em uso.
class GranPresenceService extends ChangeNotifier {
  GranPresenceService._()
    : setupTimeout = const Duration(seconds: 5),
      permissionTimeout = const Duration(seconds: 20),
      lastKnownTimeout = const Duration(seconds: 2),
      freshFixTimeout = const Duration(seconds: 10);

  @visibleForTesting
  GranPresenceService.forTesting({
    this.setupTimeout = const Duration(seconds: 5),
    this.permissionTimeout = const Duration(seconds: 20),
    this.lastKnownTimeout = const Duration(seconds: 2),
    this.freshFixTimeout = const Duration(seconds: 10),
  });

  static final GranPresenceService instance = GranPresenceService._();

  final Duration setupTimeout;
  final Duration permissionTimeout;
  final Duration lastKnownTimeout;
  final Duration freshFixTimeout;

  StreamSubscription<Position>? _positionSubscription;
  GranPresenceSnapshot _snapshot = GranPresenceSnapshot.checking;
  bool _running = false;
  bool _foreground = true;
  int _generation = 0;
  int? _startingGeneration;

  GranPresenceSnapshot get snapshot => _snapshot;
  bool get running => _running;

  Future<void> start() async {
    _running = true;
    if (_foreground) await _beginListening(requestPermission: true);
  }

  Future<void> stop() async {
    _running = false;
    _generation++;
    final subscription = _positionSubscription;
    _positionSubscription = null;
    await subscription?.cancel();
  }

  Future<void> setForeground(bool value) async {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      _generation++;
      final subscription = _positionSubscription;
      _positionSubscription = null;
      await subscription?.cancel();
    } else if (_running) {
      await _beginListening(requestPermission: false);
    }
  }

  Future<void> refresh({bool requestPermission = true}) async {
    if (!_running) _running = true;
    await _beginListening(requestPermission: requestPermission, force: true);
  }

  Future<void> openRequiredSettings() async {
    if (_snapshot.status == GranPresenceStatus.servicesDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _beginListening({
    required bool requestPermission,
    bool force = false,
  }) async {
    if (_startingGeneration == _generation || !_running || !_foreground) return;
    if (_positionSubscription != null && !force) return;
    final generation = ++_generation;
    _startingGeneration = generation;
    var waitingForPermission = false;
    try {
      // A native plugin may leave its future pending indefinitely. These
      // deadlines protect the UI independently of the plugin's own limits.
      final previous = _positionSubscription;
      _positionSubscription = null;
      await previous?.cancel().timeout(setupTimeout);
      if (!_isCurrent(generation)) return;
      final enabled = await Geolocator.isLocationServiceEnabled().timeout(
        setupTimeout,
      );
      if (!_isCurrent(generation)) return;
      if (!enabled) {
        _set(
          const GranPresenceSnapshot(
            status: GranPresenceStatus.servicesDisabled,
            detail: 'A localização do aparelho está desligada.',
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission().timeout(setupTimeout);
      if (!_isCurrent(generation)) return;
      if (permission == LocationPermission.denied && requestPermission) {
        waitingForPermission = true;
        permission = await Geolocator.requestPermission().timeout(
          permissionTimeout,
        );
        waitingForPermission = false;
        if (!_isCurrent(generation)) return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _set(
          GranPresenceSnapshot(
            status: GranPresenceStatus.permissionDenied,
            detail: permission == LocationPermission.deniedForever
                ? 'A permissão foi bloqueada nas configurações do Android.'
                : 'Permita a localização para saber se você está na Gran.',
          ),
        );
        return;
      }

      if (_snapshot.updatedAt == null) {
        _set(GranPresenceSnapshot.checking);
      }

      try {
        final last = await Geolocator.getLastKnownPosition().timeout(
          lastKnownTimeout,
        );
        if (!_isCurrent(generation)) return;
        if (last != null) _accept(last, generation);
      } catch (_) {
        // Alguns dispositivos não fornecem uma posição anterior.
      }

      if (!_isCurrent(generation)) return;
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 8,
            ),
          ).listen(
            (position) => _accept(position, generation),
            onError: (Object error) {
              if (!_isCurrent(generation)) return;
              _reportFailure(
                GranPresenceStatus.unavailable,
                'Não foi possível atualizar sua localização. '
                'Você pode usar o mapa e tentar novamente.',
              );
            },
          );
      unawaited(_requestFreshFix(generation));
    } on TimeoutException {
      if (!_isCurrent(generation)) return;
      _reportFailure(
        waitingForPermission
            ? GranPresenceStatus.uncertain
            : GranPresenceStatus.unavailable,
        waitingForPermission
            ? 'A permissão de localização ainda não foi confirmada. '
                  'Você pode usar o mapa e tentar novamente.'
            : 'A localização demorou para responder. '
                  'Você pode usar o mapa e tentar novamente.',
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _reportFailure(
        GranPresenceStatus.unavailable,
        'Não foi possível acessar sua localização. '
        'Você pode usar o mapa e tentar novamente.',
      );
    } finally {
      if (_startingGeneration == generation) _startingGeneration = null;
    }
  }

  bool _isCurrent(int generation) =>
      _running && _foreground && _generation == generation;

  Future<void> _requestFreshFix(int generation) async {
    final previousTimestamp = _snapshot.updatedAt;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: freshFixTimeout,
        ),
      ).timeout(freshFixTimeout);
      _accept(position, generation);
    } on TimeoutException {
      if (_isCurrent(generation) && _snapshot.updatedAt == previousTimestamp) {
        _reportFailure(
          GranPresenceStatus.uncertain,
          'O GPS ainda não conseguiu uma leitura confiável. '
          'Você pode usar o mapa e tentar novamente.',
        );
      }
    } catch (_) {
      if (_isCurrent(generation) && _snapshot.updatedAt == previousTimestamp) {
        _reportFailure(
          GranPresenceStatus.unavailable,
          'Não foi possível obter sua localização agora. '
          'Você pode usar o mapa e tentar novamente.',
        );
      }
    }
  }

  void _reportFailure(GranPresenceStatus status, String detail) {
    final last = _snapshot;
    _set(
      GranPresenceSnapshot(
        status: last.updatedAt == null ? status : GranPresenceStatus.uncertain,
        distanceMeters: last.distanceMeters,
        accuracyMeters: last.accuracyMeters,
        latitude: last.latitude,
        longitude: last.longitude,
        updatedAt: last.updatedAt,
        detail: detail,
      ),
    );
  }

  void _accept(Position position, int generation) {
    if (!_isCurrent(generation)) return;
    final previousTimestamp = _snapshot.updatedAt;
    if (previousTimestamp != null &&
        position.timestamp.isBefore(previousTimestamp)) {
      return;
    }
    _set(
      GranGeofence.classify(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        timestamp: position.timestamp,
      ),
    );
  }

  void _set(GranPresenceSnapshot value) {
    _snapshot = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _running = false;
    _generation++;
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    super.dispose();
  }
}
