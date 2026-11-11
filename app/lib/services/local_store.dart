import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../community/community_models.dart';
import '../config/api_config.dart';
import '../models/academic.dart';
import '../models/personal_data.dart';
import '../models/user.dart';
import '../storage/offline_database.dart';
import '../storage/secure_session_store.dart';

class LocalStore {
  static const _ioTimeout = Duration(milliseconds: 1200);

  final SharedPreferencesAsync _prefs;
  final OfflineDatabase _database;
  late final SecureSessionStore _secureSession;
  final Map<String, String> _memoryCache = <String, String>{};

  LocalStore({SharedPreferencesAsync? prefs, OfflineDatabase? database})
    : _prefs = prefs ?? SharedPreferencesAsync(),
      _database = database ?? OfflineDatabase() {
    _secureSession = SecureSessionStore(webPreferences: _prefs);
  }

  static const _userKey = 'granmap.auth.user';

  String _scopeKey(String base, String scope) => 'granmap.$base.$scope';

  bool get _usesDatabase =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _write(String key, String value) async {
    _memoryCache[key] = value;
    try {
      await _prefs.setString(key, value).timeout(_ioTimeout);
    } catch (_) {}

    if (_usesDatabase) {
      try {
        await _database.put(key, value).timeout(_ioTimeout);
      } catch (_) {}
    }
  }

  Future<String?> _read(String key) async {
    try {
      final prefVal = await _prefs.getString(key).timeout(_ioTimeout);
      if (prefVal != null) {
        _memoryCache[key] = prefVal;
        return prefVal;
      }
    } catch (_) {}
    if (_usesDatabase) {
      try {
        final dbVal = await _database.read(key).timeout(_ioTimeout);
        if (dbVal != null) {
          _memoryCache[key] = dbVal;
          return dbVal;
        }
      } catch (_) {}
    }
    return _memoryCache[key];
  }

  Future<void> _remove(String key) async {
    _memoryCache.remove(key);
    try {
      await _prefs.remove(key).timeout(_ioTimeout);
    } catch (_) {}
    if (_usesDatabase) {
      try {
        await _database.remove(key).timeout(_ioTimeout);
      } catch (_) {}
    }
  }

  Future<void> saveSession(String token, AppUser user) async {
    await _secureSession.writeToken(token);
    await _write(_userKey, jsonEncode(user.toJson()));
  }

  Future<String?> readToken() => _secureSession.readToken();

