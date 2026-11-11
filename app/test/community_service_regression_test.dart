import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/community/community_models.dart';
import 'package:granmap/config/api_config.dart';
import 'package:granmap/models/user.dart';
import 'package:granmap/services/app_session.dart';
import 'package:granmap/services/community_service.dart';
import 'package:granmap/services/granmap_api.dart';
import 'package:granmap/services/local_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late _Harness harness;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    harness = _Harness();
  });
  tearDown(() {
    harness.dispose();
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test(
    'native ACK write timeout stays visible and holds the FIFO barrier',
    () async {
      final slow = harness.another(
        storageTimeout: const Duration(milliseconds: 30),
      );
      Completer<void>? acknowledge;
      harness.api.beforeWrite = (_) async {
        acknowledge = harness.store.blockNextSave();
      };
      await expectLater(
        harness.create('ACK waiting', service: slow),
        throwsA(isA<TimeoutException>()),
      );
      expect(harness.api.writes, hasLength(1));
      expect(harness.state.operations, hasLength(1));
      harness.api.beforeWrite = null;
      final following = harness.create('Following ACK');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(harness.api.writes, hasLength(1));
      acknowledge!.complete();
      await following;
      expect(harness.state.operations, isEmpty);
      expect(harness.state.contributions.map((item) => item.subject).toSet(), {
        'ACK waiting',
        'Following ACK',
      });
    },
  );

  test('atomic community migration retains original cache and queue', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final store = LocalStore();
      final old = {
        'type': 'vote',
        'proposal_id': 42,
        'agrees': false,
        'idempotency_key': 'legacy-vote',
        'dead_letter': true,
        'attempts': 8,
      };
      await store.saveCachedProposals('user_1', [_proposal]);
      await store.saveCommunityQueue('user_1', [old]);
      final migrated = await store.readCommunityState(
        'user_1',
        backend: ApiConfig.baseUrl,
      );
      expect(migrated.contributions.single.id, '42');
      expect(migrated.operations.single['dead_letter'], isTrue);
      expect(migrated.operations.single['operation_id'], isNotEmpty);
      expect(migrated.operations.single['idempotency_key'], 'legacy-vote');
      expect(migrated.operations.single['intent_version'], isA<int>());
      expect(
        migrated.voteVersions['42'],
        migrated.operations.single['intent_version'],
      );
      expect(await store.readCommunityQueue('user_1'), [old]);
      expect(
        (await store.readCachedProposals('user_1')).single.toJson(),
        _proposal.toJson(),
      );
      final reread = await store.readCommunityState(
        'user_1',
        backend: ApiConfig.baseUrl,
      );
      expect(reread.operations, migrated.operations);
      final alternative = await store.readCommunityState(
        'user_1',
        backend: harness.api.baseUrl,
      );
      expect(alternative.operations, isEmpty);
      expect(alternative.contributions, isEmpty);
      expect(await store.readCommunityQueue('user_1'), [old]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'creation is durable with its visible cache before the API is called',
    () async {
      final save = harness.store.blockNextSave();
      final response = Completer<void>();
      harness.api.beforeWrite = (_) => response.future;
      final creating = harness.create('Atomic creation');

      await _until(() => harness.store.saveStarts == 1);
      expect(harness.api.writes, isEmpty);
      expect(harness.state.operations, isEmpty);
      save.complete();
      await _until(() => harness.api.writes.length == 1);

      final state = harness.state;
      expect(state.operations, hasLength(1));
      expect(state.contributions, hasLength(1));
      expect(state.contributions.single.pendingSync, isTrue);
      expect(
        state.operations.single['local_id'],
        state.contributions.single.id,
      );
      expect(state.operations.single['operation_id'], isNotEmpty);
      expect(
        state.operations.single['idempotency_key'],
        harness.api.writes.single.key,
      );

      response.complete();
      await creating;
      expect(harness.state.operations, isEmpty);
      expect(harness.state.contributions.single.pendingSync, isFalse);
    },
  );

  test(
    'failed durable enqueue is visible and never sends the operation',
    () async {
      harness.store.saveError = StateError('disk unavailable');

      await expectLater(
        harness.create('Not saved'),
        throwsA(isA<StateError>()),
      );

      expect(harness.api.writes, isEmpty);
      expect(harness.state.operations, isEmpty);
      expect(harness.state.contributions, isEmpty);
    },
  );

  test(
    'cache read failure is surfaced instead of returning an empty community',
    () async {
      harness.store.readError = StateError('cache unavailable');

      await expectLater(harness.service.load(), throwsA(isA<StateError>()));

      expect(harness.api.fetchTokens, isEmpty);
      expect(harness.api.writes, isEmpty);
    },
  );

  test(
    'failure saving refreshed cache remains visible to the caller',
    () async {
      harness.seed(const CommunityState(contributions: [_proposal]));
      harness.api.remote['42'] = _proposal.toJson();
      harness.store.saveError = StateError('cache cannot be saved');

      await expectLater(harness.service.load(), throwsA(isA<StateError>()));

      expect(harness.state.contributions.single.toJson(), _proposal.toJson());
    },
  );

  test(
    'offline creation keeps the proposal, outbox and error together',
    () async {
      harness.api.writeError = StateError('offline');
      harness.api.fetchError = StateError('offline');

      await harness.create('Offline creation');
      final snapshot = await harness.service.load();

      expect(snapshot.isOffline, isTrue);
      expect(snapshot.pendingOperations, 1);
      expect(snapshot.failedOperations, 0);
      expect(snapshot.lastError, isNotEmpty);
      expect(snapshot.contributions.single.subject, 'Offline creation');
      expect(snapshot.contributions.single.pendingSync, isTrue);
      expect(harness.state.operations.single['last_error'], isNotEmpty);
      expect(harness.state.operations.single['idempotency_key'], isNotEmpty);
    },
  );

  test(
    'another instance can enqueue during flush without losing either creation',
    () async {
      harness.seed(
        CommunityState(
          contributions: [_pending('local-first', 'First')],
          operations: [_creation('first', 'local-first', 'First')],
        ),
      );
      final first = Completer<void>();
      final second = Completer<void>();
      harness.api.beforeWrite = (call) =>
          call.subject == 'First' ? first.future : second.future;
      final other = harness.another();
      final loading = harness.service.load();
      await _until(() => harness.api.writes.length == 1);
      final creating = harness.create('Second', service: other);
      await _until(() => harness.state.operations.length == 2);
      expect(harness.api.writes, hasLength(1));

      first.complete();
      await _until(() => harness.api.writes.length == 2);
      await _until(() => harness.state.operations.length == 1);
      expect(harness.state.operations.single['subject'], 'Second');
      expect(
        harness.state.contributions.map((item) => item.subject),
        containsAll(['First', 'Second']),
      );

      second.complete();
      await Future.wait([loading, creating]);
      expect(harness.state.operations, isEmpty);
      expect(
        harness.state.contributions.map((item) => item.subject),
        containsAll(['First', 'Second']),
      );
    },
  );

  test(
    'latest vote survives an older acknowledgement with distinct intent keys',
    () async {
      harness.seed(const CommunityState(contributions: [_proposal]));
      final first = Completer<void>();
      final second = Completer<void>();
      harness.api.beforeWrite = (call) =>
          call.agrees! ? first.future : second.future;
      final votingYes = harness.service.vote(
        contribution: _proposal,
        agrees: true,
      );
      await _until(() => harness.api.writes.length == 1);
      final votingNo = harness.another().vote(
        contribution: _proposal,
        agrees: false,
      );
      await _until(() => harness.state.operations.single['agrees'] == false);
      final latest = Map<String, dynamic>.from(harness.state.operations.single);
      expect(latest['idempotency_key'], isNot(harness.api.writes.first.key));
      expect(harness.state.contributions.single.myVote, isFalse);

      first.complete();
      await _until(() => harness.api.writes.length == 2);
      expect(harness.api.writes.last.key, latest['idempotency_key']);
      expect(
        harness.state.operations.single['operation_id'],
        latest['operation_id'],
      );
      expect(harness.state.contributions.single.myVote, isFalse);

      second.complete();
      await Future.wait([votingYes, votingNo]);
      expect(harness.state.operations, isEmpty);
      expect(harness.state.contributions.single.myVote, isFalse);
      expect(harness.state.contributions.single.yesVotes, _proposal.yesVotes);
      expect(harness.state.contributions.single.noVotes, _proposal.noVotes + 1);
      final acknowledgedVersion = harness.state.voteVersions['42']!;
      harness.api.writeError = StateError('offline');
      await harness.service.vote(
        contribution: harness.state.contributions.single,
        agrees: true,
      );
      final retry = Map<String, dynamic>.from(harness.state.operations.single);
      expect(retry['intent_version'], greaterThan(acknowledgedVersion));
      expect(retry['idempotency_key'], isNot(latest['idempotency_key']));
      harness.seed(
        harness.state.copyWith(
          operations: [
            {...retry, 'dead_letter': true, 'attempts': 8},
          ],
        ),
      );
      harness.api.writeError = null;
      await harness.service.retryFailed(
        operationId: retry['operation_id'] as String,
      );
      expect(harness.api.writes.last.key, retry['idempotency_key']);
      expect(harness.api.writes.last.intentVersion, retry['intent_version']);
      expect(
        harness.api.writes[harness.api.writes.length - 2].key,
        retry['idempotency_key'],
      );
      expect(harness.state.operations, isEmpty);
      expect(harness.state.contributions.single.myVote, isTrue);
    },
  );

  test(
    'explicit retry preserves the selected operation id and idempotency key',
    () async {
      final failed = _creation('retry-me', 'local-retry', 'Retry me')
        ..['attempts'] = 8
        ..['dead_letter'] = true
        ..['last_error'] = 'offline'
        ..['next_attempt_at'] = DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch;
      final retained = _creation('leave-me', 'local-other', 'Leave me')
        ..['attempts'] = 8
        ..['dead_letter'] = true;
      harness.seed(
        CommunityState(
          contributions: [
            _pending('local-retry', 'Retry me'),
            _pending('local-other', 'Leave me'),
          ],
          operations: [failed, retained],
        ),
      );
      final response = Completer<void>();
      harness.api.beforeWrite = (_) => response.future;

      final retrying = harness.service.retryFailed(operationId: 'retry-me');
      await _until(() => harness.api.writes.isNotEmpty);
      final retried = harness.state.operations.firstWhere(
        (item) => item['operation_id'] == 'retry-me',
      );
      expect(retried['idempotency_key'], failed['idempotency_key']);
      expect(retried['dead_letter'], isFalse);
      expect(harness.api.writes.single.key, failed['idempotency_key']);
      response.complete();
      await retrying;

      expect(harness.state.operations, hasLength(1));
      expect(harness.state.operations.single['operation_id'], 'leave-me');
      expect(harness.state.operations.single['dead_letter'], isTrue);
    },
  );

  test('a native write timeout retains the shared barrier until the actual write ends', () async {
    harness.api.writeError = StateError('offline');
    final firstSave = harness.store.blockNextSave();
    final bounded = harness.another(
      storageTimeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      harness.create('Late first write', service: bounded),
      throwsA(isA<TimeoutException>()),
    );
    final second = harness.create('Second write');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(harness.store.saveStarts, 1);
    expect(harness.api.writes, isEmpty);

    firstSave.complete();
    await second;

    expect(
      harness.state.contributions.map((item) => item.subject),
      containsAll(['Late first write', 'Second write']),
    );
    expect(harness.state.operations, hasLength(2));
  });

  test('a network timeout retains its operation and does not release the raw request barrier', () async {
    final firstResponse = Completer<void>();
    harness.api.beforeWrite = (call) => call.subject == 'Slow first'
        ? firstResponse.future
        : Future<void>.value();
    final bounded = harness.another(
      networkTimeout: const Duration(milliseconds: 30),
    );
    await harness.create('Slow first', service: bounded);
    final originalKey = harness.state.operations.single['idempotency_key'];
    expect(harness.state.operations.single['last_error'], isNotEmpty);
    final second = harness.create('Fast second');
    await _until(() => harness.state.operations.length == 2);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(harness.api.writes, hasLength(1));

    firstResponse.complete();
    await second;
    expect(harness.api.writes.first.key, originalKey);
    expect(harness.state.operations, isEmpty);
    expect(
      harness.api.remote.values.where(
        (item) => item['subject'] == 'Slow first',
      ),
      hasLength(1),
    );
  });

  test(
    'direct non-retryable rejection removes and reverts the rejected intent',
    () async {
      harness.seed(const CommunityState(contributions: [_proposal]));
      harness.api.writeError = const ApiException('Invalid vote', 422);
      await expectLater(
        harness.service.vote(contribution: _proposal, agrees: true),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            422,
          ),
        ),
      );
      expect(harness.state.operations, isEmpty);
      expect(harness.state.contributions.single.toJson(), _proposal.toJson());

      await expectLater(
        harness.create('Rejected creation'),
        throwsA(isA<ApiException>()),
      );
      expect(harness.state.operations, isEmpty);
      expect(harness.state.contributions.map((item) => item.subject), [
        _proposal.subject,
      ]);
    },
  );

  test(
    'authorization failures retain durable intents for a recovered session',
    () async {
      for (final status in [401, 403]) {
        harness.api.writeError = ApiException('Session needs recovery', status);
        await harness.create('Recover after $status');
        expect(harness.state.operations.last['dead_letter'], isFalse);
        expect(harness.state.operations.last['last_error'], isNotEmpty);
      }
      expect(harness.state.operations, hasLength(2));
      expect(
        harness.state.contributions.every((item) => item.pendingSync),
        isTrue,
      );
    },
  );

  test('pending vote is reapplied over a stale remote refresh', () async {
    harness.seed(const CommunityState(contributions: [_proposal]));
    final fetched = Completer<List<Map<String, dynamic>>>();
    harness.api.fetchResponse = fetched;
    harness.api.writeError = StateError('offline');
    final loading = harness.service.load();
    await _until(() => harness.api.fetchTokens.isNotEmpty);
    final bounded = harness.another(
      networkTimeout: const Duration(milliseconds: 30),
    );
    await bounded.vote(contribution: _proposal, agrees: false);
    fetched.complete([_proposal.toJson()]);
    final snapshot = await loading;

    expect(snapshot.contributions.single.myVote, isFalse);
    expect(snapshot.contributions.single.noVotes, _proposal.noVotes + 1);
    expect(snapshot.pendingOperations, 1);
    expect(harness.state.contributions.single.myVote, isFalse);
    expect(harness.state.operations.single['agrees'], isFalse);
  });

  test(
    'account change during reading never sends or writes into the new account',
    () async {
      final read = harness.store.blockNextRead();
      final changing = harness.create('Captured account');
      final expectation = expectLater(
        changing,
        throwsA(isA<CommunitySessionChanged>()),
      );
      await _until(() => harness.store.readStarts == 1);
      harness.session.changeTo(2);
      read.complete();
      await expectation;

      expect(harness.api.writes, isEmpty);
      expect(harness.stateFor('user_2').operations, isEmpty);
      expect(harness.stateFor('user_2').contributions, isEmpty);
      expect(harness.store.savedScopes, everyElement('user_1'));
    },
  );

  test('account change during persistence keeps the durable intent in its captured account', () async {
    final save = harness.store.blockNextSave();
    final changing = harness.create('Account A only');
    final expectation = expectLater(
      changing,
      throwsA(isA<CommunitySessionChanged>()),
    );
    await _until(() => harness.store.saveStarts == 1);
    harness.session.changeTo(2);
    save.complete();
    await expectation;

    expect(harness.api.writes, isEmpty);
    expect(
      harness.stateFor('user_1').contributions.single.subject,
      'Account A only',
    );
    expect(harness.stateFor('user_1').operations, hasLength(1));
    expect(harness.stateFor('user_2').contributions, isEmpty);
    expect(harness.store.savedScopes, everyElement('user_1'));
  });

  test('logout during sending ignores the late response and preserves the old outbox', () async {
    final response = Completer<void>();
    harness.api.beforeWrite = (_) => response.future;
    final sending = harness.create('Before logout');
    final expectation = expectLater(
      sending,
      throwsA(isA<CommunitySessionChanged>()),
    );
    await _until(() => harness.api.writes.length == 1);
    harness.session.changeTo(null);
    response.complete();
    await expectation;

    expect(harness.api.writes.single.token, 'token_1');
    expect(harness.stateFor('user_1').operations, hasLength(1));
    expect(harness.stateFor('user_1').contributions.single.pendingSync, isTrue);
    expect(harness.stateFor('guest').operations, isEmpty);
    expect(harness.store.savedScopes, everyElement('user_1'));
  });

  test('leaving and returning to the same account invalidates the old response generation', () async {
    final response = Completer<void>();
    harness.api.beforeWrite = (_) => response.future;
    final sending = harness.create('Old account generation');
    final expectation = expectLater(
      sending,
      throwsA(isA<CommunitySessionChanged>()),
    );
    await _until(() => harness.api.writes.length == 1);
    harness.session.changeTo(2);
    harness.session.changeTo(1);
    response.complete();
    await expectation;

    expect(harness.state.operations, hasLength(1));
    expect(harness.state.contributions.single.pendingSync, isTrue);
    expect(harness.stateFor('user_2').operations, isEmpty);
  });
}

