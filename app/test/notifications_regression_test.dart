import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/models/user.dart';
import 'package:granmap/screens/login_screen.dart';
import 'package:granmap/screens/notifications_screen.dart';
import 'package:granmap/services/app_session.dart';
import 'package:granmap/services/granmap_api.dart';
import 'package:granmap/services/local_store.dart';
import 'package:granmap/services/notifications_service.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _storageTimeout = Duration(milliseconds: 100);
const _networkTimeout = Duration(milliseconds: 200);
const _offline = ApiException('offline', 0, kind: ApiFailureKind.network);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  testWidgets('cache aparece antes da rede e timeout oferece retry funcional', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    final store = _NotificationStore()
      ..cached['user_1'] = [_item(1, 'Cache da conta A')];
    final api = _NotificationApi()..onFetch = (_) => pending.future;
    final session = _Session();
    await _mount(tester, session, api, store);

    expect(find.text('Cache da conta A'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(store.readScopes, ['user_1']);

    await tester.pump(_networkTimeout);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Cache da conta A'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);

    api.onFetch = (_) async => [_item(2, 'Atualização nova')];
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Atualização nova'), findsOneWidget);
    expect(find.text('Cache da conta A'), findsNothing);
    expect(api.fetchTokens, ['token-1', 'token-1']);
    expect(find.text('Tentar novamente'), findsNothing);

    pending.complete([_item(3, 'Resposta vencida')]);
    await tester.pump();
    expect(find.text('Resposta vencida'), findsNothing);
    expect(store.cached['user_1']!.single['title'], 'Atualização nova');
    await _close(tester);
  });

  for (final hang in [true, false]) {
    testWidgets(
      'cache ${hang ? 'travado' : 'com erro'} e rede indisponível liberam loading',
      (tester) async {
        final cache = Completer<List<Map<String, dynamic>>>();
        final remote = Completer<List<Map<String, dynamic>>>();
        final store = _NotificationStore()
          ..onRead = (_) => hang
              ? cache.future
              : Future.error(StateError('storage unavailable'));
        final api = _NotificationApi()..onFetch = (_) => remote.future;
        final session = _Session();
        await _mount(tester, session, api, store);
        if (hang) {
          expect(api.fetchTokens, isEmpty);
          await tester.pump(_storageTimeout);
        }
        expect(api.fetchTokens, ['token-1']);
        await tester.pump(_networkTimeout);

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Tentar novamente'), findsOneWidget);
        expect(tester.takeException(), isNull);
        cache.complete([]);
        remote.completeError(_offline);
        await tester.pump();
        await _close(tester);
      },
    );
  }

  testWidgets('cache com erro não impede dados válidos da rede', (
    tester,
  ) async {
    final store = _NotificationStore()
      ..onRead = (_) async => throw StateError('read failed');
    final api = _NotificationApi()
      ..onFetch = (_) async => [_item(1, 'Recebida online')];
    final session = _Session();
    await _mount(tester, session, api, store);

    expect(find.text('Recebida online'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _close(tester);
  });

  testWidgets('gravação falha preserva dados online sem esperar pelo badge', (
    tester,
  ) async {
    final badge = Completer<void>();
    final store = _NotificationStore()
      ..cached['user_1'] = [_item(1, 'Cache antigo')]
      ..onSave = (_, _) async => throw StateError('write failed');
    final api = _NotificationApi()
      ..onFetch = (_) async => [_item(2, 'Online autoritativa')];
    final session = _Session()..badge = badge.future;
    await _mount(tester, session, api, store);

    expect(find.text('Online autoritativa'), findsOneWidget);
    expect(find.text('Cache antigo'), findsNothing);
    expect(find.textContaining('não foi possível salvá-las'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(session.badgeCalls, 1);
    badge.complete();
    await tester.pump();
    await _close(tester);
  });

  testWidgets(
    'logout limpa cache visível e ignora resposta da conta anterior',
    (tester) async {
      final remote = Completer<List<Map<String, dynamic>>>();
      final store = _NotificationStore()
        ..cached['user_1'] = [_item(1, 'Privada da conta A')];
      final api = _NotificationApi()..onFetch = (_) => remote.future;
      final session = _Session();
      await _mount(tester, session, api, store);
      expect(find.text('Privada da conta A'), findsOneWidget);

      session.useAccount(null);
      await tester.pump();
      expect(find.text('Privada da conta A'), findsNothing);
      expect(find.text('Entrar na minha conta'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      remote.complete([_item(2, 'Remota da conta A')]);
      await tester.pump();
      expect(find.text('Remota da conta A'), findsNothing);
      expect(store.saveStarts, isEmpty);
      expect(session.badgeCalls, 0);
      await _close(tester);
    },
  );

  testWidgets('A troca por B antes da resposta não grava A no cache de B', (
    tester,
  ) async {
    final remoteA = Completer<List<Map<String, dynamic>>>();
    final store = _NotificationStore();
    final api = _NotificationApi()
      ..onFetch = (token) => token == 'token-1'
          ? remoteA.future
          : Future.value([_item(2, 'Exclusiva da conta B')]);
    final session = _Session();
    await _mount(tester, session, api, store);

    session.useAccount(2);
    await tester.pump();
    remoteA.complete([_item(1, 'Exclusiva da conta A')]);
    await tester.pumpAndSettle();

    expect(find.text('Exclusiva da conta B'), findsOneWidget);
    expect(find.text('Exclusiva da conta A'), findsNothing);
    expect(store.saveStarts, ['user_2:Exclusiva da conta B']);
    expect(store.cached['user_2']!.single['title'], 'Exclusiva da conta B');
    expect(store.cached['user_1'], isNull);
    await _close(tester);
  });

  testWidgets('gravação A já iniciada mantém escopo após troca para B', (
    tester,
  ) async {
    final writeA = Completer<void>();
    final store = _NotificationStore()
      ..onSave = (scope, _) =>
          scope == 'user_1' ? writeA.future : Future<void>.value();
    final api = _NotificationApi()
      ..onFetch = (token) async => [
        _item(token == 'token-1' ? 1 : 2, 'Item de $token'),
      ];
    final session = _Session();
    await _mount(tester, session, api, store);
    expect(find.text('Item de token-1'), findsOneWidget);
    expect(store.saveStarts, ['user_1:Item de token-1']);

    session.useAccount(2);
    await tester.pump();
    expect(find.text('Item de token-1'), findsNothing);
    expect(find.text('Item de token-2'), findsOneWidget);
    writeA.complete();
    await tester.pumpAndSettle();

    expect(store.cached['user_1']!.single['title'], 'Item de token-1');
    expect(store.cached['user_2']!.single['title'], 'Item de token-2');
    expect(find.textContaining('não foi possível salvá-las'), findsNothing);
    await _close(tester);
  });

  test('FIFO entre instâncias aguarda gravação nativa após timeout', () async {
    final pending = Completer<void>();
    final store = _NotificationStore()
      ..onSave = (_, items) => items.single['title'] == 'Antiga'
          ? pending.future
          : Future<void>.value();
    final api = _NotificationApi();
    final first = NotificationsService(
      store: store,
      api: api,
      storageTimeout: const Duration(milliseconds: 10),
    );
    final second = NotificationsService(store: store, api: api);
    await expectLater(
      first.saveCached('fifo_user', [_item(1, 'Antiga')]),
      throwsA(isA<TimeoutException>()),
    );

    final newer = second.saveCached('fifo_user', [_item(2, 'Nova')]);
    await Future<void>.delayed(Duration.zero);
    expect(store.saveStarts, ['fifo_user:Antiga']);
    pending.complete();
    await newer;

    expect(store.saveCompletions, ['fifo_user:Antiga', 'fifo_user:Nova']);
    expect(store.cached['fifo_user']!.single['title'], 'Nova');
    first.dispose();
    second.dispose();
    api.dispose();
  });

  testWidgets(
    'falha ao marcar preserva item/cache e permite repetir a marcação',
    (tester) async {
      final store = _NotificationStore();
      var attempts = 0;
      final api = _NotificationApi()
        ..onMark = (_, _) async {
          if (++attempts == 1) throw _offline;
        };
      final session = _Session();
      await _mount(tester, session, api, store);
      await tester.tap(find.text('Aviso da faculdade'));
      await tester.pump();

      expect(
        find.textContaining('A leitura não foi confirmada'),
        findsOneWidget,
      );
      expect(find.text('Lida'), findsNothing);
      expect(store.cached['user_1']!.single['read'], isFalse);
      expect(store.saveStarts, hasLength(1));
      expect(_markAllButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(api.markCalls, ['token-1:1', 'token-1:1']);
      expect(find.text('Lida'), findsOneWidget);
      expect(store.cached['user_1']!.single['read'], isTrue);
      expect(find.text('Tentar novamente'), findsNothing);
      await _close(tester);
    },
  );

  testWidgets('ID inválido não envia marcação nem prende o botão', (
    tester,
  ) async {
    final store = _NotificationStore();
    final api = _NotificationApi()
      ..onFetch = (_) async => [_item('invalid', 'Aviso com ID inválido')];
    final session = _Session();
    await _mount(tester, session, api, store);
    await tester.tap(find.text('Aviso com ID inválido'));
    await tester.pump();

    expect(api.markCalls, isEmpty);
    expect(
      find.textContaining('Esta notificação está indisponível'),
      findsOneWidget,
    );
    expect(_markAllButton(tester).onPressed, isNotNull);
    expect(store.cached['user_1']!.single['read'], isFalse);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  test(
    'validação de ID recusa ausente, fracionário, negativo e não finito',
    () {
      for (final invalid in [
        null,
        '1',
        0,
        -1,
        1.5,
        double.nan,
        double.infinity,
      ]) {
        expect(NotificationsService.notificationId(invalid), isNull);
      }
      expect(NotificationsService.notificationId(1), 1);
      expect(NotificationsService.notificationId(2.0), 2);
    },
  );

  testWidgets(
    'marcar todas trava duplo toque, expira e permite tentar de novo',
    (tester) async {
      final pending = Completer<void>();
      final store = _NotificationStore();
      final api = _NotificationApi();
      api.onMarkAll = (_) =>
          api.markAllTokens.length == 1 ? pending.future : Future<void>.value();
      final session = _Session();
      await _mount(tester, session, api, store);

      final submit = _markAllButton(tester).onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(api.markAllTokens, ['token-1']);
      expect(find.text('Atualizando…'), findsOneWidget);
      await tester.pump(_networkTimeout);

      expect(find.text('Lida'), findsNothing);
      expect(store.cached['user_1']!.single['read'], isFalse);
      expect(_markAllButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(api.markAllTokens, ['token-1', 'token-1']);
      expect(find.text('Lida'), findsOneWidget);
      expect(store.cached['user_1']!.single['read'], isTrue);
      pending.complete();
      await tester.pump();
      await _close(tester);
    },
  );

  testWidgets('marcação A pendente não modifica itens nem cache de B', (
    tester,
  ) async {
    final pending = Completer<void>();
    final store = _NotificationStore();
    final api = _NotificationApi();
    api.onMark = (_, _) => pending.future;
    api.onFetch = (token) async => [_item(1, 'Aviso de $token')];
    final session = _Session();
    await _mount(tester, session, api, store);
    await tester.tap(find.text('Aviso de token-1'));
    await tester.pump();

    session.useAccount(2);
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Aviso de token-2'), findsOneWidget);
    expect(find.text('Lida'), findsNothing);
    expect(api.markCalls, ['token-1:1']);
    expect(store.cached['user_1']!.single['read'], isFalse);
    expect(store.cached['user_2']!.single['read'], isFalse);
    expect(_markAllButton(tester).onPressed, isNotNull);
    await _close(tester);
  });

  testWidgets('toque capturado em A não marca o mesmo ID da conta B', (
    tester,
  ) async {
    final store = _NotificationStore();
    final api = _NotificationApi()
      ..onFetch = (token) async => [_item(1, 'Aviso de $token')];
    final session = _Session();
    await _mount(tester, session, api, store);
    final oldTap = tester
        .widget<InkWell>(
          find
              .ancestor(
                of: find.text('Aviso de token-1'),
                matching: find.byType(InkWell),
              )
              .first,
        )
        .onTap!;

    session.useAccount(2);
    await tester.pump();
    oldTap();
    await tester.pump();

    expect(api.markCalls, isEmpty);
    expect(find.text('Aviso de token-2'), findsOneWidget);
    expect(store.cached['user_2']!.single['read'], isFalse);
    await _close(tester);
  });

  testWidgets('401 preserva cache e oferece login compreensível', (
    tester,
  ) async {
    final store = _NotificationStore()
      ..cached['user_1'] = [_item(1, 'Último aviso salvo')];
    final api = _NotificationApi()
      ..onFetch = (_) async => throw const ApiException('expired', 401);
    final session = _Session();
    await _mount(tester, session, api, store);

    expect(find.text('Último aviso salvo'), findsOneWidget);
    expect(find.textContaining('Sua sessão expirou'), findsOneWidget);
    expect(find.text('Entrar novamente'), findsOneWidget);
    await tester.tap(find.text('Entrar novamente'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  for (final marking in [false, true]) {
    for (final fail in [false, true]) {
      testWidgets(
        'tela fechada ignora ${marking ? 'marcação' : 'consulta'} ${fail ? 'com erro' : 'concluída'}',
        (tester) async {
          final remote = Completer<List<Map<String, dynamic>>>();
          final mark = Completer<void>();
          final store = _NotificationStore();
          final api = _NotificationApi();
          if (marking) {
            api.onMark = (_, _) => mark.future;
          } else {
            api.onFetch = (_) => remote.future;
          }
          final session = _Session();
          await _mount(tester, session, api, store);
          if (marking) {
            await tester.tap(find.text('Aviso da faculdade'));
            await tester.pump();
          }
          await _close(tester);

          if (marking) {
            if (fail) {
              mark.completeError(_offline);
            } else {
              mark.complete();
            }
          } else if (fail) {
            remote.completeError(_offline);
          } else {
            remote.complete([_item(1, 'Resposta após fechar')]);
          }
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(api.disposed, isFalse);
          if (marking) {
            expect(store.cached['user_1']!.single['read'], isFalse);
          } else {
            expect(store.saveStarts, isEmpty);
          }
        },
      );
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Session session,
  _NotificationApi api,
  _NotificationStore store,
) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(session.dispose);
  addTearDown(api.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: GranMapTheme.dark,
      home: NotificationsScreen(
        session: session,
        api: api,
        store: store,
        storageTimeout: _storageTimeout,
        networkTimeout: _networkTimeout,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

TextButton _markAllButton(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Marcar lidas'));

Map<String, dynamic> _item(Object? id, String title) => {
  'id': id,
  'title': title,
  'body': 'Sua turma recebeu uma atualização.',
  'kind': 'schedule_changed',
  'read': false,
};

class _NotificationStore extends LocalStore {
  final Map<String, List<Map<String, dynamic>>> cached = {};
  final List<String> readScopes = [];
  final List<String> saveStarts = [];
  final List<String> saveCompletions = [];
  Future<List<Map<String, dynamic>>> Function(String)? onRead;
  Future<void> Function(String, List<Map<String, dynamic>>)? onSave;

  @override
  Future<List<Map<String, dynamic>>> readNotifications(String scope) async {
    readScopes.add(scope);
    return onRead?.call(scope) ?? cached[scope] ?? [];
  }

  @override
  Future<void> saveNotifications(
    String scope,
    List<Map<String, dynamic>> items,
  ) async {
    final label = '$scope:${items.map((item) => item['title']).join(',')}';
    saveStarts.add(label);
    if (onSave != null) await onSave!(scope, items);
    cached[scope] = [for (final item in items) Map<String, dynamic>.from(item)];
    saveCompletions.add(label);
  }
}

class _NotificationApi extends GranMapApi {
  _NotificationApi()
    : super(client: MockClient((_) async => http.Response('', 500)));

  Future<List<Map<String, dynamic>>> Function(String)? onFetch;
  Future<void> Function(String, int)? onMark;
  Future<void> Function(String)? onMarkAll;
  final List<String> fetchTokens = [];
  final List<String> markCalls = [];
  final List<String> markAllTokens = [];
  bool disposed = false;

  @override
  Future<List<Map<String, dynamic>>> fetchNotifications(
    String token, {
    bool unreadOnly = false,
  }) {
    fetchTokens.add(token);
    return onFetch?.call(token) ??
        Future.value([_item(1, 'Aviso da faculdade')]);
  }

  @override
  Future<void> markNotificationRead(String token, int notificationId) {
    markCalls.add('$token:$notificationId');
    return onMark?.call(token, notificationId) ?? Future<void>.value();
  }

  @override
  Future<void> markAllNotificationsRead(String token) {
    markAllTokens.add(token);
    return onMarkAll?.call(token) ?? Future<void>.value();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Session extends AppSession {
  _Session() : super(store: _NotificationStore(), api: _NotificationApi());

  int? account = 1;
  int badgeCalls = 0;
  Future<void>? badge;

  void useAccount(int? value) {
    account = value;
    notifyListeners();
  }

  @override
  String? get token => account == null ? null : 'token-$account';

  @override
  bool get isLoggedIn => account != null;

  @override
  String get storageScope => account == null ? 'guest' : 'user_$account';

  @override
  AppUser? get user => account == null
      ? null
      : AppUser(
          id: account!,
          name: 'Conta $account',
          email: 'conta$account@example.com',
          course: 'Engenharia',
          semester: 1,
          group: 'EC4A',
          role: 'student',
        );

  @override
  Future<void> refreshNotificationCount() {
    badgeCalls++;
    return badge ?? Future<void>.value();
  }
}
