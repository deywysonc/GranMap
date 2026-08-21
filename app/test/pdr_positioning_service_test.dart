import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/positioning/pdr_positioning_service.dart';
import 'package:granmap/positioning/position_sample.dart';
import 'package:granmap/positioning/sensor_service.dart';
import 'package:granmap/positioning/sensor_snapshot.dart';

void main() {
  test('PDR move, casa no corredor e aceita reancoragem QR', () async {
    final sensors = _FakeSensors();
    final service = PdrPositioningService(
      campus: _campus(),
      sensors: sensors,
      initialPosition: PositionSample(
        x: 0,
        y: 0,
        z: 0,
        floor: 0,
        headingDegrees: 0,
        accuracyMeters: 1,
        confidence: .9,
        timestamp: DateTime(2026),
      ),
      strideUnits: 1,
    );
    final received = <PositionSample>[];
    final subscription = service.positions.listen(received.add);
    await service.start();

    sensors.emit(steps: 1, heading: 0);
    await Future<void>.delayed(Duration.zero);
    expect(service.current.x, closeTo(1, .01));
    expect(service.current.y, closeTo(0, .01));

    service.reanchor(
      PositionSample(
        x: 7,
        y: 0,
        z: 0,
        floor: 0,
        headingDegrees: 0,
        accuracyMeters: .4,
        confidence: .99,
        timestamp: DateTime(2026),
      ),
    );
    expect(service.current.x, 7);
    await Future<void>.delayed(Duration.zero);
    expect(received.last.confidence, .99);

    await subscription.cancel();
    await service.dispose();
    await sensors.dispose();
  });
}

class _FakeSensors implements SensorService {
  final StreamController<SensorSnapshot> _controller =
      StreamController<SensorSnapshot>.broadcast();

  @override
  Stream<SensorSnapshot> get snapshots => _controller.stream;

  void emit({required int steps, required double heading}) {
    _controller.add(
      SensorSnapshot(
        accelerationX: 0,
        accelerationY: 0,
        accelerationZ: 1.5,
        gyroscopeZ: 0,
        magneticField: 48,
        headingDegrees: heading,
        stepCount: steps,
        confidence: .85,
        source: 'test',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  Future<void> dispose() => _controller.close();
}

CampusMap _campus() => const CampusMap(
  building: BuildingInfo(id: 'demo', name: 'Demo', version: '1'),
  floors: [CampusFloor(id: 'f0', name: 'Térreo', level: 0, elevation: 0)],
  pois: [],
  nodes: [
    NavigationNode(id: 'a', floor: 0, x: 0, y: 0, z: 0, type: 'corridor'),
    NavigationNode(id: 'b', floor: 0, x: 10, y: 0, z: 0, type: 'corridor'),
  ],
  edges: [
    NavigationEdge(
      from: 'a',
      to: 'b',
      distance: 10,
      type: 'corridor',
      accessible: true,
    ),
  ],
);