const _proposal = RoomChangeContribution(
  id: '42',
  subject: 'Existing proposal',
  authorName: 'Student',
  fromRoomName: 'Room A',
  toRoomName: 'Room B',
  reason: 'Teacher confirmed the move.',
  status: ContributionStatus.voting,
  yesVotes: 3,
  noVotes: 1,
);

RoomChangeContribution _pending(String id, String subject) =>
    RoomChangeContribution(
      id: id,
      subject: subject,
      authorName: 'Student 1',
      fromRoomName: 'Room A',
      toRoomName: 'Room B',
      reason: 'Teacher confirmed the move.',
      status: ContributionStatus.unverified,
      yesVotes: 0,
      noVotes: 0,
      pendingSync: true,
    );

Map<String, dynamic> _creation(String id, String localId, String subject) => {
  'operation_id': id,
  'idempotency_key': 'key-$id',
  'type': 'create',
  'local_id': localId,
  'subject': subject,
  'from_room': 'Room A',
  'to_room': 'Room B',
  'reason': 'Teacher confirmed the move.',
  'attempts': 0,
  'next_attempt_at': 0,
  'dead_letter': false,
};

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The expected asynchronous step did not occur.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _Harness {
  static int _sequence = 0;
  final _Session session = _Session();
  final _MemoryStore store = _MemoryStore();
  late final _Api api = _Api('https://community-${++_sequence}.example.test');
  late final CommunityService service = another();
  final List<CommunityService> _services = [];

  _Harness() {
    service;
  }

  CommunityState get state => stateFor('user_1');

  CommunityState stateFor(String scope) => store.state(api.baseUrl, scope);

  void seed(CommunityState state, {String scope = 'user_1'}) =>
      store.states[_MemoryStore.key(api.baseUrl, scope)] = state;

  CommunityService another({
    Duration storageTimeout = const Duration(seconds: 1),
    Duration networkTimeout = const Duration(seconds: 1),
  }) {
    final result = CommunityService(
      api: api,
      store: store,
      session: session,
      storageTimeout: storageTimeout,
      networkTimeout: networkTimeout,
    );
    _services.add(result);
    return result;
  }

  Future<void> create(String subject, {CommunityService? service}) =>
      (service ?? this.service).createProposal(
        subject: subject,
        fromRoom: 'Room A',
        toRoom: 'Room B',
        reason: 'Teacher confirmed the move.',
      );

  void dispose() {
    store.releaseGates();
    for (final service in _services) {
      service.dispose();
    }
    session.dispose();
  }
}

