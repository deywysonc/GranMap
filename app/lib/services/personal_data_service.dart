import 'dart:async';

import '../models/personal_data.dart';
import 'app_session.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class PersonalDataService {
  final LocalStore store;
  final GranMapApi api;
  final AppSession session;
  final Duration storageTimeout;
  final Duration networkTimeout;
  static final Map<String, Future<void>> _writes = {};
  static final Map<String, Future<void>> _syncs = {};
  bool _disposed = false;

  PersonalDataService({
    LocalStore? store,
    GranMapApi? api,
    AppSession? session,
    this.storageTimeout = const Duration(seconds: 2),
    this.networkTimeout = const Duration(seconds: 4),
  }) : store = store ?? LocalStore(),
       api = api ?? GranMapApi(),
       session = session ?? AppSession.instance;

  bool _current(String scope, String? token) =>
      !_disposed && session.storageScope == scope && session.token == token;

  Future<T> _write<T>(String key, Future<T> Function() action) {
    final previous = _writes[key] ?? Future<void>.value();
    final operation = previous.then((_) => action());
    // O prazo limita a interface, mas a gravação nativa continua na fila.
    final barrier = operation.then<void>((_) {}, onError: (Object _) {});
    _writes[key] = barrier;
    unawaited(
      barrier.whenComplete(() {
        if (identical(_writes[key], barrier)) _writes.remove(key);
      }),
    );
    return operation.timeout(storageTimeout);
  }

  Future<List<String>> loadFavorites() async {
    final scope = session.storageScope;
    final token = session.token;
    FavoriteState initial;
    try {
      initial = await store.readFavoriteState(scope).timeout(storageTimeout);
    } catch (_) {
      return const [];
    }
    if (token == null || !_current(scope, token)) return initial.ids;

    try {
      final remote = await api.fetchFavorites(token).timeout(networkTimeout);
      if (!_current(scope, token)) return initial.ids;
      final ids = await _write('favorites:$scope', () async {
        final latest = await store.readFavoriteState(scope);
        if (latest.revision != initial.revision) return latest.ids;
        final merged = {...latest.ids, ...remote};
        final pending = Map<String, bool>.from(latest.pending);
        for (final change in pending.entries) {
          if (change.value) {
            merged.add(change.key);
          } else {
            merged.remove(change.key);
          }
        }
        for (final id in merged.where((id) => !remote.contains(id))) {
          pending[id] = true;
        }
        final next = FavoriteState(
          ids: merged.toList()..sort(),
          pending: pending,
          revision: latest.revision + 1,
        );
        await store.saveFavoriteState(scope, next);
        return next.ids;
      });
      unawaited(_syncFavorites(scope, token));
      return ids;
    } catch (_) {
      return initial.ids;
    }
  }

  Future<List<String>> loadCachedFavorites() async {
    final scope = session.storageScope;
    final state = await store.readFavoriteState(scope).timeout(storageTimeout);
    return state.ids;
  }

  Future<List<String>> toggleFavorite(
    String poiId,
    List<String> current,
  ) async {
    final scope = session.storageScope;
    final token = session.token;
    final list = await _write('favorites:$scope', () async {
      final saved = await store.readFavoriteState(scope);
      final next = current.toSet();
      final selected = !next.contains(poiId);
      if (selected) {
        next.add(poiId);
      } else {
        next.remove(poiId);
      }
      final pending = Map<String, bool>.from(saved.pending);
      if (token != null) pending[poiId] = selected;
      final state = FavoriteState(
        ids: next.toList()..sort(),
        pending: pending,
        revision: saved.revision + 1,
      );
      await store.saveFavoriteState(scope, state);
      return state.ids;
    });
    if (token != null) unawaited(_syncFavorites(scope, token));
    return list;
  }

  Future<void> synchronizeFavorites() async {
    final token = session.token;
    if (token != null) await _syncFavorites(session.storageScope, token);
  }

  Future<void> _syncFavorites(String scope, String token) {
    final key = '${api.baseUrl}:$scope:$token';
    final existing = _syncs[key];
    if (existing != null) {
      return existing.then((_) {
        if (_current(scope, token)) return _syncFavorites(scope, token);
      });
    }
    late final Future<void> operation;
    operation = _drainFavorites(scope, token).whenComplete(() {
      if (identical(_syncs[key], operation)) _syncs.remove(key);
    });
    _syncs[key] = operation;
    return operation;
  }

  Future<void> _drainFavorites(String scope, String token) async {
    try {
      while (_current(scope, token)) {
        final state = await store
            .readFavoriteState(scope)
            .timeout(storageTimeout);
        if (state.pending.isEmpty) return;
        final change = state.pending.entries.first;
        if (!_current(scope, token)) return;
        if (change.value) {
          await api.addFavorite(token, change.key).timeout(networkTimeout);
        } else {
          await api.removeFavorite(token, change.key).timeout(networkTimeout);
        }
        await _write('favorites:$scope', () async {
          final latest = await store.readFavoriteState(scope);
          if (latest.pending[change.key] != change.value) return;
          final remaining = Map<String, bool>.from(latest.pending)
            ..remove(change.key);
          await store.saveFavoriteState(
            scope,
            FavoriteState(
              ids: latest.ids,
              pending: remaining,
              revision: latest.revision + 1,
            ),
          );
        });
      }
    } catch (_) {
      // A intenção fica salva para a próxima carga ou tentativa de conexão.
    }
  }

  Future<void> addHistory({
    required String poiId,
    required String poiName,
  }) async {
    final scope = session.storageScope;
    final token = session.token;
    final item = NavigationHistoryItem(
      poiId: poiId,
      poiName: poiName,
      visitedAt: DateTime.now(),
    );
    await _write('history:$scope', () async {
      final history = await store.readHistory(scope);
      await store.saveHistory(scope, _mergeHistory([item], history));
    });
    if (token != null && _current(scope, token)) {
      unawaited(_sendHistory(scope, token, item));
    }
  }

  Future<void> _sendHistory(
    String scope,
    String token,
    NavigationHistoryItem item,
  ) async {
    try {
      if (_current(scope, token)) {
        await api.addHistory(token, item).timeout(networkTimeout);
      }
    } catch (_) {}
  }

  Future<List<NavigationHistoryItem>> loadHistory() async {
    final scope = session.storageScope;
    final token = session.token;
    List<NavigationHistoryItem> local;
    try {
      local = await store.readHistory(scope).timeout(storageTimeout);
    } catch (_) {
      return const [];
    }
    if (token == null || !_current(scope, token)) return local;
    try {
      final remote = await api.fetchHistory(token).timeout(networkTimeout);
      if (!_current(scope, token)) return local;
      return await _write('history:$scope', () async {
        final latest = await store.readHistory(scope);
        final merged = _mergeHistory(latest, remote);
        await store.saveHistory(scope, merged);
        return merged;
      });
    } catch (_) {
      return local;
    }
  }

  List<NavigationHistoryItem> _mergeHistory(
    List<NavigationHistoryItem> a,
    List<NavigationHistoryItem> b,
  ) {
    final sorted = [...a, ...b]
      ..sort((left, right) => right.visitedAt.compareTo(left.visitedAt));
    final ids = <String>{};
    return sorted.where((item) => ids.add(item.poiId)).take(50).toList();
  }

  void dispose() {
    _disposed = true;
    api.dispose();
  }
}
