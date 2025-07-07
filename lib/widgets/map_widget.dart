import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../services/convoy_service.dart';
import '../services/dummy_user_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import '../services/location_service.dart';
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? mapboxMap;
  PointAnnotationManager? pointAnnotationManager;
  PolylineAnnotationManager? polylineAnnotationManager;
  static const String _accessToken = 'pk.eyJ1IjoiY2hlZWt5dyIsImEiOiJjbWM3bDMzaXkwcWprMm9zM21ydmNiZHZrIn0.Ll9ev_0u6Yc9FMd-MkbZgg';

  final ConvoyService _convoyService = ConvoyService();
  DummyUserService? _dummyUserService;

  // Search bar state
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  Timer? _searchDebounce;
  Map<String, dynamic>? _selectedDestination;

  // Convoy state
  bool _isInConvoy = false;
  String _currentConvoyId = '';
  bool _showConvoyDialog = false;
  final TextEditingController _convoyIdController = TextEditingController();

  // Dummy user state
  bool _isDummyUserActive = false;

  // Route info
  String? _routeDistance;
  String? _routeDuration;

  // Add this field to the state:
  List<PolylineAnnotation> _searchRoutePolylines = [];

  // Follow mode state
  bool _followMe = true;

  StreamSubscription<Position>? _deviceLocationSub;

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(_accessToken);
    _convoyService.locationUpdates.listen(_onConvoyLocationUpdate);
    _startDeviceLocationFollow();
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;
    pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    polylineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _showAllConvoyMembers();
    mapboxMap.location.updateSettings(LocationComponentSettings(
      enabled: true,
      pulsingEnabled: true,
    ));
  }

  Future<Uint8List> _loadAssetImage(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
  }

  void _onConvoyLocationUpdate(ConvoyLocation location) async {
    if (pointAnnotationManager == null || polylineAnnotationManager == null) return;
    await pointAnnotationManager!.deleteAll();
    for (final member in _convoyService.memberLocations.values) {
      Uint8List? customImage;
      if (member.userId.startsWith('dummy_')) {
        customImage = await _loadAssetImage('assets/user_marker.png');
      }
      await pointAnnotationManager!.create(PointAnnotationOptions(
        geometry: Point(coordinates: Position(member.coordinates[0], member.coordinates[1])),
        image: customImage,
        iconSize: member.userId.startsWith('dummy_') ? 0.5 : 1.5,
      ));
      if (member.routePoints != null && member.routePoints!.isNotEmpty) {
        await polylineAnnotationManager!.create(PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: member.routePoints!.map((p) => Position(p[0], p[1])).toList(),
          ),
          lineColor: member.userId.startsWith('dummy_') ? 0xFF800080 : 0xFF008000,
          lineWidth: 4.0,
        ));
      }
      // Do NOT move camera here; follow mode is handled by device location
    }
  }

  void _showAllConvoyMembers() {
    for (final member in _convoyService.memberLocations.values) {
      _onConvoyLocationUpdate(member);
    }
  }

  // --- Search logic ---
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlaces(query);
    });
  }

  void _onSearchSubmitted(String query) {
    if (_searchResults.isNotEmpty) {
      _selectPlace(_searchResults[0]);
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
    });
    try {
      final String url =
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json'
          '?access_token=$_accessToken&limit=5&types=poi,address';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> features = data['features'];
        setState(() {
          _searchResults = features.cast<Map<String, dynamic>>();
          _showSearchResults = true;
        });
      }
    } catch (e) {
      // ignore
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _selectPlace(Map<String, dynamic> place) async {
    setState(() {
      _showSearchResults = false;
      _searchController.text = place['place_name'] ?? '';
      _selectedDestination = place;
    });
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    _moveCameraTo(place['center'][0], place['center'][1], 16.0);
    await _getRoute(place['center'][0], place['center'][1]);
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchResults = [];
      _showSearchResults = false;
    });
    FocusScope.of(context).unfocus();
  }

  // --- Route logic ---
  Future<void> _getRoute(double lon, double lat) async {
    setState(() {
      _routeDistance = null;
      _routeDuration = null;
    });
    try {
      final location = await LocationService().getCurrentLocation();
      final double startLon = location['lng'] ?? -0.1263;
      final double startLat = location['lat'] ?? 51.5344;
      final String url =
          'https://api.mapbox.com/directions/v5/mapbox/driving/'
          '$startLon,$startLat;$lon,$lat'
          '?geometries=geojson&overview=full&steps=true&access_token=$_accessToken';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final double distance = route['distance'] / 1000;
          final int duration = route['duration'].round();
          // Draw each step as a separate polyline
          List<List<double>> allRoutePoints = [];
          if (polylineAnnotationManager != null) {
            // Delete previous polylines
            await polylineAnnotationManager!.deleteAll();
            _searchRoutePolylines.clear();
            final steps = route['legs'][0]['steps'] as List<dynamic>;
            for (final step in steps) {
              final List<dynamic> coords = step['geometry']['coordinates'];
              final List<Position> positions = coords.map<Position>((c) => Position(c[0].toDouble(), c[1].toDouble())).toList();
              final polyline = await polylineAnnotationManager!.create(PolylineAnnotationOptions(
                geometry: LineString(coordinates: positions),
                lineColor: 0xFF0000FF,
                lineWidth: 4.0,
                lineOpacity: 0.9,
              ));
              _searchRoutePolylines.add(polyline);
              // Add to allRoutePoints for server
              allRoutePoints.addAll(coords.map<List<double>>((c) => [c[0].toDouble(), c[1].toDouble()]));
            }
          }
          // Send route to server if in convoy
          if (_isInConvoy && allRoutePoints.isNotEmpty) {
            final routeMessage = {
              'type': 'route_update',
              'routePoints': allRoutePoints,
            };
            _convoyService.sendLocationUpdate(routeMessage);
          }
          setState(() {
            _routeDistance = distance >= 1 ? '${distance.toStringAsFixed(1)} km' : '${(distance * 1000).round()} m';
            _routeDuration = duration < 60 ? '$duration sec' : '${(duration / 60).round()} min';
          });
        }
      }
    } catch (e) {
      print('Route error: $e');
    }
  }

  // --- Convoy logic ---
  void _showConvoyJoinDialog() {
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
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
    if (convoyId.isEmpty) return;
    _convoyService.connect('user_${DateTime.now().millisecondsSinceEpoch}', convoyId: convoyId).then((success) {
      if (success) {
        setState(() {
          _isInConvoy = true;
          _currentConvoyId = convoyId;
          _followMe = true; // Enable follow by default
        });
        _convoyService.startLocationTracking();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined convoy $convoyId!')),
        );
      }
    });
  }

  void _leaveConvoy() {
    _convoyService.leaveConvoy();
    _convoyService.stopLocationTracking();
    setState(() {
      _isInConvoy = false;
      _currentConvoyId = '';
    });
  }

  void _startDummyUser() async {
    if (_currentConvoyId.isEmpty) return;
    final dummyUserId = 'dummy_${DateTime.now().millisecondsSinceEpoch}';
    final dummyConvoyService = ConvoyService();
    final success = await dummyConvoyService.connect(dummyUserId, convoyId: _currentConvoyId);
    if (success) {
      _dummyUserService = DummyUserService(dummyConvoyService, dummyUserId, _currentConvoyId);
      _dummyUserService!.startDummyUser();
      setState(() {
        _isDummyUserActive = true;
      });
    }
  }

  void _stopDummyUser() {
    _dummyUserService?.stopDummyUser();
    _dummyUserService?.dispose();
    _dummyUserService = null;
    setState(() {
      _isDummyUserActive = false;
    });
  }

  void _moveCameraTo(double lon, double lat, double zoom) {
    mapboxMap?.flyTo(
      CameraOptions(center: Point(coordinates: Position(lon, lat)), zoom: zoom),
      MapAnimationOptions(duration: 1000),
    );
  }

  // Add a method to clear the route
  void _clearRoute() async {
    if (polylineAnnotationManager != null) {
      await polylineAnnotationManager!.deleteAll();
      _searchRoutePolylines.clear();
    }
    setState(() {
      _routeDistance = null;
      _routeDuration = null;
      _selectedDestination = null;
    });
  }

  void _startDeviceLocationFollow() {
    _deviceLocationSub?.cancel();
    _deviceLocationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2),
    ).listen((position) {
      if (_followMe) {
        _moveCameraTo(position.longitude, position.latitude, mapboxMap != null ? mapboxMap!.getCameraState().then((c) => c.zoom).catchError((_) => 15.0) : 15.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_showSearchResults) {
          setState(() {
            _showSearchResults = false;
          });
          FocusScope.of(context).unfocus();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            MapWidget(
              key: const ValueKey("mapWidget"),
              onMapCreated: _onMapCreated,
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(-0.1263, 51.5344)),
                zoom: 13.0,
              ),
              styleUri: MapboxStyles.LIGHT,
            ),
            // Search bar overlay
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
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            onSubmitted: _onSearchSubmitted,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Search destination...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: _clearSearch,
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                            ),
                          ),
                        ),
                      ],
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
                            title: Text(result['place_name'] ?? ''),
                            subtitle: Text(result['address'] ?? ''),
                            onTap: () => _selectPlace(result),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            // Convoy and dummy user controls
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
                ],
              ),
            ),
            // Route info card
            if (_routeDistance != null && _routeDuration != null)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 20,
                right: 20,
                child: Column(
                  children: [
                    Container(
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
                            'Route to ${_selectedDestination?['place_name'] ?? 'Destination'}',
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
                              Text('$_routeDistance • $_routeDuration'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _clearRoute,
                      icon: Icon(Icons.cancel),
                      label: Text('Cancel Route'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            // Follow mode toggle button
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 90,
              right: 20,
              child: FloatingActionButton.small(
                onPressed: () {
                  setState(() {
                    _followMe = !_followMe;
                  });
                },
                backgroundColor: _followMe ? Colors.blue : Colors.grey,
                child: Icon(_followMe ? Icons.my_location : Icons.location_disabled, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _deviceLocationSub?.cancel();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _convoyService.dispose();
    _dummyUserService?.dispose();
    _convoyIdController.dispose();
    super.dispose();
  }
}

 