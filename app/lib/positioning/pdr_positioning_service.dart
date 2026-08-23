import 'dart:async';
import 'dart:math' as math;

import '../models/campus_map.dart';
import 'map_matcher.dart';
import 'magnetic_fingerprint_matcher.dart';
import 'position_sample.dart';
import 'positioning_service.dart';
import 'sensor_service.dart';
import 'sensor_snapshot.dart';

/// PDR (Pedestrian Dead Reckoning) com map matching e reancoragem explícita.
class PdrPositioningService implements PositioningService {
  final CampusMap campus;
  final SensorService sensors;
  final MapMatcher matcher;
  final double strideUnits;
  final MagneticFingerprintMatcher magneticMatcher;
  final StreamController<PositionSample> _controller =
      StreamController<PositionSample>.broadcast();

  StreamSubscription<SensorSnapshot>? _subscription;
  bool _running = false;
  late PositionSample _position;
  int _lastSteps = 0;
  DateTime? _lastAnchorAt;
  List<MagneticFingerprint> _magneticReferences = const [];

  PdrPositioningService({
    required this.campus,
    required this.sensors,
    required PositionSample initialPosition,
    this.matcher = const MapMatcher(),
    this.magneticMatcher = const MagneticFingerprintMatcher(),
    this.strideUnits = .72,
  }) : _position = initialPosition;

  @override
  Stream<PositionSample> get positions => _controller.stream;

  PositionSample get current => _position;

  void setMagneticReferences(List<MagneticFingerprint> references) {
    _magneticReferences = List.unmodifiable(references);
  }

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _subscription?.cancel();
    _subscription = sensors.snapshots.listen(_onSensor);
    try {
      await sensors.start();
      _controller.add(_position);
    } catch (_) {
      _running = false;
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    }
  }

  void _onSensor(SensorSnapshot snapshot) {
    final stepDelta = math.max(0, snapshot.stepCount - _lastSteps);
    _lastSteps = snapshot.stepCount;
    final radians = snapshot.headingDegrees * math.pi / 180;
    final ageSeconds = _lastAnchorAt == null
        ? 999.0
        : DateTime.now().difference(_lastAnchorAt!).inSeconds.toDouble();
    final driftPenalty = (ageSeconds / 240).clamp(0, .42);
    final predicted = PositionSample(
      x: _position.x + math.cos(radians) * strideUnits * stepDelta,
      y: _position.y + math.sin(radians) * strideUnits * stepDelta,
      z: _position.z,
      floor: _position.floor,
      headingDegrees: snapshot.headingDegrees,
      accuracyMeters: (_position.accuracyMeters + stepDelta * .16).clamp(
        1.2,
        14,
      ),
      confidence: (snapshot.confidence - driftPenalty).clamp(.08, .9),
      timestamp: snapshot.timestamp,
    );
    var fused = predicted;
    final magnetic = magneticMatcher.match(
      snapshot: snapshot,
      floor: predicted.floor,
      references: _magneticReferences,
    );
    if (magnetic != null) {
      final weight = (magnetic.confidence * .38).clamp(0, .35).toDouble();
      fused = PositionSample(
        x: predicted.x * (1 - weight) + magnetic.x * weight,
        y: predicted.y * (1 - weight) + magnetic.y * weight,
        z: predicted.z * (1 - weight) + magnetic.z * weight,
        floor: predicted.floor,
        headingDegrees: predicted.headingDegrees,
        accuracyMeters: predicted.accuracyMeters * (1 - weight),
        confidence: (predicted.confidence * .7 + magnetic.confidence * .3)
            .clamp(0, .94),
        timestamp: predicted.timestamp,
      );
    }
    _position = matcher.match(campus: campus, sample: fused).position;
    _controller.add(_position);
  }

  void reanchor(PositionSample anchor) {
    _position = anchor;
    _lastAnchorAt = DateTime.now();
    _controller.add(_position);
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
    await sensors.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
