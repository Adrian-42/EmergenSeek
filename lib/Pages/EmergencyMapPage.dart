import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String? routeDistance;
  String? routeDuration;
  String? activePlaceName;
  double? activePlaceRating;

  // Render Backend URL
  String get baseUrl => "https://emergenseek.onrender.com";

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
    _loadOfflineData();
    _startTracking();

    sosController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    sosAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(sosController);
  }

  @override
  void dispose() {
    positionStream?.cancel();
    sosController.dispose();
    mapController?.dispose();
    super.dispose();
  }

  // --- DATA PERSISTENCE ---
  Future<void> _loadOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    for (var service in emergencyServices) {
      String type = service["type"];
      String? cached = prefs.getString('offline_data_$type');
      if (cached != null) {
        final List results = jsonDecode(cached);
        if (mounted) {
          setState(() {
            allNearbyData[type] = results;
            servicePointer[type] = 0;
            _refreshMarkers();
          });
        }
      }
    }
  }

  Future<void> _saveOfflineData(String type, List data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_data_$type', jsonEncode(data));
  }

  void _refreshMarkers() {
    Set<Marker> newMarkers = {};
    allNearbyData.forEach((type, results) {
      for (var p in results) {
        newMarkers.add(
          Marker(
            markerId: MarkerId(p["place_id"]),
            position: LatLng(
              p["geometry"]["location"]["lat"],
              p["geometry"]["location"]["lng"],
            ),
            infoWindow: InfoWindow(
              title: p["name"],
              snippet: "Rating: ${p["rating"] ?? 'N/A'}",
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              type == "hospital"
                  ? BitmapDescriptor.hueRed
                  : type == "police"
                  ? BitmapDescriptor.hueAzure
                  : BitmapDescriptor.hueOrange,
            ),
          ),
        );
      }
    });
    setState(() {
      markers = newMarkers;
    });
  }

  // --- LOCATION TRACKING ---
  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied) return;
    }

    positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
          ),
        ).listen((pos) {
          if (!mounted) return;
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

          for (var s in emergencyServices) {
            _fetchPlaces(s["type"]);
          }
        });
  }

  Future<void> _fetchPlaces(String type) async {
    if (currentPosition == null) return;

    final String lat = currentPosition!.latitude.toStringAsFixed(6);
    final String lng = currentPosition!.longitude.toStringAsFixed(6);
    final url = Uri.parse("$baseUrl/places?lat=$lat&lng=$lng&type=$type");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List results = data['results'] ?? [];

        if (mounted) {
          setState(() {
            allNearbyData[type] = results;
            if (!servicePointer.containsKey(type)) servicePointer[type] = 0;
            _refreshMarkers();
          });
          _saveOfflineData(type, results);
        }
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
    }
  }

  void _showNextNearest() {
    if (activeServiceType == null || allNearbyData[activeServiceType!] == null)
      return;

    int total = allNearbyData[activeServiceType!]!.length;
    if (total == 0) return;

    int nextIdx = ((servicePointer[activeServiceType!] ?? 0) + 1) % total;
    setState(() => servicePointer[activeServiceType!] = nextIdx);

    var place = allNearbyData[activeServiceType!]![nextIdx];
    _drawRoute(
      LatLng(
        place["geometry"]["location"]["lat"],
        place["geometry"]["location"]["lng"],
      ),
      place,
    );
  }

  Future<void> _drawRoute(LatLng dest, dynamic placeData) async {
    if (currentPosition == null) return;

    setState(() {
      isDrawing = true;
      polylines.clear();
      isFollowingUser = false;
      activePlaceName = placeData["name"];
      activePlaceRating = (placeData["rating"] ?? 0).toDouble();
    });

    final String oLat = currentPosition!.latitude.toStringAsFixed(6);
    final String oLng = currentPosition!.longitude.toStringAsFixed(6);
    final String dLat = dest.latitude.toStringAsFixed(6);
    final String dLng = dest.longitude.toStringAsFixed(6);

    final url = Uri.parse(
      "$baseUrl/directions?origin=$oLat,$oLng&destination=$dLat,$dLng",
    );

    try {
      final response = await http.get(url);
      final data = jsonDecode(response.body);

      if (data["routes"] == null || data["routes"].isEmpty) {
        throw Exception("No route found");
      }

      final leg = data["routes"][0]["legs"][0];
      setState(() {
        routeDistance = leg["distance"]["text"];
        routeDuration = leg["duration"]["text"];
      });

      PolylinePoints pp = PolylinePoints();
      List<PointLatLng> res = pp.decodePolyline(
        data["routes"][0]["overview_polyline"]["points"],
      );
      List<LatLng> path = res
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();

      _zoomToFit(path);

      // Smooth path drawing
      for (
        int i = 0;
        i < path.length;
        i += (path.length / 10).ceil().clamp(1, path.length)
      ) {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 30));
        setState(() {
          polylines = {
            Polyline(
              polylineId: const PolylineId("route_line"),
              points: path.sublist(0, (i + 1).clamp(0, path.length)),
              color: Colors.blueAccent,
              width: 6,
              jointType: JointType.round,
            ),
          };
        });
      }
      setState(() => isDrawing = false);
    } catch (e) {
      debugPrint("Route Error: $e");
      setState(() => isDrawing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not calculate route.")),
      );
    }
  }

  void _zoomToFit(List<LatLng> p) {
    if (p.isEmpty) return;
    double minLat = p.map((e) => e.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = p.map((e) => e.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = p.map((e) => e.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = p.map((e) => e.longitude).reduce((a, b) => a > b ? a : b);

    mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.5176, 121.0509),
              zoom: 15,
            ),
            markers: markers,
            polylines: polylines,
            circles: circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            onMapCreated: (c) {
              mapController = c;
              if (currentPosition != null) {
                mapController?.animateCamera(
                  CameraUpdate.newLatLng(
                    LatLng(
                      currentPosition!.latitude,
                      currentPosition!.longitude,
                    ),
                  ),
                );
              }
            },
          ),
          if (routeDistance != null)
            Positioned(
              top: 50,
              left: 15,
              right: 15,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: Text(
                          activePlaceName ?? "Location",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "Rating: ${activePlaceRating ?? 'N/A'} ⭐",
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => setState(() {
                            routeDistance = null;
                            polylines.clear();
                            isFollowingUser = true;
                          }),
                        ),
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "$routeDistance • $routeDuration",
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: isDrawing ? null : _showNextNearest,
                            icon: const Icon(Icons.navigate_next),
                            label: const Text("Next"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FloatingActionButton(
                        heroTag: "recenter",
                        mini: true,
                        backgroundColor: Colors.white,
                        onPressed: () {
                          setState(() => isFollowingUser = true);
                          if (currentPosition != null) {
                            mapController?.animateCamera(
                              CameraUpdate.newLatLng(
                                LatLng(
                                  currentPosition!.latitude,
                                  currentPosition!.longitude,
                                ),
                              ),
                            );
                          }
                        },
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                        ),
                      ),
                      ScaleTransition(
                        scale: sosAnimation,
                        child: FloatingActionButton.extended(
                          heroTag: "sos_btn",
                          backgroundColor: Colors.red,
                          onPressed: () {},
                          label: const Text(
                            "SOS",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 10),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: emergencyServices.map((s) {
                      return InkWell(
                        onTap: () {
                          activeServiceType = s["type"];
                          if (allNearbyData[activeServiceType!]?.isNotEmpty ??
                              false) {
                            servicePointer[activeServiceType!] = 0;
                            var place = allNearbyData[activeServiceType!]![0];
                            _drawRoute(
                              LatLng(
                                place["geometry"]["location"]["lat"],
                                place["geometry"]["location"]["lng"],
                              ),
                              place,
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Searching for ${s['title']}..."),
                              ),
                            );
                          }
                        },
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.red.withOpacity(0.1),
                              child: Icon(s["icon"], color: Colors.red),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              s["title"],
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
