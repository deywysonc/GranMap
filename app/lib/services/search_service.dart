import '../models/campus_map.dart';

class SearchService {
  const SearchService();

  static const _typeLabels = <String, String>{
    'administration': 'administracao secretaria atendimento',
    'agronomy': 'agronomia plantacao',
    'auditorium': 'auditorio',
    'cafeteria': 'lanchonete lanche comida cantina',
    'classroom': 'sala aula',
    'clinic': 'clinica escola',
    'construction': 'obra construcao',
    'court': 'quadra esporte',
    'entrance': 'entrada acesso portao',
    'upper_entrance': 'entrada acesso portao superior',
    'finance': 'financeiro pagamento boleto',
    'laboratory': 'laboratorio lab',
    'library': 'biblioteca livros estudo',
    'ramp': 'rampa acessibilidade piso',
    'restroom': 'banheiro sanitarios toalete wc',
    'staff_room': 'sala professores docente',
  };

  List<CampusPoi> search(List<CampusPoi> pois, String query) {
    final normalized = _normalize(query);

    if (normalized.isEmpty) return List<CampusPoi>.from(pois);

    final scored = <(CampusPoi, int)>[];
    for (final poi in pois) {
      final score = _score(poi, normalized);
      if (score > 0) scored.add((poi, score));
    }

    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$1.name.compareTo(b.$1.name);
    });
    return scored.map((item) => item.$1).toList(growable: false);
  }

  int _score(CampusPoi poi, String query) {
    final name = _normalize(poi.name);
    final type = _normalize(poi.type);
    final sector = _normalize(poi.sector);
    final aliases = _typeLabels[type] ?? type;
    final searchable = '$name $sector $aliases';
    if (name == query) return 1000;
    if (name.startsWith(query)) return 850;
    if (name.contains(query)) return 720;
    if (searchable.split(' ').any((word) => word.startsWith(query))) return 620;
    if (searchable.contains(query)) return 560;

    if (query.length < 4) return 0;
    var bestDistance = query.length;
    for (final word in searchable.split(RegExp(r'[^a-z0-9]+'))) {
      if (word.length < 3 || (word.length - query.length).abs() > 2) continue;
      final distance = _editDistance(query, word, maximum: 2);
      if (distance < bestDistance) bestDistance = distance;
    }
    return bestDistance <= 2 ? 360 - (bestDistance * 80) : 0;
  }

  int _editDistance(String source, String target, {required int maximum}) {
    if ((source.length - target.length).abs() > maximum) return maximum + 1;
    var previous = List<int>.generate(target.length + 1, (index) => index);
    for (var row = 1; row <= source.length; row++) {
      final current = List<int>.filled(target.length + 1, 0)..[0] = row;
      var rowMinimum = current[0];
      for (var column = 1; column <= target.length; column++) {
        final substitution =
            previous[column - 1] +
            (source.codeUnitAt(row - 1) == target.codeUnitAt(column - 1)
                ? 0
                : 1);
        current[column] = _minimum(
          previous[column] + 1,
          current[column - 1] + 1,
          substitution,
        );
        if (current[column] < rowMinimum) rowMinimum = current[column];
      }
      if (rowMinimum > maximum) return maximum + 1;
      previous = current;
    }
    return previous.last;
  }

  int _minimum(int first, int second, int third) {
    final pair = first < second ? first : second;
    return pair < third ? pair : third;
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .trim();
  }
}
