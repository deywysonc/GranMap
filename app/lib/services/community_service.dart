import '../community/community_models.dart';
import 'app_session.dart';
import 'app_runtime_config.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class CommunityService {
  static const _maxAutomaticAttempts = 8;

  final GranMapApi _api;
  final LocalStore _store;
  final AppSession _session;

  CommunityService({GranMapApi? api, LocalStore? store, AppSession? session})
    : _api = api ?? GranMapApi(),
      _store = store ?? LocalStore(),
      _session = session ?? AppSession.instance;

  Future<CommunitySnapshot> load() async {
    final scope = _session.storageScope;
    final cachedBeforeSync = await _store.readCachedProposals(scope);
    final token = _session.token;
    if (token != null) {
      await _flushPending(token);
    }

    final remaining = await _store.readCommunityQueue(_session.storageScope);
    final pendingOperations = remaining
        .where((item) => item['dead_letter'] != true)
        .length;
    final failedOperations = remaining
        .where((item) => item['dead_letter'] == true)
        .length;
    final nextRetryAt = _nextRetryAt(remaining);
    try {
      final raw = await _api.fetchProposals(token: token);
      final server = raw
          .map(RoomChangeContribution.fromJson)
          .toList(growable: false);
      final pendingIds = remaining
          .where((item) => item['type'] == 'create')
          .map((item) => item['local_id'].toString())
          .toSet();
      final pending = cachedBeforeSync
          .where((item) => pendingIds.contains(item.id))
          .toList(growable: false);
      final merged = <RoomChangeContribution>[...pending, ...server];
      await _store.saveCachedProposals(scope, merged);
      return CommunitySnapshot(
        contributions: merged,
        isOffline: false,
        pendingOperations: pendingOperations,
        failedOperations: failedOperations,
        nextRetryAt: nextRetryAt,
      );
    } catch (_) {
      final cached = await _store.readCachedProposals(scope);
      return CommunitySnapshot(
        contributions: cached,
        isOffline: true,
        pendingOperations: pendingOperations,
        failedOperations: failedOperations,
        nextRetryAt: nextRetryAt,
      );
    }
  }

  Future<void> createProposal({
    required String subject,
    required String fromRoom,
    required String toRoom,
    required String reason,
  }) async {
    if (!AppRuntimeConfig.instance.communityWritesEnabled) {
      throw const ApiException(
        'Novas contribuições estão temporariamente pausadas.',
        503,
      );
    }
    final token = _session.token;
    final user = _session.user;
    if (token == null || user == null) {
      throw const ApiException(
        'Entre na sua conta para enviar uma contribuição.',
        401,
      );
    }

    final idempotencyKey = _newIdempotencyKey('proposal');
    try {
      final raw = await _api.createProposal(
        token: token,
        subject: subject,
        fromRoom: fromRoom,
        toRoom: toRoom,
        reason: reason,
        idempotencyKey: idempotencyKey,
      );
      final created = RoomChangeContribution.fromJson(raw);
      final cached = await _store.readCachedProposals(_session.storageScope);
      await _store.saveCachedProposals(_session.storageScope, [
        created,
        ...cached.where((item) => item.id != created.id),
      ]);
      return;
    } catch (error) {
      if (!_isRetriable(error)) rethrow;
    }

    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final operation = <String, dynamic>{
      'type': 'create',
      'local_id': localId,
      'idempotency_key': idempotencyKey,
      'attempts': 0,
      'next_attempt_at': 0,
      'dead_letter': false,
      'subject': subject,
      'from_room': fromRoom,
      'to_room': toRoom,
      'reason': reason,
    };
    final queue = await _store.readCommunityQueue(_session.storageScope);
    queue.add(operation);
    await _store.saveCommunityQueue(_session.storageScope, queue);

    final pending = RoomChangeContribution(
      id: localId,
      subject: subject,
      authorName: user.name,
      authorReputation: user.reputation,
      fromRoomName: fromRoom,
      toRoomName: toRoom,
      reason: reason,
      status: ContributionStatus.unverified,
      yesVotes: 0,
      noVotes: 0,
      createdAt: DateTime.now(),
      pendingSync: true,
    );
    final cached = await _store.readCachedProposals(_session.storageScope);
    await _store.saveCachedProposals(_session.storageScope, [
      pending,
      ...cached,
    ]);
  }

  Future<void> vote({
    required RoomChangeContribution contribution,
    required bool agrees,
  }) async {
    if (!AppRuntimeConfig.instance.communityWritesEnabled) {
      throw const ApiException('A votação está temporariamente pausada.', 503);
    }
    final token = _session.token;
    if (token == null) {
      throw const ApiException(
        'Entre na sua conta para confirmar informações.',
        401,
      );
    }
    final proposalId = int.tryParse(contribution.id);
    if (proposalId == null || contribution.pendingSync) {
      throw const ApiException(
        'Aguarde a sincronização desta proposta antes de votar.',
        409,
      );
    }

    final idempotencyKey = 'vote-${_session.user?.id ?? 'user'}-$proposalId';
    try {
      final raw = await _api.voteProposal(
        token: token,
        proposalId: proposalId,
        agrees: agrees,
        idempotencyKey: idempotencyKey,
      );
      await _replaceCached(RoomChangeContribution.fromJson(raw));
      return;
    } catch (error) {
      if (!_isRetriable(error)) rethrow;
    }

    final queue = await _store.readCommunityQueue(_session.storageScope);
    queue.removeWhere(
      (item) =>
          item['type'] == 'vote' &&
          item['proposal_id'].toString() == contribution.id,
    );
    queue.add({
      'type': 'vote',
      'proposal_id': proposalId,
      'agrees': agrees,
      'idempotency_key': idempotencyKey,
      'attempts': 0,
      'next_attempt_at': 0,
      'dead_letter': false,
    });
    await _store.saveCommunityQueue(_session.storageScope, queue);
    await _replaceCached(_optimisticVote(contribution, agrees));
  }

  Future<void> _flushPending(String token) async {
    final queue = await _store.readCommunityQueue(_session.storageScope);
    if (queue.isEmpty) return;

    final retained = <Map<String, dynamic>>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final queued in queue) {
      final operation = Map<String, dynamic>.from(queued);
      if (operation['dead_letter'] == true ||
          ((operation['next_attempt_at'] as num?)?.toInt() ?? 0) > now) {
        retained.add(operation);
        continue;
      }
      try {
        if (operation['type'] == 'create') {
          final raw = await _api.createProposal(
            token: token,
            subject: operation['subject'].toString(),
            fromRoom: operation['from_room'].toString(),
            toRoom: operation['to_room'].toString(),
            reason: operation['reason'].toString(),
            idempotencyKey: operation['idempotency_key']?.toString(),
          );
          final created = RoomChangeContribution.fromJson(raw);
          final cached = await _store.readCachedProposals(
            _session.storageScope,
          );
          final localId = operation['local_id'].toString();
          await _store.saveCachedProposals(_session.storageScope, [
            created,
            ...cached.where((item) => item.id != localId),
          ]);
        } else if (operation['type'] == 'vote') {
          final raw = await _api.voteProposal(
            token: token,
            proposalId: operation['proposal_id'] as int,
            agrees: operation['agrees'] as bool,
            idempotencyKey: operation['idempotency_key']?.toString(),
          );
          await _replaceCached(RoomChangeContribution.fromJson(raw));
        } else {
          operation
            ..['dead_letter'] = true
            ..['last_error'] = 'Operação offline desconhecida.';
          retained.add(operation);
        }
      } catch (error) {
        final attempts = ((operation['attempts'] as num?)?.toInt() ?? 0) + 1;
        final recoverableSession =
            error is ApiException &&
            (error.statusCode == 401 || error.statusCode == 403);
        final retryable = _isRetriable(error) || recoverableSession;
        final deadLetter = !retryable || attempts >= _maxAutomaticAttempts;
        operation
          ..['attempts'] = attempts
          ..['last_error'] = _safeError(error)
          ..['dead_letter'] = deadLetter
          ..['next_attempt_at'] = deadLetter
              ? 0
              : now + _retryDelay(attempts, recoverableSession).inMilliseconds;
        retained.add(operation);
      }
    }
    await _store.saveCommunityQueue(_session.storageScope, retained);
  }

  RoomChangeContribution _optimisticVote(
    RoomChangeContribution item,
    bool agrees,
  ) {
    var yes = item.yesVotes;
    var no = item.noVotes;
    if (item.myVote == true) yes = yes > 0 ? yes - 1 : 0;
    if (item.myVote == false) no = no > 0 ? no - 1 : 0;
    agrees ? yes++ : no++;
    final total = yes + no;
    final confidence = total == 0 ? 0.0 : yes / total;
    final status = total < 5
        ? ContributionStatus.voting
        : confidence >= 0.75
        ? ContributionStatus.confirmed
        : confidence <= 0.35
        ? ContributionStatus.contested
        : ContributionStatus.voting;
    return item.copyWith(
      yesVotes: yes,
      noVotes: no,
      myVote: agrees,
      status: status,
    );
  }

  Future<void> _replaceCached(RoomChangeContribution replacement) async {
    final cached = await _store.readCachedProposals(_session.storageScope);
    final index = cached.indexWhere((item) => item.id == replacement.id);
    final updated = [...cached];
    if (index < 0) {
      updated.insert(0, replacement);
    } else {
      updated[index] = replacement;
    }
    await _store.saveCachedProposals(_session.storageScope, updated);
  }

  bool _isRetriable(Object error) {
    return error is! ApiException ||
        error.statusCode == 0 ||
        error.statusCode == 408 ||
        error.statusCode == 429 ||
        error.statusCode >= 500;
  }

  Duration _retryDelay(int attempts, bool waitingForSession) {
    if (waitingForSession) return const Duration(minutes: 5);
    final exponent = attempts.clamp(1, 6);
    return Duration(seconds: 5 * (1 << (exponent - 1)));
  }

  DateTime? _nextRetryAt(List<Map<String, dynamic>> queue) {
    final timestamps = queue
        .where((item) => item['dead_letter'] != true)
        .map((item) => (item['next_attempt_at'] as num?)?.toInt() ?? 0)
        .where((value) => value > 0)
        .toList();
    if (timestamps.isEmpty) return null;
    timestamps.sort();
    return DateTime.fromMillisecondsSinceEpoch(timestamps.first);
  }

  String _newIdempotencyKey(String prefix) =>
      '$prefix-${_session.user?.id ?? 'user'}-${DateTime.now().microsecondsSinceEpoch}';

  String _safeError(Object error) {
    final message = error is ApiException ? error.message : error.toString();
    return message.length <= 240 ? message : message.substring(0, 240);
  }

  void dispose() => _api.dispose();
}
