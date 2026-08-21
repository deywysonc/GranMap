import '../models/campus_map.dart';

class SearchService {
  const SearchService();

  List<CampusPoi> search(List<CampusPoi> pois, String query) {
    final normalized = _normalize(query);

    if (normalized.isEmpty) return List<CampusPoi>.from(pois);

    final results = pois.where((poi) {
      final name = _normalize(poi.name);
      final type = _normalize(poi.type);
      return name.contains(normalized) || type.contains(normalized);
    }).toList();

    results.sort((a, b) {
      final aName = _normalize(a.name);
      final bName = _normalize(b.name);
      final aStarts = aName.startsWith(normalized);
      final bStarts = bName.startsWith(normalized);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    return results;
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
