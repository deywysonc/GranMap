import 'sensor_snapshot.dart';

abstract class SensorService {
  Stream<SensorSnapshot> get snapshots;

  Future<void> start();
  Future<void> stop();
  Future<void> reset();
}
