import 'package:flutter/material.dart';
import '../services/location_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Map<String, double>? _userLocation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  void _getLocation() async {
    final location = await LocationService().getCurrentLocation();
    setState(() {
      _userLocation = location;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _userLocation == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: CustomMap(userLocation: _userLocation!),
    );
  }
} 