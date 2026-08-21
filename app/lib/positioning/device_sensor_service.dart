import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import 'sensor_service.dart';
import 'sensor_snapshot.dart';

/// Fonte de telemetria dos sensores físicos do aparelho.
///
/// A contagem de passos é deliberadamente conservadora: ela detecta picos no
/// acelerômetro, aplica período refratário e deixa o MapMatcher limitar a deriva.
/// Na implantação real os limiares devem ser calibrados com amostras do campus.
class DeviceSensorService implements SensorService {
  final StreamController<SensorSnapshot> _controller =
      StreamController<SensorSnapshot>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  double _ax = 0;
  double _ay = 0;
  double _az = 9.81;
  double _gz = 0;
  double _mx = 0;
  double _my = 0;
  double _mz = 0;
  double? _pressure;
  double _heading = 0;
  int _stepCount = 0;
  DateTime? _lastStep;
  DateTime? _lastGyroscopeAt;
  bool _aboveThreshold = false;
  bool _running = false;

  @override
  Stream<SensorSnapshot> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _subscriptions.add(
      userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen(_onAcceleration, onError: (_) {}),
    );
    _subscriptions.add(
      gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen((event) {
            _gz = event.z;
            final now = DateTime.now();
            final elapsed = _lastGyroscopeAt == null
                ? 0.0
                : now.difference(_lastGyroscopeAt!).inMicroseconds /
                      Duration.microsecondsPerSecond;
            _lastGyroscopeAt = now;
            _heading = (_heading + _gz * elapsed * 180 / math.pi + 360) % 360;
            _emit();
          }, onError: (_) {}),
    );
    _subscriptions.add(
      magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen((event) {
            _mx = event.x;
            _my = event.y;
            _mz = event.z;
            final magneticHeading =
                (math.atan2(_my, _mx) * 180 / math.pi + 360) % 360;
            final correction = ((magneticHeading - _heading + 540) % 360) - 180;
            _heading = (_heading + correction * .08 + 360) % 360;
            _emit();
          }, onError: (_) {}),
    );
    _subscriptions.add(
      barometerEventStream(samplingPeriod: SensorInterval.normalInterval)
          .listen((event) {
            _pressure = event.pressure;
            _emit();
          }, onError: (_) {}),
    );
    _emit();
  }

  void _onAcceleration(UserAccelerometerEvent event) {
    _ax = event.x;
    _ay = event.y;
    _az = event.z;
    final magnitude = math.sqrt(_ax * _ax + _ay * _ay + _az * _az);
    final now = DateTime.now();
    final canStep =
        _lastStep == null || now.difference(_lastStep!).inMilliseconds > 310;
    if (magnitude > 1.35 && !_aboveThreshold && canStep) {
      _stepCount++;
      _lastStep = now;
      _aboveThreshold = true;
    } else if (magnitude < .72) {
      _aboveThreshold = false;
    }
    _emit();
  }

  void _emit() {
    if (!_running || _controller.isClosed) return;
    final magnetic = math.sqrt(_mx * _mx + _my * _my + _mz * _mz);
    final availableSignals = [
      _mx != 0 || _my != 0 || _mz != 0,
      _gz != 0,
      _ax != 0 || _ay != 0 || _az != 0,
    ].where((value) => value).length;
    _controller.add(
      SensorSnapshot(
        accelerationX: _ax,
        accelerationY: _ay,
        accelerationZ: _az,
        gyroscopeZ: _gz,
        magneticX: _mx,
        magneticY: _my,
        magneticZ: _mz,
        magneticField: magnetic,
        headingDegrees: _heading,
        stepCount: _stepCount,
        confidence: (.36 + availableSignals * .17).clamp(0, .87),
        pressureHpa: _pressure,
        source: 'device',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> reset() async {
    _stepCount = 0;
    _lastStep = null;
    _emit();
  }

  @override
  Future<void> stop() async {
    _running = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
