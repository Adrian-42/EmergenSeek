import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:url_launcher/url_launcher.dart';
// import 'package:shared_preferences/shared_preferences.dart';

import 'SettingsPage.dart';
import 'package:emergenseek/services/socket_service.dart';

class EmergencyMapPage extends StatefulWidget {
  final bool isResponder;
  final String? activeEmergencyId;

  const EmergencyMapPage({
    super.key,
    this.isResponder = false,
    this.activeEmergencyId,
  });

  @override
  State<EmergencyMapPage> createState() => _EmergencyMapPageState();
}

class _EmergencyMapPageState extends State<EmergencyMapPage>
    with TickerProviderStateMixin {
  GoogleMapController? mapController;
  Position? currentPosition;
  StreamSubscription<Position>? positionStream;
  StreamSubscription<LatLng>? victimSocketStream;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  bool isMapMoving = false;
  BitmapDescriptor? userIcon;
  bool isAppReady = false;
  bool isDrawing = false;

  // Real-time Data
  LatLng? liveVictimLocation;
  String? routeDuration;

  late AnimationController sosPulseController;
  late Animation<double> sosPulseAnimation;

  final String baseUrl = "https://emergenseek.onrender.com";

  final List<Map<String, dynamic>> emergencyServices = [
    {
      "title": "Medical",
      "icon": Icons.local_hospital,
      "type": "hospital",
      "color": Colors.red,
    },
    {
      "title": "Police",
      "icon": Icons.local_police,
      "type": "police",
      "color": Colors.blue,
    },
    {
      "title": "Fire Dept",
      "icon": Icons.local_fire_department,
      "type": "fire_station",
      "color": Colors.orange,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCustomMarker();
    _initApp();
    _setupSocketListeners();

    sosPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    sosPulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: sosPulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    positionStream?.cancel();
    victimSocketStream?.cancel();
    sosPulseController.dispose();
    mapController?.dispose();
    super.dispose();
  }

  // --- SOCKET LOGIC ---
  void _setupSocketListeners() {
    // Listen to the stream from SocketService
    victimSocketStream = SocketService().locationStream.listen((
      LatLng newLocation,
    ) {
      if (mounted) {
        setState(() {
          liveVictimLocation = newLocation;
          _updateVictimMarker(newLocation);

          // If responder is active, move camera to keep victim in view
          if (widget.isResponder && mapController != null) {
            mapController!.animateCamera(CameraUpdate.newLatLng(newLocation));
          }
        });
      }
    });
  }

  // --- CORE INITIALIZATION ---
  Future<void> _initApp() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Position pos = await Geolocator.getCurrentPosition();
    _handleLocationUpdate(pos);

    // Continuous Tracking
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) => _handleLocationUpdate(pos));

    // If a responder enters this page for a specific mission, join the room
    if (widget.isResponder && widget.activeEmergencyId != null) {
      SocketService().startEmergencyStreaming(widget.activeEmergencyId!);
    }

    if (mounted) setState(() => isAppReady = true);
  }

  void _handleLocationUpdate(Position pos) {
    if (!mounted) return;
    setState(() {
      currentPosition = pos;
      markers.removeWhere((m) => m.markerId.value == "user_location");
      markers.add(
        Marker(
          markerId: const MarkerId("user_location"),
          position: LatLng(pos.latitude, pos.longitude),
          icon:
              userIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          rotation: pos.heading,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          zIndex: 2,
        ),
      );
    });

    // CRITICAL: If victim is in SOS mode, send their live GPS to the socket server
    if (!widget.isResponder && widget.activeEmergencyId != null) {
      SocketService().sendLiveLocation(
        widget.activeEmergencyId!,
        pos.latitude,
        pos.longitude,
      );
    }
  }

  void _updateVictimMarker(LatLng pos) {
    setState(() {
      markers.removeWhere((m) => m.markerId.value == "victim_location");
      markers.add(
        Marker(
          markerId: const MarkerId("victim_location"),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "VICTIM LIVE LOCATION"),
          zIndex: 3,
        ),
      );
    });
  }

  // --- ASSET LOADING ---
  Future<void> _loadCustomMarker() async {
    try {
      final Uint8List markerIcon = await _getBytesFromAsset(
        'assets/navigation_arrow.png',
        48,
      );
      setState(() => userIcon = BitmapDescriptor.fromBytes(markerIcon));
    } catch (e) {
      debugPrint("Marker error: $e");
    }
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.5995, 120.9842),
              zoom: 14,
            ),
            markers: markers,
            polylines: polylines,
            onMapCreated: (c) => mapController = c,
            myLocationButtonEnabled: false,
            padding: EdgeInsets.only(bottom: widget.isResponder ? 150 : 120),
          ),

          // Settings
          Positioned(
            top: 50,
            right: 20,
            child: FloatingActionButton.small(
              heroTag: "settings",
              backgroundColor: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              ),
              child: const Icon(Icons.settings, color: Colors.black87),
            ),
          ),

          // SOS Pulse Button (Citizen/Victim Only)
          if (!widget.isResponder)
            Positioned(
              bottom: 130,
              right: 20,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ScaleTransition(
                    scale: sosPulseAnimation,
                    child: Container(
                      width: 75,
                      height: 75,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(0.3),
                      ),
                    ),
                  ),
                  FloatingActionButton(
                    heroTag: "sos",
                    backgroundColor: Colors.red,
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      // Trigger SOS start logic here
                    },
                    child: const Text(
                      "SOS",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Bottom Dynamic Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: widget.isResponder
                ? _buildResponderPanel()
                : _buildVictimPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildVictimPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 15, 10, 35),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: emergencyServices.map((s) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(s["icon"], color: s["color"]),
                onPressed: () {},
              ),
              Text(s["title"], style: const TextStyle(fontSize: 11)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildResponderPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "MISSION IN PROGRESS",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.red,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: const Text("Tracking Victim"),
            subtitle: Text(
              liveVictimLocation != null
                  ? "Signal: Strong"
                  : "Waiting for GPS...",
            ),
            trailing: IconButton(
              icon: const Icon(Icons.message, color: Colors.blue),
              onPressed: () {}, // Navigate to ChatPage
            ),
          ),
          ElevatedButton.icon(
            onPressed: _launchNavigation,
            icon: const Icon(Icons.navigation),
            label: const Text("OPEN IN GOOGLE MAPS"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }

  void _launchNavigation() async {
    if (liveVictimLocation == null) return;
    final url =
        'google.navigation:q=${liveVictimLocation!.latitude},${liveVictimLocation!.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}
