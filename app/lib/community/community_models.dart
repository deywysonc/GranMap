enum ContributionStatus { unverified, voting, confirmed, contested, rejected }

ContributionStatus contributionStatusFromName(String? value) {
  return ContributionStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ContributionStatus.unverified,
  );
}

class RoomChangeContribution {
  final String id;
  final String subject;
  final String authorName;
  final int authorReputation;
  final String fromRoomName;
  final String toRoomName;
  final String reason;
  final ContributionStatus status;
  final int yesVotes;
  final int noVotes;
  final bool? myVote;
  final bool officialPriority;
  final String moderationNote;
  final DateTime? createdAt;
  final bool pendingSync;

  const RoomChangeContribution({
    required this.id,
    required this.subject,
    required this.authorName,
    required this.fromRoomName,
    required this.toRoomName,
    required this.reason,
    required this.status,
    required this.yesVotes,
    required this.noVotes,
    this.authorReputation = 0,
    this.myVote,
    this.officialPriority = false,
    this.moderationNote = '',
    this.createdAt,
    this.pendingSync = false,
  });

  factory RoomChangeContribution.fromJson(Map<String, dynamic> json) {
    return RoomChangeContribution(
      id: (json['id'] ?? '').toString(),
      subject: (json['subject'] ?? '') as String,
      authorName: (json['author_name'] ?? '') as String,
      authorReputation: (json['author_reputation'] as num?)?.toInt() ?? 0,
      fromRoomName: (json['from_room'] ?? '') as String,
      toRoomName: (json['to_room'] ?? '') as String,
      reason: (json['reason'] ?? '') as String,
      status: contributionStatusFromName(json['status'] as String?),
      yesVotes: (json['yes_votes'] as num?)?.toInt() ?? 0,
      noVotes: (json['no_votes'] as num?)?.toInt() ?? 0,
      myVote: json['my_vote'] as bool?,
      officialPriority: json['official_priority'] as bool? ?? false,
      moderationNote: (json['moderation_note'] ?? '') as String,
      createdAt: DateTime.tryParse((json['created_at'] ?? '') as String),
      pendingSync: json['pending_sync'] as bool? ?? false,
    );
  }

  int get totalVotes => yesVotes + noVotes;
  double get confidence => totalVotes == 0 ? 0 : yesVotes / totalVotes;
  bool get canVote => !pendingSync && status != ContributionStatus.rejected;

  Map<String, dynamic> toJson() => {
    'id': id,
    'subject': subject,
    'author_name': authorName,
    'author_reputation': authorReputation,
    'from_room': fromRoomName,
    'to_room': toRoomName,
    'reason': reason,
    'status': status.name,
    'yes_votes': yesVotes,
    'no_votes': noVotes,
    'my_vote': myVote,
    'official_priority': officialPriority,
    'moderation_note': moderationNote,
    'created_at': createdAt?.toIso8601String(),
    'pending_sync': pendingSync,
  };

  RoomChangeContribution copyWith({
    String? id,
    int? yesVotes,
    int? noVotes,
    bool? myVote,
    ContributionStatus? status,
    bool? pendingSync,
  }) {
    return RoomChangeContribution(
      id: id ?? this.id,
      subject: subject,
      authorName: authorName,
      authorReputation: authorReputation,
      fromRoomName: fromRoomName,
      toRoomName: toRoomName,
      reason: reason,
      status: status ?? this.status,
      yesVotes: yesVotes ?? this.yesVotes,
      noVotes: noVotes ?? this.noVotes,
      myVote: myVote ?? this.myVote,
      officialPriority: officialPriority,
      moderationNote: moderationNote,
      createdAt: createdAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}

class CommunitySnapshot {
  final List<RoomChangeContribution> contributions;
  final bool isOffline;
  final int pendingOperations;
  final int failedOperations;
  final DateTime? nextRetryAt;

  const CommunitySnapshot({
    required this.contributions,
    required this.isOffline,
    required this.pendingOperations,
    this.failedOperations = 0,
    this.nextRetryAt,
  });
}
