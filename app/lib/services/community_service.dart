import 'dart:async';
import 'dart:math' as math;

import '../community/community_models.dart';
import '../models/user.dart';
import 'app_session.dart';
import 'app_runtime_config.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class CommunityService {
  static const _maxAutomaticAttempts = 8;
  static final Map<String, Future<void>> _storageTails = {};
  static final Map<String, Future<void>> _networkTails = {};
  static final Map<String, Future<void>> _sends = {};
  static final Map<String, Future<void>> _syncs = {};
  static int _sequence = 0;

  final GranMapApi _api;
  final LocalStore _store;
  final AppSession _session;
  final bool _ownsApi;
  final Duration storageTimeout;
  final Duration networkTimeout;
  bool _disposed = false;
  int _generation = 0;
  late String _observedScope;
  String? _observedToken;
  int? _observedUser;

  CommunityService({
    GranMapApi? api,
    LocalStore? store,
    AppSession? session,
    this.storageTimeout = const Duration(seconds: 2),
    this.networkTimeout = const Duration(seconds: 4),
  }) : _api = api ?? GranMapApi(),
       _ownsApi = api == null,
       _store = store ?? LocalStore(),
       _session = session ?? AppSession.instance {
    _observedScope = _session.storageScope;
    _observedToken = _session.token;
    _observedUser = _session.user?.id;
    _session.addListener(_sessionChanged);
  }

  String get _backend => _api.baseUrl.replaceFirst(RegExp(r'/+$'), '');

  void _sessionChanged() {
    if (_observedScope != _session.storageScope ||
        _observedToken != _session.token ||
        _observedUser != _session.user?.id) {
      _generation++;
      _observedScope = _session.storageScope;
      _observedToken = _session.token;
      _observedUser = _session.user?.id;
    }
  }

  _CommunityContext _capture() {
    _sessionChanged();
    if (_disposed) throw const CommunitySessionChanged();
    return _CommunityContext(
      scope: _session.storageScope,
      token: _session.token,
      user: _session.user,
      generation: _generation,
      backend: _backend,
    );
  }

  bool _current(_CommunityContext context) {
    _sessionChanged();
    return !_disposed &&
        context.generation == _generation &&
        context.scope == _session.storageScope &&
        context.token == _session.token &&
        context.user?.id == _session.user?.id;
  }

  void _requireCurrent(_CommunityContext context) {
    if (!_current(context)) throw const CommunitySessionChanged();
  }

  void _requireWrite(_CommunityContext context, String message) {
    if (!AppRuntimeConfig.instance.communityWritesEnabled) {
      throw const ApiException(
        'As contribuições estão temporariamente pausadas.',
        503,
      );
    }
    if (context.token == null || context.user == null) {
      throw ApiException(message, 401);
    }
  }

  /// The UI deadline never releases the actual native transaction's barrier.
  Future<T> _storage<T>(
    _CommunityContext context,
    Future<T> Function() action,
  ) {
    final key = context.key;
    final operation = (_storageTails[key] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final barrier = operation.then<void>((_) {}, onError: (Object _) {});
    _storageTails[key] = barrier;
    unawaited(
      barrier.then((_) {
        if (identical(_storageTails[key], barrier)) _storageTails.remove(key);
      }),
    );
    return operation.timeout(storageTimeout);
  }

  Future<CommunityState> _read(_CommunityContext context) => _storage(
    context,
    () => _store.readCommunityState(context.scope, backend: context.backend),
  );

  Future<CommunityState> _change(
    _CommunityContext context,
    CommunityState Function(CommunityState) transform,
  ) => _storage(context, () async {
    final previous = await _store.readCommunityState(
      context.scope,
      backend: context.backend,
    );
    final next = transform(previous);
    if (identical(next, previous)) return previous;
    final updated = next.copyWith(revision: previous.revision + 1);
    await _store.saveCommunityState(
      context.scope,
      updated,
      backend: context.backend,
    );
    return updated;
  });

  Future<bool> hasPendingWork() async {
    final context = _capture();
    final state = await _read(context);
    _requireCurrent(context);
    return state.operations.any((item) => item['dead_letter'] != true);
  }

  Future<CommunitySnapshot> load() async {
    final context = _capture();
    await _read(context);
    _requireCurrent(context);
    if (context.token != null &&
        AppRuntimeConfig.instance.communityWritesEnabled) {
      await _synchronize(context);
      _requireCurrent(context);
    }
    final before = await _read(context);
    _requireCurrent(context);
    List<RoomChangeContribution> server;
    try {
      final raw = await _api
          .fetchProposals(token: context.token)
          .timeout(networkTimeout);
      _requireCurrent(context);
      server = raw.map(RoomChangeContribution.fromJson).toList();
    } on CommunitySessionChanged {
      rethrow;
    } catch (_) {
      final cached = await _read(context);
      _requireCurrent(context);
      return _snapshot(cached, isOffline: true);
    }
    final merged = await _change(context, (state) {
      _requireCurrent(context);
      if (state.revision != before.revision) return state;
      return state.copyWith(contributions: _merge(server, state));
    });
    _requireCurrent(context);
    return _snapshot(merged, isOffline: false);
  }

  Future<void> createProposal({
    required String subject,
    required String fromRoom,
    required String toRoom,
    required String reason,
  }) async {
    final context = _capture();
    _requireWrite(context, 'Entre na sua conta para enviar uma contribuição.');
    final id = _newId('proposal', context);
    final localId = 'local_$id';
    final operation = <String, dynamic>{
      'operation_id': id,
      'idempotency_key': id,
      'type': 'create',
      'local_id': localId,
      'discard_on_rejection': true,
      'attempts': 0,
      'next_attempt_at': 0,
      'dead_letter': false,
      'subject': subject,
      'from_room': fromRoom,
      'to_room': toRoom,
      'reason': reason,
    };
    final pending = RoomChangeContribution(
      id: localId,
      subject: subject,
      authorName: context.user!.name,
      authorReputation: context.user!.reputation,
      fromRoomName: fromRoom,
      toRoomName: toRoom,
      reason: reason,
      status: ContributionStatus.unverified,
      yesVotes: 0,
      noVotes: 0,
      createdAt: DateTime.now(),
      pendingSync: true,
    );
    await _change(
      context,
      (state) => state.copyWith(
        contributions: [pending, ...state.contributions],
        operations: [...state.operations, operation],
      ),
    );
    _requireCurrent(context);
    await _deliver(context, operation, initial: true);
    _requireCurrent(context);
  }

  Future<void> vote({
    required RoomChangeContribution contribution,
    required bool agrees,
  }) async {
    final context = _capture();
    _requireWrite(context, 'Entre na sua conta para confirmar informações.');
    final proposalId = int.tryParse(contribution.id);
    if (proposalId == null || !contribution.canVote) {
      throw const ApiException(
        'Aguarde a sincronização desta proposta antes de votar.',
        409,
      );
    }
    final id = _newId('vote', context);
    late Map<String, dynamic> operation;
    await _change(context, (state) {
      final existing =
          state.contributions
              .where((item) => item.id == contribution.id)
              .firstOrNull ??
          contribution;
      final previousVote = state.operations
          .where((item) => _sameVote(item, contribution.id))
          .firstOrNull;
      final priorVersion = state.voteVersions[contribution.id] ?? 0;
      final intentVersion = math.max(
        DateTime.now().microsecondsSinceEpoch,
        priorVersion + 1,
      );
      operation = {
        'operation_id': id,
        'idempotency_key': id,
        'type': 'vote',
        'proposal_id': proposalId,
        'agrees': agrees,
        'intent_version': intentVersion,
        'attempts': 0,
        'next_attempt_at': 0,
        'dead_letter': false,
        'previous_contribution': existing.toJson(),
        'previous_vote_operation': ?previousVote,
        'discard_on_rejection': true,
      };
      return state.copyWith(
        voteVersions: {...state.voteVersions, contribution.id: intentVersion},
        operations: [
          ...state.operations.where(
            (item) => !_sameVote(item, contribution.id),
          ),
          operation,
        ],
        contributions: _replace(
          state.contributions,
          _optimisticVote(existing, agrees),
        ),
      );
    });
    _requireCurrent(context);
    await _deliver(context, operation, initial: true);
    _requireCurrent(context);
  }

  /// Retry changes eligibility, never an operation's idempotency identity.
  Future<CommunitySnapshot> retryFailed({String? operationId}) async {
    final context = _capture();
    _requireWrite(context, 'Entre na sua conta para tentar novamente.');
    await _change(context, (state) {
      _requireCurrent(context);
      return state.copyWith(
        operations: [
          for (final operation in state.operations)
            if (operation['dead_letter'] == true &&
                (operationId == null ||
                    operation['operation_id'] == operationId))
              {
                ...operation,
                'attempts': 0,
                'next_attempt_at': 0,
                'dead_letter': false,
                'last_error': null,
              }
            else
              operation,
        ],
      );
    });
    _requireCurrent(context);
    await _synchronize(context);
    final state = await _read(context);
    _requireCurrent(context);
    return _snapshot(state, isOffline: false);
  }

  Future<void> _synchronize(_CommunityContext context) async {
    final key = '${context.key}:${context.token}';
    var syncing = _syncs[key];
    if (syncing == null) {
      syncing = _drain(context);
      _syncs[key] = syncing;
      final tracked = syncing;
      unawaited(
        tracked.then<void>(
          (_) {
            if (identical(_syncs[key], tracked)) _syncs.remove(key);
          },
          onError: (Object _) {
            if (identical(_syncs[key], tracked)) _syncs.remove(key);
          },
        ),
      );
    }
    await syncing;
  }

  Future<void> _drain(_CommunityContext context) async {
    while (_current(context) &&
        AppRuntimeConfig.instance.communityWritesEnabled) {
      final state = await _read(context);
      _requireCurrent(context);
      final now = DateTime.now().millisecondsSinceEpoch;
      final operation = state.operations
          .where(
            (item) =>
                item['dead_letter'] != true &&
                ((item['next_attempt_at'] as num?)?.toInt() ?? 0) <= now,
          )
          .firstOrNull;
      if (operation == null) return;
      if (!await _deliver(context, operation, initial: false)) return;
    }
  }

  Future<bool> _deliver(
    _CommunityContext context,
    Map<String, dynamic> operation, {
    required bool initial,
  }) async {
    final key = '${context.key}:${operation['operation_id']}';
    var sending = _sends[key];
    if (sending == null) {
      sending = (_networkTails[context.key] ?? Future<void>.value()).then(
        (_) => _send(context, operation, initial: initial),
      );
      _sends[key] = sending;
      // A caller's network deadline does not release a still-running API call.
      final barrier = sending.then<void>((_) {}, onError: (Object _) {});
      _networkTails[context.key] = barrier;
      final tracked = sending;
      unawaited(
        barrier.then((_) {
          if (identical(_sends[key], tracked)) _sends.remove(key);
          if (identical(_networkTails[context.key], barrier)) {
            _networkTails.remove(context.key);
          }
        }),
      );
    }
    try {
      await sending.timeout(
        networkTimeout,
        onTimeout: () => throw const _CommunityNetworkDeadline(),
      );
      return true;
    } on _CommunityNetworkDeadline {
      _requireCurrent(context);
      await _recordFailure(
        context,
        operation,
        TimeoutException('Community network deadline'),
      );
      return false;
    }
  }

  Future<void> _send(
    _CommunityContext context,
    Map<String, dynamic> requested, {
    required bool initial,
  }) async {
    final state = await _read(context);
    _requireCurrent(context);
    final operation = state.operations
        .where((item) => item['operation_id'] == requested['operation_id'])
        .firstOrNull;
    if (operation == null || operation['dead_letter'] == true) return;
    if (!AppRuntimeConfig.instance.communityWritesEnabled) return;
    final Map<String, dynamic> raw;
    try {
      if (operation['type'] == 'create') {
        raw = await _api.createProposal(
          token: context.token!,
          subject: operation['subject'].toString(),
          fromRoom: operation['from_room'].toString(),
          toRoom: operation['to_room'].toString(),
          reason: operation['reason'].toString(),
          idempotencyKey: operation['idempotency_key']?.toString(),
        );
      } else if (operation['type'] == 'vote') {
        raw = await _api.voteProposal(
          token: context.token!,
          proposalId: (operation['proposal_id'] as num).toInt(),
          agrees: operation['agrees'] as bool,
          idempotencyKey: operation['idempotency_key']?.toString(),
          intentVersion: (operation['intent_version'] as num?)?.toInt(),
        );
      } else {
        throw const ApiException('Operação offline desconhecida.', 422);
      }
    } catch (error) {
      _requireCurrent(context);
      final current = await _read(context);
      _requireCurrent(context);
      final persisted = current.operations
          .where((item) => item['operation_id'] == operation['operation_id'])
          .firstOrNull;
      if (!_isRetriable(error) &&
          persisted != null &&
          (persisted['discard_on_rejection'] == true ||
              (initial && persisted['last_error'] == null))) {
        await _reject(context, operation);
        rethrow;
      }
      await _recordFailure(context, operation, error);
      return;
    }
    _requireCurrent(context);
    final created = RoomChangeContribution.fromJson(raw);
    await _change(context, (current) {
      _requireCurrent(context);
      final remaining = current.operations
          .where((item) => item['operation_id'] != operation['operation_id'])
          .toList();
      var proposals = current.contributions;
      if (operation['type'] == 'create') {
        proposals = proposals
            .where((item) => item.id != operation['local_id'])
            .toList();
      }
      proposals = _replace(proposals, created);
      return current.copyWith(
        contributions: _applyPendingVotes(proposals, remaining),
        operations: remaining,
      );
    });
  }

  Future<void> _reject(
    _CommunityContext context,
    Map<String, dynamic> operation,
  ) async {
    await _change(context, (state) {
      if (!state.operations.any(
        (item) => item['operation_id'] == operation['operation_id'],
      )) {
        return state;
      }
      var proposals = state.contributions;
      if (operation['type'] == 'create') {
        proposals = proposals
            .where((item) => item.id != operation['local_id'])
            .toList();
      } else if (operation['previous_contribution'] is Map) {
        proposals = _replace(
          proposals,
          RoomChangeContribution.fromJson(
            Map<String, dynamic>.from(
              operation['previous_contribution'] as Map,
            ),
          ),
        );
      }
      final remaining = state.operations
          .where((item) => item['operation_id'] != operation['operation_id'])
          .toList();
      final previousVote = operation['previous_vote_operation'];
      if (previousVote is Map) {
        remaining.add(Map<String, dynamic>.from(previousVote));
      }
      return state.copyWith(contributions: proposals, operations: remaining);
    });
  }

  Future<void> _recordFailure(
    _CommunityContext context,
    Map<String, dynamic> operation,
    Object error,
  ) async {
    await _change(context, (state) {
      final id = operation['operation_id'];
      if (!state.operations.any((item) => item['operation_id'] == id)) {
        return state;
      }
      return state.copyWith(
        operations: [
          for (final current in state.operations)
            if (current['operation_id'] == id)
              _failedOperation(current, operation, error)
            else
              current,
        ],
      );
    });
  }

  Map<String, dynamic> _failedOperation(
    Map<String, dynamic> current,
    Map<String, dynamic> sent,
    Object error,
  ) {
    final attempts = math.max(
      (current['attempts'] as num?)?.toInt() ?? 0,
      ((sent['attempts'] as num?)?.toInt() ?? 0) + 1,
    );
    final deadLetter =
        !_isRetriable(error) || attempts >= _maxAutomaticAttempts;
    final waiting =
        error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403);
    return {
      ...current,
      'attempts': attempts,
      'last_error': _safeError(error),
      'dead_letter': deadLetter,
      'discard_on_rejection': false,
      'next_attempt_at': deadLetter
          ? 0
          : DateTime.now().millisecondsSinceEpoch +
                (waiting
                        ? const Duration(minutes: 5)
                        : Duration(
                            seconds: 5 * (1 << (attempts.clamp(1, 6) - 1)),
                          ))
                    .inMilliseconds,
    };
  }

  CommunitySnapshot _snapshot(CommunityState state, {required bool isOffline}) {
    final pending = state.operations
        .where((item) => item['dead_letter'] != true)
        .toList();
    final retries =
        pending
            .map((item) => (item['next_attempt_at'] as num?)?.toInt() ?? 0)
            .where((value) => value > 0)
            .toList()
          ..sort();
    final errors = state.operations
        .map((item) => item['last_error'])
        .whereType<String>()
        .toList();
    return CommunitySnapshot(
      contributions: _applyPendingVotes(state.contributions, state.operations),
      isOffline: isOffline,
      pendingOperations: pending.length,
      failedOperations: state.operations.length - pending.length,
      nextRetryAt: retries.isEmpty
          ? null
          : DateTime.fromMillisecondsSinceEpoch(retries.first),
      lastError: errors.isEmpty ? null : errors.last,
    );
  }

  List<RoomChangeContribution> _merge(
    List<RoomChangeContribution> server,
    CommunityState state,
  ) {
    final localIds = state.operations
        .where((item) => item['type'] == 'create')
        .map((item) => item['local_id'].toString())
        .toSet();
    final merged = [
      ...state.contributions.where((item) => localIds.contains(item.id)),
      ...server,
    ];
    final ids = merged.map((item) => item.id).toSet();
    for (final operation in state.operations.where(
      (item) => item['type'] == 'vote',
    )) {
      final item = state.contributions
          .where((item) => item.id == operation['proposal_id'].toString())
          .firstOrNull;
      if (item != null && ids.add(item.id)) merged.add(item);
    }
    return _applyPendingVotes(merged, state.operations);
  }

  List<RoomChangeContribution> _applyPendingVotes(
    List<RoomChangeContribution> proposals,
    List<Map<String, dynamic>> operations,
  ) {
    var result = proposals;
    for (final operation in operations.where(
      (item) => item['type'] == 'vote',
    )) {
      final item = result
          .where((item) => item.id == operation['proposal_id'].toString())
          .firstOrNull;
      if (item != null) {
        result = _replace(
          result,
          _optimisticVote(item, operation['agrees'] as bool),
        );
      }
    }
    return result;
  }

  List<RoomChangeContribution> _replace(
    List<RoomChangeContribution> items,
    RoomChangeContribution replacement,
  ) => [replacement, ...items.where((item) => item.id != replacement.id)];

  RoomChangeContribution _optimisticVote(
    RoomChangeContribution item,
    bool agrees,
  ) {
    var yes = item.yesVotes;
    var no = item.noVotes;
    if (item.myVote == true) yes = math.max(0, yes - 1);
    if (item.myVote == false) no = math.max(0, no - 1);
    agrees ? yes++ : no++;
    final total = yes + no;
    final confidence = total == 0 ? 0.0 : yes / total;
    final status = total < 5
        ? ContributionStatus.voting
        : confidence >= .75
        ? ContributionStatus.confirmed
        : confidence <= .35
        ? ContributionStatus.contested
        : ContributionStatus.voting;
    return item.copyWith(
      yesVotes: yes,
      noVotes: no,
      myVote: agrees,
      status: status,
    );
  }

  bool _sameVote(Map<String, dynamic> operation, String proposalId) =>
      operation['type'] == 'vote' &&
      operation['proposal_id'].toString() == proposalId;

  bool _isRetriable(Object error) =>
      error is! ApiException ||
      error.statusCode == 0 ||
      error.statusCode == 401 ||
      error.statusCode == 403 ||
      error.statusCode == 408 ||
      error.statusCode == 429 ||
      error.statusCode >= 500;

  String _newId(String prefix, _CommunityContext context) =>
      '$prefix-${context.user?.id ?? 0}-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  String _safeError(Object error) {
    final message = error is ApiException
        ? error.message
        : error is TimeoutException
        ? 'A sincronização demorou. A alteração continua salva neste aparelho.'
        : 'Não foi possível sincronizar. A alteração continua salva neste aparelho.';
    return message.length <= 240 ? message : message.substring(0, 240);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _session.removeListener(_sessionChanged);
    if (_ownsApi) _api.dispose();
  }
}

class _CommunityNetworkDeadline implements Exception {
  const _CommunityNetworkDeadline();
}

class _CommunityContext {
  final String scope;
  final String? token;
  final AppUser? user;
  final int generation;
  final String backend;

  const _CommunityContext({
    required this.scope,
    required this.token,
    required this.user,
    required this.generation,
    required this.backend,
  });

  String get key => '$backend::$scope';
}
