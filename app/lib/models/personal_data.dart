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
