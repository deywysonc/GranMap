import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/campus_map.dart';
import 'package:granmap/models/user.dart';
import 'package:granmap/screens/edit_profile_screen.dart';
import 'package:granmap/screens/login_screen.dart';
import 'package:granmap/screens/profile_screen.dart';
import 'package:granmap/screens/register_screen.dart';
import 'package:granmap/services/app_session.dart';
import 'package:granmap/services/granmap_api.dart';
import 'package:granmap/services/local_store.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _user = AppUser(
  id: 1,
  name: 'Aluno Teste',
  email: 'aluno@example.com',
  course: 'Engenharia',
  semester: 1,
  group: 'EC4A',
  role: 'student',
);
const _auth = AuthResult(token: 'token-a', user: _user);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  for (final register in [false, true]) {
    test(
      '${register ? 'cadastro' : 'login'} não espera pelas notificações',
      () async {
        final notifications = Completer<List<Map<String, dynamic>>>();
        final api = _TestApi()..onNotifications = (_) => notifications.future;
        final store = _MemorySessionStore();
        final session = AppSession(api: api, store: store);
        addTearDown(session.dispose);
        var authenticatedNotice = false;
        session.addListener(() {
          if (session.isLoggedIn) authenticatedNotice = true;
        });

        await _authenticate(
          session,
          register: register,
        ).timeout(const Duration(milliseconds: 250));

        expect(authenticatedNotice, isTrue);
        expect(session.isLoggedIn, isTrue);
        expect(store.token, 'token-a');
        expect(session.unreadNotifications, 0);
        notifications.complete([
          {'id': 1},
        ]);
        await Future<void>.delayed(Duration.zero);
        expect(session.unreadNotifications, 1);
      },
    );
  }

  test(
    'inicialização libera sessão antes do contador de notificações',
    () async {
      final notifications = Completer<List<Map<String, dynamic>>>();
      final api = _TestApi()..onNotifications = (_) => notifications.future;
      final store = _MemorySessionStore()
        ..token = _auth.token
        ..user = _user;
      final session = AppSession(api: api, store: store);
      addTearDown(session.dispose);

      await session.initialize().timeout(const Duration(milliseconds: 250));

      expect(session.initialized, isTrue);
      expect(session.isLoggedIn, isTrue);
      notifications.complete([]);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'notificação de sessão anterior não aparece após logout e novo login',
    () async {
      final oldNotifications = Completer<List<Map<String, dynamic>>>();
      final api = _TestApi()
        ..onNotifications = (token) => token == 'token-a'
            ? oldNotifications.future
            : Future.value([
                {'id': 2},
                {'id': 3},
              ]);
      final session = AppSession(api: api, store: _MemorySessionStore());
      addTearDown(session.dispose);

      await _authenticate(session);
      await session.logout();
      api.auth = AuthResult(
        token: 'token-b',
        user: _user.copyWith(name: 'Aluno B'),
      );
      await _authenticate(session);
      await Future<void>.delayed(Duration.zero);
      expect(session.unreadNotifications, 2);

      oldNotifications.complete([
        {'id': 1},
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(session.token, 'token-b');
      expect(session.unreadNotifications, 2);
    },
  );

  test('contador atrasado ignora resultado recebido após seu prazo', () async {
    final notifications = Completer<List<Map<String, dynamic>>>();
    final api = _TestApi()..onNotifications = (_) => notifications.future;
    final session = AppSession(
      api: api,
      store: _MemorySessionStore(),
      notificationTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(session.dispose);
    await _authenticate(session);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    notifications.complete([
      {'id': 1},
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(session.unreadNotifications, 0);
  });

  test('falha de gravação nunca publica sessão autenticada', () async {
    final store = _MemorySessionStore()
      ..onSave = (_) async => throw StateError('secure storage unavailable');
    final session = AppSession(api: _TestApi(), store: store);
    addTearDown(session.dispose);
    var publishedAuthentication = false;
    session.addListener(() {
      if (session.isLoggedIn) publishedAuthentication = true;
    });

    await expectLater(_authenticate(session), throwsA(isA<SessionException>()));

    expect(publishedAuthentication, isFalse);
    expect(session.user, isNull);
    expect(session.token, isNull);
    expect(session.persistenceError, contains('salvar a sessão'));
    expect(store.token, isNull);
  });

  test('gravação após timeout é limpa antes da sessão seguinte', () async {
    final delayedSave = Completer<void>();
    final store = _MemorySessionStore()
      ..onSave = (token) =>
          token == 'token-a' ? delayedSave.future : Future<void>.value();
    final api = _TestApi();
    final session = AppSession(
      api: api,
      store: store,
      storageTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(session.dispose);

    await expectLater(_authenticate(session), throwsA(isA<SessionException>()));
    expect(session.isLoggedIn, isFalse);
    api.auth = const AuthResult(token: 'token-b', user: _user);
    final newLogin = _authenticate(session);
    delayedSave.complete();
    await newLogin;

    expect(store.events, ['save:token-a', 'clear', 'save:token-b']);
    expect(store.token, 'token-b');
    expect(session.token, 'token-b');
    expect(session.persistenceError, isNull);
  });

  test(
    'logout avisa imediatamente e permite repetir limpeza após falha',
    () async {
      final delayedClear = Completer<void>();
      final store = _MemorySessionStore();
      final session = AppSession(
        api: _TestApi(),
        store: store,
        storageTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(session.dispose);
      await _authenticate(session);
      store.onClear = () => delayedClear.future;
      var guestNotice = false;
      session.addListener(() {
        if (!session.isLoggedIn) guestNotice = true;
      });

      final logout = session.logout();
      expect(session.user, isNull);
      expect(session.token, isNull);
      expect(guestNotice, isTrue);
      await logout;
      expect(session.persistenceError, contains('apagar a sessão'));

      delayedClear.complete();
      await Future<void>.delayed(Duration.zero);
      store.onClear = null;
      await session.logout();
      expect(store.token, isNull);
      expect(session.persistenceError, isNull);
    },
  );

  test('resultado de login pendente não restaura sessão após logout', () async {
    final delayedLogin = Completer<AuthResult>();
    final api = _TestApi()..onLogin = () => delayedLogin.future;
    final store = _MemorySessionStore();
    final session = AppSession(api: api, store: store);
    addTearDown(session.dispose);
    final rejected = expectLater(
      _authenticate(session),
      throwsA(isA<SessionException>()),
    );

    await session.logout();
    delayedLogin.complete(_auth);
    await rejected;

    expect(session.isLoggedIn, isFalse);
    expect(store.events, ['clear']);
  });

  test('perfil pendente não restaura dados depois do logout', () async {
    final delayedUpdate = Completer<AppUser>();
    final api = _TestApi()..onUpdate = () => delayedUpdate.future;
    final store = _MemorySessionStore();
    final session = AppSession(api: api, store: store);
    addTearDown(session.dispose);
    await _authenticate(session);
    final rejected = expectLater(
      _updateProfile(session),
      throwsA(isA<SessionException>()),
    );

    await session.logout();
    delayedUpdate.complete(_user.copyWith(name: 'Outro nome'));
    await rejected;

    expect(session.user, isNull);
    expect(store.token, isNull);
  });

  testWidgets('login mostra campos obrigatórios e e-mail inválido', (
    tester,
  ) async {
    final api = _TestApi();
    final session = AppSession(api: api, store: _MemorySessionStore());
    addTearDown(session.dispose);
    await _showScreen(tester, LoginScreen(session: session));

    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(find.text('Informe sua senha.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'endereco-invalido');
    await tester.enterText(find.byType(TextField).at(1), 'senha123');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(api.loginCalls, 0);
  });

  testWidgets('teclado envia login uma vez e exibe espera', (tester) async {
    final delayedLogin = Completer<AuthResult>();
    final api = _TestApi()..onLogin = () => delayedLogin.future;
    final session = AppSession(api: api, store: _MemorySessionStore());
    addTearDown(session.dispose);
    await _showScreen(tester, LoginScreen(session: session));
    await _fillScreen(tester, 'login');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    tester.widget<TextField>(find.byType(TextField).at(1)).onSubmitted!(
      'senha123',
    );
    expect(api.loginCalls, 1);
    expect(find.text('Entrando...'), findsOneWidget);
    delayedLogin.complete(_auth);
    await tester.pumpAndSettle();
    expect(session.isLoggedIn, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro valida e-mail antes de enviar', (tester) async {
    final api = _TestApi();
    final session = AppSession(api: api, store: _MemorySessionStore());
    addTearDown(session.dispose);
    await _showScreen(tester, RegisterScreen(session: session, api: api));
    await _fillScreen(tester, 'register');
    await tester.enterText(find.byType(TextField).at(1), 'sem-arroba');

    await tester.ensureVisible(find.text('Criar conta'));
    await tester.tap(find.text('Criar conta'));
    await tester.pump();

    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(api.registerCalls, 0);
  });

  testWidgets('cadastro permite recarregar cursos após erro', (tester) async {
    var attempts = 0;
    final api = _TestApi()
      ..onCourses = () async {
        if (++attempts == 1) throw StateError('offline');
        return ['Engenharia'];
      };
    final session = AppSession(api: api, store: _MemorySessionStore());
    addTearDown(session.dispose);
    await _showScreen(tester, RegisterScreen(session: session, api: api));
    expect(find.text('Não foi possível carregar os cursos.'), findsOneWidget);

    await tester.tap(find.text('Tentar carregar os cursos'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Engenharia'), findsOneWidget);
    expect(find.text('Não foi possível carregar os cursos.'), findsNothing);
  });

  testWidgets('perfil aceita o semestre máximo permitido no cadastro', (
    tester,
  ) async {
    final api = _TestApi();
    final session = AppSession(api: api, store: _MemorySessionStore());
    addTearDown(session.dispose);
    await _showScreen(
      tester,
      EditProfileScreen(
        user: _user.copyWith(semester: 20),
        session: session,
        api: api,
      ),
    );
    expect(find.text('20º semestre'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cadastro rejeita senha menor que o contrato do servidor', (
    tester,
  ) async {
    final api = _TestApi();
    final session = AppSession(api: api, store: _MemorySessionStore());
    addTearDown(session.dispose);
    await _showScreen(tester, RegisterScreen(session: session, api: api));
    await _fillScreen(tester, 'register');
    await tester.enterText(find.byType(TextField).at(2), '123456789');
  await tester.ensureVisible(find.text('Criar conta'));
  await tester.tap(find.text('Criar conta'));
  await tester.pump();
  expect(
    find.text('Use uma senha entre 10 e 128 caracteres.'),
    findsOneWidget,
  );
  expect(api.registerCalls, 0);
});

testWidgets('cadastro exige nome com pelo menos dois caracteres', (
  tester,
) async {
  final api = _TestApi();
  final session = AppSession(api: api, store: _MemorySessionStore());
  addTearDown(session.dispose);
  await _showScreen(tester, RegisterScreen(session: session, api: api));
  await _fillScreen(tester, 'register');
  await tester.enterText(find.byType(TextField).at(0), ' A ');
  await tester.ensureVisible(find.text('Criar conta'));
  await tester.tap(find.text('Criar conta'));
  await tester.pump();
  expect(
    find.text('Informe um nome entre 2 e 100 caracteres.'),
    findsOneWidget,
  );
  expect(api.registerCalls, 0);
});

  for (final screen in ['login', 'register', 'profile']) {
    for (final failure in [false, true]) {
      testWidgets(
        '$screen ignora ${failure ? 'erro' : 'sucesso'} após fechar a tela',
        (tester) async {
          final delayedAuth = Completer<AuthResult>();
          final delayedUpdate = Completer<AppUser>();
          final api = _TestApi();
          final session = AppSession(api: api, store: _MemorySessionStore());
          addTearDown(session.dispose);
          if (screen == 'profile') await _authenticate(session);
          api.onLogin = () => delayedAuth.future;
          api.onRegister = () => delayedAuth.future;
          api.onUpdate = () => delayedUpdate.future;
          await _showScreen(tester, _screen(screen, session, api));
          await _fillScreen(tester, screen);
          await tester.tap(find.text(_submitLabel(screen)));
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());

          if (screen == 'profile') {
            if (failure) {
              delayedUpdate.completeError(
                const ApiException('Falha tardia.', 503),
              );
            } else {
              delayedUpdate.complete(_user.copyWith(name: 'Perfil atualizado'));
            }
          } else if (failure) {
            delayedAuth.completeError(const ApiException('Falha tardia.', 503));
          } else {
            delayedAuth.complete(_auth);
          }
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final screen in ['register', 'profile']) {
    testWidgets('$screen ignora erro de cursos após fechar a tela', (
      tester,
    ) async {
      final delayedCourses = Completer<List<String>>();
      final api = _TestApi()..onCourses = () => delayedCourses.future;
      final session = AppSession(api: api, store: _MemorySessionStore());
      addTearDown(session.dispose);
      await _showScreen(tester, _screen(screen, session, api), settle: false);
      await tester.pumpWidget(const SizedBox.shrink());

      delayedCourses.completeError(StateError('Falha tardia.'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'register faz login automático quando servidor retorna 409 e senha confere',
    () async {
      final api = _TestApi()
        ..onRegister = () async => throw const ApiException(
          'Este e-mail já está cadastrado.',
          409,
          kind: ApiFailureKind.conflict,
        );
      final store = _MemorySessionStore();
      final session = AppSession(api: api, store: store);
      addTearDown(session.dispose);

      await _authenticate(session, register: true);

      expect(api.registerCalls, 1);
      expect(api.loginCalls, 1);
      expect(session.isLoggedIn, isTrue);
      expect(session.user, _user);
      expect(store.token, _auth.token);
    },
  );

  test(
    'register preserva 409 quando fallback de login falha com 401 e propaga 429',
    () async {
      final wrongPassApi = _TestApi()
        ..onRegister = () async {
          throw const ApiException(
            'Este e-mail já está cadastrado.',
            409,
            kind: ApiFailureKind.conflict,
          );
        }
        ..onLogin = () async {
          throw const ApiException(
            'E-mail ou senha inválidos.',
            401,
            kind: ApiFailureKind.unauthorized,
          );
        };
      final wrongPassSession = AppSession(
        api: wrongPassApi,
        store: _MemorySessionStore(),
      );
      addTearDown(wrongPassSession.dispose);

      await expectLater(
        _authenticate(wrongPassSession, register: true),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.message, 'message', 'Este e-mail já está cadastrado.'),
        ),
      );
      expect(wrongPassSession.isLoggedIn, isFalse);

      final rateLimitedApi = _TestApi()
        ..onRegister = () async {
          throw const ApiException(
            'Este e-mail já está cadastrado.',
            409,
            kind: ApiFailureKind.conflict,
          );
        }
        ..onLogin = () async {
          throw const ApiException(
            'Muitas tentativas em sequência.',
            429,
            kind: ApiFailureKind.rateLimited,
          );
        };
      final rateLimitedSession = AppSession(
        api: rateLimitedApi,
        store: _MemorySessionStore(),
      );
      addTearDown(rateLimitedSession.dispose);

      await expectLater(
        _authenticate(rateLimitedSession, register: true),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 429)
              .having((e) => e.kind, 'kind', ApiFailureKind.rateLimited),
        ),
      );
      expect(rateLimitedSession.isLoggedIn, isFalse);
    },
  );

  testWidgets('edit profile valida nome curto antes de chamar a API', (
    tester,
  ) async {
    var updateCalls = 0;
    final api = _TestApi()
      ..onUpdate = () async {
        updateCalls++;
        return _user;
      };
    final session = AppSession(api: api, store: _MemorySessionStore());
    addTearDown(session.dispose);
    await session.login(email: _user.email, password: 'senha123');

    await _showScreen(tester, _screen('profile', session, api));
    await tester.enterText(find.byType(TextField).first, 'A');
    final saveButton = find.text(_submitLabel('profile'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Informe um nome entre 2 e 100 caracteres.'), findsOneWidget);
    expect(updateCalls, 0);
  });

  testWidgets('profile screen suporta nome com espaços sem RangeError', (
    tester,
  ) async {
    const blankNameUser = AppUser(
      id: 1,
      name: '   ',
      email: 'aluno@example.com',
      course: 'Engenharia',
      semester: 1,
      group: 'EC4A',
      role: 'student',
    );
    final api = _TestApi()
      ..auth = const AuthResult(token: 'token-blank', user: blankNameUser);
    final session = AppSession(api: api, store: _MemorySessionStore());
    addTearDown(session.dispose);
    await session.login(email: blankNameUser.email, password: 'senha123');

    const emptyCampus = CampusMap(
      building: BuildingInfo(id: 'b1', name: 'Campus', version: '1'),
      floors: [],
      pois: [],
      nodes: [],
      edges: [],
    );

    await _showScreen(
      tester,
      ProfileScreen(campus: emptyCampus, session: session),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('G'), findsOneWidget);
  });
}

Future<void> _authenticate(AppSession session, {bool register = false}) =>
    register
    ? session.register(
        name: _user.name,
        email: _user.email,
        password: 'senha123',
        course: _user.course,
        semester: _user.semester,
        group: _user.group,
      )
    : session.login(email: _user.email, password: 'senha123');

Future<void> _updateProfile(AppSession session) => session.updateProfile(
  name: _user.name,
  course: _user.course,
  semester: _user.semester,
  group: _user.group,
);

Future<void> _showScreen(
  WidgetTester tester,
  Widget screen, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: GranMapTheme.dark, home: screen));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Widget _screen(String screen, AppSession session, GranMapApi api) =>
    switch (screen) {
      'login' => LoginScreen(session: session),
      'register' => RegisterScreen(session: session, api: api),
      _ => EditProfileScreen(user: _user, session: session, api: api),
    };

String _submitLabel(String screen) => switch (screen) {
  'login' => 'Entrar',
  'register' => 'Criar conta',
  _ => 'Salvar alterações',
};

Future<void> _fillScreen(WidgetTester tester, String screen) async {
  final fields = find.byType(TextField);
  if (screen == 'login') {
    await tester.enterText(fields.at(0), _user.email);
    await tester.enterText(fields.at(1), 'senha123');
  } else if (screen == 'register') {
    await tester.enterText(fields.at(0), _user.name);
    await tester.enterText(fields.at(1), _user.email);
    await tester.enterText(fields.at(2), 'Senha12345!');
    await tester.enterText(fields.at(3), _user.group);
  }
}

class _MemorySessionStore extends LocalStore {
  String? token;
  AppUser? user;
  Future<void> Function(String)? onSave;
  Future<void> Function()? onClear;
  final List<String> events = [];

  @override
  Future<void> saveSession(String token, AppUser user) async {
    if (onSave != null) await onSave!(token);
    events.add('save:$token');
    this.token = token;
    this.user = user;
  }

  @override
  Future<void> clearSession() async {
    if (onClear != null) await onClear!();
    events.add('clear');
    token = null;
    user = null;
  }

  @override
  Future<String?> readToken() async => token;

  @override
  Future<AppUser?> readUser() async => user;
}

class _TestApi extends GranMapApi {
  _TestApi() : super(client: MockClient((_) async => http.Response('', 500)));

  AuthResult auth = _auth;
  Future<AuthResult> Function()? onLogin;
  Future<AuthResult> Function()? onRegister;
  Future<AppUser> Function()? onUpdate;
  Future<List<String>> Function()? onCourses;
  Future<List<Map<String, dynamic>>> Function(String)? onNotifications;
  int loginCalls = 0;
  int registerCalls = 0;

  @override
  Future<AuthResult> login({required String email, required String password}) {
    loginCalls++;
    return onLogin?.call() ?? Future.value(auth);
  }

  @override
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    required String course,
    required int semester,
    required String group,
  }) {
    registerCalls++;
    return onRegister?.call() ?? Future.value(auth);
  }

  @override
  Future<AppUser> updateMe({
    required String token,
    required String name,
    required String course,
    required int semester,
    required String group,
  }) => onUpdate?.call() ?? Future.value(_user);

  @override
  Future<List<String>> fetchCourses() =>
      onCourses?.call() ?? Future.value(['Engenharia']);

  @override
  Future<List<Map<String, dynamic>>> fetchNotifications(
    String token, {
    bool unreadOnly = false,
  }) => onNotifications?.call(token) ?? Future.value([]);

  @override
  Future<bool> health() async => true;

  @override
  Future<AppUser> fetchMe(String token) async => _user;

  @override
  Future<void> logout(String token) async {}
}
