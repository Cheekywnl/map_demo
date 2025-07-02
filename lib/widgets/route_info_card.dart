import 'package:flutter/material.dart';

class RouteInfoCard extends StatelessWidget {
  final String info;
  const RouteInfoCard({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    // TODO: Display route information
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(info),
      ),
    );
  }
} 