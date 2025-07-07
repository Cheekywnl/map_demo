import 'dart:async';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'convoy_service.dart';

class DummyUserService {
  Timer? _movementTimer;
  final ConvoyService _convoyService;
  final String _userId;
  final String _convoyId;
  
  // London route coordinates (from Kings Cross to Camden)
  final List<LatLng> _routePoints = [
    LatLng(51.5320, -0.1233), // Kings Cross Station
    LatLng(51.5335, -0.1250), // York Way
    LatLng(51.5350, -0.1270), // Caledonian Road
    LatLng(51.5370, -0.1300), // Camden Road
    LatLng(51.5390, -0.1350), // Camden High Street
    LatLng(51.5410, -0.1400), // Camden Town
    LatLng(51.5420, -0.1450), // Chalk Farm
    LatLng(51.5430, -0.1500), // Belsize Park
    LatLng(51.5440, -0.1550), // Hampstead
    LatLng(51.5450, -0.1600), // Hampstead Heath
  ];
  
  int _currentRouteIndex = 0;
  double _progressAlongSegment = 0.0;
  double _currentSpeed = 0.0; // m/s
  double _currentHeading = 0.0;
  bool _isOnJourney = true;
  
  // Movement parameters
  static const double _maxSpeed = 13.89; // ~50 km/h in m/s
  static const double _minSpeed = 2.78;  // ~10 km/h in m/s
  static const int _updateInterval = 1000; // 1 second updates
  
  DummyUserService(this._convoyService, this._userId, this._convoyId);
  
  void startDummyUser() {
    print('🚗 Starting dummy user: $_userId in convoy: $_convoyId');
    print('🗺️ Route: Kings Cross → Hampstead Heath (${_routePoints.length} waypoints)');
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
  }
  
  void stopDummyUser() {
    print('🛑 Stopping dummy user: $_userId');
    _movementTimer?.cancel();
  }
  
  void _updatePosition() {
    if (_currentRouteIndex >= _routePoints.length - 1) {
      // Reached destination, restart journey
      _currentRouteIndex = 0;
      _progressAlongSegment = 0.0;
      print('🔄 Dummy user restarting journey from Kings Cross');
    }
    
    // Calculate current position along route
    final currentPoint = _routePoints[_currentRouteIndex];
    final nextPoint = _routePoints[_currentRouteIndex + 1];
    
    // Interpolate position between current and next waypoint
    final lat = currentPoint.latitude + (nextPoint.latitude - currentPoint.latitude) * _progressAlongSegment;
    final lng = currentPoint.longitude + (nextPoint.longitude - currentPoint.longitude) * _progressAlongSegment;
    final interpolatedPosition = LatLng(lat, lng);
    
    // Build remaining route polyline: start with interpolated position, then remaining waypoints
    List<List<double>> remainingRoute = [
      [interpolatedPosition.longitude, interpolatedPosition.latitude],
      ..._routePoints
        .sublist(_currentRouteIndex + 1)
        .map((p) => [p.longitude, p.latitude])
    ];
    
    // Calculate heading (direction of travel)
    _currentHeading = _calculateHeading(currentPoint, nextPoint);
    
    // Simulate realistic speed variations
    _currentSpeed = _simulateSpeed();
    
    // Create location data
    final locationData = {
      'type': 'location_update',
      'coordinates': [lng, lat],
      'velocity': _currentSpeed,
      'heading': _currentHeading,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'accuracy': 5.0,
      'isOnJourney': _isOnJourney,
      'routePoints': _isOnJourney ? remainingRoute : null,
    };
    
    // Send to convoy service
    print('DUMMY USER SENDING LOCATION: $locationData');
    _convoyService.sendLocationUpdate(locationData);
    
    // Log progress
    final progressPercent = ((_currentRouteIndex + _progressAlongSegment) / (_routePoints.length - 1) * 100).round();
    print('🚗 Dummy user: ${progressPercent}% complete - [${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}] - ${(_currentSpeed * 3.6).round()} km/h');
    
    // Update progress
    _progressAlongSegment += _currentSpeed * _updateInterval / 1000 / _calculateDistance(currentPoint, nextPoint);
    
    if (_progressAlongSegment >= 1.0) {
      _progressAlongSegment = 0.0;
      _currentRouteIndex++;
      print('📍 Dummy user reached waypoint ${_currentRouteIndex + 1}/${_routePoints.length}');
    }
  }
  
  double _calculateHeading(LatLng from, LatLng to) {
    final deltaLng = to.longitude - from.longitude;
    final deltaLat = to.latitude - from.latitude;
    return atan2(deltaLng, deltaLat) * 180 / pi;
  }
  
  double _calculateDistance(LatLng from, LatLng to) {
    // Simple distance calculation (for demo purposes)
    final deltaLat = to.latitude - from.latitude;
    final deltaLng = to.longitude - from.longitude;
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