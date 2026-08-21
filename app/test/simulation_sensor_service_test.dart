import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/positioning/simulation_sensor_service.dart';

void main() {
  test(
    'simulador emite telemetria física plausível e determinística',
    () async {
      final service = SimulationSensorService();
      final snapshotsFuture = service.snapshots.take(2).toList();

      await service.start();
      final snapshots = await snapshotsFuture.timeout(
        const Duration(seconds: 1),
      );

      expect(snapshots, hasLength(2));
      expect(snapshots.first.accelerationZ, greaterThanOrEqualTo(9.8));
      expect(snapshots.last.magneticField, inInclusiveRange(40, 60));
      expect(snapshots.last.confidence, inInclusiveRange(0, 1));
      expect(snapshots.last.headingDegrees, greaterThanOrEqualTo(0));

      await service.dispose();
    },
  );
}
