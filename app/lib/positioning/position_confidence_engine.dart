enum PositionConfidenceLevel { reliable, attention, lost }

class PositionConfidenceResult {
  final double score;
  final PositionConfidenceLevel level;
  final String message;

  const PositionConfidenceResult({
    required this.score,
    required this.level,
    required this.message,
  });
}

class PositionConfidenceEngine {
  const PositionConfidenceEngine();

  PositionConfidenceResult evaluate({
    required double sensorConfidence,
    required double mapMatchDistanceUnits,
    required double headingDriftDegrees,
    bool hasRecentAnchor = false,
  }) {
    final sensor = sensorConfidence.clamp(0, 1).toDouble();
    final mapMatch = (1 - mapMatchDistanceUnits / 14).clamp(0, 1).toDouble();
    final heading = (1 - headingDriftDegrees.abs() / 100)
        .clamp(0, 1)
        .toDouble();
    var score = sensor * .46 + mapMatch * .39 + heading * .15;
    if (hasRecentAnchor) score = score * .86 + .14;
    score = score.clamp(0, 1).toDouble();

    if (score >= .75) {
      return PositionConfidenceResult(
        score: score,
        level: PositionConfidenceLevel.reliable,
        message: 'Posição confiável',
      );
    }
    if (score >= .45) {
      return PositionConfidenceResult(
        score: score,
        level: PositionConfidenceLevel.attention,
        message: 'Posição aproximada',
      );
    }
    return PositionConfidenceResult(
      score: score,
      level: PositionConfidenceLevel.lost,
      message: 'Localização incerta — confirme onde você está',
    );
  }
}
