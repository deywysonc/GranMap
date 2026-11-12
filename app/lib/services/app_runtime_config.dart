import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class AppRuntimeConfig extends ChangeNotifier {
  AppRuntimeConfig._();

  static final AppRuntimeConfig instance = AppRuntimeConfig._();

  final GranMapApi _api = GranMapApi();
  final LocalStore _store = LocalStore();
  bool _initialized = false;
  bool _fromCache = false;
  int _minimumBuild = 1;
  int _latestBuild = ApiConfig.appBuild;
  bool _maintenanceMode = false;
  Map<String, bool> _features = const {
    'ar': true,
    'physical_positioning': true,
    'community_writes': true,
  };

  bool get initialized => _initialized;
  bool get fromCache => _fromCache;
  int get minimumBuild => _minimumBuild;
  int get latestBuild => _latestBuild;
  bool get requiresUpdate => ApiConfig.appBuild < _minimumBuild;
  bool get updateAvailable => ApiConfig.appBuild < _latestBuild;
  bool get maintenanceMode => _maintenanceMode && !_fromCache;
  bool get arEnabled => _features['ar'] ?? false;
  bool get physicalPositioningEnabled =>
      _features['physical_positioning'] ?? false;
  bool get communityWritesEnabled => _features['community_writes'] ?? false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final cached = await _store.readRuntimeConfig();
      if (cached != null) _apply(cached, fromCache: true);
    } catch (_) {
      // Os padrões mantêm o núcleo disponível no primeiro uso offline.
    }
    _initialized = true;
    scheduleMicrotask(notifyListeners);
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final config = await _api.fetchAppConfig();
      _apply(config, fromCache: false);
      await _store.saveRuntimeConfig(config);
    } catch (_) {
      try {
        final cached = await _store.readRuntimeConfig();
        if (cached != null) _apply(cached, fromCache: true);
      } catch (_) {
        // Os padrões mantêm o núcleo disponível no primeiro uso offline.
      }
    }
    notifyListeners();
  }

  void _apply(Map<String, dynamic> config, {required bool fromCache}) {
    final schema = (config['schema_version'] as num?)?.toInt() ?? 1;
    if (schema > 1) return;
    _fromCache = fromCache;
    _minimumBuild = (config['minimum_app_build'] as num?)?.toInt() ?? 1;
    _latestBuild =
        (config['latest_app_build'] as num?)?.toInt() ?? ApiConfig.appBuild;
    _maintenanceMode = config['maintenance_mode'] == true;
    final features = config['features'] as Map<String, dynamic>? ?? const {};
    _features = {
      'ar': features['ar'] != false,
      'physical_positioning': features['physical_positioning'] != false,
      'community_writes': features['community_writes'] != false,
    };
  }
}
