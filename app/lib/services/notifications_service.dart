import 'dart:async';

import 'granmap_api.dart';
import 'local_store.dart';

class NotificationsService {
  NotificationsService({
    GranMapApi? api,
    LocalStore? store,
    this.storageTimeout = const Duration(seconds: 2),
    this.networkTimeout = const Duration(seconds: 6),
  }) : _api = api ?? GranMapApi(),
       _store = store ?? LocalStore(),
       _ownsApi = api == null;

  final GranMapApi _api;
  final LocalStore _store;
  final bool _ownsApi;
  final Duration storageTimeout;
  final Duration networkTimeout;

  static final Map<String, Future<void>> _cacheWrites = {};

  Future<List<Map<String, dynamic>>> readCached(String scope) =>
      _store.readNotifications(scope).timeout(storageTimeout);

  Future<List<Map<String, dynamic>>> fetch(String token) =>
      _api.fetchNotifications(token).timeout(networkTimeout);

  Future<void> saveCached(String scope, List<Map<String, dynamic>> items) {
    final snapshot = [
      for (final item in items) Map<String, dynamic>.from(item),
    ];
    final previous = _cacheWrites[scope] ?? Future<void>.value();
    final operation = previous.then(
      (_) => _store.saveNotifications(scope, snapshot),
    );
    // O timeout libera a interface; apenas a conclusão nativa libera a fila.
    // A fila compartilhada também preserva a ordem ao reabrir a tela.
    final barrier = operation.then<void>((_) {}, onError: (Object _) {});
    _cacheWrites[scope] = barrier;
    unawaited(
      barrier.whenComplete(() {
        if (identical(_cacheWrites[scope], barrier)) {
          _cacheWrites.remove(scope);
        }
      }),
    );
    return operation.timeout(storageTimeout);
  }

  Future<void> markRead(String token, int id) =>
      _api.markNotificationRead(token, id).timeout(networkTimeout);

  Future<void> markAllRead(String token) =>
      _api.markAllNotificationsRead(token).timeout(networkTimeout);

  static int? notificationId(Object? value) {
    if (value is int) return value > 0 ? value : null;
    if (value is! num || !value.isFinite || value != value.truncateToDouble()) {
      return null;
    }
    final id = value.toInt();
    return id > 0 ? id : null;
  }

  void dispose() {
    if (_ownsApi) _api.dispose();
  }
}
