class PositionSample {
  final double x;
  final double y;
  final double z;
  final int floor;
  final double headingDegrees;
  final double accuracyMeters;
  final double confidence;
  final DateTime timestamp;

  const PositionSample({
    required this.x,
    required this.y,
    required this.z,
    required this.floor,
    required this.headingDegrees,
    required this.accuracyMeters,
    required this.confidence,
    required this.timestamp,
  });
}
