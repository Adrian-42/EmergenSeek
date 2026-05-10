import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'SettingsPage.dart';
import 'package:emergenseek/services/socket_service.dart';

class EmergencyMapPage extends StatefulWidget {
  final bool isResponder;
  final String? activeEmergencyId; // This is the Victim's User ID

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
  BitmapDescriptor? userIcon;
  bool isAppReady = false;

  // --- Dynamic User Data ---
  String victimName = "Loading...";
  bool isSafe = true;
  LatLng? liveVictimLocation;

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

    // If we are a responder, fetch the victim's actual profile info
    if (widget.isResponder && widget.activeEmergencyId != null) {
      _fetchVictimProfile();
    }

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
    if (mapController != null) mapController = null;
    super.dispose();
  }

  // --- NEW: Fetch Victim Data for Responder Dashboard ---
  Future<void> _fetchVictimProfile() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/user/${widget.activeEmergencyId}"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            victimName = data['name'] ?? "Unknown Victim";
            isSafe = data['isSafe'] ?? true;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching victim profile: $e");
    }
  }

  // --- NEW: Toggle Safety Status (For Victim side) ---
  Future<void> _toggleSafetyStatus(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    setState(() => isSafe = value);

    try {
      await http.put(
        Uri.parse("$baseUrl/user/status"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "isSafe": isSafe,
          "lastLocation": {
            "lat": currentPosition?.latitude,
            "lng": currentPosition?.longitude,
          },
        }),
      );

      if (!isSafe) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Emergency Broadcasted to Responders!"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error updating status: $e");
    }
  }

  void _setupSocketListeners() {
    victimSocketStream = SocketService().locationStream.listen((
      LatLng newLocation,
    ) {
      if (!mounted) return;
      setState(() {
        liveVictimLocation = newLocation;
        _updateVictimMarker(newLocation);
        if (widget.isResponder && mapController != null) {
          mapController!.animateCamera(CameraUpdate.newLatLng(newLocation));
        }
      });
    });
  }

  Future<void> _initApp() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    try {
      Position pos = await Geolocator.getCurrentPosition();
      _handleLocationUpdate(pos);
    } catch (e) {
      debugPrint("Location error: $e");
    }

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) => _handleLocationUpdate(pos));

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

    if (!widget.isResponder && widget.activeEmergencyId != null) {
      SocketService().sendLiveLocation(
        widget.activeEmergencyId!,
        pos.latitude,
        pos.longitude,
      );
    }
  }

  void _updateVictimMarker(LatLng pos) {
    if (!mounted) return;
    setState(() {
      markers.removeWhere((m) => m.markerId.value == "victim_location");
      markers.add(
        Marker(
          markerId: const MarkerId("victim_location"),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: widget.isResponder ? "VICTIM: $victimName" : "MY LOCATION",
          ),
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
      if (mounted)
        setState(() => userIcon = BitmapDescriptor.fromBytes(markerIcon));
    } catch (e) {
      debugPrint("Asset loading error: $e");
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

  void _centerOnUser() {
    if (currentPosition != null && mapController != null) {
      mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(currentPosition!.latitude, currentPosition!.longitude),
          16,
        ),
      );
    }
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
            onMapCreated: (c) {
              if (mounted) mapController = c;
            },
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            padding: EdgeInsets.only(bottom: widget.isResponder ? 200 : 180),
          ),

          // Top Header Area
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FloatingActionButton.small(
                  heroTag: "center",
                  backgroundColor: Colors.white,
                  onPressed: _centerOnUser,
                  child: const Icon(Icons.my_location, color: Colors.blue),
                ),
                FloatingActionButton.small(
                  heroTag: "settings",
                  backgroundColor: Colors.white,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  ),
                  child: const Icon(Icons.settings, color: Colors.black87),
                ),
              ],
            ),
          ),

          // SOS Pulse Button (Citizen/Victim Only)
          if (!widget.isResponder)
            Positioned(
              bottom: 180,
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
                    onPressed: () => _toggleSafetyStatus(false),
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
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 35),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isSafe ? "STATUS: SAFE" : "STATUS: NEED HELP",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSafe ? Colors.green : Colors.red,
                ),
              ),
              Switch(
                value: isSafe,
                activeColor: Colors.green,
                onChanged: (val) => _toggleSafetyStatus(val),
              ),
            ],
          ),
          const Divider(),
          Row(
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
        ],
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "ACTIVE MISSION",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.red,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text("Victim: $victimName"),
            subtitle: Text(
              liveVictimLocation != null
                  ? "Signal: Live Tracking"
                  : "Waiting for GPS...",
            ),
            trailing: IconButton(
              icon: const Icon(Icons.message, color: Colors.blue),
              onPressed: () {},
            ),
          ),
          ElevatedButton.icon(
            onPressed: _launchNavigation,
            icon: const Icon(Icons.navigation),
            label: const Text("LAUNCH GOOGLE MAPS"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _launchNavigation() async {
    if (liveVictimLocation == null) return;
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${liveVictimLocation!.latitude},${liveVictimLocation!.longitude}&travelmode=driving';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
