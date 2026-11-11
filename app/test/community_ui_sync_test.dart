import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/community/community_models.dart';
import 'package:granmap/models/user.dart';
import 'package:granmap/screens/community_screen.dart';
import 'package:granmap/screens/login_screen.dart';
import 'package:granmap/services/app_session.dart';
import 'package:granmap/services/community_service.dart';
import 'package:granmap/services/community_sync_coordinator.dart';
import 'package:granmap/theme/granmap_theme.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _user = AppUser(
  id: 1,
  name: 'Aluno',
  email: 'aluno@test.local',
  course: 'Engenharia',
  semester: 4,
  group: 'EC4A',
  role: 'student',
);
RoomChangeContribution _proposal(String subject) => RoomChangeContribution(
  id: '1',
  subject: subject,
  authorName: 'Aluno',
  fromRoomName: 'A',
  toRoomName: 'B',
  reason: 'Aviso do professor',
  status: ContributionStatus.unverified,
  yesVotes: 0,
  noVotes: 0,
);
CommunitySnapshot _snapshot(String subject) => CommunitySnapshot(
  contributions: [_proposal(subject)],
  isOffline: false,
  pendingOperations: 0,
);

CommunitySnapshot _pendingSnapshot() => CommunitySnapshot(
  contributions: [_proposal('Voto pendente')],
  isOffline: true,
  pendingOperations: 1,
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  testWidgets(
    'comunidade ignora resposta da conta anterior e limpa dados no logout',
    (tester) async {
      final session = _Session();
      final service = _Service(session);
      final old = Completer<CommunitySnapshot>();
      service.onLoad = () =>
          service.loads == 1 ? old.future : Future.value(_snapshot('Conta B'));
      final sync = CommunitySyncCoordinator(session: session, service: service);
      addTearDown(() {
        sync.dispose();
        service.dispose();
        session.dispose();
      });
      await _show(
        tester,
        CommunityScreen(
          session: session,
          service: service,
          syncCoordinator: sync,
        ),
      );
      session.switchTo('user_2', 'token-b');
      await tester.pumpAndSettle();
      expect(find.text('Conta B'), findsOneWidget);
      old.complete(_snapshot('Conta A antiga'));
      await tester.pumpAndSettle();
      expect(find.text('Conta A antiga'), findsNothing);
      service.onLoad = () => Completer<CommunitySnapshot>().future;
      session.switchTo('guest', null);
      await tester.pump();
      expect(find.text('Conta B'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 13));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('voto não duplica e botão volta após timeout', (tester) async {
    final session = _Session();
    final service = _Service(session)
      ..onLoad = () async => _snapshot('Disciplina teste');
    final vote = Completer<void>();
    service.onVote = () => vote.future;
    final sync = CommunitySyncCoordinator(session: session, service: service);
    addTearDown(() {
      sync.dispose();
      service.dispose();
      session.dispose();
    });
    await _show(
      tester,
      CommunityScreen(
        session: session,
        service: service,
        syncCoordinator: sync,
        operationTimeout: const Duration(milliseconds: 50),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Está correto');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(service.votes, 1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(
      find.textContaining('Não foi possível confirmar o voto'),
      findsOneWidget,
    );
    vote.complete();
    await tester.pumpAndSettle();
    expect(service.votes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'coordenador envia fila sem abrir comunidade e pausa fora do app',
    (tester) async {
      final session = _Session();
      final service = _Service(session)..pending = true;
      final sync = CommunitySyncCoordinator(
        session: session,
        service: service,
        interval: const Duration(milliseconds: 100),
      );
      addTearDown(() {
        sync.dispose();
        service.dispose();
        session.dispose();
      });
      sync.start();
      await tester.pump();
      expect(service.loads, 1);
      sync.setForeground(false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.loads, 1);
      sync.setForeground(true);
      await tester.pump();
      expect(service.loads, 2);
      sync.stop();
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.loads, 2);
    },
  );

  testWidgets('coordenador não publica sincronização de outra conta', (
    tester,
  ) async {
    final session = _Session();
    final old = Completer<CommunitySnapshot>();
    final service = _Service(session)..pending = true;
    service.onLoad = () =>
        service.loads == 1 ? old.future : Future.value(_snapshot('Conta B'));
    final sync = CommunitySyncCoordinator(session: session, service: service);
    addTearDown(() {
      sync.dispose();
      service.dispose();
      session.dispose();
    });
    sync.start();
    await tester.pump();
    session.switchTo('user_2', 'token-b');
    await tester.pump();
    expect(sync.snapshotScope, 'user_2');
    old.complete(_snapshot('Conta A'));
    await tester.pump();
    expect(sync.lastSnapshot!.contributions.single.subject, 'Conta B');
    sync.stop();
  });

  testWidgets('substituir voto offline não anuncia confirmação remota', (
    tester,
  ) async {
    final session = _Session();
    final service = _Service(session)..onLoad = () async => _pendingSnapshot();
    final sync = CommunitySyncCoordinator(session: session, service: service);
    addTearDown(() {
      sync.dispose();
      service.dispose();
      session.dispose();
    });
    await _show(
      tester,
      CommunityScreen(
        session: session,
        service: service,
        syncCoordinator: sync,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contestar'));
    await tester.pumpAndSettle();
    expect(find.text('Seu voto foi registrado.'), findsNothing);
    expect(
      find.textContaining('Há envios aguardando sincronização'),
      findsOneWidget,
    );
  });

  testWidgets('evento de sync durante diálogo é aplicado ao cancelar', (
    tester,
  ) async {
    final session = _Session();
    final service = _Service(session)..pending = true;
    service.onLoad = () async =>
        service.loads == 1 ? _pendingSnapshot() : _snapshot('Sincronizada');
    final sync = CommunitySyncCoordinator(session: session, service: service);
    addTearDown(() {
      sync.dispose();
      service.dispose();
      session.dispose();
    });
    await _show(
      tester,
      CommunityScreen(
        session: session,
        service: service,
        syncCoordinator: sync,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Informar'));
    await tester.pumpAndSettle();
    sync.start();
    await tester.pump();
    expect(service.loads, 2);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(service.loads, 3);
    expect(find.text('Sincronizada'), findsOneWidget);
    expect(find.text('1 pendente'), findsNothing);
    sync.stop();
  });

  testWidgets('visitante com duplo toque abre somente um login', (
    tester,
  ) async {
    final session = _Session()..switchTo('guest', null);
    final service = _Service(session);
    final sync = CommunitySyncCoordinator(session: session, service: service);
    addTearDown(() {
      sync.dispose();
      service.dispose();
      session.dispose();
    });
    await _show(
      tester,
      CommunityScreen(
        session: session,
        service: service,
        syncCoordinator: sync,
      ),
    );
    await tester.pumpAndSettle();
    final action = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Informar'))
        .onPressed!;
    action();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen, skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('callback de voto de um frame antigo não usa conta nova', (
    tester,
  ) async {
    final session = _Session();
    final service = _Service(session);
    final sync = CommunitySyncCoordinator(session: session, service: service);
    addTearDown(() {
      sync.dispose();
      service.dispose();
      session.dispose();
    });
    await _show(
      tester,
      CommunityScreen(
        session: session,
        service: service,
        syncCoordinator: sync,
      ),
    );
    await tester.pumpAndSettle();
    final action = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Está correto'))
        .onPressed!;
    session.switchTo('user_2', 'token-b');
    action();
    await tester.pumpAndSettle();
    expect(service.votes, 0);
  });
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: GranMapTheme.dark,
      home: Scaffold(body: screen),
    ),
  );
  await tester.pump();
}

class _Session extends AppSession {
  String scope = 'user_1';
  String? authToken = 'token-a';
  @override
  String get storageScope => scope;
  @override
  String? get token => authToken;
  @override
  AppUser? get user => authToken == null ? null : _user;
  @override
  bool get isLoggedIn => authToken != null;
  void switchTo(String newScope, String? newToken) {
    scope = newScope;
    authToken = newToken;
    notifyListeners();
  }
}

class _Service extends CommunityService {
  _Service(AppSession session) : super(session: session);
  int loads = 0;
  int votes = 0;
  bool pending = false;
  Future<CommunitySnapshot> Function()? onLoad;
  Future<void> Function()? onVote;
  @override
  Future<CommunitySnapshot> load() {
    loads++;
    return onLoad?.call() ?? Future.value(_snapshot('Sincronizada'));
  }

  @override
  Future<bool> hasPendingWork() async => pending;
  @override
  Future<void> vote({
    required RoomChangeContribution contribution,
    required bool agrees,
  }) {
    votes++;
    return onVote?.call() ?? Future.value();
  }
}
