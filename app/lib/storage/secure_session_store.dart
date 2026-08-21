import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureSessionStore {
  static const _tokenKey = 'granmap.auth.token';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferencesAsync _webPreferences;

  SecureSessionStore({
    FlutterSecureStorage? secureStorage,
    SharedPreferencesAsync? webPreferences,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _webPreferences = webPreferences ?? SharedPreferencesAsync();

  Future<void> writeToken(String token) async {
    if (kIsWeb) {
      // Exclusivo da demo Web. Aplicativos comerciais usam Keychain/Keystore.
      await _webPreferences.setString(_tokenKey, token);
      return;
    }
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<String?> readToken() async {
    if (kIsWeb) return _webPreferences.getString(_tokenKey);
    return _secureStorage.read(key: _tokenKey);
  }

  Future<void> clearToken() async {
    if (kIsWeb) {
      await _webPreferences.remove(_tokenKey);
      return;
    }
    await _secureStorage.delete(key: _tokenKey);
  }
}
