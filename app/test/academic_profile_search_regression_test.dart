import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/academic.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/models/personal_data.dart';
import 'package:granmap/models/user.dart';
import 'package:granmap/screens/academic_screen.dart';
import 'package:granmap/screens/home_screen.dart';
import 'package:granmap/screens/profile_screen.dart';
import 'package:granmap/screens/route_screen.dart';
import 'package:granmap/screens/search_screen.dart';
import 'package:granmap/services/app_session.dart';
import 'package:granmap/services/granmap_api.dart';
import 'package:granmap/services/local_store.dart';
import 'package:granmap/services/personal_data_service.dart';
import 'package:granmap/services/user_academic_service.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:granmap/widgets/campus_map_canvas.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  for (final stalls in [false, true]) {
    _testWidgets(
      'grade abre desvio com histórico ${stalls ? 'ocupado' : 'com falha'}',
      (tester) async {
        final session = _TestSession()..changeAccount(1);
        final history = Completer<void>();
        final personal = _TestPersonal(
          session: session,
          remember: () => stalls
              ? history.future
              : Future<void>.error(StateError('storage unavailable')),
        );
        await _show(
          tester,
          AcademicScreen(
            campus: _campus,
            blockedEdgeIds: const {'a__b'},
            session: session,
            academicService: _TestAcademic(() async => _schedule),
            personalDataService: personal,
          ),
        );

        await tester.tap(find.byTooltip('Traçar rota para a sala'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(RouteScreen), findsOneWidget);
        final map = tester.widget<CampusMapCanvas>(
          find.byType(CampusMapCanvas),
        );
        expect(map.route.map((node) => node.id), ['a', 'c', 'd']);
        expect(personal.historyWrites, 1);
        expect(tester.takeException(), isNull);
        if (stalls) history.complete();
        await _close(tester);
      },
    );
  }

  _testWidgets('grade com falha encerra espera e permite tentar novamente', (
    tester,
  ) async {
    final session = _TestSession()..changeAccount(1);
    var attempts = 0;
    await _show(
      tester,
      AcademicScreen(
        campus: _campus,
        session: session,
        academicService: _TestAcademic(() async {
          if (attempts++ == 0) throw StateError('cache unavailable');
          return _schedule;
        }),
      ),
    );

    expect(find.text('Sua grade está indisponível'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Estrutura de Dados'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  _testWidgets('grade ocupada termina após limite e pode ser recarregada', (
    tester,
  ) async {
    final session = _TestSession()..changeAccount(1);
    final pending = Completer<AcademicSnapshot>();
    var attempts = 0;
    await _show(
      tester,
      AcademicScreen(
        campus: _campus,
        session: session,
        academicService: _TestAcademic(
          () => attempts++ == 0 ? pending.future : Future.value(_schedule),
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Estrutura de Dados'), findsOneWidget);
    pending.complete(_schedule);
    await _close(tester);
  });

  _testWidgets('resposta acadêmica antiga não reaparece após sair', (
    tester,
  ) async {
    final session = _TestSession()..changeAccount(1);
    final pending = Completer<AcademicSnapshot>();
    var attempts = 0;
    await _show(
      tester,
      AcademicScreen(
        campus: _campus,
        session: session,
        academicService: _TestAcademic(
          () => attempts++ == 0
              ? pending.future
              : Future.value(
                  const AcademicSnapshot(
                    classes: [],
                    source: AcademicDataSource.none,
                  ),
                ),
        ),
      ),
    );
    session.changeAccount(null);
    await tester.pump();
    pending.complete(_schedule);
    await tester.pump();
    expect(find.text('Conectar minha conta'), findsOneWidget);
    expect(find.text('Estrutura de Dados'), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  _testWidgets('perfil passa bloqueios à grade e ao favorito', (tester) async {
    final session = _TestSession()..changeAccount(1);
    final personal = _TestPersonal(
      session: session,
      favorites: () async => ['room'],
    );
    await _show(
      tester,
      ProfileScreen(
        campus: _campus,
        blockedEdgeIds: const {'a__b'},
        session: session,
        personalDataService: personal,
      ),
    );
    await tester.tap(find.text('Minha grade de aulas'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final academic = tester.widget<AcademicScreen>(find.byType(AcademicScreen));
    expect(academic.blockedEdgeIds, {'a__b'});
    expect(academic.session, same(session));
    final context = tester.element(find.byType(AcademicScreen));
    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Favoritos').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Sala destino'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final map = tester.widget<CampusMapCanvas>(find.byType(CampusMapCanvas));
    expect(map.route.map((node) => node.id), ['a', 'c', 'd']);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  _testWidgets('busca descarta favoritos pendentes da conta anterior', (
    tester,
  ) async {
    final session = _TestSession()..changeAccount(1);
    final first = Completer<List<String>>();
    final second = Completer<List<String>>();
    var requests = 0;
    await _show(
      tester,
      SearchScreen(
        campus: _campus,
        session: session,
        personalDataService: _TestPersonal(
          session: session,
          favorites: () => requests++ == 0 ? first.future : second.future,
        ),
      ),
    );
    session.changeAccount(2);
    await tester.pump();
    second.complete([]);
    await tester.pump();
    first.complete(['room']);
    await tester.pump();

    expect(find.byTooltip('Remover dos favoritos'), findsNothing);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  _testWidgets('busca limpa favoritos ao sair e ignora gravação antiga', (
    tester,
  ) async {
    final session = _TestSession()..changeAccount(1);
    final saved = Completer<List<String>>();
    final personal = _TestPersonal(
      session: session,
      favorites: () async => session.isLoggedIn ? ['room'] : [],
      toggle: (_, _) => saved.future,
    );
    await _show(
      tester,
      SearchScreen(
        campus: _campus,
        session: session,
        personalDataService: personal,
      ),
    );
    expect(find.byTooltip('Remover dos favoritos'), findsOneWidget);
    await tester.tap(find.byTooltip('Remover dos favoritos'));
    session.changeAccount(null);
    await tester.pump();
    saved.complete(['room']);
    await tester.pump();

    expect(find.byTooltip('Remover dos favoritos'), findsNothing);
    expect(personal.toggleScopes, ['user_1']);
    expect(find.text('Sala destino'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  _testWidgets('busca mantém favoritos locais com rede indisponível', (
    tester,
  ) async {
    final session = _TestSession()..changeAccount(1);
    final remote = Completer<List<String>>();
    await _show(
      tester,
      SearchScreen(
        campus: _campus,
        session: session,
        personalDataService: _TestPersonal(
          session: session,
          cachedFavorites: () async => ['room'],
          favorites: () => remote.future,
        ),
      ),
    );
    expect(find.byTooltip('Remover dos favoritos'), findsOneWidget);
    remote.completeError(StateError('offline'));
    await tester.pump();
    expect(find.byTooltip('Remover dos favoritos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  _testWidgets('perfil permite abrir favorito antes de a rede responder', (
    tester,
  ) async {
    final session = _TestSession()..changeAccount(1);
    final remote = Completer<List<String>>();
    await _show(
      tester,
      ProfileScreen(
        campus: _campus,
        session: session,
        personalDataService: _TestPersonal(
          session: session,
          cachedFavorites: () async => ['room'],
          favorites: () => remote.future,
        ),
      ),
    );
    await tester.tap(find.text('Favoritos').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Sala destino'), findsOneWidget);
    remote.completeError(StateError('offline'));
    await tester.pump();
    expect(find.text('Sala destino'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  _testWidgets('início usa cache e descarta dados recebidos depois de sair', (
    tester,
  ) async {
    final session = _TestSession()..changeAccount(1);
    final schedule = Completer<AcademicSnapshot>();
    final remoteFavorites = Completer<List<String>>();
    await _show(
      tester,
      HomeScreen(
        campus: _campus,
        session: session,
        academicService: _TestAcademic(() => schedule.future),
        personalDataService: _TestPersonal(
          session: session,
          cachedFavorites: () async => session.isLoggedIn ? ['room'] : [],
          favorites: () =>
              session.isLoggedIn ? remoteFavorites.future : Future.value([]),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Sala destino'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sala destino'), findsOneWidget);
    session.changeAccount(null);
    await tester.pump();
    schedule.complete(_schedule);
    remoteFavorites.complete(['room']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pump();
    expect(find.text('Entre para ver sua próxima aula'), findsOneWidget);
    expect(find.textContaining('Estrutura de Dados'), findsNothing);
    expect(find.text('Sala destino'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  _testWidgets('perfil oferece nova tentativa de limpar sessão persistida', (
    tester,
  ) async {
    final session = _TestSession()..cleanupError = 'Falha ao limpar sessão';
    await _show(
      tester,
      ProfileScreen(
        campus: _campus,
        session: session,
        personalDataService: _TestPersonal(session: session),
      ),
    );
    expect(find.text('Falha ao limpar sessão'), findsOneWidget);
    await tester.tap(find.text('Tentar limpar sessão'));
    await tester.pump();
    expect(session.cleanupRequests, 1);
    expect(find.text('Falha ao limpar sessão'), findsNothing);
    expect(find.text('Tentar limpar sessão'), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  for (final stalls in [false, true]) {
    test(
      'grade offline limita leitura de cache ${stalls ? 'ocupada' : 'com falha'}',
      () async {
        final session = _TestSession()..changeAccount(1);
        final service = UserAcademicService(
          session: session,
          api: _ScheduleApi(() => Future.error(StateError('offline'))),
          store: _ScheduleStore(
            read: () => stalls
                ? Completer<AcademicSnapshot?>().future
                : Future.error(StateError('cache unavailable')),
          ),
          storageTimeout: const Duration(milliseconds: 20),
        );
        final snapshot = await service.load();
        expect(snapshot.source, AcademicDataSource.none);
        expect(snapshot.message, contains('Tente novamente'));
        service.dispose();
      },
    );
  }

  test('grade com rede ocupada usa cache após limite', () async {
    final session = _TestSession()..changeAccount(1);
    final service = UserAcademicService(
      session: session,
      api: _ScheduleApi(() => Completer<List<AcademicClass>>().future),
      store: _ScheduleStore(read: () async => _cachedSchedule),
      requestTimeout: const Duration(milliseconds: 20),
    );
    expect(await service.load(), same(_cachedSchedule));
    service.dispose();
  });

  for (final stalls in [false, true]) {
    test(
      'grade recebida continua disponível com gravação ${stalls ? 'ocupada' : 'com falha'}',
      () async {
        final session = _TestSession()..changeAccount(1);
        final service = UserAcademicService(
          session: session,
          api: _ScheduleApi(() async => _schedule.classes),
          store: _ScheduleStore(
            save: () => stalls
                ? Completer<void>().future
                : Future.error(StateError('cache unavailable')),
          ),
          storageTimeout: const Duration(milliseconds: 20),
        );
        final snapshot = await service.load();
        expect(snapshot.source, AcademicDataSource.online);
        expect(snapshot.classes, _schedule.classes);
        expect(snapshot.cachedAt, isNull);
        service.dispose();
      },
    );
  }
}

void _testWidgets(String description, WidgetTesterCallback test) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await test(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: GranMapTheme.dark,
      home: Scaffold(body: screen),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

class _TestSession extends AppSession {
  AppUser? _account;
  String? cleanupError;
  int cleanupRequests = 0;

  void changeAccount(int? id) {
    _account = id == null
        ? null
        : AppUser(
            id: id,
            name: 'Aluno $id',
            email: 'aluno$id@example.test',
            course: 'Computação',
            semester: 4,
            group: 'A',
            role: 'student',
          );
    notifyListeners();
  }

  @override
  AppUser? get user => _account;
  @override
  String? get token => _account == null ? null : 'token_${_account!.id}';
  @override
  bool get isLoggedIn => _account != null;
  @override
  String get storageScope =>
      _account == null ? 'guest' : 'user_${_account!.id}';
  @override
  String? get persistenceError => cleanupError;
  @override
  Future<void> logout() async {
    cleanupRequests++;
    cleanupError = null;
    changeAccount(null);
  }
}

class _TestAcademic extends UserAcademicService {
  final Future<AcademicSnapshot> Function() read;
  _TestAcademic(this.read);
  @override
  Future<AcademicSnapshot> load() => read();
}

class _TestPersonal extends PersonalDataService {
  final Future<List<String>> Function()? favorites;
  final Future<List<String>> Function()? cachedFavorites;
  final Future<List<String>> Function(String, List<String>)? toggle;
  final Future<void> Function()? remember;
  final List<String> toggleScopes = [];
  int historyWrites = 0;

  _TestPersonal({
    required super.session,
    this.favorites,
    this.cachedFavorites,
    this.toggle,
    this.remember,
  });

  @override
  Future<List<String>> loadFavorites() => favorites?.call() ?? Future.value([]);
  @override
  Future<List<String>> loadCachedFavorites() =>
      cachedFavorites?.call() ?? Future.value([]);
  @override
  Future<List<NavigationHistoryItem>> loadHistory() async => [];
  @override
  Future<List<String>> toggleFavorite(String poiId, List<String> current) {
    toggleScopes.add(session.storageScope);
    return toggle?.call(poiId, current) ?? Future.value(current);
  }

  @override
  Future<void> addHistory({required String poiId, required String poiName}) {
    historyWrites++;
    return remember?.call() ?? Future.value();
  }
}

class _ScheduleApi extends GranMapApi {
  final Future<List<AcademicClass>> Function() read;
  _ScheduleApi(this.read);
  @override
  Future<List<AcademicClass>> fetchMySchedule(String token) => read();
}

class _ScheduleStore extends LocalStore {
  final Future<AcademicSnapshot?> Function()? read;
  final Future<void> Function()? save;
  _ScheduleStore({this.read, this.save});
  @override
  Future<AcademicSnapshot?> readCachedSchedule(String scope) =>
      read?.call() ?? Future.value(null);
  @override
  Future<void> saveCachedSchedule(String scope, List<AcademicClass> classes) =>
      save?.call() ?? Future.value();
}

const _schedule = AcademicSnapshot(
  classes: [
    AcademicClass(
      subject: 'Estrutura de Dados',
      professor: 'Professora',
      roomPoiId: 'room',
      roomName: 'Sala destino',
      weekday: 'Segunda-feira',
      startTime: '19:00',
      endTime: '20:40',
    ),
  ],
  source: AcademicDataSource.online,
);

final _cachedSchedule = AcademicSnapshot(
  classes: _schedule.classes,
  source: AcademicDataSource.cache,
);

const _campus = CampusMap(
  building: BuildingInfo(id: 'gran', name: 'Gran Tietê', version: 'test'),
  floors: [CampusFloor(id: 'f0', name: 'Térreo', level: 0, elevation: 0)],
  pois: [
    CampusPoi(
      id: 'entrada_gran',
      name: 'Entrada Gran',
      type: 'entrance',
      floor: 0,
      x: 0,
      y: 0,
      z: 0,
      navigationNode: 'a',
    ),
    CampusPoi(
      id: 'room',
      name: 'Sala destino',
      type: 'classroom',
      floor: 0,
      x: 2,
      y: 0,
      z: 0,
      navigationNode: 'd',
    ),
  ],
  nodes: [
    NavigationNode(id: 'a', floor: 0, x: 0, y: 0, z: 0, type: 'corridor'),
    NavigationNode(id: 'b', floor: 0, x: 1, y: 0, z: 0, type: 'corridor'),
    NavigationNode(id: 'c', floor: 0, x: 1, y: 1, z: 0, type: 'corridor'),
    NavigationNode(id: 'd', floor: 0, x: 2, y: 0, z: 0, type: 'corridor'),
  ],
  edges: [
    NavigationEdge(
      from: 'a',
      to: 'b',
      distance: 1,
      type: 'corridor',
      accessible: true,
    ),
    NavigationEdge(
      from: 'b',
      to: 'd',
      distance: 1,
      type: 'corridor',
      accessible: true,
    ),
    NavigationEdge(
      from: 'a',
      to: 'c',
      distance: 2,
      type: 'corridor',
      accessible: true,
    ),
    NavigationEdge(
      from: 'c',
      to: 'd',
      distance: 2,
      type: 'corridor',
      accessible: true,
    ),
  ],
);
