import 'package:geolocator/geolocator.dart';

class LocationService {
  // TODO: Implement method to get current user location
  Future<Map<String, double>> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return {'lat': 0.0, 'lng': 0.0};
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return {'lat': 0.0, 'lng': 0.0};
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return {'lat': 0.0, 'lng': 0.0};
    }
    Position position = await Geolocator.getCurrentPosition();
    return {'lat': position.latitude, 'lng': position.longitude};
  }
} 