class _Session extends AppSession {
  int? _id = 1;

  void changeTo(int? id) {
    _id = id;
    notifyListeners();
  }

  @override
  String get storageScope => _id == null ? 'guest' : 'user_$_id';
  @override
  String? get token => _id == null ? null : 'token_$_id';
  @override
  bool get isLoggedIn => _id != null;
  @override
  AppUser? get user => _id == null
      ? null
      : AppUser(
          id: _id!,
          name: 'Student $_id',
          email: 'student$_id@example.test',
          course: 'EC',
          semester: 4,
          group: 'EC4',
          role: 'student',
        );
}

class _MemoryStore extends LocalStore {
  final Map<String, CommunityState> states = {};
  final List<String> savedScopes = [];
  final List<Completer<void>> _gates = [];
  Completer<void>? _nextRead;
  Completer<void>? _nextSave;
  Object? readError;
  Object? saveError;
  int readStarts = 0;
  int saveStarts = 0;

  static String key(String backend, String scope) => '$backend|$scope';

  CommunityState state(String backend, String scope) =>
      states[key(backend, scope)] ?? const CommunityState();

  Completer<void> blockNextRead() {
    final gate = Completer<void>();
    _gates.add(gate);
    _nextRead = gate;
    return gate;
  }

  Completer<void> blockNextSave() {
    final gate = Completer<void>();
    _gates.add(gate);
    _nextSave = gate;
    return gate;
  }

