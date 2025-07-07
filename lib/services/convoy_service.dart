import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class ConvoyLocation {
  final String userId;
  final LatLng coordinates;
  final double velocity;
  final double heading;
  final DateTime timestamp;
  final double accuracy;
  final bool isOnJourney;
  final List<LatLng>? routePoints;

  ConvoyLocation({
    required this.userId,
    required this.coordinates,
    required this.velocity,
    required this.heading,
    required this.timestamp,
    required this.accuracy,
    this.isOnJourney = false,
    this.routePoints,
  });

  factory ConvoyLocation.fromJson(Map<String, dynamic> json) {
    List<LatLng>? routePoints;
    if (json['routePoints'] != null) {
      routePoints = (json['routePoints'] as List)
          .map((point) => LatLng(point[1].toDouble(), point[0].toDouble()))
          .toList();
    }

    return ConvoyLocation(
      userId: json['userId'],
      coordinates: LatLng(
        json['coordinates'][1].toDouble(),
        json['coordinates'][0].toDouble(),
      ),
      velocity: json['velocity']?.toDouble() ?? 0.0,
      heading: json['heading']?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      accuracy: json['accuracy']?.toDouble() ?? 0.0,
      isOnJourney: json['isOnJourney'] ?? false,
      routePoints: routePoints,
    );
  }
}

class ConvoyService {
  WebSocketChannel? _channel;
  String? _userId;
  String? _convoyId;
  bool _isConnected = false;
  
  // Streams for real-time updates
  final StreamController<ConvoyLocation> _locationController = 
      StreamController<ConvoyLocation>.broadcast();
  final StreamController<String> _memberJoinedController = 
      StreamController<String>.broadcast();
  final StreamController<String> _memberLeftController = 
      StreamController<String>.broadcast();
  final StreamController<String> _connectionStatusController = 
      StreamController<String>.broadcast();

  // Getters for streams
  Stream<ConvoyLocation> get locationUpdates => _locationController.stream;
  Stream<String> get memberJoined => _memberJoinedController.stream;
  Stream<String> get memberLeft => _memberLeftController.stream;
  Stream<String> get connectionStatus => _connectionStatusController.stream;

  // Current convoy members locations
  final Map<String, ConvoyLocation> _memberLocations = {};

  // Location tracking timer
  Timer? _locationTimer;

  // Connection status
  bool get isConnected => _isConnected;
  String? get userId => _userId;
  String? get convoyId => _convoyId;
  Map<String, ConvoyLocation> get memberLocations => Map.unmodifiable(_memberLocations);

  // Connect to convoy server
  Future<bool> connect(String userId, {String? convoyId}) async {
    try {
      print('🔌 Connecting to convoy server...');
      _connectionStatusController.add('connecting');
      
      final wsUrl = Uri.parse('ws://192.168.1.55:3000?userId=$userId${convoyId != null ? '&convoyId=$convoyId' : ''}');
      _channel = WebSocketChannel.connect(wsUrl);
      _userId = userId;
      _convoyId = convoyId;

      // Listen for messages
      _channel!.stream.listen(
        (message) => _handleMessage(message),
        onError: (error) {
          print('❌ WebSocket error: $error');
          _connectionStatusController.add('error');
          _isConnected = false;
        },
        onDone: () {
          print('🔌 WebSocket connection closed');
          _connectionStatusController.add('disconnected');
          _isConnected = false;
        },
      );

      _isConnected = true;
      _connectionStatusController.add('connected');
      print('✅ Connected to convoy server');
      
      // Send join_convoy message if convoyId is provided
      if (convoyId != null) {
        final joinMessage = {
          'type': 'join_convoy',
          'convoyId': convoyId,
        };
        _channel?.sink.add(jsonEncode(joinMessage));
        print('➡️ Sent join_convoy message for convoyId: $convoyId');
      }
      
      return true;
    } catch (e) {
      print('❌ Failed to connect: $e');
      _connectionStatusController.add('error');
      return false;
    }
  }

  // Disconnect from server
  void disconnect() {
    print('🔌 Disconnecting from convoy server...');
    _locationTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _connectionStatusController.add('disconnected');
    _memberLocations.clear();
  }

