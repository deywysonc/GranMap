import 'dart:async';

import '../models/campus_map.dart';
import 'position_sample.dart';
import 'positioning_service.dart';

class SimulationPositioningService implements PositioningService {
  final StreamController<PositionSample> _controller =
      StreamController<PositionSample>.broadcast();

  Timer? _timer;
  List<NavigationNode> _route = const [];
  int _index = 0;

  @override
  Stream<PositionSample> get positions => _controller.stream;

  void setRoute(List<NavigationNode> route) {
    _route = route;
    _index = 0;
  }

  @override
  Future<void> start() async {
    _timer?.cancel();
    if (_route.isEmpty) return;

    _emit(_route[_index]);
    _timer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (_index >= _route.length - 1) {
        timer.cancel();
        return;
      }
      _index++;
      _emit(_route[_index]);
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }

  void _emit(NavigationNode node) {
    _controller.add(
      PositionSample(
        x: node.x,
        y: node.y,
        z: node.z,
        floor: node.floor,
        headingDegrees: 0,
        accuracyMeters: 0.1,
        confidence: 1,
        timestamp: DateTime.now(),
      ),
    );
  }
}