  @override
  Future<CommunityState> readCommunityState(
    String scope, {
    required String backend,
  }) async {
    readStarts++;
    final gate = _nextRead;
    _nextRead = null;
    await gate?.future;
    if (readError case final error?) throw error;
    return _clone(state(backend, scope));
  }

  @override
  Future<void> saveCommunityState(
    String scope,
    CommunityState state, {
    required String backend,
  }) async {
    saveStarts++;
    final gate = _nextSave;
    _nextSave = null;
    await gate?.future;
    if (saveError case final error?) throw error;
    states[key(backend, scope)] = _clone(state);
    savedScopes.add(scope);
  }

  CommunityState _clone(CommunityState state) => CommunityState(
    contributions: List.of(state.contributions),
    operations: state.operations
        .map((item) => Map<String, dynamic>.from(item))
        .toList(),
    revision: state.revision,
    voteVersions: Map.of(state.voteVersions),
  );

  void releaseGates() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

class _Write {
  final String token;
  final String? key;
  final String? subject;
  final int? proposalId;
  final bool? agrees;
  final int? intentVersion;

  const _Write({
    required this.token,
    required this.key,
    this.subject,
    this.proposalId,
    this.agrees,
    this.intentVersion,
  });
}

class _Api extends GranMapApi {
  _Api(String backend) : super(baseUrl: backend);

