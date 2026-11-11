import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureSessionStore {
  static const _tokenKey = 'granmap.auth.token';
  static const _fallbackTokenKey = 'granmap.auth.token_fallback';
  static const _opTimeout = Duration(milliseconds: 1200);

  final FlutterSecureStorage _secureStorage;
  final SharedPreferencesAsync _preferences;
  String? _memoryToken;

  SecureSessionStore({
    FlutterSecureStorage? secureStorage,
    SharedPreferencesAsync? webPreferences,
  }) : _secureStorage = secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: true),
           ),
       _preferences = webPreferences ?? SharedPreferencesAsync();

  Future<void> writeToken(String token) async {
    _memoryToken = token;
    try {
      await _preferences
          .setString(_fallbackTokenKey, token)
          .timeout(_opTimeout);
    } catch (_) {}

    if (kIsWeb) {
      try {
        await _preferences.setString(_tokenKey, token).timeout(_opTimeout);
      } catch (_) {}
      return;
    }
    try {
      await _secureStorage
          .write(key: _tokenKey, value: token)
          .timeout(_opTimeout);
    } catch (_) {}
  }

  Future<String?> readToken() async {
    if (kIsWeb) {
      try {
        final token = await _preferences
            .getString(_tokenKey)
            .timeout(_opTimeout);
        if (token != null && token.isNotEmpty) {
          _memoryToken = token;
          return token;
        }
      } catch (_) {}
      return _memoryToken;
    }
    try {
      final fallback = await _preferences
          .getString(_fallbackTokenKey)
          .timeout(_opTimeout);
      if (fallback != null && fallback.isNotEmpty) {
        _memoryToken = fallback;
        return fallback;
      }
    } catch (_) {}
    try {
      final token = await _secureStorage
          .read(key: _tokenKey)
          .timeout(_opTimeout);
      if (token != null && token.isNotEmpty) {
        _memoryToken = token;
        return token;
      }
    } catch (_) {}
    return _memoryToken;
  }

  Future<void> clearToken() async {
    _memoryToken = null;
    try {
      await _preferences.remove(_tokenKey).timeout(_opTimeout);
    } catch (_) {}
    try {
      await _preferences.remove(_fallbackTokenKey).timeout(_opTimeout);
    } catch (_) {}
    if (!kIsWeb) {
      try {
        await _secureStorage.delete(key: _tokenKey).timeout(_opTimeout);
      } catch (_) {}
    }
  }
}
