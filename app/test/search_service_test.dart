import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/services/search_service.dart';

void main() {
  test('Busca encontra sala por número', () {
    const pois = [
      CampusPoi(
        id: '1',
        name: 'Sala 202',
        type: 'classroom',
        floor: 1,
        x: 0,
        y: 0,
        z: 0,
        navigationNode: 'n1',
      ),
      CampusPoi(
        id: '2',
        name: 'Laboratório 1',
        type: 'laboratory',
        floor: 1,
        x: 0,
        y: 0,
        z: 0,
        navigationNode: 'n2',
      ),
    ];

    final result = const SearchService().search(pois, '202');
    expect(result.length, 1);
    expect(result.first.name, 'Sala 202');
  });
}
