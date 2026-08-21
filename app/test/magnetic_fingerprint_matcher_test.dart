import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/positioning/magnetic_fingerprint_matcher.dart';
import 'package:granmap/positioning/sensor_snapshot.dart';

void main() {
  test('fingerprinting estima a região pelas referências mais próximas', () {
    const references = [
      MagneticFingerprint(
        x: 0,
        y: 0,
        z: 0,
        floor: 0,
        magneticX: 10,
        magneticY: 20,
        magneticZ: 30,
        quality: .9,
      ),
      MagneticFingerprint(
        x: 2,
        y: 0,
        z: 0,
        floor: 0,
        magneticX: 11,
        magneticY: 20,
        magneticZ: 30,
        quality: .9,
      ),
      MagneticFingerprint(
        x: 20,
        y: 0,
        z: 0,
        floor: 0,
        magneticX: 70,
        magneticY: 70,
        magneticZ: 70,
        quality: .9,
      ),
    ];
    final result = const MagneticFingerprintMatcher().match(
      snapshot: SensorSnapshot(
        accelerationX: 0,
        accelerationY: 0,
        accelerationZ: 0,
        gyroscopeZ: 0,
        magneticX: 10.5,
        magneticY: 20,
        magneticZ: 30,
        magneticField: 37,
        headingDegrees: 0,
        stepCount: 0,
        confidence: .8,
        timestamp: DateTime(2026),
      ),
      floor: 0,
      references: references,
      neighbors: 2,
    );
    expect(result, isNotNull);
    expect(result!.x, closeTo(1, .2));
    expect(result.confidence, greaterThan(.8));
  });
}
