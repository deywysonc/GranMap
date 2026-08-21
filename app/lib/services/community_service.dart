import '../community/community_models.dart';
import 'app_session.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class CommunityService {
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
        pendingOperations: remaining.length,
      );
    } catch (_) {
      final cached = await _store.readCachedProposals(scope);
      return CommunitySnapshot(
        contributions: cached,
        isOffline: true,
        pendingOperations: remaining.length,
      );
    }
  }

  Future<void> createProposal({
    required String subject,
    required String fromRoom,
    required String toRoom,
    required String reason,
  }) async {
    final token = _session.token;
    final user = _session.user;
    if (token == null || user == null) {
      throw const ApiException(
        'Entre na sua conta para enviar uma contribuição.',
        401,
      );
    }

    try {
      final raw = await _api.createProposal(
        token: token,
        subject: subject,
        fromRoom: fromRoom,
        toRoom: toRoom,
        reason: reason,
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

    try {
      final raw = await _api.voteProposal(
        token: token,
        proposalId: proposalId,
        agrees: agrees,
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
    queue.add({'type': 'vote', 'proposal_id': proposalId, 'agrees': agrees});
    await _store.saveCommunityQueue(_session.storageScope, queue);
    await _replaceCached(_optimisticVote(contribution, agrees));
  }

  Future<void> _flushPending(String token) async {
    final queue = await _store.readCommunityQueue(_session.storageScope);
    if (queue.isEmpty) return;

    final retained = <Map<String, dynamic>>[];
    for (var index = 0; index < queue.length; index++) {
      final operation = queue[index];
      try {
        if (operation['type'] == 'create') {
          final raw = await _api.createProposal(
            token: token,
            subject: operation['subject'].toString(),
            fromRoom: operation['from_room'].toString(),
            toRoom: operation['to_room'].toString(),
            reason: operation['reason'].toString(),
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
          );
          await _replaceCached(RoomChangeContribution.fromJson(raw));
        }
      } catch (_) {
        retained.addAll(queue.skip(index));
        break;
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
    return error is! ApiException || error.statusCode >= 500;
  }

  void dispose() => _api.dispose();
}
