import 'dart:async';
import 'dart:math';
import 'convoy_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class DummyUserService {
  Timer? _movementTimer;
  final ConvoyService _convoyService;
  final String _userId;
  final String _convoyId;
  
  // London route coordinates (from Kings Cross to Camden)
  final List<List<double>> _routePoints = [
    [51.5320, -0.1233], // Kings Cross Station
    [51.5335, -0.1250], // York Way
    [51.5350, -0.1270], // Caledonian Road
    [51.5370, -0.1300], // Camden Road
    [51.5390, -0.1350], // Camden High Street
    [51.5410, -0.1400], // Camden Town
    [51.5420, -0.1450], // Chalk Farm
    [51.5430, -0.1500], // Belsize Park
    [51.5440, -0.1550], // Hampstead
    [51.5450, -0.1600], // Hampstead Heath
  ];
  
  List<List<double>> _routePolyline = [];
  int _currentPolylineIndex = 0;
  double _progressAlongPolyline = 0.0;
  double _currentSpeed = 0.0; // m/s
  double _currentHeading = 0.0;
  bool _isOnJourney = true;
  
  // Movement parameters
  static const double _maxSpeed = 13.89; // ~50 km/h in m/s
  static const double _minSpeed = 2.78;  // ~10 km/h in m/s
  static const int _updateInterval = 1000; // 1 second updates
  
  DummyUserService(this._convoyService, this._userId, this._convoyId);
  
  Future<void> _fetchRoutePolyline() async {
    // Kings Cross to Hampstead Heath
    final start = _routePoints.first;
    final end = _routePoints.last;
    final accessToken = 'pk.eyJ1IjoiY2hlZWt5dyIsImEiOiJjbWM3bDMzaXkwcWprMm9zM21ydmNiZHZrIn0.Ll9ev_0u6Yc9FMd-MkbZgg';
    final url =
        'https://api.mapbox.com/directions/v5/mapbox/driving/${start[1]},${start[0]};${end[1]},${end[0]}'
        '?geometries=geojson&overview=full&steps=true&access_token=$accessToken';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'] != null && data['routes'].isNotEmpty) {
        final route = data['routes'][0];
        final coords = route['geometry']['coordinates'] as List<dynamic>;
        _routePolyline = coords.map<List<double>>((c) => [c[0].toDouble(), c[1].toDouble()]).toList();
        _currentPolylineIndex = 0;
        _progressAlongPolyline = 0.0;
      }
    }
  }
  
  void startDummyUser() {
    print('🚗 Starting dummy user: $_userId in convoy: $_convoyId');
    print('🗺️ Route: Kings Cross → Hampstead Heath (${_routePoints.length} waypoints)');
    _fetchRoutePolyline().then((_) {
      _convoyService.connect(_userId, convoyId: _convoyId).then((success) {
        print('DUMMY USER CONNECT RESULT: $success');
        if (success) {
          _movementTimer = Timer.periodic(Duration(milliseconds: _updateInterval), (timer) {
            _updatePosition();
          });
        } else {
          print('❌ Dummy user failed to connect, not starting movement timer.');
        }
      });
    });
  }
  
  void stopDummyUser() {
    print('🛑 Stopping dummy user: $_userId');
    _movementTimer?.cancel();
  }
  
  void _updatePosition() {
    if (_routePolyline.length < 2) return;
    if (_currentPolylineIndex >= _routePolyline.length - 1) {
      // Reached destination, restart journey
      _currentPolylineIndex = 0;
      _progressAlongPolyline = 0.0;
      print('🔄 Dummy user restarting journey from Kings Cross');
    }
    final currentPoint = _routePolyline[_currentPolylineIndex];
    final nextPoint = _routePolyline[_currentPolylineIndex + 1];
    final lng = currentPoint[0] + (nextPoint[0] - currentPoint[0]) * _progressAlongPolyline;
    final lat = currentPoint[1] + (nextPoint[1] - currentPoint[1]) * _progressAlongPolyline;
    final interpolatedPosition = [lng, lat];
    // Build remaining route polyline: start with interpolated position, then remaining polyline points
    List<List<double>> remainingRoute = [
      interpolatedPosition,
      ..._routePolyline.sublist(_currentPolylineIndex + 1)
    ];
    _currentHeading = _calculateHeading(currentPoint, nextPoint);
    _currentSpeed = _simulateSpeed();
    final locationData = {
      'type': 'location_update',
      'coordinates': interpolatedPosition,
      'velocity': _currentSpeed,
      'heading': _currentHeading,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'accuracy': 5.0,
      'isOnJourney': _isOnJourney,
      'routePoints': _isOnJourney ? remainingRoute : null,
    };
    _convoyService.sendLocationUpdate(locationData);
    final progressPercent = ((_currentPolylineIndex + _progressAlongPolyline) / (_routePolyline.length - 1) * 100).round();
    print('🚗 Dummy user: ${progressPercent}% complete - [$lng, $lat] - ${(_currentSpeed * 3.6).round()} km/h');
    // Update progress
    final segmentDistance = _calculateDistance(currentPoint, nextPoint);
    _progressAlongPolyline += _currentSpeed * _updateInterval / 1000 / segmentDistance;
    if (_progressAlongPolyline >= 1.0) {
      _progressAlongPolyline = 0.0;
      _currentPolylineIndex++;
      print('📍 Dummy user reached polyline point ${_currentPolylineIndex + 1}/${_routePolyline.length}');
    }
  }
  
  double _calculateHeading(List<double> from, List<double> to) {
    final deltaLng = to[0] - from[0];
    final deltaLat = to[1] - from[1];
    return atan2(deltaLng, deltaLat) * 180 / pi;
  }
  
  double _calculateDistance(List<double> from, List<double> to) {
    // Simple distance calculation (for demo purposes)
    final deltaLat = to[1] - from[1];
    final deltaLng = to[0] - from[0];
    return sqrt(deltaLat * deltaLat + deltaLng * deltaLng) * 111000; // Rough conversion to meters
  }
  
  double _simulateSpeed() {
    // Simulate realistic speed variations
    final random = Random();
    final baseSpeed = _minSpeed + (_maxSpeed - _minSpeed) * 0.7; // Average speed
    final variation = (random.nextDouble() - 0.5) * 2.0; // ±1 m/s variation
    return (baseSpeed + variation).clamp(_minSpeed, _maxSpeed);
  }
  
  void toggleJourney() {
    _isOnJourney = !_isOnJourney;
    print('🚗 Dummy user journey mode: ${_isOnJourney ? "ON" : "OFF"}');
  }
  
  void dispose() {
    stopDummyUser();
  }
} 