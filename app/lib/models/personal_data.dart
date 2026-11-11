class FavoriteState {
  final List<String> ids;
  final Map<String, bool> pending;
  final int revision;

  const FavoriteState({
    this.ids = const [],
    this.pending = const {},
    this.revision = 0,
  });

  factory FavoriteState.fromJson(Map<String, dynamic> json) => FavoriteState(
    ids: (json['ids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet()
        .toList(),
    pending: {
      for (final entry
          in (json['pending'] as Map<String, dynamic>? ?? {}).entries)
        if (entry.value is bool) entry.key: entry.value as bool,
    },
    revision: (json['revision'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'ids': ids,
    'pending': pending,
    'revision': revision,
  };
}

class NavigationHistoryItem {
  final String poiId;
  final String poiName;
  final DateTime visitedAt;

  const NavigationHistoryItem({
    required this.poiId,
    required this.poiName,
    required this.visitedAt,
  });

  factory NavigationHistoryItem.fromJson(Map<String, dynamic> json) {
    return NavigationHistoryItem(
      poiId: (json['poi_id'] ?? '') as String,
      poiName: (json['poi_name'] ?? '') as String,
      visitedAt:
          DateTime.tryParse((json['visited_at'] ?? '') as String) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'poi_id': poiId,
    'poi_name': poiName,
    'visited_at': visitedAt.toIso8601String(),
  };
}
