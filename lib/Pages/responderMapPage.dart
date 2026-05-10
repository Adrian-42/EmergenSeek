import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:emergenseek/services/socket_service.dart';

class ResponderMapPage extends StatefulWidget {
  final String activeEmergencyId;
  const ResponderMapPage({super.key, required this.activeEmergencyId});

  @override
  State<ResponderMapPage> createState() => _ResponderMapPageState();
}

class _ResponderMapPageState extends State<ResponderMapPage> {
  GoogleMapController? _controller;
  Set<Marker> _markers = {};
  StreamSubscription? _locationSubscription;
  LatLng? _lastKnownVictimPos;

  @override
  void initState() {
    super.initState();
    _setupTracking();
  }

  void _setupTracking() {
    // 1. Join the victim's room
    SocketService().startEmergencyStreaming(widget.activeEmergencyId);

    // 2. Listen for live updates
    _locationSubscription = SocketService().locationStream.listen((LatLng pos) {
      if (!mounted) return;
      setState(() {
        _lastKnownVictimPos = pos;
        _markers.clear();
        _markers.add(
          Marker(
            markerId: const MarkerId("victim"),
            position: pos,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: const InfoWindow(title: "VICTIM LOCATION"),
          ),
        );
      });
      // 3. Move camera to follow victim
      _controller?.animateCamera(CameraUpdate.newLatLng(pos));
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel(); // Important to prevent memory leaks
    super.dispose();
  }

  void _openInGoogleMaps() async {
    if (_lastKnownVictimPos == null) return;
    final url =
        'https://www.google.com/maps/search/?api=1&query=${_lastKnownVictimPos!.latitude},${_lastKnownVictimPos!.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tracking Victim"),
        backgroundColor: Colors.redAccent,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.59, 120.98),
              zoom: 17,
            ),
            onMapCreated: (c) => _controller = c,
            markers: _markers,
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: _openInGoogleMaps,
              icon: const Icon(Icons.navigation),
              label: const Text("NAVIGATE TO VICTIM"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
