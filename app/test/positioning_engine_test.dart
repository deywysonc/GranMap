import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/positioning/map_matcher.dart';
import 'package:granmap/positioning/position_confidence_engine.dart';
import 'package:granmap/positioning/position_sample.dart';

void main() {
  test('Map Matching projeta uma amostra no corredor mais próximo', () {
    final result = const MapMatcher().match(
      campus: _campus(),
      sample: PositionSample(
        x: 4,
        y: 3,
        z: 0,
        floor: 0,
        headingDegrees: 0,
        accuracyMeters: 2,
        confidence: .8,
        timestamp: DateTime(2026),
      ),
    );

    expect(result.position.x, closeTo(4, .001));
    expect(result.position.y, closeTo(0, .001));
    expect(result.distanceUnits, closeTo(3, .001));
    expect(result.edge?.from, 'a');
    expect(result.confidence, greaterThan(.7));
  });

  test('confiança diferencia posição confiável de localização perdida', () {
    const engine = PositionConfidenceEngine();
    final reliable = engine.evaluate(
      sensorConfidence: .92,
      mapMatchDistanceUnits: .5,
      headingDriftDegrees: 4,
      hasRecentAnchor: true,
    );
    final lost = engine.evaluate(
      sensorConfidence: .15,
      mapMatchDistanceUnits: 30,
      headingDriftDegrees: 150,
    );

    expect(reliable.level, PositionConfidenceLevel.reliable);
    expect(reliable.score, greaterThan(.85));
    expect(lost.level, PositionConfidenceLevel.lost);
    expect(lost.score, lessThan(.2));
  });
}

CampusMap _campus() {
  return const CampusMap(
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
}
