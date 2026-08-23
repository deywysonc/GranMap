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
  GranPresenceService._();

  static final GranPresenceService instance = GranPresenceService._();

  StreamSubscription<Position>? _positionSubscription;
  GranPresenceSnapshot _snapshot = GranPresenceSnapshot.checking;
  bool _running = false;
  bool _foreground = true;
  bool _starting = false;

  GranPresenceSnapshot get snapshot => _snapshot;
  bool get running => _running;

  Future<void> start() async {
    _running = true;
    if (_foreground) await _beginListening(requestPermission: true);
  }

  Future<void> stop() async {
    _running = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> setForeground(bool value) async {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
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
    if (_starting || !_running || !_foreground) return;
    if (_positionSubscription != null && !force) return;
    _starting = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _set(
          const GranPresenceSnapshot(
            status: GranPresenceStatus.servicesDisabled,
            detail: 'A localização do aparelho está desligada.',
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
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

      if (_snapshot.status != GranPresenceStatus.inside &&
          _snapshot.status != GranPresenceStatus.nearby &&
          _snapshot.status != GranPresenceStatus.outside) {
        _set(GranPresenceSnapshot.checking);
      }

      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) _accept(last);
      } catch (_) {
        // Alguns dispositivos não fornecem uma posição anterior.
      }

      await _positionSubscription?.cancel();
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 8,
            ),
          ).listen(
            _accept,
            onError: (Object error) {
              _set(
                GranPresenceSnapshot(
                  status: GranPresenceStatus.unavailable,
                  detail: 'Não foi possível atualizar o GPS: $error',
                ),
              );
            },
          );
      unawaited(_requestFreshFix());
    } catch (error) {
      _set(
        GranPresenceSnapshot(
          status: GranPresenceStatus.unavailable,
          detail: 'Localização indisponível neste aparelho: $error',
        ),
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> _requestFreshFix() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _accept(position);
    } on TimeoutException {
      if (_snapshot.status == GranPresenceStatus.checking) {
        _set(
          const GranPresenceSnapshot(
            status: GranPresenceStatus.uncertain,
            detail: 'O GPS ainda não conseguiu uma leitura confiável.',
          ),
        );
      }
    } catch (_) {
      // O stream pode entregar a posição mesmo quando a leitura pontual falha.
    }
  }

  void _accept(Position position) {
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
}
