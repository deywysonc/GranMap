import 'dart:math' as math;

import 'sensor_snapshot.dart';

class MagneticFingerprint {
  final double x;
  final double y;
  final double z;
  final int floor;
  final double magneticX;
  final double magneticY;
  final double magneticZ;
  final double quality;

  const MagneticFingerprint({
    required this.x,
    required this.y,
    required this.z,
    required this.floor,
    required this.magneticX,
    required this.magneticY,
    required this.magneticZ,
    required this.quality,
  });

  factory MagneticFingerprint.fromJson(Map<String, dynamic> json) {
    return MagneticFingerprint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      floor: (json['floor'] as num).toInt(),
      magneticX: (json['magnetic_x'] as num).toDouble(),
      magneticY: (json['magnetic_y'] as num).toDouble(),
      magneticZ: (json['magnetic_z'] as num).toDouble(),
      quality: ((json['quality'] ?? 0) as num).toDouble(),
    );
  }
}

class MagneticMatch {
  final double x;
  final double y;
  final double z;
  final double confidence;
  final int neighbors;

  const MagneticMatch({
    required this.x,
    required this.y,
    required this.z,
    required this.confidence,
    required this.neighbors,
  });
}

/// k-NN ponderado no vetor magnético. A saída é evidência para a fusão, nunca
/// uma posição absoluta isolada.
class MagneticFingerprintMatcher {
  const MagneticFingerprintMatcher();

  MagneticMatch? match({
    required SensorSnapshot snapshot,
    required int floor,
    required List<MagneticFingerprint> references,
    int neighbors = 4,
  }) {
    final candidates =
        references
            .where((item) => item.floor == floor && item.quality >= .35)
            .map((item) => _Distance(item, _distance(snapshot, item)))
            .toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));
    if (candidates.length < 2) return null;
    final selected = candidates.take(math.min(neighbors, candidates.length));
    var weightSum = 0.0;
    var x = 0.0;
    var y = 0.0;
    var z = 0.0;
    var distanceSum = 0.0;
    var count = 0;
    for (final candidate in selected) {
      final weight = candidate.item.quality / math.max(.5, candidate.distance);
      weightSum += weight;
      x += candidate.item.x * weight;
      y += candidate.item.y * weight;
      z += candidate.item.z * weight;
      distanceSum += candidate.distance;
      count++;
    }
    if (weightSum <= 0) return null;
    final averageDistance = distanceSum / count;
    final confidence =
        ((1 - averageDistance / 30) * math.min(1, count / neighbors))
            .clamp(0, .92)
            .toDouble();
    if (confidence < .2) return null;
    return MagneticMatch(
      x: x / weightSum,
      y: y / weightSum,
      z: z / weightSum,
      confidence: confidence,
      neighbors: count,
    );
  }

  double _distance(SensorSnapshot sample, MagneticFingerprint reference) {
    final dx = sample.magneticX - reference.magneticX;
    final dy = sample.magneticY - reference.magneticY;
    final dz = sample.magneticZ - reference.magneticZ;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

class _Distance {
  final MagneticFingerprint item;
  final double distance;

  const _Distance(this.item, this.distance);
}
