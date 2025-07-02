import 'package:flutter/material.dart';
import 'package:here_sdk/mapview.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/search.dart';
import 'package:here_sdk/routing.dart' as here_routing;
import 'package:here_sdk/src/sdk/gestures/tap_listener.dart';
import '../utils/constants.dart';

class CustomMap extends StatefulWidget {
  final Map<String, double> userLocation;
  const CustomMap({super.key, required this.userLocation});

  @override
  State<CustomMap> createState() => _CustomMapState();
}

class _CustomMapState extends State<CustomMap> {
  HereMapController? _hereMapController;
  final TextEditingController _searchController = TextEditingController();
  MapPolyline? _routePolyline;
  here_routing.Route? _currentRoute;
  MapMarker? _userMarker;
  MapMarker? _destinationMarker;
  final _searchEngine = SearchEngine();
  here_routing.RoutingEngine? _routingEngine;
  String? _routeInfo;
  bool _routingInProgress = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onMapCreated(HereMapController controller) {
    _hereMapController = controller;
    _routingEngine = here_routing.RoutingEngine();
    _centerMapOnUser();
    _addUserMarker();
  }

  void _centerMapOnUser() {
    if (_hereMapController != null) {
      _hereMapController!.camera.lookAtPoint(GeoCoordinates(
        widget.userLocation['lat']!,
        widget.userLocation['lng']!,
      ));
    }
  }

  void _addUserMarker() {
    if (_hereMapController == null) return;
    final coords = GeoCoordinates(widget.userLocation['lat']!, widget.userLocation['lng']!);
    final image = MapImage.withFilePathAndWidthAndHeight('assets/user_marker.png', 48, 48);
    _userMarker = MapMarker(coords, image);
    _hereMapController!.mapScene.addMapMarker(_userMarker!);
  }

  void _addDestinationMarker(GeoCoordinates coords) {
    if (_hereMapController == null) return;
    _removeDestinationMarker();
    final image = MapImage.withFilePathAndWidthAndHeight('assets/destination_marker.png', 48, 48);
    _destinationMarker = MapMarker(coords, image);
    _hereMapController!.mapScene.addMapMarker(_destinationMarker!);
  }

  void _removeDestinationMarker() {
    if (_destinationMarker != null && _hereMapController != null) {
      _hereMapController!.mapScene.removeMapMarker(_destinationMarker!);
      _destinationMarker = null;
    }
  }

  void _clearRoute() {
    if (_routePolyline != null && _hereMapController != null) {
      _hereMapController!.mapScene.removeMapPolyline(_routePolyline!);
      _routePolyline = null;
    }
    setState(() {
      _routeInfo = null;
    });
  }

  void _searchAndRoute() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final userCoords = GeoCoordinates(widget.userLocation['lat']!, widget.userLocation['lng']!);
    final textQuery = TextQuery.withArea(query, TextQueryArea.withCenter(userCoords));
    final searchOptions = SearchOptions();
    setState(() => _routingInProgress = true);
    _searchEngine.searchByText(
      textQuery,
      searchOptions,
      (SearchError? error, List<Place>? places) {
        setState(() => _routingInProgress = false);
        if (error != null || places == null || places.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Destination not found')));
          return;
        }
        final destination = places.first.geoCoordinates;
        if (destination == null) return;
        _addDestinationMarker(destination);
        _routeToDestination(destination);
      },
    );
  }

  void _routeToDestination(GeoCoordinates destination) async {
    if (_routingEngine == null) return;
    final start = here_routing.Waypoint(GeoCoordinates(widget.userLocation['lat']!, widget.userLocation['lng']!));
    final end = here_routing.Waypoint(destination);
    final waypoints = [start, end];
    setState(() => _routingInProgress = true);
    _routingEngine!.calculateCarRoute(
      waypoints,
      here_routing.CarOptions(),
      (here_routing.RoutingError? error, List<here_routing.Route>? routes) {
        setState(() => _routingInProgress = false);
        if (error != null || routes == null || routes.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route calculation failed')));
          _clearRoute();
          return;
        }
        final route = routes.first;
        _showRouteOnMap(route);
        _showRouteInfo(route);
      },
    );
  }

  void _showRouteOnMap(here_routing.Route route) {
    _clearRoute();
    // Get geometry from the first section of the route
    final section = route.sections.first;
    final geometry = section.geometry;
    final routeGeoCoords = geometry.vertices;
    final geoPolyline = GeoPolyline(routeGeoCoords);
    final width = MapMeasureDependentRenderSize.withSingleSize(RenderSizeUnit.pixels, 8);
    final solid = MapPolylineSolidRepresentation(width, Colors.blue, LineCap.round);
    _routePolyline = MapPolyline.withRepresentation(geoPolyline, solid);
    _hereMapController!.mapScene.addMapPolyline(_routePolyline!);
    // Optionally, zoom to route (not using GeoBox.boundingBox as it's not available)
    // You may want to implement your own bounding box logic here.
  }

  void _showRouteInfo(here_routing.Route route) {
    final lengthMeters = route.lengthInMeters;
    final km = (lengthMeters / 1000).toStringAsFixed(2);
    setState(() {
      _routeInfo = 'Distance: $km km';
    });
  }

  void _onMapTap(Point2D touchPoint) async {
    if (_hereMapController == null) return;
    final coords = _hereMapController!.viewToGeoCoordinates(touchPoint);
    if (coords == null) return;
    _addDestinationMarker(coords);
    _routeToDestination(coords);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HereMap(
          onMapCreated: (controller) {
            _onMapCreated(controller);
            controller.gestures.tapListener = TapListener((Point2D touchPoint) {
              _onMapTap(touchPoint);
            });
          },
        ),
        Positioned(
          top: 40,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search destination',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _searchAndRoute(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _searchAndRoute,
                child: _routingInProgress
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
              ),
            ],
          ),
        ),
        if (_routeInfo != null)
          Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(_routeInfo!, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
      ],
    );
  }
}

// Placeholder LatLng class for tap callback
typedef LatLng = Map<String, double>; // Replace with actual LatLng from HERE SDK 