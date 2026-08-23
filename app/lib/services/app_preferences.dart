import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences._();

  static final AppPreferences instance = AppPreferences._();

  SharedPreferencesAsync? _preferences;
  bool _initialized = false;
  bool _onboardingCompleted = false;
  bool _locationEnabled = true;
  bool _highContrast = false;
  bool _accessibleRoutes = false;

  bool get initialized => _initialized;
  bool get onboardingCompleted => _onboardingCompleted;
  bool get locationEnabled => _locationEnabled;
  bool get highContrast => _highContrast;
  bool get accessibleRoutes => _accessibleRoutes;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final preferences = _preferences ??= SharedPreferencesAsync();
      final values = await Future.wait<bool?>([
        preferences.getBool('granmap.preferences.onboarding'),
        preferences.getBool('granmap.preferences.location'),
        preferences.getBool('granmap.preferences.high_contrast'),
        preferences.getBool('granmap.preferences.accessible_routes'),
      ]);
      _onboardingCompleted = values[0] ?? false;
      _locationEnabled = values[1] ?? true;
      _highContrast = values[2] ?? false;
      _accessibleRoutes = values[3] ?? false;
    } catch (_) {
      // Testes e plataformas sem plugin continuam com padrões privados.
    }
    _initialized = true;
    scheduleMicrotask(notifyListeners);
  }

  Future<void> completeOnboarding() =>
      _set('granmap.preferences.onboarding', true, (value) {
        _onboardingCompleted = value;
      });

  Future<void> setLocationEnabled(bool value) =>
      _set('granmap.preferences.location', value, (next) {
        _locationEnabled = next;
      });

  Future<void> setHighContrast(bool value) =>
      _set('granmap.preferences.high_contrast', value, (next) {
        _highContrast = next;
      });

  Future<void> setAccessibleRoutes(bool value) =>
      _set('granmap.preferences.accessible_routes', value, (next) {
        _accessibleRoutes = next;
      });

  Future<void> _set(
    String key,
    bool value,
    void Function(bool value) update,
  ) async {
    update(value);
    notifyListeners();
    try {
      final preferences = _preferences ??= SharedPreferencesAsync();
      await preferences.setBool(key, value);
    } catch (_) {
      // A preferência permanece válida durante esta execução.
    }
  }
}
