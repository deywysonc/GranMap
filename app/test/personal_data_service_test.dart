import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/personal_data.dart';
import 'package:granmap/models/user.dart';
import 'package:granmap/services/app_session.dart';
import 'package:granmap/services/granmap_api.dart';
import 'package:granmap/services/local_store.dart';
import 'package:granmap/services/personal_data_service.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late _MemoryStore store;
  late _Session session;
  late _Api api;
  late PersonalDataService personal;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = _MemoryStore();
    session = _Session();
    api = _Api();
    personal = PersonalDataService(store: store, api: api, session: session);
  });

  tearDown(() {
    personal.dispose();
    session.dispose();
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test(
    'remoção offline permanece removida ao reconectar e é reenviada',
    () async {
      store.favorites['user_1'] = const FavoriteState(ids: ['biblioteca']);
      api.remote.add('biblioteca');
      api.offline = true;

      expect(
        await personal.toggleFavorite('biblioteca', ['biblioteca']),
        isEmpty,
      );
      await personal.synchronizeFavorites();
      expect(store.favorites['user_1']!.pending, {'biblioteca': false});

      api.offline = false;
      expect(await personal.loadFavorites(), isEmpty);
      await personal.synchronizeFavorites();
      expect(api.remote, isEmpty);
      expect(store.favorites['user_1']!.pending, isEmpty);
    },
  );

  test(
    'toque no favorito não aguarda uma requisição de rede pendente',
    () async {
      api.change = Completer<void>();
      expect(await personal.toggleFavorite('biblioteca', []), ['biblioteca']);
      expect(store.favorites['user_1']!.pending, {'biblioteca': true});
      api.change!.complete();
      await personal.synchronizeFavorites();
      expect(api.remote, {'biblioteca'});
    },
  );

  test(
    'resposta antiga não desfaz remoção feita durante atualização',
    () async {
      store.favorites['user_1'] = const FavoriteState(ids: ['biblioteca']);
      api.remote.add('biblioteca');
      api.fetch = Completer<List<String>>();
      final loading = personal.loadFavorites();
      await Future<void>.delayed(Duration.zero);
      await personal.toggleFavorite('biblioteca', ['biblioteca']);
      await personal.synchronizeFavorites();
      api.fetch!.complete(['biblioteca']);

      expect(await loading, isEmpty);
      expect(store.favorites['user_1']!.ids, isEmpty);
    },
  );

  test(
    'troca de conta durante gravação não move os dados para outra conta',
    () async {
      store.readGate = Completer<void>();
      final changing = personal.toggleFavorite('biblioteca', []);
      await Future<void>.delayed(Duration.zero);
      session.id = 2;
      store.readGate!.complete();

      await changing;
      expect(store.favorites['user_1']!.ids, ['biblioteca']);
      expect(store.favorites['user_2'], isNull);
      expect(api.addTokens, isEmpty);
    },
  );

  test(
    'última intenção prevalece quando um envio anterior ainda está em curso',
    () async {
      api.change = Completer<void>();
      await personal.toggleFavorite('biblioteca', []);
      await Future<void>.delayed(Duration.zero);
      await personal.toggleFavorite('biblioteca', ['biblioteca']);
      api.change!.complete();
      await personal.synchronizeFavorites();

      expect(store.favorites['user_1']!.ids, isEmpty);
      expect(store.favorites['user_1']!.pending, isEmpty);
      expect(api.remote, isEmpty);
    },
  );

  test('gravação tardia não sobrescreve uma alteração mais recente', () async {
    api.offline = true;
    final gate = Completer<void>();
    store.saveGate = gate;
    final bounded = PersonalDataService(
      store: store,
      api: api,
      session: session,
      storageTimeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      bounded.toggleFavorite('biblioteca', []),
      throwsA(isA<TimeoutException>()),
    );
    final next = bounded.toggleFavorite('biblioteca', ['biblioteca']);
    await Future<void>.delayed(Duration.zero);
    expect(store.favorites['user_1'], isNull);
    gate.complete();
    expect(await next, isEmpty);
    await bounded.synchronizeFavorites();
    expect(store.favorites['user_1']!.pending, {'biblioteca': false});
    bounded.dispose();
  });

  test('telas diferentes enviam mudanças na ordem das intenções', () async {
    final other = PersonalDataService(store: store, api: api, session: session);
    api.change = Completer<void>();
    await personal.toggleFavorite('biblioteca', []);
    await Future<void>.delayed(Duration.zero);
    await other.toggleFavorite('biblioteca', ['biblioteca']);
    final syncing = other.synchronizeFavorites();
    api.change!.complete();
    await syncing;
    expect(api.remote, isEmpty);
    expect(store.favorites['user_1']!.ids, isEmpty);
    expect(store.favorites['user_1']!.pending, isEmpty);
    other.dispose();
  });

  test(
    'histórico remoto não apaga os destinos recentes guardados offline',
    () async {
      final local = NavigationHistoryItem(
        poiId: 'biblioteca',
        poiName: 'Biblioteca',
        visitedAt: DateTime(2026, 10, 13),
      );
      store.history['user_1'] = [local];
      api.history = [
        NavigationHistoryItem(
          poiId: 'secretaria',
          poiName: 'Secretaria',
          visitedAt: DateTime(2026, 10, 12),
        ),
      ];
      final result = await personal.loadHistory();
      expect(result.map((item) => item.poiId), ['biblioteca', 'secretaria']);
    },
  );
}

class _Session extends AppSession {
  int id = 1;
  @override
  String get storageScope => 'user_$id';
  @override
  String get token => 'token_$id';
  @override
  bool get isLoggedIn => true;
  @override
  AppUser get user => AppUser(
    id: id,
    name: 'Aluno $id',
    email: 'aluno$id@example.test',
    course: 'EC',
    semester: 4,
    group: 'EC4',
    role: 'student',
  );
}

class _MemoryStore extends LocalStore {
  final Map<String, FavoriteState> favorites = {};
  final Map<String, List<NavigationHistoryItem>> history = {};
  Completer<void>? readGate;
  Completer<void>? saveGate;

  @override
  Future<FavoriteState> readFavoriteState(String scope) async {
    await readGate?.future;
    return favorites[scope] ?? const FavoriteState();
  }

  @override
  Future<void> saveFavoriteState(String scope, FavoriteState state) async {
    final gate = saveGate;
    saveGate = null;
    await gate?.future;
    favorites[scope] = state;
  }

  @override
  Future<List<NavigationHistoryItem>> readHistory(String scope) async =>
      history[scope] ?? [];
  @override
  Future<void> saveHistory(
    String scope,
    List<NavigationHistoryItem> items,
  ) async {
    history[scope] = items;
  }
}

class _Api extends GranMapApi {
  final Set<String> remote = {};
  final List<String> addTokens = [];
  List<NavigationHistoryItem> history = [];
  bool offline = false;
  Completer<void>? change;
  Completer<List<String>>? fetch;

  @override
  Future<List<String>> fetchFavorites(String token) async {
    if (offline) throw StateError('offline');
    return fetch == null ? remote.toList() : await fetch!.future;
  }

  @override
  Future<void> addFavorite(String token, String poiId) async {
    if (offline) throw StateError('offline');
    addTokens.add(token);
    await change?.future;
    remote.add(poiId);
  }

  @override
  Future<void> removeFavorite(String token, String poiId) async {
    if (offline) throw StateError('offline');
    await change?.future;
    remote.remove(poiId);
  }

  @override
  Future<List<NavigationHistoryItem>> fetchHistory(String token) async =>
      history;
}
