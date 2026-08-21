import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/navigation/navigation_session.dart';
import 'package:granmap/navigation/route_result.dart';

void main() {
  test('sessão interpola posição e métricas continuamente', () {
    final session = NavigationSession(route: _linearRoute(), autoTick: false);

    session.start();
    session.advance(const Duration(milliseconds: 500));

    expect(session.position.x, closeTo(6, .001));
    expect(session.position.y, 0);
    expect(session.progress, closeTo(.25, .001));
    expect(session.remainingUnits, closeTo(18, .001));
    expect(session.status, NavigationSessionStatus.navigating);

    session.advance(const Duration(milliseconds: 1500));

    expect(session.position.x, 12);
    expect(session.position.y, 12);
    expect(session.progress, 1);
    expect(session.remainingUnits, 0);
    expect(session.status, NavigationSessionStatus.arrived);
    session.dispose();
  });

  test('troca o piso durante a conexão vertical', () {
    final route = RouteResult(
      nodes: const [
        NavigationNode(id: 'ground', floor: 0, x: 2, y: 3, z: 0, type: 'ramp'),
        NavigationNode(id: 'upper', floor: 1, x: 2, y: 3, z: 1, type: 'ramp'),
      ],
      edges: const [
        NavigationEdge(
          from: 'ground',
          to: 'upper',
          distance: 12,
          type: 'ramp',
          accessible: true,
        ),
      ],
      instructions: const [
        RouteInstruction(title: 'Suba', detail: 'Use a rampa.', type: 'ramp'),
        RouteInstruction(title: 'Chegou', detail: 'Destino.', type: 'arrival'),
      ],
      routeCost: 12,
    );
    final session = NavigationSession(route: route, autoTick: false)..start();

    session.advance(const Duration(milliseconds: 400));
    expect(session.currentFloor, 0);
    expect(session.position.z, closeTo(.4, .001));

    session.advance(const Duration(milliseconds: 200));
    expect(session.currentFloor, 1);
    expect(session.position.z, closeTo(.6, .001));
    session.dispose();
  });

  test('pausa impede avanço até a retomada', () {
    final session = NavigationSession(route: _linearRoute(), autoTick: false)
      ..start()
      ..advance(const Duration(milliseconds: 250))
      ..pause();
    final pausedX = session.position.x;

    session.advance(const Duration(seconds: 1));
    expect(session.position.x, pausedX);

    session.start();
    session.advance(const Duration(milliseconds: 250));
    expect(session.position.x, greaterThan(pausedX));
    session.dispose();
  });
}

RouteResult _linearRoute() {
  return RouteResult(
    nodes: const [
      NavigationNode(id: 'a', floor: 0, x: 0, y: 0, z: 0, type: 'corridor'),
      NavigationNode(id: 'b', floor: 0, x: 12, y: 0, z: 0, type: 'corridor'),
      NavigationNode(id: 'c', floor: 0, x: 12, y: 12, z: 0, type: 'door'),
    ],
    edges: const [
      NavigationEdge(
        from: 'a',
        to: 'b',
        distance: 12,
        type: 'corridor',
        accessible: true,
      ),
      NavigationEdge(
        from: 'b',
        to: 'c',
        distance: 12,
        type: 'door',
        accessible: true,
      ),
    ],
    instructions: const [
      RouteInstruction(title: 'Siga', detail: 'Continue.', type: 'walk'),
      RouteInstruction(title: 'Entre', detail: 'Use a porta.', type: 'door'),
      RouteInstruction(title: 'Chegou', detail: 'Destino.', type: 'arrival'),
    ],
    routeCost: 24,
  );
}
