import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class AppSession extends ChangeNotifier {
  AppSession._();

  static final AppSession instance = AppSession._();

  final LocalStore _store = LocalStore();
  final GranMapApi _api = GranMapApi();

  AppUser? _user;
  String? _token;
  bool _initialized = false;
  bool _backendReachable = false;
  int _unreadNotifications = 0;

  AppUser? get user => _user;
  String? get token => _token;
  bool get initialized => _initialized;
  bool get isLoggedIn => _user != null && _token != null;
  bool get backendReachable => _backendReachable;
  int get unreadNotifications => _unreadNotifications;

  String get storageScope => _user == null ? 'guest' : 'user_${_user!.id}';

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _token = await _store.readToken().timeout(const Duration(seconds: 2));
    } catch (_) {
      _token = null;
    }
    try {
      _user = await _store.readUser().timeout(const Duration(seconds: 2));
    } catch (_) {
      _user = null;
    }
    try {
      _backendReachable = await _api.health();
    } catch (_) {
      _backendReachable = false;
    }

    if (_backendReachable && _token != null) {
      try {
        _user = await _api.fetchMe(_token!);
        await _store.saveSession(_token!, _user!);
      } on ApiException catch (error) {
        if (error.statusCode == 401) {
          await _store.clearSession();
          _token = null;
          _user = null;
        }
      } catch (_) {
        // Mantém a sessão em cache para experiência offline.
      }
      await _refreshNotificationCount(silent: true);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    final result = await _api.login(email: email, password: password);
    _token = result.token;
    _user = result.user;
    _backendReachable = true;
    await _store.saveSession(result.token, result.user);
    await _refreshNotificationCount(silent: true);
    notifyListeners();
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String course,
    required int semester,
    required String group,
  }) async {
    final result = await _api.register(
      name: name,
      email: email,
      password: password,
      course: course,
      semester: semester,
      group: group,
    );

    _token = result.token;
    _user = result.user;
    _backendReachable = true;
    await _store.saveSession(result.token, result.user);
    await _refreshNotificationCount(silent: true);
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String course,
    required int semester,
    required String group,
  }) async {
    if (_token == null || _user == null) return;

    final updated = await _api.updateMe(
      token: _token!,
      name: name,
      course: course,
      semester: semester,
      group: group,
    );

    _user = updated;
    _backendReachable = true;
    await _store.saveSession(_token!, updated);
    notifyListeners();
  }

  Future<void> refreshBackendState() async {
    _backendReachable = await _api.health();
    if (_backendReachable && _token != null) {
      try {
        _user = await _api.fetchMe(_token!);
        await _store.saveSession(_token!, _user!);
      } on ApiException catch (error) {
        if (error.statusCode == 401) {
          await _store.clearSession();
          _token = null;
          _user = null;
        }
      } catch (_) {
        // Preserva a sessão local quando só a atualização falhar.
      }
    }
    notifyListeners();
  }

  Future<void> logout() async {
    final currentToken = _token;
    _token = null;
    _user = null;
    _unreadNotifications = 0;
    await _store.clearSession();
    notifyListeners();

    if (currentToken != null) {
      await _api.logout(currentToken);
    }
  }

  Future<void> refreshNotificationCount() => _refreshNotificationCount();

  Future<void> _refreshNotificationCount({bool silent = false}) async {
    final currentToken = _token;
    if (currentToken == null) {
      _unreadNotifications = 0;
      if (!silent) notifyListeners();
      return;
    }
    try {
      _unreadNotifications = (await _api.fetchNotifications(
        currentToken,
        unreadOnly: true,
      )).length;
      _backendReachable = true;
      if (!silent) notifyListeners();
    } catch (_) {
      // O contador anterior permanece disponível offline.
    }
  }

  String exportDebugSession() {
    return jsonEncode({
      'logged_in': isLoggedIn,
      'user_id': _user?.id,
      'role': _user?.role,
      'backend': _backendReachable,
      'scope': storageScope,
    });
  }
}
