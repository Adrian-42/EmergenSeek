import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emergenseek/services/socket_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:emergenseek/Pages/SettingsPage.dart';

class EmergencyMapPage extends StatefulWidget {
  const EmergencyMapPage({super.key});

  @override
  State<EmergencyMapPage> createState() => _EmergencyMapPageState();
}

class _EmergencyMapPageState extends State<EmergencyMapPage> {
  GoogleMapController? mapController;
  Position? currentPosition;
  Timer? _socketTimer;
  BitmapDescriptor? navigationIcon;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  bool isSafe = true;

  List<dynamic> _nearbyPlaces = [];
  int _currentIndex = 0;
  String _currentType = '';

  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    _loadCustomMarker();
    _initLocationTracking();
  }

  // --- ASSET LOADING ---
  Future<void> _loadCustomMarker() async {
    final data = await rootBundle.load('assets/navigation_arrow.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 100,
    );
    final fi = await codec.getNextFrame();
    final bytes = (await fi.image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    setState(() => navigationIcon = BitmapDescriptor.fromBytes(bytes));
  }

  // --- LOCATION & ROTATION LOGIC ---
  Future<void> _initLocationTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // Updates more frequently for rotation smoothness
      ),
    ).listen((Position pos) {
      if (mounted) {
        setState(() {
          currentPosition = pos;
          _updateUserMarker(pos);
        });
      }
    });
  }

  void _updateUserMarker(Position pos) {
    markers.removeWhere((m) => m.markerId.value == "me");
    markers.add(
      Marker(
        markerId: const MarkerId("me"),
        position: LatLng(pos.latitude, pos.longitude),
        icon: navigationIcon ?? BitmapDescriptor.defaultMarker,
        rotation: pos.heading, // CRITICAL: This rotates the PNG arrow
        anchor: const Offset(0.5, 0.5),
        flat: true, // Keeps the icon flat against the map while rotating
        zIndex: 5,
      ),
    );
  }

  void _recenterCamera() {
    if (currentPosition != null && mapController != null) {
      mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(
              currentPosition!.latitude,
              currentPosition!.longitude,
            ),
            zoom: 17,
            tilt: 45, // Slight tilt for a navigation feel
          ),
        ),
      );
    }
  }

  // --- ROUTING VIA BACKEND (CORS FIX) ---
  Future<void> _getRoadDirections(LatLng destination) async {
    if (currentPosition == null) return;

    final origin = "${currentPosition!.latitude},${currentPosition!.longitude}";
    final dest = "${destination.latitude},${destination.longitude}";

    // Using your Node.js backend to bypass CORS
    final url = "$baseUrl/get-directions?origin=$origin&destination=$dest";

    try {
      final response = await http.get(Uri.parse(url));
      final data = jsonDecode(response.body);

      if (data['status'] == 'OK') {
        final polylinePoints = PolylinePoints();
        List<PointLatLng> result = polylinePoints.decodePolyline(
          data['routes'][0]['overview_polyline']['points'],
        );

        setState(() {
          polylines.clear();
          polylines.add(
            Polyline(
              polylineId: const PolylineId("road_route"),
              points: result
                  .map((p) => LatLng(p.latitude, p.longitude))
                  .toList(),
              color: Colors.blueAccent,
              width: 6,
              jointType: JointType.round,
            ),
          );
        });
      }
    } catch (e) {
      debugPrint("Directions Error: $e");
    }
  }

  // --- SOS & FACILITY LOGIC ---
  Future<void> _toggleSOS(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? "unknown";
    setState(() => isSafe = value);

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
      _socketTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (currentPosition != null && !isSafe) {
          SocketService().sendLiveLocation(
            userId,
            currentPosition!.latitude,
            currentPosition!.longitude,
          );
        } else {
          timer.cancel();
        }
      });
    } else {
      _socketTimer?.cancel();
    }
  }

  void _showCurrentFacility() {
    if (_nearbyPlaces.isEmpty) return;
    final place = _nearbyPlaces[_currentIndex];
    final pos = LatLng(
      place['geometry']['location']['lat'],
      place['geometry']['location']['lng'],
    );

    setState(() {
      markers.removeWhere((m) => m.markerId.value == "selected_facility");
      markers.add(
        Marker(
          markerId: const MarkerId("selected_facility"),
          position: pos,
          infoWindow: InfoWindow(title: place['name']),
        ),
      );
    });

    _getRoadDirections(pos);
  }

  Future<void> _fetchNearby(String type) async {
    if (currentPosition == null) return;
    try {
      final res = await http.get(
        Uri.parse(
          "$baseUrl/places?lat=${currentPosition!.latitude}&lng=${currentPosition!.longitude}&type=$type",
        ),
      );
      if (res.statusCode == 200) {
        setState(() {
          _nearbyPlaces = jsonDecode(res.body)['results'];
          _currentIndex = 0;
          _currentType = type;
        });
        _showCurrentFacility();
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.settings, color: Colors.black87),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.59, 120.98),
              zoom: 15,
            ),
            onMapCreated: (c) => mapController = c,
            markers: markers,
            polylines: polylines,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
          ),

          // --- LEFT SIDE SOS BUTTON ---
          Positioned(
            left: 20,
            bottom: 250, // Adjusted to be above the bottom sheet
            child: FloatingActionButton(
              heroTag: "sos_btn",
              backgroundColor: isSafe ? Colors.red : Colors.grey,
              child: const Text(
                "SOS",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              onPressed: () => _toggleSOS(!isSafe),
            ),
          ),

          // --- RIGHT SIDE LOCATION FOCUS BUTTON ---
          Positioned(
            right: 20,
            bottom: 250,
            child: FloatingActionButton(
              heroTag: "loc_btn",
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Colors.blue),
              onPressed: _recenterCamera,
            ),
          ),

          // --- BOTTOM INFO PANEL ---
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isSafe ? "You are marked safe" : "Help is on the way!",
                    style: TextStyle(
                      color: isSafe ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildServiceBtn(
                        "Medical",
                        Icons.local_hospital,
                        Colors.red,
                        'hospital',
                      ),
                      _buildServiceBtn(
                        "Police",
                        Icons.local_police,
                        Colors.blue,
                        'police',
                      ),
                      _buildServiceBtn(
                        "Fire",
                        Icons.local_fire_department,
                        Colors.orange,
                        'fire_station',
                      ),
                    ],
                  ),
                  if (_nearbyPlaces.isNotEmpty) ...[
                    const Divider(),
                    ListTile(
                      title: Text(
                        _nearbyPlaces[_currentIndex]['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.call, color: Colors.green),
                        onPressed: () {},
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceBtn(
    String label,
    IconData icon,
    Color color,
    String type,
  ) {
    return Column(
      children: [
        IconButton(
          onPressed: () => _fetchNearby(type),
          icon: Icon(icon, color: color, size: 30),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
