import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/positioning/device_sensor_service.dart';
import 'package:granmap/positioning/sensor_snapshot.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  test('giroscópio não integra tempo em pausa ou lacunas longas', () async {
    final gyro = StreamController<GyroscopeEvent>.broadcast();
    var now = DateTime(2026);
    final service = DeviceSensorService(
      accelerationEvents: const Stream<UserAccelerometerEvent>.empty(),
      gyroscopeEvents: gyro.stream,
      magnetometerEvents: const Stream<MagnetometerEvent>.empty(),
      barometerEvents: const Stream<BarometerEvent>.empty(),
      clock: () => now,
    );
    final readings = <SensorSnapshot>[];
    final subscription = service.snapshots.listen(readings.add);
    Future<void> emit() async {
      gyro.add(GyroscopeEvent(0, 0, 1, now));
      await Future<void>.delayed(Duration.zero);
    }

    await service.start();
    await emit();
    now = now.add(const Duration(milliseconds: 100));
    await emit();
    final beforePause = readings.last.headingDegrees;
    expect(beforePause, closeTo(5.73, .01));
    await service.stop();
    now = now.add(const Duration(minutes: 10));
    await service.start();
    await emit();
    expect(readings.last.headingDegrees, beforePause);
    now = now.add(const Duration(seconds: 5));
    await emit();
    expect(readings.last.headingDegrees, beforePause);
    await subscription.cancel();
    await service.dispose();
    await gyro.close();
  });
}
