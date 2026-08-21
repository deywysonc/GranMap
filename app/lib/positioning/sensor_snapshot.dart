class SensorSnapshot {
  final double accelerationX;
  final double accelerationY;
  final double accelerationZ;
  final double gyroscopeZ;
  final double magneticX;
  final double magneticY;
  final double magneticZ;
  final double magneticField;
  final double headingDegrees;
  final int stepCount;
  final double confidence;
  final double? pressureHpa;
  final String source;
  final DateTime timestamp;

  const SensorSnapshot({
    required this.accelerationX,
    required this.accelerationY,
    required this.accelerationZ,
    required this.gyroscopeZ,
    this.magneticX = 0,
    this.magneticY = 0,
    this.magneticZ = 0,
    required this.magneticField,
    required this.headingDegrees,
    required this.stepCount,
    required this.confidence,
    this.pressureHpa,
    this.source = 'simulation',
    required this.timestamp,
  });
}
