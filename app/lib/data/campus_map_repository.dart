import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/campus_map.dart';
import '../services/granmap_api.dart';
import '../services/local_store.dart';

enum CampusMapSource { online, onlineValidated, cache, bundled }

class CampusMapSnapshot {
  final CampusMap campus;
  final Set<String> blockedEdgeIds;
  final String version;
  final CampusMapSource source;
  final DateTime? updatedAt;
  final String? warning;

  const CampusMapSnapshot({
    required this.campus,
    required this.blockedEdgeIds,
    required this.version,
    required this.source,
    this.updatedAt,
    this.warning,
  });

  bool get isStale =>
      updatedAt != null && DateTime.now().difference(updatedAt!).inHours >= 24;
}

class CampusMapRepository {
  GranMapApi? _api;
  LocalStore? _store;

  CampusMapRepository();

  Future<CampusMapSnapshot> loadCampus() async {
    Map<String, dynamic>? cached;
    List<Map<String, dynamic>> cachedClosures = const [];
    try {
      final store = _store ??= LocalStore();
      cached = await store.readPublishedMap();
      cachedClosures = await store.readRouteClosures();
    } catch (_) {
      // Primeira abertura ou testes sem plugin seguem para rede/asset.
    }

    try {
      final api = _api ??= GranMapApi();
      final store = _store ??= LocalStore();
      final fetched = await api.fetchCurrentMapConditional(
        etag: cached?['_etag']?.toString(),
      );
      final publication = fetched.notModified ? cached : fetched.data;
      if (publication == null) {
        throw const ApiException('O cache do mapa está incompleto.', 500);
      }
      _validatePublication(publication);

      var closures = cachedClosures;
      try {
        closures = await api.fetchRouteClosures();
        await store.saveRouteClosures(closures);
      } catch (_) {
        // Um erro nos bloqueios não descarta uma versão válida do mapa.
      }

      final cachedAt = DateTime.now();
      if (!fetched.notModified) {
        final stored = Map<String, dynamic>.from(publication)
          ..['_etag'] = fetched.etag
          ..['_cached_at'] = cachedAt.toIso8601String();
        await store.savePublishedMap(stored);
      }
      return CampusMapSnapshot(
        campus: CampusMap.fromJson(
          publication['map_data'] as Map<String, dynamic>,
        ),
        blockedEdgeIds: _closureIds(closures),
        version: publication['version']?.toString() ?? 'desconhecida',
        source: fetched.notModified
            ? CampusMapSource.onlineValidated
            : CampusMapSource.online,
        updatedAt: fetched.notModified
            ? _cachedAt(publication) ?? cachedAt
            : cachedAt,
      );
    } catch (error) {
      if (cached != null && cached['map_data'] is Map<String, dynamic>) {
        try {
          _validatePublication(cached);
          return CampusMapSnapshot(
            campus: CampusMap.fromJson(
              cached['map_data'] as Map<String, dynamic>,
            ),
            blockedEdgeIds: _closureIds(cachedClosures),
            version: cached['version']?.toString() ?? 'cache',
            source: CampusMapSource.cache,
            updatedAt: _cachedAt(cached),
            warning: _safeWarning(error),
          );
        } catch (_) {
          // Cache inválido não impede o fallback empacotado.
        }
      }
    }

    final jsonString = await rootBundle.loadString(
      'assets/maps/gran_tiete_upper_floorplan_v11.json',
    );

    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return CampusMapSnapshot(
      campus: CampusMap.fromJson(json),
      blockedEdgeIds: const {},
      version: 'upper-floorplan-v11-bundled',
      source: CampusMapSource.bundled,
      warning: 'Usando o mapa incluído no aplicativo; bloqueios recentes podem não aparecer.',
    );
  }

  void _validatePublication(Map<String, dynamic> publication) {
    final schemaVersion = (publication['schema_version'] as num?)?.toInt() ?? 1;
    if (schemaVersion > 1) {
      throw const ApiException(
        'O mapa exige uma versão mais nova do aplicativo.',
        426,
      );
    }
    if (publication['map_data'] is! Map<String, dynamic>) {
      throw const ApiException('O servidor enviou um mapa inválido.', 502);
    }
  }

  DateTime? _cachedAt(Map<String, dynamic> publication) =>
      DateTime.tryParse(publication['_cached_at']?.toString() ?? '') ??
      DateTime.tryParse(publication['published_at']?.toString() ?? '');

  String _safeWarning(Object error) {
    final message = error is ApiException
        ? error.message
        : 'Servidor indisponível.';
    return 'Mapa em cache: $message';
  }

  Set<String> _closureIds(List<Map<String, dynamic>> closures) => closures
      .map((item) => item['edge_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();
}
