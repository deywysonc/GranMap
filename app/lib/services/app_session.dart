import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class AppSession extends ChangeNotifier {
  AppSession({
    LocalStore? store,
    GranMapApi? api,
    this.storageTimeout = const Duration(seconds: 10),
    this.notificationTimeout = const Duration(seconds: 5),
    this.authTimeout = const Duration(seconds: 15),
  }) : _store = store ?? LocalStore(),
       _api = api ?? GranMapApi();

  static final AppSession instance = AppSession();

  final LocalStore _store;
  final GranMapApi _api;
  final Duration storageTimeout;
  final Duration notificationTimeout;
  final Duration authTimeout;
  Future<void> _storageTail = Future<void>.value();
  Future<void>? _initialization;
  int _sessionGeneration = 0;
  int _notificationGeneration = 0;
  bool _disposed = false;

  AppUser? _user;
  String? _token;
  bool _initialized = false;
  bool _backendReachable = false;
  int _unreadNotifications = 0;
  String? _persistenceError;

  AppUser? get user => _user;
  String? get token => _token;
  bool get initialized => _initialized;
  bool get isLoggedIn => _user != null && _token != null;
  bool get backendReachable => _backendReachable;
  int get unreadNotifications => _unreadNotifications;
  String? get persistenceError => _persistenceError;

  String get storageScope => _user == null ? 'guest' : 'user_${_user!.id}';

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final generation = _sessionGeneration;
    String? cachedToken;
    AppUser? cachedUser;

    try {
      cachedToken = await _store.readToken().timeout(storageTimeout);
    } catch (_) {}
    try {
      cachedUser = await _store.readUser().timeout(storageTimeout);
    } catch (_) {}
    var reachable = false;
    try {
      reachable = await _api.health().timeout(authTimeout);
    } catch (_) {}

    if (_isCurrent(generation)) {
      _token = cachedToken;
      _user = cachedUser;
      _backendReachable = reachable;
      if (reachable && cachedToken != null) {
        await _refreshUser(cachedToken, generation);
      }
      if (_isCurrent(generation) && (_token == null || _user == null)) {
        _clearMemory();
      }
    }

    if (_disposed) return;
    _initialized = true;
    _notify();
    if (_isCurrent(generation)) unawaited(refreshNotificationCount());
  }

  Future<void> login({required String email, required String password}) async {
    final generation = ++_sessionGeneration;
    final result = await _api
        .login(email: email, password: password)
        .timeout(authTimeout, onTimeout: _authTimedOut);
    _requireCurrent(generation);
    await _persistSession(result.token, result.user, generation);
    _commitAuthentication(result, generation);
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String course,
    required int semester,
    required String group,
  }) async {
    final generation = ++_sessionGeneration;
    AuthResult result;
    try {
      result = await _api
          .register(
            name: name,
            email: email,
            password: password,
            course: course,
            semester: semester,
            group: group,
          )
          .timeout(authTimeout, onTimeout: _authTimedOut);
    } on ApiException catch (error) {
      if (error.statusCode != 409) rethrow;
      try {
        result = await _api
            .login(email: email, password: password)
            .timeout(authTimeout, onTimeout: _authTimedOut);
      } on ApiException catch (loginError) {
        if (loginError.statusCode == 429) rethrow;
        throw error;
      } catch (_) {
        throw error;
      }
    }

    _requireCurrent(generation);
    await _persistSession(
      result.token,
      result.user,
      generation,
      failureMessage:
          'Sua conta foi criada, mas não foi possível salvar a sessão neste '
          'aparelho. Volte e tente entrar novamente.',
    );
    _commitAuthentication(result, generation);
  }

  void _commitAuthentication(AuthResult result, int generation) {
    _requireCurrent(generation);
    _token = result.token;
    _user = result.user;
    _unreadNotifications = 0;
    _backendReachable = true;
    _persistenceError = null;
    _notify();
    unawaited(refreshNotificationCount());
  }

  Future<void> updateProfile({
    required String name,
    required String course,
    required int semester,
    required String group,
  }) async {
    final currentToken = _token;
    final generation = _sessionGeneration;
    if (currentToken == null || _user == null) {
      throw const SessionException('Entre novamente para editar seu perfil.');
    }

    final updated = await _api
        .updateMe(
          token: currentToken,
          name: name,
          course: course,
          semester: semester,
          group: group,
        )
        .timeout(authTimeout, onTimeout: _authTimedOut);

    _requireCurrent(generation);
    await _persistSession(currentToken, updated, generation);
    _requireCurrent(generation);
    _user = updated;
    _backendReachable = true;
    _persistenceError = null;
    _notify();
  }

  Future<void> refreshBackendState() async {
    final generation = _sessionGeneration;
    final currentToken = _token;
    var reachable = false;
    try {
      reachable = await _api.health().timeout(authTimeout);
    } catch (_) {}
    if (!_isCurrent(generation)) return;
    _backendReachable = reachable;
    if (reachable && currentToken != null) {
      await _refreshUser(currentToken, generation);
    }
    _notify();
  }

  Future<void> _refreshUser(String currentToken, int generation) async {
    try {
      final updated = await _api.fetchMe(currentToken).timeout(authTimeout);
      if (!_isCurrent(generation)) return;
      await _persistSession(currentToken, updated, generation);
      if (_isCurrent(generation)) _user = updated;
    } on ApiException catch (error) {
      if (error.statusCode == 401 && _isCurrent(generation)) {
        final expiredGeneration = ++_sessionGeneration;
        _clearMemory();
        _notify();
        await _clearStoredSession(expiredGeneration);
      }
    } catch (_) {
      // A atualização remota pode falhar; erros de persistência já são visíveis.
    }
  }

  Future<void> logout() async {
    final currentToken = _token;
    final generation = ++_sessionGeneration;
    _clearMemory();
    _persistenceError = null;
    _notify();
    final clearing = _clearStoredSession(generation);
    if (currentToken != null) unawaited(_revokeToken(currentToken));
    await clearing;
  }

  void _clearMemory() {
    _token = null;
    _user = null;
    _unreadNotifications = 0;
  }

  Future<void> _revokeToken(String token) async {
    try {
      await _api.logout(token).timeout(authTimeout);
    } catch (_) {
      // A saída local não depende da conexão com o servidor.
    }
  }

  Future<void> _clearStoredSession(int generation) async {
    try {
      await _queueStorage(_store.clearSession).timeout(storageTimeout);
      if (_isCurrent(generation)) {
        _persistenceError = null;
        _notify();
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        _persistenceError =
            'Você saiu, mas não foi possível apagar a sessão deste aparelho. '
            'Tente sair novamente antes de fechar o app.';
        _notify();
      }
    }
  }

  Future<void> _persistSession(
    String token,
    AppUser user,
    int generation, {
    String failureMessage = 'Não foi possível salvar a sessão neste aparelho. Tente entrar novamente.',
  }) async {
    var abandoned = false;
    final write = _queueStorage(() async {
      var saved = false;
      try {
        if (!_isCurrent(generation) || abandoned) return;
        await _store.saveSession(token, user);
        saved = true;
      } finally {
        // Future.timeout não cancela a gravação nativa. A limpeza permanece
        // na mesma fila, antes de qualquer gravação de uma sessão posterior.
        if (!saved || abandoned || !_isCurrent(generation)) {
          await _store.clearSession();
        }
      }
    });
    try {
      await write.timeout(storageTimeout);
    } catch (_) {
      abandoned = true;
      if (_isCurrent(generation)) {
        _sessionGeneration++;
        _clearMemory();
        _persistenceError = failureMessage;
        _notify();
      }
      throw SessionException(failureMessage);
    }
    _requireCurrent(generation);
  }

  Future<void> _queueStorage(Future<void> Function() action) {
    final operation = _storageTail.then((_) => action());
    _storageTail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _sessionGeneration;

  void _requireCurrent(int generation) {
    if (!_isCurrent(generation)) {
      throw const SessionException(
        'Esta solicitação foi cancelada. Tente novamente.',
      );
    }
  }

  Never _authTimedOut() => throw const ApiException(
    'O servidor demorou para responder. Tente novamente.',
    0,
    kind: ApiFailureKind.timeout,
  );

  Future<void> refreshNotificationCount() async {
    final currentToken = _token;
    final generation = _sessionGeneration;
    final notificationGeneration = ++_notificationGeneration;
    if (currentToken == null) {
      _unreadNotifications = 0;
      _notify();
      return;
    }
    try {
      final notifications = await _api
          .fetchNotifications(currentToken, unreadOnly: true)
          .timeout(notificationTimeout);
      if (!_isCurrent(generation) ||
          notificationGeneration != _notificationGeneration ||
          currentToken != _token) {
        return;
      }
      _unreadNotifications = notifications.length;
      _backendReachable = true;
      _notify();
    } catch (_) {
      // O contador anterior permanece disponível offline.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
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

  @override
  void dispose() {
    _disposed = true;
    _sessionGeneration++;
    _api.dispose();
    super.dispose();
  }
}

class SessionException implements Exception {
  final String message;

  const SessionException(this.message);

  @override
  String toString() => message;
}
