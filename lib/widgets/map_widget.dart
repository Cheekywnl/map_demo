import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

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

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
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
                        color: Colors.blue.withOpacity(0.8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
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
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                if (_showSearchResults && _searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final place = _searchResults[index];
                        return ListTile(
                          title: Text(
                            place.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => _selectPlace(place),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  onPressed: _centerOnLocation,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Colors.black87),
                ),
              ],
            ),
          ),
          if (_routeInfo != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Route',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_routeInfo!.distanceText} • ${_routeInfo!.durationText}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoadingRoute)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
} 