import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../services/convoy_service.dart';
import '../services/dummy_user_service.dart';

class SearchResult {
  final String name;
  final String address;
  final LatLng coordinates;

  SearchResult({
    required this.name,
    required this.address,
    required this.coordinates,
  });
}

class RouteInfo {
  final double distance; // in kilometers
  final int duration; // in seconds
  final String distanceText;
  final String durationText;

  RouteInfo({
    required this.distance,
    required this.duration,
    required this.distanceText,
    required this.durationText,
  });
}

class MapWidget extends StatefulWidget {
  const MapWidget({super.key});

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  RouteInfo? _routeInfo;
  final TextEditingController _searchController = TextEditingController();
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  SearchResult? _selectedDestination;
  Timer? _searchDebounce;
  bool _isMapReady = false;

  // Convoy functionality
  final ConvoyService _convoyService = ConvoyService();
  bool _isInConvoy = false;
  String _currentConvoyId = '';
  final Map<String, Marker> _convoyMarkers = {};
  final TextEditingController _convoyIdController = TextEditingController();
  bool _showConvoyDialog = false;

  // Dummy user functionality
  DummyUserService? _dummyUserService;
  bool _isDummyUserActive = false;
  final Map<String, List<LatLng>> _memberRoutes = {};

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _setupConvoyListeners();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _convoyIdController.dispose();
    _convoyService.dispose();
    _dummyUserService?.dispose();
    super.dispose();
  }

  void _setupConvoyListeners() {
    // Listen for convoy member location updates
    _convoyService.locationUpdates.listen((location) {
      setState(() {
        // Update member marker
        _convoyMarkers[location.userId] = Marker(
          point: location.coordinates,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: location.isOnJourney ? Colors.purple.withOpacity(0.8) : Colors.blue.withOpacity(0.8),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(
              location.isOnJourney ? Icons.directions_car : Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
        );
        
        // Update member route if available
        if (location.routePoints != null && location.routePoints!.isNotEmpty) {
          _memberRoutes[location.userId] = location.routePoints!;
        }
      });
      
      print('📍 Location update from ${location.userId}: [${location.coordinates.latitude.toStringAsFixed(6)}, ${location.coordinates.longitude.toStringAsFixed(6)}] - Journey: ${location.isOnJourney}');
      
      // If this is a dummy user, center the map on them for the first few updates
      if (location.userId.startsWith('dummy_') && _convoyMarkers.length <= 2) {
        print('🗺️ Centering map on dummy user location');
        _animatedMapMove(location.coordinates, 15.0);
      }
    });

    // Listen for member joined
    _convoyService.memberJoined.listen((userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('👥 $userId joined the convoy')),
      );
    });

    // Listen for member left
    _convoyService.memberLeft.listen((userId) {
      setState(() {
        _convoyMarkers.remove(userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('👋 $userId left the convoy')),
      );
    });

    // Listen for connection status
    _convoyService.connectionStatus.listen((status) {
      print('🔌 Connection status: $status');
      if (status == 'connected') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Connected to convoy server')),
        );
      } else if (status == 'error') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Failed to connect to convoy server')),
        );
      }
    });
  }



  Future<void> _getCurrentLocation() async {
    print('📍 Getting current location...');
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return;
      }
      print('✅ Location services are enabled');
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        print('🔐 Requesting location permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permission denied forever');
        return;
      }
      print('✅ Location permission granted');
      
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print('📍 Current position: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}');
      setState(() {
        _currentPosition = position;
      });
      if (_isMapReady) {
        _animatedMapMove(LatLng(position.latitude, position.longitude), 20.0);
      }
    } catch (e) {
      print('❌ Error getting location: $e');
    }
  }

  void _centerOnLocation() {
    if (_currentPosition != null && _isMapReady) {
      print('📍 Centering map on current location');
      _animatedMapMove(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 20.0);
    }
  }

  void _centerOnDummyUser() {
    // Find the first dummy user marker
    final dummyUserEntry = _convoyMarkers.entries
        .where((entry) => entry.key.startsWith('dummy_'))
        .firstOrNull;
    
    if (dummyUserEntry != null && _isMapReady) {
      print('🚗 Centering map on dummy user');
      _animatedMapMove(dummyUserEntry.value.point, 15.0);
    } else {
      print('❌ No dummy user found on map');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ No dummy user found on map')),
      );
    }
  }

  void _animatedMapMove(LatLng dest, double zoom) {
    print('🗺️ Moving map to: ${dest.latitude.toStringAsFixed(6)}, ${dest.longitude.toStringAsFixed(6)} at zoom level: ${zoom.toStringAsFixed(1)}');
    _mapController.move(dest, zoom);
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      print('🔍 Search cleared');
      return;
    }
    print('🔍 Search query: "$query"');
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) return;
    print('🌍 Searching for: "$query"');
    setState(() {
      _isSearching = true;
    });
    try {
      const String accessToken = 'pk.eyJ1IjoiY2hlZWt5dyIsImEiOiJjbWM3bDMzaXkwcWprMm9zM21ydmNiZHZrIn0.Ll9ev_0u6Yc9FMd-MkbZgg';
      final String url = 
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json'
          '?access_token=$accessToken'
          '&limit=5'
          '&types=poi,address';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> features = data['features'];
        print('✅ Found ${features.length} search results');
        setState(() {
          _searchResults = features.map((feature) => SearchResult(
            name: feature['place_name'],
            address: feature['place_name'],
            coordinates: LatLng(feature['center'][1], feature['center'][0]),
          )).toList();
          _showSearchResults = true;
        });
      }
    } catch (e) {
      print('❌ Error searching places: $e');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _selectPlace(SearchResult place) {
    print('🎯 Selected place: "${place.name}" at ${place.coordinates.latitude.toStringAsFixed(6)}, ${place.coordinates.longitude.toStringAsFixed(6)}');
    setState(() {
      _showSearchResults = false;
      _searchController.text = place.name;
    });
    _animatedMapMove(place.coordinates, 18.0);
    _getRoute(place.coordinates);
  }

  Future<void> _getRoute(LatLng destination) async {
    if (_currentPosition == null) return;
    print('🛣️ Getting route to: ${destination.latitude.toStringAsFixed(6)}, ${destination.longitude.toStringAsFixed(6)}');
    setState(() {
      _isLoadingRoute = true;
      _routeInfo = null;
    });
    try {
      const String accessToken = 'pk.eyJ1IjoiY2hlZWt5dyIsImEiOiJjbWM3bDMzaXkwcWprMm9zM21ydmNiZHZrIn0.Ll9ev_0u6Yc9FMd-MkbZgg';
      final LatLng origin = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final String url = 
          'https://api.mapbox.com/directions/v5/mapbox/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?geometries=geojson&overview=full&steps=true&annotations=distance,duration,speed&access_token=$accessToken';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final List<dynamic> coordinates = route['geometry']['coordinates'];
          final double distance = route['distance'] / 1000; // Convert to km
          final int duration = route['duration'].round(); // Duration in seconds
          final String distanceText = distance >= 1 
              ? '${distance.toStringAsFixed(1)} km'
              : '${(distance * 1000).round()} m';
          final String durationText = _formatDuration(duration);
          print('✅ Route calculated: $distanceText, $durationText (${coordinates.length} points)');
          setState(() {
            _routePoints = coordinates.map((coord) => 
                LatLng(coord[1].toDouble(), coord[0].toDouble())).toList();
            _routeInfo = RouteInfo(
              distance: distance,
              duration: duration,
              distanceText: distanceText,
              durationText: durationText,
            );
          });
        }
      }
    } catch (e) {
      print('❌ Error getting route: $e');
    } finally {
      setState(() {
        _isLoadingRoute = false;
      });
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '$seconds sec';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).round();
      return '$minutes min';
    } else {
      final hours = (seconds / 3600).floor();
      final minutes = ((seconds % 3600) / 60).round();
      return '$hours hr $minutes min';
    }
  }

  // Convoy functions
  void _showConvoyJoinDialog() {
    print('🔧 Showing convoy join dialog...');
    setState(() {
      _showConvoyDialog = true;
    });
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Join Convoy'),
          content: TextField(
            controller: _convoyIdController,
            decoration: const InputDecoration(
              labelText: 'Convoy ID',
              hintText: 'Enter convoy ID',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                print('❌ Convoy join cancelled');
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                print('✅ Convoy join button pressed');
                _joinConvoy();
                Navigator.of(context).pop();
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }

  void _joinConvoy() {
    final convoyId = _convoyIdController.text.trim();
    print('🔧 Attempting to join convoy: "$convoyId"');
    
    if (convoyId.isEmpty) {
      print('❌ Convoy ID is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Please enter a convoy ID')),
      );
      return;
    }

    print('🔌 Connecting to convoy server with ID: $convoyId');
    _convoyService.connect('user_${DateTime.now().millisecondsSinceEpoch}', convoyId: convoyId).then((success) {
      print('🔌 Connection result: $success');
      if (success) {
        setState(() {
          _isInConvoy = true;
          _currentConvoyId = convoyId;
          _showConvoyDialog = false;
        });
        print('📍 Starting location tracking...');
        _convoyService.startLocationTracking();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🚗 Joined convoy: $convoyId')),
        );
        print('✅ Successfully joined convoy: $convoyId');
      } else {
        print('❌ Failed to join convoy');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Failed to connect to convoy server')),
        );
      }
    }).catchError((error) {
      print('❌ Error joining convoy: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $error')),
      );
    });
  }

  void _leaveConvoy() {
    _convoyService.leaveConvoy();
    _convoyService.stopLocationTracking();
    setState(() {
      _isInConvoy = false;
      _currentConvoyId = '';
      _convoyMarkers.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('👋 Left convoy')),
    );
  }



  void _startDummyUser() {
    if (_currentConvoyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Please join a convoy first')),
      );
      return;
    }

    final dummyUserId = 'dummy_${DateTime.now().millisecondsSinceEpoch}';
    // Create a NEW ConvoyService for the dummy user!
    final dummyConvoyService = ConvoyService();
    dummyConvoyService.connect(dummyUserId, convoyId: _currentConvoyId);
    _dummyUserService = DummyUserService(dummyConvoyService, dummyUserId, _currentConvoyId);
    _dummyUserService!.startDummyUser();
    
    setState(() {
      _isDummyUserActive = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🚗 Started dummy user: $dummyUserId')),
    );
    print('🚗 Dummy user started: $dummyUserId in convoy: $_currentConvoyId');
  }

  void _stopDummyUser() {
    _dummyUserService?.stopDummyUser();
    _dummyUserService?.dispose();
    _dummyUserService = null;
    
    setState(() {
      _isDummyUserActive = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🛑 Stopped dummy user')),
    );
    print('🛑 Dummy user stopped');
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPosition == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              initialZoom: 20.0,
              maxZoom: 22.0,
              minZoom: 3.0,
              onMapReady: () {
                print('🗺️ Map is ready!');
                setState(() {
                  _isMapReady = true;
                });
              },
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && position.zoom != null) {
                  print('🔍 User zoomed to level: ${position.zoom!.toStringAsFixed(1)} at center: ${position.center!.latitude.toStringAsFixed(6)}, ${position.center!.longitude.toStringAsFixed(6)}');
                  double newZoom = position.zoom!;
                  if (newZoom < 5.0) {
                    print('⚠️ Zoom level too low, adjusting to 5.0');
                    newZoom = 5.0;
                  }
                  if ((newZoom - position.zoom!).abs() > 0.1) {
                    _animatedMapMove(position.center!, newZoom);
                  }
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/light-v11/tiles/{z}/{x}/{y}?access_token=pk.eyJ1IjoiY2hlZWt5dyIsImEiOiJjbWM3bDMzaXkwcWprMm9zM21ydmNiZHZrIn0.Ll9ev_0u6Yc9FMd-MkbZgg',
                userAgentPackageName: 'com.example.map_here_demo',
                maxZoom: 22,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                    ),
                  ),
                  ..._convoyMarkers.values,
                ],
              ),
              // Route polyline
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4,
                      color: Colors.blue,
                    ),
                  ],
                ),
              // Convoy member routes
              if (_memberRoutes.isNotEmpty)
                PolylineLayer(
                  polylines: _memberRoutes.entries.map((entry) {
                    final userId = entry.key;
                    final routePoints = entry.value;
                    final isDummyUser = userId.startsWith('dummy_');
                    
                    return Polyline(
                      points: routePoints,
                      strokeWidth: 3,
                      color: isDummyUser ? Colors.purple : Colors.green,
                    );
                  }).toList(),
                ),
              if (_routePoints.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _routePoints.last,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            right: 10,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search destination...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                  ),
                ),
                if (_showSearchResults)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          title: Text(result.name),
                          subtitle: Text(result.address),
                          onTap: () => _selectPlace(result),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            right: 10,
            child: Column(
              children: [
                FloatingActionButton.small(
                  onPressed: _isInConvoy ? _leaveConvoy : _showConvoyJoinDialog,
                  backgroundColor: _isInConvoy ? Colors.red : Colors.green,
                  child: Icon(
                    _isInConvoy ? Icons.exit_to_app : Icons.group,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                if (_isInConvoy)
                  FloatingActionButton.small(
                    onPressed: _isDummyUserActive ? _stopDummyUser : _startDummyUser,
                    backgroundColor: _isDummyUserActive ? Colors.orange : Colors.purple,
                    child: Icon(
                      _isDummyUserActive ? Icons.stop : Icons.directions_car,
                      color: Colors.white,
                    ),
                  ),
                if (_isInConvoy) const SizedBox(height: 8),
                FloatingActionButton.small(
                  onPressed: _centerOnLocation,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Colors.black87),
                ),
                if (_isDummyUserActive) const SizedBox(height: 8),
                if (_isDummyUserActive)
                  FloatingActionButton.small(
                    onPressed: _centerOnDummyUser,
                    backgroundColor: Colors.purple,
                    child: const Icon(Icons.directions_car, color: Colors.white),
                  ),
              ],
            ),
          ),
          if (_routeInfo != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Route to ${_selectedDestination?.name ?? 'Destination'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.directions_car, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text('${_routeInfo!.distanceText} • ${_routeInfo!.durationText}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_isInConvoy)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '🚗 Convoy: $_currentConvoyId',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_isDummyUserActive)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                                  child: const Text(
                    '🚗 Dummy User Active',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ),
            ),
        ],
      ),
    );
  }
}

// Convoy join dialog
class ConvoyJoinDialog extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onJoin;

  const ConvoyJoinDialog({
    super.key,
    required this.controller,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join Convoy'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Convoy ID',
          hintText: 'Enter convoy ID',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            onJoin();
            Navigator.of(context).pop();
          },
          child: const Text('Join'),
        ),
      ],
    );
  }
}

 