import 'position_sample.dart';

abstract class PositioningService {
  Stream<PositionSample> get positions;

  Future<void> start();
  Future<void> stop();
}
