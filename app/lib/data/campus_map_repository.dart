import 'dart:async';
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
  final AssetBundle _assets;
  final Duration storageTimeout;
  final Duration requestTimeout;

  // Only the untouched built-in v11 seed is superseded. A publication edited
  // through Admin, even with an older-looking name, keeps institutional priority.
  static const _legacyV11Checksum =
      'c950c72596f5b62989a248ed11d9b0734f1ef68fb7ae5b0c3462731e293f5c88';

  CampusMapRepository({
    GranMapApi? api,
    LocalStore? store,
    AssetBundle? assets,
    this.storageTimeout = const Duration(seconds: 2),
    this.requestTimeout = const Duration(seconds: 5),
    // Keep injected dependencies private while exposing usable named arguments.
    // ignore: prefer_initializing_formals
  }) : _api = api,
       // ignore: prefer_initializing_formals
       _store = store,
       _assets = assets ?? rootBundle;

  Future<CampusMapSnapshot> loadCampus() async {
    Map<String, dynamic>? cached;
    List<Map<String, dynamic>> cachedClosures = const [];
    try {
      final store = _store ??= LocalStore();
      cached = await store.readPublishedMap().timeout(storageTimeout);
      cachedClosures = await store.readRouteClosures().timeout(storageTimeout);
    } catch (_) {
      // Primeira abertura ou testes sem plugin seguem para rede/asset.
    }

    try {
      final api = _api ??= GranMapApi();
      final store = _store ??= LocalStore();
      final fetched = await api
          .fetchCurrentMapConditional(etag: cached?['_etag']?.toString())
          .timeout(requestTimeout);
      final publication = fetched.notModified ? cached : fetched.data;
      if (publication == null) {
        throw const ApiException('O cache do mapa está incompleto.', 500);
      }
      _validatePublication(publication);

      var closures = cachedClosures;
      try {
        closures = await api.fetchRouteClosures().timeout(requestTimeout);
        unawaited(_saveSafely(() => store.saveRouteClosures(closures)));
      } catch (_) {
        // Um erro nos bloqueios não descarta uma versão válida do mapa.
      }

      final cachedAt = DateTime.now();
      if (!fetched.notModified) {
        final stored = Map<String, dynamic>.from(publication)
          ..['_etag'] = fetched.etag
          ..['_cached_at'] = cachedAt.toIso8601String();
        unawaited(_saveSafely(() => store.savePublishedMap(stored)));
      }
      if (_isLegacySeed(publication)) {
        return await _updatedBundled(
          closures,
          online: true,
          updatedAt: cachedAt,
        );
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
          if (_isLegacySeed(cached)) {
            return await _updatedBundled(cachedClosures, online: false);
          }
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

    return loadBundledCampus();
  }

  Future<CampusMapSnapshot> loadBundledCampus() async {
    final jsonString = await _assets.loadString(
      'assets/maps/gran_tiete_floorplan_v12.json',
    );

    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return CampusMapSnapshot(
      campus: CampusMap.fromJson(json),
      blockedEdgeIds: const {},
      version: 'floorplan-v12-bundled',
      source: CampusMapSource.bundled,
      warning: 'Usando o mapa incluído no aplicativo; bloqueios recentes podem não aparecer.',
    );
  }

  Future<void> _saveSafely(Future<void> Function() save) async {
    try {
      await save().timeout(storageTimeout);
    } catch (_) {
      // Valid map data remains usable when native storage is unavailable.
    }
  }

  bool _isLegacySeed(Map<String, dynamic> publication) =>
      publication['version'] == 'upper-floorplan-v11' &&
      publication['checksum'] == _legacyV11Checksum;

  Future<CampusMapSnapshot> _updatedBundled(
    List<Map<String, dynamic>> closures, {
    required bool online,
    DateTime? updatedAt,
  }) async {
    final bundled = await loadBundledCampus();
    return CampusMapSnapshot(
      campus: bundled.campus,
      blockedEdgeIds: _translatedClosureIds(closures),
      version: bundled.version,
      source: CampusMapSource.bundled,
      updatedAt: updatedAt,
      warning: online
          ? null
          : 'Modo offline — mapa e bloqueios salvos, sem conexão.',
    );
  }

  Set<String> _translatedClosureIds(List<Map<String, dynamic>> closures) {
    final ids = _closureIds(closures);
    const replacements = {
      'ground_c1_end__ground_spiral_ramp_landing': [
        'ground_c1_end__ground_ramp_access_corner',
        'ground_ramp_access_corner__ground_spiral_ramp_landing',
      ],
      'upper_spine_5__upper_spine_6': [
        'upper_spine_5__upper_gallery_turn',
        'upper_gallery_turn__upper_gallery_step',
        'upper_gallery_step__upper_spine_6',
      ],
      'upper_service_spine__upper_bwc_masc': [
        'upper_service_spine__upper_bwc_passage',
        'upper_bwc_passage__upper_bwc_masc',
      ],
      'ground_court_east_north__ground_services_north': [
        'ground_court_east_north__ground_services_north_approach',
      ],
      'ground_services_north__ground_services_mid': [
        'ground_services_north_approach__ground_services_mid_approach',
      ],
      'ground_services_mid__ground_services_south': [
        'ground_services_mid_approach__ground_services_south_approach',
      ],
      'ground_services_south__ground_court_east_south': [
        'ground_services_south_approach__ground_court_east_south',
      ],
    };
    for (final entry in replacements.entries) {
      if (ids.contains(entry.key)) ids.addAll(entry.value);
    }
    return ids;
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
