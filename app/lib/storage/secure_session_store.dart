import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureSessionStore {
  static const _tokenKey = 'granmap.auth.token';
  static const _fallbackTokenKey = 'granmap.auth.token_fallback';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferencesAsync _preferences;

  SecureSessionStore({
    FlutterSecureStorage? secureStorage,
    SharedPreferencesAsync? webPreferences,
  }) : _secureStorage = secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: true),
           ),
       _preferences = webPreferences ?? SharedPreferencesAsync();

  Future<void> writeToken(String token) async {
    try {
      await _preferences.setString(_fallbackTokenKey, token);
    } catch (_) {}

    if (kIsWeb) {
      await _preferences.setString(_tokenKey, token);
      return;
    }
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (_) {
      try {
        await _secureStorage.deleteAll();
        await _secureStorage.write(key: _tokenKey, value: token);
      } catch (_) {}
    }
  }

  Future<String?> readToken() async {
    if (kIsWeb) return _preferences.getString(_tokenKey);
    try {
      final token = await _secureStorage.read(key: _tokenKey);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}
    try {
      return await _preferences.getString(_fallbackTokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearToken() async {
    try {
      await _preferences.remove(_tokenKey);
    } catch (_) {}
    try {
      await _preferences.remove(_fallbackTokenKey);
    } catch (_) {}
    if (!kIsWeb) {
      try {
        await _secureStorage.delete(key: _tokenKey);
      } catch (_) {}
    }
  }
}
