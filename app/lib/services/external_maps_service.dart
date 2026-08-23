import 'package:url_launcher/url_launcher.dart';

import '../positioning/gran_presence_service.dart';

class ExternalMapsService {
  const ExternalMapsService();

  Uri directionsToGran() => Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${GranGeofence.latitude},${GranGeofence.longitude}',
    'travelmode': 'driving',
    'dir_action': 'navigate',
  });

  Future<bool> openDirectionsToGran() async {
    try {
      return await launchUrl(
        directionsToGran(),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
