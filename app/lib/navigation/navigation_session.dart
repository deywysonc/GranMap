import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/campus_map.dart';
import '../positioning/position_sample.dart';
import '../positioning/position_confidence_engine.dart';
import 'route_result.dart';

enum NavigationSessionStatus { ready, navigating, paused, arrived }

/// A fonte única de verdade para uma navegação em andamento.
///
/// A sessão trabalha no sistema de coordenadas do mapa. Hoje essas unidades
/// pertencem à maquete conceitual; quando a geometria métrica chegar, os mesmos
/// consumidores (2D, 3D, primeira pessoa e AR) continuarão recebendo a posição
/// por esta interface.
class NavigationSession extends ChangeNotifier {
  static const double demoWalkingSpeedUnitsPerSecond = 1.25;
  static const double _simulationUnitsPerSecond = 12;

  final RouteResult route;
  final bool autoTick;
  final PositionConfidenceEngine _confidenceEngine =
      const PositionConfidenceEngine();

  Timer? _timer;
  Stopwatch? _clock;
  NavigationSessionStatus _status = NavigationSessionStatus.ready;
  int _segmentIndex = 0;
  double _segmentOffset = 0;
  double _playbackSpeed = 1;
  late PositionSample _position;

  NavigationSession({required this.route, this.autoTick = true}) {
    if (route.nodes.isEmpty) {
      throw ArgumentError.value(
        route.nodes,
        'route.nodes',
        'não pode ser vazio',
      );
    }
    _position = _sampleAt(route.nodes.first, headingDegrees: 0);
  }

  NavigationSessionStatus get status => _status;
  PositionSample get position => _position;
  int get segmentIndex => _segmentIndex;
  double get playbackSpeed => _playbackSpeed;
  int get currentFloor => _position.floor;
  bool get isPlaying => _status == NavigationSessionStatus.navigating;
  bool get hasArrived => _status == NavigationSessionStatus.arrived;

  int get currentNodeIndex {
    if (hasArrived) return route.nodes.length - 1;
    if (_segmentIndex >= route.edges.length) return route.nodes.length - 1;
    final length = math.max(route.edges[_segmentIndex].distance, .0001);
    return (_segmentOffset / length) >= .5
        ? math.min(_segmentIndex + 1, route.nodes.length - 1)
        : _segmentIndex;
  }

  String get activeNodeId => route.nodes[currentNodeIndex].id;

  int get currentInstructionIndex {
    if (hasArrived) return route.instructions.length - 1;
    return math.min(_segmentIndex, route.instructions.length - 1);
  }

  RouteInstruction get currentInstruction =>
      route.instructions[currentInstructionIndex];

  double get travelledUnits {
    var travelled = _segmentOffset;
    for (var index = 0; index < _segmentIndex; index++) {
      travelled += route.edges[index].distance;
    }
    return travelled.clamp(0, route.routeCost).toDouble();
  }

  double get remainingUnits =>
      math.max(0, route.routeCost - travelledUnits).toDouble();

  double get progress {
    if (route.routeCost <= 0) return 1;
    return (travelledUnits / route.routeCost).clamp(0, 1).toDouble();
  }

  Duration get demoRemainingDuration => Duration(
    seconds: (remainingUnits / demoWalkingSpeedUnitsPerSecond).ceil(),
  );

  void start() {
    if (hasArrived) reset();
    if (route.edges.isEmpty) {
      _status = NavigationSessionStatus.arrived;
      notifyListeners();
      return;
    }

    _status = NavigationSessionStatus.navigating;
    _startClock();
    notifyListeners();
  }

  void pause() {
    if (!isPlaying) return;
    _timer?.cancel();
    _clock = null;
    _status = NavigationSessionStatus.paused;
    notifyListeners();
  }

  void toggle() => isPlaying ? pause() : start();

  void reset() {
    _timer?.cancel();
    _clock = null;
    _segmentIndex = 0;
    _segmentOffset = 0;
    _status = NavigationSessionStatus.ready;
    _position = _sampleAt(route.nodes.first, headingDegrees: 0);
    notifyListeners();
  }

  void setPlaybackSpeed(double value) {
    _playbackSpeed = value.clamp(.5, 2).toDouble();
    notifyListeners();
  }