  final List<_Write> writes = [];
  final List<String?> fetchTokens = [];
  final Map<String, Map<String, dynamic>> remote = {};
  final Map<String, String> _createdIds = {};
  Object? writeError;
  Object? fetchError;
  Future<void> Function(_Write call)? beforeWrite;
  Completer<List<Map<String, dynamic>>>? fetchResponse;

  @override
  Future<List<Map<String, dynamic>>> fetchProposals({String? token}) async {
    fetchTokens.add(token);
    if (fetchError case final error?) throw error;
    return fetchResponse == null
        ? remote.values.map(Map<String, dynamic>.from).toList()
        : await fetchResponse!.future;
  }

  @override
  Future<Map<String, dynamic>> createProposal({
    required String token,
    required String subject,
    required String fromRoom,
    required String toRoom,
    required String reason,
    String? idempotencyKey,
  }) async {
    final call = _Write(token: token, key: idempotencyKey, subject: subject);
    writes.add(call);
    await beforeWrite?.call(call);
    if (writeError case final error?) throw error;
    final id = _createdIds.putIfAbsent(
      idempotencyKey ?? subject,
      () => '${100 + _createdIds.length}',
    );
    final result = {
      ..._pending(id, subject).toJson(),
      'pending_sync': false,
      'status': 'voting',
    };
    remote[id] = result;
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<Map<String, dynamic>> voteProposal({
    required String token,
    required int proposalId,
    required bool agrees,
    String? idempotencyKey,
    int? intentVersion,
  }) async {
    final call = _Write(
      token: token,
      key: idempotencyKey,
      proposalId: proposalId,
      agrees: agrees,
      intentVersion: intentVersion,
    );
    writes.add(call);
    await beforeWrite?.call(call);
    if (writeError case final error?) throw error;
    final result = {
      ..._proposal.toJson(),
      'id': proposalId.toString(),
      'my_vote': agrees,
      'yes_votes': _proposal.yesVotes + (agrees ? 1 : 0),
      'no_votes': _proposal.noVotes + (agrees ? 0 : 1),
    };
    remote[proposalId.toString()] = result;
    return Map<String, dynamic>.from(result);
  }

  @override
  void dispose() {}
}
