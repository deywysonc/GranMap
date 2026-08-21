import 'dart:async';
import 'dart:math' as math;

import 'sensor_service.dart';
import 'sensor_snapshot.dart';

/// Emite telemetria determinística para desenvolver a cadeia de localização
/// antes da coleta dos fingerprints magnéticos e da calibração em campo.
class SimulationSensorService implements SensorService {
  final StreamController<SensorSnapshot> _controller =
      StreamController<SensorSnapshot>.broadcast();

  Timer? _timer;
  int _tick = 0;
  double _noiseLevel = .18;

  double get noiseLevel => _noiseLevel;

  void setNoiseLevel(double value) {
    _noiseLevel = value.clamp(0, 1).toDouble();
    _emit();
  }

  @override
  Stream<SensorSnapshot> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    _timer?.cancel();
    _emit();
    _timer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      _tick++;
      _emit();
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
  }

  @override
  Future<void> reset() async {
    _tick = 0;
    _emit();
  }

  void _emit() {
    final phase = _tick / 5.5;
    final stride = math.sin(phase);
    final noise = _noiseLevel;
    final magneticX = 31.4 + math.sin(phase * .41) * (1.8 + noise * 7);
    final magneticY = 24.8 + math.cos(phase * .37) * (1.6 + noise * 6);
    final magneticZ = 24.1 + math.sin(phase * .29) * (1.2 + noise * 5);
    final confidence = (.96 - noise * .48 - math.sin(phase * .23).abs() * .08)
        .clamp(0, 1);
    _controller.add(
      SensorSnapshot(
        accelerationX: stride * (.16 + noise * .34),
        accelerationY: math.cos(phase * .72) * (.1 + noise * .28),
        accelerationZ: 9.81 + stride.abs() * (.3 + noise * .55),
        gyroscopeZ: math.cos(phase) * (.06 + noise * .22),
        magneticX: magneticX,
        magneticY: magneticY,
        magneticZ: magneticZ,
        magneticField: math.sqrt(
          magneticX * magneticX + magneticY * magneticY + magneticZ * magneticZ,
        ),
        headingDegrees: (_tick * 3.2) % 360,
        stepCount: _tick ~/ 3,
        confidence: confidence.toDouble(),
        pressureHpa: 1013.2 + math.sin(phase * .08) * .18,
        source: 'simulation',
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}