  /// Atualiza a sessão a partir de uma posição física já fundida e casada com
  /// o grafo. O progresso é projetado no segmento de rota mais próximo.
  void applyExternalPosition(PositionSample sample) {
    if (route.nodes.length == 1) {
      _position = sample;
      notifyListeners();
      return;
    }

    var bestSegment = 0;
    var bestOffset = 0.0;
    var bestDistanceSquared = double.infinity;
    for (var index = 0; index < route.edges.length; index++) {
      final from = route.nodes[index];
      final to = route.nodes[index + 1];
      if (from.floor != sample.floor && to.floor != sample.floor) continue;
      final dx = to.x - from.x;
      final dy = to.y - from.y;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared <= .000001
          ? 0.0
          : (((sample.x - from.x) * dx + (sample.y - from.y) * dy) /
                    lengthSquared)
                .clamp(0, 1)
                .toDouble();
      final px = from.x + dx * t;
      final py = from.y + dy * t;
      final distanceSquared =
          math.pow(sample.x - px, 2).toDouble() +
          math.pow(sample.y - py, 2).toDouble();
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestSegment = index;
        bestOffset = route.edges[index].distance * t;
      }
    }
    _segmentIndex = bestSegment;
    _segmentOffset = bestOffset;
    _position = sample;
    if (_status == NavigationSessionStatus.ready ||
        _status == NavigationSessionStatus.paused) {
      _status = NavigationSessionStatus.navigating;
    }
    if (bestSegment == route.edges.length - 1 &&
        bestOffset >= route.edges.last.distance * .96) {
      _status = NavigationSessionStatus.arrived;
    }
    notifyListeners();
  }

  /// Avança a sessão. Público para permitir replays determinísticos e testes.
  void advance(Duration elapsed) {
    if (!isPlaying || hasArrived || elapsed <= Duration.zero) return;

    var movement =
        elapsed.inMicroseconds /
        Duration.microsecondsPerSecond *
        _simulationUnitsPerSecond *
        _playbackSpeed;

    while (movement > 0 && _segmentIndex < route.edges.length) {
      final edge = route.edges[_segmentIndex];
      final edgeLength = math.max(edge.distance, .0001);
      final available = edgeLength - _segmentOffset;

      if (movement >= available) {
        movement -= available;
        _segmentIndex++;
        _segmentOffset = 0;

        if (_segmentIndex >= route.edges.length) {
          _position = _sampleAt(
            route.nodes.last,
            headingDegrees: _position.headingDegrees,
          );
          _status = NavigationSessionStatus.arrived;
          _timer?.cancel();
          _clock = null;
          break;
        }
      } else {
        _segmentOffset += movement;
        movement = 0;
      }

      if (_segmentIndex < route.edges.length) _updateInterpolatedPosition();
    }

    notifyListeners();
  }

  void _startClock() {
    _timer?.cancel();
    if (!autoTick) return;

    _clock = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(milliseconds: 32), (_) {
      final clock = _clock;
      if (clock == null) return;
      final elapsed = clock.elapsed;
      clock.reset();
      advance(elapsed);
    });
  }

  void _updateInterpolatedPosition() {
    final from = route.nodes[_segmentIndex];
    final to = route.nodes[_segmentIndex + 1];
    final edge = route.edges[_segmentIndex];
    final edgeLength = math.max(edge.distance, .0001);
    final t = (_segmentOffset / edgeLength).clamp(0, 1).toDouble();
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final heading = dx == 0 && dy == 0
        ? _position.headingDegrees
        : math.atan2(dy, dx) * 180 / math.pi;
    final openArea = edge.type == 'open_area' || edge.type == 'outdoor';
    final confidence = _confidenceEngine.evaluate(
      sensorConfidence: openArea ? .84 : .92,
      mapMatchDistanceUnits: 0,
      headingDriftDegrees: edge.type == 'ramp' ? 10 : 4,
    );

    _position = PositionSample(
      x: _lerp(from.x, to.x, t),
      y: _lerp(from.y, to.y, t),
      z: _lerp(from.z, to.z, t),
      floor: from.floor == to.floor
          ? from.floor
          : (t < .5 ? from.floor : to.floor),
      headingDegrees: heading,
      accuracyMeters: openArea ? 3.8 : 1.8,
      confidence: confidence.score,
      timestamp: DateTime.now(),
    );
  }

  PositionSample _sampleAt(
    NavigationNode node, {
    required double headingDegrees,
  }) {
    final confidence = _confidenceEngine.evaluate(
      sensorConfidence: .94,
      mapMatchDistanceUnits: 0,
      headingDriftDegrees: 0,
      hasRecentAnchor: true,
    );
    return PositionSample(
      x: node.x,
      y: node.y,
      z: node.z,
      floor: node.floor,
      headingDegrees: headingDegrees,
      accuracyMeters: 1.8,
      confidence: confidence.score,
      timestamp: DateTime.now(),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