  // Send location update (for dummy user)
  void sendLocationUpdate(Map<String, dynamic> locationData) {
    print('ConvoyService.sendLocationUpdate: userId=$_userId, isConnected=$_isConnected, data=$locationData');
    if (!_isConnected) {
      print('❌ Not connected to server');
      return;
    }
    _channel?.sink.add(jsonEncode(locationData));
    print('📍 Location sent: [${locationData['coordinates'][1].toStringAsFixed(6)}, ${locationData['coordinates'][0].toStringAsFixed(6)}]');
  }

  // Start location tracking (3Hz)
  void startLocationTracking() {
    if (!_isConnected) {
      print('❌ Not connected to server');
      return;
    }

    print('📍 Starting 3Hz location tracking...');
    _locationTimer?.cancel();
    
    _locationTimer = Timer.periodic(const Duration(milliseconds: 333), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        final locationData = {
          'type': 'location_update',
          'coordinates': [position.longitude, position.latitude],
          'velocity': position.speed,
          'heading': position.heading,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'accuracy': position.accuracy,
        };

        _channel?.sink.add(jsonEncode(locationData));
        print('📍 Location sent: [${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}]');
      } catch (e) {
        print('❌ Error getting location: $e');
      }
    });
  }

  // Stop location tracking
  void stopLocationTracking() {
    print('📍 Stopping location tracking...');
    _locationTimer?.cancel();
  }

  // Join a convoy
  void joinConvoy(String convoyId) {
    if (!_isConnected) {
      print('❌ Not connected to server');
      return;
    }

    print('👥 Joining convoy: $convoyId');
    final message = {
      'type': 'join_convoy',
      'convoyId': convoyId,
    };
    
    _channel?.sink.add(jsonEncode(message));
    _convoyId = convoyId;
  }

  // Leave current convoy
  void leaveConvoy() {
    if (!_isConnected || _convoyId == null) {
      print('❌ Not in a convoy');
      return;
    }

    print('👋 Leaving convoy: $_convoyId');
    final message = {
      'type': 'leave_convoy',
      'convoyId': _convoyId,
    };
    
    _channel?.sink.add(jsonEncode(message));
    _convoyId = null;
    _memberLocations.clear();
  }

  // Handle incoming messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];
      
      print('📨 Received message type: $type');
      print('📨 Message data: $data');

      switch (type) {
        case 'connection_established':
          print('✅ Connection established with server');
          break;

        case 'member_location_update':
          _handleLocationUpdate(data);
          break;

        case 'all_member_locations':
          final locations = data['locations'] as List<dynamic>;
          final userIds = locations.map((loc) => loc['userId']).toList();
          print('🟣 Received all_member_locations for userIds: $userIds');
          print('🟣 Full locations data: $locations');
          for (final loc in locations) {
            final location = ConvoyLocation.fromJson(loc);
            _memberLocations[location.userId] = location;
            _locationController.add(location);
            print('🟣 Added location for ${location.userId}: [${location.coordinates.latitude.toStringAsFixed(6)}, ${location.coordinates.longitude.toStringAsFixed(6)}]');
          }
          break;

        case 'member_joined':
          final userId = data['userId'];
          print('👥 Member joined: $userId');
          _memberJoinedController.add(userId);
          break;

        case 'member_left':
          final userId = data['userId'];
          print('👋 Member left: $userId');
          _memberLocations.remove(userId);
          _memberLeftController.add(userId);
          break;

        case 'error':
          print('❌ Server error: ${data['message']}');
          break;

        default:
          print('❓ Unknown message type: $type');
      }
    } catch (e) {
      print('❌ Error parsing message: $e');
      print('❌ Raw message: $message');
    }
  }

  // Handle location updates from convoy members
  void _handleLocationUpdate(Map<String, dynamic> data) {
    final location = ConvoyLocation.fromJson(data['location']);
    _memberLocations[location.userId] = location;
    _locationController.add(location);
    
    print('📍 Location update from ${location.userId}: [${location.coordinates.latitude.toStringAsFixed(6)}, ${location.coordinates.longitude.toStringAsFixed(6)}]');
  }

  // Dispose resources
  void dispose() {
    disconnect();
    _locationController.close();
    _memberJoinedController.close();
    _memberLeftController.close();
    _connectionStatusController.close();
  }
} 