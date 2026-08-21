import '../models/personal_data.dart';
import 'app_session.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class PersonalDataService {
  final LocalStore store;
  final GranMapApi api;

  PersonalDataService({LocalStore? store, GranMapApi? api})
    : store = store ?? LocalStore(),
      api = api ?? GranMapApi();

  Future<List<String>> loadFavorites() async {
    final session = AppSession.instance;
    final local = await store.readFavorites(session.storageScope);

    if (!session.isLoggedIn) return local;

    try {
      final remote = await api.fetchFavorites(session.token!);
      final merged = {...local, ...remote}.toList();
      await store.saveFavorites(session.storageScope, merged);

      for (final id in local.where((id) => !remote.contains(id))) {
        try {
          await api.addFavorite(session.token!, id);
        } catch (_) {}
      }

      return merged;
    } catch (_) {
      return local;
    }
  }

  Future<List<String>> toggleFavorite(
    String poiId,
    List<String> current,
  ) async {
    final session = AppSession.instance;
    final next = current.toSet();

    final removing = next.contains(poiId);
    if (removing) {
      next.remove(poiId);
    } else {
      next.add(poiId);
    }

    final list = next.toList();
    await store.saveFavorites(session.storageScope, list);

    if (session.isLoggedIn) {
      try {
        if (removing) {
          await api.removeFavorite(session.token!, poiId);
        } else {
          await api.addFavorite(session.token!, poiId);
        }
      } catch (_) {
        // A cópia local permanece e será reconciliada depois.
      }
    }

    return list;
  }

  Future<void> addHistory({
    required String poiId,
    required String poiName,
  }) async {
    final session = AppSession.instance;
    final item = NavigationHistoryItem(
      poiId: poiId,
      poiName: poiName,
      visitedAt: DateTime.now(),
    );

    final history = await store.readHistory(session.storageScope);
    final next = <NavigationHistoryItem>[
      item,
      ...history.where((old) => old.poiId != poiId),
    ].take(50).toList();

    await store.saveHistory(session.storageScope, next);

    if (session.isLoggedIn) {
      try {
        await api.addHistory(session.token!, item);
      } catch (_) {}
    }
  }

  Future<List<NavigationHistoryItem>> loadHistory() async {
    final session = AppSession.instance;
    final local = await store.readHistory(session.storageScope);

    if (!session.isLoggedIn) return local;

    try {
      final remote = await api.fetchHistory(session.token!);
      if (remote.isNotEmpty) {
        await store.saveHistory(session.storageScope, remote);
        return remote;
      }
    } catch (_) {}

    return local;
  }

  void dispose() => api.dispose();
}
