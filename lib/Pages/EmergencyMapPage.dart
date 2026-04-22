import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'SettingsPage.dart';

class EmergencyMapPage extends StatefulWidget {
  const EmergencyMapPage({super.key});

  @override
  State<EmergencyMapPage> createState() => _EmergencyMapPageState();
}

class _EmergencyMapPageState extends State<EmergencyMapPage>
    with SingleTickerProviderStateMixin {
  GoogleMapController? mapController;
  Position? currentPosition;
  StreamSubscription<Position>? positionStream;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  Set<Circle> circles = {};

  Map<String, List<dynamic>> allNearbyData = {};
  Map<String, int> servicePointer = {};
  String? activeServiceType;

  late AnimationController sosController;
  late Animation<double> sosAnimation;

  bool isDrawing = false;
  bool isFollowingUser = true;
  bool isAppReady = false;
  bool isSendingSOS = false;

  String? routeDistance;
  String? routeDuration;
  String? activePlaceName;
  double? activePlaceRating;
  String? activePlacePhone;
  bool? activePlaceOpen;

  LatLng? activeDestination;
  List<LatLng> currentPath = [];

  // Backend URL
  final String baseUrl = "https://emergenseek.onrender.com";

  final List<Map<String, dynamic>> emergencyServices = [
    {"title": "Medical", "icon": Icons.local_hospital, "type": "hospital"},
    {"title": "Police", "icon": Icons.local_police, "type": "police"},
    {
      "title": "Fire Dept",
      "icon": Icons.local_fire_department,
      "type": "fire_station",
    },
  ];

  @override
  void initState() {
    super.initState();
    _initApp();
    sosController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    sosAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(sosController);
  }

  Future<void> _initApp() async {
    await _loadOfflineData();
    await _startTracking();
  }

  @override
  void dispose() {
    positionStream?.cancel();
    sosController.dispose();
    mapController?.dispose();
    super.dispose();
  }

  // --- SOS LOGIC ---
  Future<void> _triggerSOS() async {
    if (currentPosition == null || isSendingSOS) return;

    setState(() => isSendingSOS = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🚨 Alerting Emergency Contacts..."),
        backgroundColor: Colors.red,
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');

      // Create a direct Google Maps link for the rescuers
      final String googleMapsUrl =
          "https://www.google.com/maps/search/?api=1&query=${currentPosition!.latitude},${currentPosition!.longitude}";

      final response = await http
          .post(
            Uri.parse("$baseUrl/trigger-sos"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"userId": userId, "locationLink": googleMapsUrl}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ SOS Emails Sent!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception("Server Error");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ SOS Failed. Check connection.")),
        );
      }
    } finally {
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) setState(() => isSendingSOS = false);
      });
    }
  }

  // --- TRACKING & NAVIGATION ---
  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied) return;
    }

    Position firstPos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _handleNewPosition(firstPos);

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) => _handleNewPosition(pos));
  }

  void _handleNewPosition(Position pos) {
    if (!mounted) return;

    // Reroute if user deviates more than 50 meters from path
    if (activeDestination != null && currentPath.isNotEmpty && !isDrawing) {
      double distanceToPathStart = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        currentPath.first.latitude,
        currentPath.first.longitude,
      );

      if (distanceToPathStart > 50) {
        _drawRoute(activeDestination!, {
          "name": activePlaceName,
          "rating": activePlaceRating,
          "formatted_phone_number": activePlacePhone,
        });
      }
    }

    setState(() {
      currentPosition = pos;
      circles = {
        Circle(
          circleId: const CircleId("user_loc"),
          center: LatLng(pos.latitude, pos.longitude),
          radius: 20,
          fillColor: Colors.blue.withOpacity(0.2),
          strokeColor: Colors.blue,
          strokeWidth: 2,
        ),
      };
    });

    if (isFollowingUser && !isDrawing) {
      mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }

    if (!isAppReady) {
      for (var s in emergencyServices) {
        _fetchPlaces(s["type"]);
      }
    }
  }

  Future<void> _fetchPlaces(String type) async {
    if (currentPosition == null) return;
    final url = Uri.parse(
      "$baseUrl/places?lat=${currentPosition!.latitude}&lng=${currentPosition!.longitude}&type=$type",
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List results = data['results'] ?? [];

        if (mounted) {
          setState(() {
            allNearbyData[type] = results;
            if (!servicePointer.containsKey(type)) servicePointer[type] = 0;
            _refreshMarkers();
            isAppReady = true;
          });
          _saveOfflineData(type, results);
        }
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
    }
  }

  Future<void> _drawRoute(LatLng dest, dynamic placeData) async {
    if (currentPosition == null) return;

    setState(() {
      isDrawing = true;
      activeDestination = dest;
      activePlaceName = placeData["name"];
      activePlaceRating = (placeData["rating"] ?? 0).toDouble();
      activePlacePhone =
          placeData["formatted_phone_number"] ?? "No phone available";
    });

    final url = Uri.parse(
      "$baseUrl/directions?origin=${currentPosition!.latitude},${currentPosition!.longitude}&destination=${dest.latitude},${dest.longitude}",
    );

    try {
      final response = await http.get(url);
      final data = jsonDecode(response.body);

      if (data["routes"] == null || data["routes"].isEmpty) return;

      final leg = data["routes"][0]["legs"][0];
      PolylinePoints pp = PolylinePoints();
      List<PointLatLng> res = pp.decodePolyline(
        data["routes"][0]["overview_polyline"]["points"],
      );

      setState(() {
        routeDistance = leg["distance"]["text"];
        routeDuration = leg["duration"]["text"];
        currentPath = res.map((p) => LatLng(p.latitude, p.longitude)).toList();

        polylines = {
          Polyline(
            polylineId: const PolylineId("route_line"),
            points: currentPath,
            color: Colors.redAccent,
            width: 7,
            jointType: JointType.round,
          ),
        };
        isDrawing = false;
        isFollowingUser = false;
      });
      _zoomToFit(currentPath);
    } catch (e) {
      setState(() => isDrawing = false);
    }
  }

  void _showNextNearest() {
    if (activeServiceType == null) return;
    List? data = allNearbyData[activeServiceType!];
    if (data == null || data.isEmpty) return;

    int nextIdx = ((servicePointer[activeServiceType!] ?? 0) + 1) % data.length;
    setState(() => servicePointer[activeServiceType!] = nextIdx);

    var place = data[nextIdx];
    _drawRoute(
      LatLng(
        place["geometry"]["location"]["lat"],
        place["geometry"]["location"]["lng"],
      ),
      place,
    );
  }

  void _refreshMarkers() {
    Set<Marker> newMarkers = {};
    allNearbyData.forEach((type, results) {
      for (var p in results) {
        double hue = type == "hospital"
            ? BitmapDescriptor.hueRed
            : type == "police"
            ? BitmapDescriptor.hueAzure
            : BitmapDescriptor.hueOrange;

        newMarkers.add(
          Marker(
            markerId: MarkerId(p["place_id"]),
            position: LatLng(
              p["geometry"]["location"]["lat"],
              p["geometry"]["location"]["lng"],
            ),
            infoWindow: InfoWindow(title: p["name"]),
            icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          ),
        );
      }
    });
    setState(() => markers = newMarkers);
  }

  void _zoomToFit(List<LatLng> p) {
    if (p.isEmpty || mapController == null) return;
    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        p.map((e) => e.latitude).reduce((a, b) => a < b ? a : b),
        p.map((e) => e.longitude).reduce((a, b) => a < b ? a : b),
      ),
      northeast: LatLng(
        p.map((e) => e.latitude).reduce((a, b) => a > b ? a : b),
        p.map((e) => e.longitude).reduce((a, b) => a > b ? a : b),
      ),
    );
    mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  Future<void> _makeCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final Uri url = Uri.parse("tel:${phoneNumber.replaceAll(' ', '')}");
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _loadOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    for (var service in emergencyServices) {
      String type = service["type"];
      String? cached = prefs.getString('offline_data_$type');
      if (cached != null) {
        setState(() {
          allNearbyData[type] = jsonDecode(cached);
          _refreshMarkers();
        });
      }
    }
  }

  Future<void> _saveOfflineData(String type, List data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_data_$type', jsonEncode(data));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: isAppReady
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 15, top: 10),
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.settings, color: Colors.black87),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsPage(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.5995, 120.9842),
              zoom: 14,
            ),
            markers: markers,
            polylines: polylines,
            circles: circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            onMapCreated: (c) => mapController = c,
          ),

          if (!isAppReady)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.red),
                    SizedBox(height: 20),
                    Text(
                      "Finding Emergency Services...",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (routeDistance != null)
            Positioned(
              top: 100,
              left: 15,
              right: 15,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          activePlaceName ?? "Unknown",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text("ETA: $routeDuration ($routeDistance)"),
                        trailing: IconButton(
                          icon: const CircleAvatar(
                            backgroundColor: Colors.grey,
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          onPressed: () => setState(() {
                            routeDistance = null;
                            polylines.clear();
                            activeDestination = null;
                          }),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _makeCall(activePlacePhone),
                              icon: const Icon(Icons.phone),
                              label: const Text("CALL"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isDrawing ? null : _showNextNearest,
                              icon: const Icon(Icons.skip_next),
                              label: const Text("NEXT"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 130,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FloatingActionButton(
                  heroTag: "recenter",
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: () => setState(() => isFollowingUser = true),
                  child: const Icon(Icons.my_location, color: Colors.blue),
                ),
                ScaleTransition(
                  scale: sosAnimation,
                  child: FloatingActionButton.extended(
                    heroTag: "sos",
                    backgroundColor: isSendingSOS ? Colors.grey : Colors.red,
                    onPressed: isSendingSOS ? null : _triggerSOS,
                    label: Text(
                      isSendingSOS ? "SENDING..." : "SOS",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: emergencyServices.map((s) {
                  return InkWell(
                    onTap: () {
                      activeServiceType = s["type"];
                      if (allNearbyData[s["type"]]?.isNotEmpty ?? false) {
                        var place = allNearbyData[s["type"]]![0];
                        _drawRoute(
                          LatLng(
                            place["geometry"]["location"]["lat"],
                            place["geometry"]["location"]["lng"],
                          ),
                          place,
                        );
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.red.withOpacity(0.1),
                          child: Icon(s["icon"], color: Colors.red),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s["title"],
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
