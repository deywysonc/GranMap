import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../community/community_models.dart';
import '../models/academic.dart';
import '../models/personal_data.dart';
import '../models/user.dart';
import '../storage/offline_database.dart';
import '../storage/secure_session_store.dart';

class LocalStore {
  final SharedPreferencesAsync _prefs;
  final OfflineDatabase _database;
  late final SecureSessionStore _secureSession;

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

  Future<void> _write(String key, String value) =>
      _usesDatabase ? _database.put(key, value) : _prefs.setString(key, value);

  Future<String?> _read(String key) =>
      _usesDatabase ? _database.read(key) : _prefs.getString(key);

  Future<void> _remove(String key) =>
      _usesDatabase ? _database.remove(key) : _prefs.remove(key);

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
    if (!_usesDatabase) return await _prefs.getStringList(key) ?? <String>[];
    final raw = await _database.read(key);
    if (raw == null) return <String>[];
    return (jsonDecode(raw) as List<dynamic>).map((item) => '$item').toList();
  }

  Future<void> saveFavorites(String scope, List<String> ids) async {
    final clean = ids.toSet().toList()..sort();
    final key = _scopeKey('favorites', scope);
    if (_usesDatabase) {
      await _database.put(key, jsonEncode(clean));
    } else {
      await _prefs.setStringList(key, clean);
    }
  }

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
