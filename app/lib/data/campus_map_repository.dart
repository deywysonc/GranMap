import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/campus_map.dart';
import '../services/granmap_api.dart';
import '../services/local_store.dart';

enum CampusMapSource { online, cache, bundled }

class CampusMapSnapshot {
  final CampusMap campus;
  final Set<String> blockedEdgeIds;
  final String version;
  final CampusMapSource source;

  const CampusMapSnapshot({
    required this.campus,
    required this.blockedEdgeIds,
    required this.version,
    required this.source,
  });
}

class CampusMapRepository {
  GranMapApi? _api;
  LocalStore? _store;

  CampusMapRepository();

  Future<CampusMapSnapshot> loadCampus() async {
    try {
      final api = _api ??= GranMapApi();
      final store = _store ??= LocalStore();
      final publication = await api.fetchCurrentMap();
      final closures = await api.fetchRouteClosures();
      await Future.wait([
        store.savePublishedMap(publication),
        store.saveRouteClosures(closures),
      ]);
      return CampusMapSnapshot(
        campus: CampusMap.fromJson(
          publication['map_data'] as Map<String, dynamic>,
        ),
        blockedEdgeIds: _closureIds(closures),
        version: publication['version']?.toString() ?? 'desconhecida',
        source: CampusMapSource.online,
      );
    } catch (_) {
      try {
        final store = _store ??= LocalStore();
        final cached = await store.readPublishedMap();
        if (cached != null && cached['map_data'] is Map<String, dynamic>) {
          final closures = await store.readRouteClosures();
          return CampusMapSnapshot(
            campus: CampusMap.fromJson(
              cached['map_data'] as Map<String, dynamic>,
            ),
            blockedEdgeIds: _closureIds(closures),
            version: cached['version']?.toString() ?? 'cache',
            source: CampusMapSource.cache,
          );
        }
      } catch (_) {
        // Testes sem plugin e primeira abertura offline usam o mapa empacotado.
      }
    }

    final jsonString = await rootBundle.loadString(
      'assets/maps/gran_tiete_user_corrected_v10.json',
    );

    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return CampusMapSnapshot(
      campus: CampusMap.fromJson(json),
      blockedEdgeIds: const {},
      version: 'user-corrected-v10-bundled',
      source: CampusMapSource.bundled,
    );
  }

  Set<String> _closureIds(List<Map<String, dynamic>> closures) => closures
      .map((item) => item['edge_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();
}