  Future<AppUser?> readUser() async {
    final raw = await _read(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSession() async {
    await _secureSession.clearToken();
    await _remove(_userKey);
  }

  Future<void> saveRuntimeConfig(Map<String, dynamic> config) async {
    await _write(
      'granmap.runtime.config',
      jsonEncode({
        'cached_at': DateTime.now().toIso8601String(),
        'config': config,
      }),
    );
  }

  Future<Map<String, dynamic>?> readRuntimeConfig() async {
    final raw = await _read('granmap.runtime.config');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded['config'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePublishedMap(Map<String, dynamic> publication) async {
    await _write('granmap.map.published', jsonEncode(publication));
  }

  Future<Map<String, dynamic>?> readPublishedMap() async {
    final raw = await _read('granmap.map.published');
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRouteClosures(List<Map<String, dynamic>> closures) async {
    await _write('granmap.map.closures', jsonEncode(closures));
  }

  Future<List<Map<String, dynamic>>> readRouteClosures() async {
    final raw = await _read('granmap.map.closures');
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveNotifications(
    String scope,
    List<Map<String, dynamic>> notifications,
  ) async {
    await _write(
      _scopeKey('notifications', scope),
      jsonEncode({
        'cached_at': DateTime.now().toIso8601String(),
        'items': notifications,
      }),
    );
  }

  Future<List<Map<String, dynamic>>> readNotifications(String scope) async {
    final raw = await _read(_scopeKey('notifications', scope));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return (data['items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCachedSchedule(
    String scope,
    List<AcademicClass> classes,
  ) async {
    final payload = {
      'cached_at': DateTime.now().toIso8601String(),
      'classes': classes.map((item) => item.toJson()).toList(),
    };

    await _write(_scopeKey('schedule', scope), jsonEncode(payload));
  }

  Future<AcademicSnapshot?> readCachedSchedule(String scope) async {
    final raw = await _read(_scopeKey('schedule', scope));
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final items = (json['classes'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(AcademicClass.fromApi)
          .toList(growable: false);

      return AcademicSnapshot(
        classes: items,
        source: AcademicDataSource.cache,
        cachedAt: DateTime.tryParse((json['cached_at'] ?? '') as String),
        message: 'Dados acadêmicos carregados do cache deste aparelho.',
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> readFavorites(String scope) async {
    final key = _scopeKey('favorites', scope);
    if (!_usesDatabase) {
      try {
        final values = await _prefs.getStringList(key).timeout(_ioTimeout);
        if (values != null) return values;
      } catch (_) {}
      final cached = _memoryCache[key];
      if (cached == null) return <String>[];
      try {
        return (jsonDecode(cached) as List<dynamic>)
            .map((item) => '$item')
            .toList();
      } catch (_) {
        return <String>[];
      }
    }
    String? raw;
    try {
      raw = await _database.read(key).timeout(_ioTimeout);
    } catch (_) {}
    raw ??= _memoryCache[key];
    if (raw == null) return <String>[];
    try {
      return (jsonDecode(raw) as List<dynamic>).map((item) => '$item').toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> saveFavorites(String scope, List<String> ids) async {
    final clean = ids.toSet().toList()..sort();
    final encoded = jsonEncode(clean);
    final key = _scopeKey('favorites', scope);
    _memoryCache[key] = encoded;
    if (_usesDatabase) {
      try {
        await _database.put(key, encoded).timeout(_ioTimeout);
      } catch (_) {}
    } else {
      try {
        await _prefs.setStringList(key, clean).timeout(_ioTimeout);
      } catch (_) {}
    }
  }

  Future<FavoriteState> readFavoriteState(String scope) async {
    final raw = await _read(_scopeKey('favorites.state', scope));
    if (raw != null && raw.isNotEmpty) {
      try {
        return FavoriteState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Recupera favoritos guardados antes da fila de sincronização.
      }
    }
    return FavoriteState(ids: await readFavorites(scope));
  }

  Future<void> saveFavoriteState(String scope, FavoriteState state) =>
      _write(_scopeKey('favorites.state', scope), jsonEncode(state.toJson()));

  Future<List<NavigationHistoryItem>> readHistory(String scope) async {
    final raw = await _read(_scopeKey('history', scope));
    if (raw == null || raw.isEmpty) return <NavigationHistoryItem>[];

    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .cast<Map<String, dynamic>>()
          .map(NavigationHistoryItem.fromJson)
          .toList(growable: false);
    } catch (_) {
      return <NavigationHistoryItem>[];
    }
  }

  Future<void> saveHistory(
    String scope,
    List<NavigationHistoryItem> history,
  ) async {
    final data = history.take(50).map((item) => item.toJson()).toList();
    await _write(_scopeKey('history', scope), jsonEncode(data));
  }

  Future<List<RoomChangeContribution>> readCachedProposals(String scope) async {
    final raw = await _read(_scopeKey('community.proposals', scope));
    if (raw == null || raw.isEmpty) return <RoomChangeContribution>[];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .cast<Map<String, dynamic>>()
          .map(RoomChangeContribution.fromJson)
          .toList(growable: false);
    } catch (_) {
      return <RoomChangeContribution>[];
    }
  }

  Future<CommunityState> readCommunityState(
    String scope, {
    required String backend,
  }) async {
    final key = _scopeKey(
      'community.state.v1.${Uri.encodeComponent(backend)}',
      scope,
    );
    final raw = await _read(key);
    if (raw != null && raw.isNotEmpty) {
      // Corruption is surfaced; silently treating it as an empty outbox loses
      // previously accepted offline work on the next write.
      return CommunityState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    if (backend.replaceFirst(RegExp(r'/+$'), '') !=
        ApiConfig.baseUrl.replaceFirst(RegExp(r'/+$'), '')) {
      // Legacy records did not record their server. Only the installation's
      // configured backend may claim them; never replay them on a test/other API.
      const empty = CommunityState();
      await saveCommunityState(scope, empty, backend: backend);
      return empty;
    }
    final proposalRaw = await _read(_scopeKey('community.proposals', scope));
    final contributions = proposalRaw == null || proposalRaw.isEmpty
        ? <RoomChangeContribution>[]
        : (jsonDecode(proposalRaw) as List<dynamic>)
              .map(
                (item) => RoomChangeContribution.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
    final List<Map<String, dynamic>> operations;
    if (_usesDatabase) {
      operations = await _database.readOutbox(scope);
    } else {
      final queueRaw = await _prefs.getString(
        _scopeKey('community.queue', scope),
      );
      operations = queueRaw == null || queueRaw.isEmpty
          ? <Map<String, dynamic>>[]
          : (jsonDecode(queueRaw) as List<dynamic>)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
    }
    final migratedOperations = <Map<String, dynamic>>[];
    final voteVersions = <String, int>{};
    for (var index = 0; index < operations.length; index++) {
      final operation = Map<String, dynamic>.from(operations[index]);
      final id =
          operation['operation_id'] ??
          'legacy-$index-${operation['idempotency_key'] ?? operation['local_id'] ?? 'operation'}';
      operation['operation_id'] = id;
      operation['idempotency_key'] ??= id;
      if (operation['type'] == 'vote') {
        final version =
            (operation['intent_version'] as num?)?.toInt() ??
            DateTime.now().microsecondsSinceEpoch + index;
        operation['intent_version'] = version;
        final proposalId = operation['proposal_id'].toString();
        if (version > (voteVersions[proposalId] ?? 0)) {
          voteVersions[proposalId] = version;
        }
      }
      migratedOperations.add(operation);
    }
    final migrated = CommunityState(
      contributions: contributions,
      operations: migratedOperations,
      voteVersions: voteVersions,
    );
    await saveCommunityState(scope, migrated, backend: backend);
    // Keep both legacy records intact so migration is recoverable.
    return migrated;
  }

  Future<void> saveCommunityState(
    String scope,
    CommunityState state, {
    required String backend,
  }) => _write(
    _scopeKey('community.state.v1.${Uri.encodeComponent(backend)}', scope),
    jsonEncode(state.toJson()),
  );

  Future<void> saveCachedProposals(
    String scope,
    List<RoomChangeContribution> proposals,
  ) async {
    await _write(
      _scopeKey('community.proposals', scope),
      jsonEncode(proposals.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<Map<String, dynamic>>> readCommunityQueue(String scope) async {
    if (_usesDatabase) return _database.readOutbox(scope);
    final raw = await _prefs.getString(_scopeKey('community.queue', scope));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> saveCommunityQueue(
    String scope,
    List<Map<String, dynamic>> operations,
  ) async {
    if (_usesDatabase) {
      await _database.replaceOutbox(scope, operations);
      return;
    }
    await _prefs.setString(
      _scopeKey('community.queue', scope),
      jsonEncode(operations),
    );
  }
}
