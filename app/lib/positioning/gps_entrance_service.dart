import 'package:geolocator/geolocator.dart';

class GpsEntranceFix {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;

  const GpsEntranceFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });
}

/// GPS é usado apenas como apoio próximo às entradas. A conversão GPS → X/Y/Z
/// depende dos pontos georreferenciados obtidos no levantamento da faculdade.
class GpsEntranceService {
  Future<GpsEntranceFix> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Ative a localização do aparelho para obter o GPS.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Permissão de localização não concedida.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return GpsEntranceFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
    );
  }
}
