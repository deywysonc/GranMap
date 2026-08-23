import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/positioning/gran_presence_service.dart';

void main() {
  group('GranGeofence', () {
    test('reconhece uma leitura confiável dentro da Gran Tietê', () {
      final result = GranGeofence.classify(
        latitude: GranGeofence.latitude,
        longitude: GranGeofence.longitude,
        accuracyMeters: 8,
      );

      expect(result.status, GranPresenceStatus.inside);
      expect(result.distanceMeters, closeTo(0, .01));
    });

    test('distingue proximidade de uma posição distante', () {
      final nearby = GranGeofence.classify(
        latitude: GranGeofence.latitude + .0045,
        longitude: GranGeofence.longitude,
        accuracyMeters: 12,
      );
      final outside = GranGeofence.classify(
        latitude: GranGeofence.latitude + 1,
        longitude: GranGeofence.longitude,
        accuracyMeters: 12,
      );

      expect(nearby.status, GranPresenceStatus.nearby);
      expect(outside.status, GranPresenceStatus.outside);
    });

    test('não afirma presença quando o GPS é impreciso', () {
      final result = GranGeofence.classify(
        latitude: GranGeofence.latitude + .0045,
        longitude: GranGeofence.longitude,
        accuracyMeters: 250,
      );

      expect(result.status, GranPresenceStatus.uncertain);
    });

    test('não usa uma posição antiga como se fosse atual', () {
      final result = GranGeofence.classify(
        latitude: GranGeofence.latitude,
        longitude: GranGeofence.longitude,
        accuracyMeters: 8,
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(result.status, GranPresenceStatus.uncertain);
      expect(result.detail, contains('desatualizada'));
    });

    test('calcula distância geográfica em metros', () {
      final distance = GranGeofence.distanceBetween(0, 0, 0, 1);
      expect(distance, closeTo(111195, 100));
    });
  });
}
