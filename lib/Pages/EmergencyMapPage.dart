import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emergenseek/services/socket_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:emergenseek/Pages/SettingsPage.dart';
import 'package:emergenseek/Pages/safety_guide_page.dart';

class EmergencyMapPage extends StatefulWidget {
  final bool isResponder;
  const EmergencyMapPage({super.key, this.isResponder = false});

  @override
  State<EmergencyMapPage> createState() => _EmergencyMapPageState();
}

class _EmergencyMapPageState extends State<EmergencyMapPage> {
  GoogleMapController? mapController;
  Position? currentPosition;
  Timer? _socketTimer;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  Set<Polygon> polygons = {};

  bool isSafe = true;
  bool _showDetails = false;
  List<dynamic> _nearbyPlaces = [];
  int _currentIndex = 0;
  String _currentType = '';

  // Update this to your local IP (e.g., http://192.168.1.XX:3000) for testing
  // or your Render URL for production.
  final String baseUrl = "https://emergenseek.onrender.com";

  LatLng? _lastStart;
  LatLng? _lastNext;
  double? _lastBearing;
  double _currentZoom = 15.0;

  @override
  void initState() {
    super.initState();
    _loadCachedPlaces();
    _initLocationTracking();
  }

  Future<void> _loadCachedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cachedData = prefs.getString('cached_nearby_places');
    if (cachedData != null) {
      setState(() {
        _nearbyPlaces = jsonDecode(cachedData);
      });
      if (_nearbyPlaces.isNotEmpty) {
        _showCurrentFacility();
      }
    }
  }

  Future<void> _initLocationTracking() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((Position pos) {
      if (mounted) {
        setState(() => currentPosition = pos);
      }
    });
  }

  // --- SOS EMAIL LOGIC (Nodemailer Integration) ---
  Future<void> _sendSOSAlert() async {
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Wait for GPS location before sending SOS."),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId =
        prefs.getString('userId') ?? "Guest_User"; // Fallback for testing

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Sending SOS Alerts..."),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final String locationLink =
          "https://www.google.com/maps/search/?api=1&query=${currentPosition!.latitude},${currentPosition!.longitude}";

      final response = await http.post(
        Uri.parse("$baseUrl/user/trigger-sos"),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({"userId": userId, "locationLink": locationLink}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("SOS SUCCESS: Emails sent!"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("SOS FAILED: ${errorData['error']}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("SOS Fetch Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Network Error. Check your backend."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- CALL LOGIC ---
  Future<void> _makeCall() async {
    if (_nearbyPlaces.isEmpty) return;
    String? phoneNumber =
        _nearbyPlaces[_currentIndex]['formatted_phone_number'];

    if (phoneNumber != null) {
      final Uri callUri = Uri.parse("tel:$phoneNumber");
      if (await canLaunchUrl(callUri)) {
        await launchUrl(callUri);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Phone number not available for this facility."),
        ),
      );
    }
  }

  // --- NAVIGATION LOGIC ---
  Future<void> _launchNavigation() async {
    if (_nearbyPlaces.isEmpty) return;
    final lat = _nearbyPlaces[_currentIndex]['geometry']['location']['lat'];
    final lng = _nearbyPlaces[_currentIndex]['geometry']['location']['lng'];
    final url = 'google.navigation:q=$lat,$lng&mode=d';
    final fallbackUrl =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      await launchUrl(Uri.parse(fallbackUrl));
    }
  }

  // --- STATUS TOGGLE ---
  Future<void> _updateSafetyStatus(bool value) async {
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
          ),
        ),
      );
    }
  }

  double _calculateDynamicSize(double zoom) => 0.001 / math.pow(2, zoom - 15);

  void _createDynamicArrowPolygon(LatLng start, LatLng next, double bearing) {
    _lastStart = start;
    _lastNext = next;
    _lastBearing = bearing;
    double arrowSizeDegrees = _calculateDynamicSize(_currentZoom);
    double bearingRad = bearing * math.pi / 180.0;
    double offset = arrowSizeDegrees * 0.05;
    double peakLat =
        (start.latitude + offset * math.cos(bearingRad)) +
        arrowSizeDegrees * math.cos(bearingRad);
    double peakLng =
        (start.longitude + offset * math.sin(bearingRad)) +
        arrowSizeDegrees * math.sin(bearingRad);
    double sideOffset = arrowSizeDegrees * 0.6;
    double bLeftLat =
        start.latitude + sideOffset * math.cos(bearingRad - (math.pi / 2));
    double bLeftLng =
        start.longitude + sideOffset * math.sin(bearingRad - (math.pi / 2));
    double bRightLat =
        start.latitude + sideOffset * math.cos(bearingRad + (math.pi / 2));
    double bRightLng =
        start.longitude + sideOffset * math.sin(bearingRad + (math.pi / 2));

    setState(() {
      polygons.clear();
      polygons.add(
        Polygon(
          polygonId: const PolygonId("dynamic_arrow"),
          points: [
            LatLng(bLeftLat, bLeftLng),
            LatLng(peakLat, peakLng),
            LatLng(bRightLat, bRightLng),
          ],
          fillColor: Colors.blue.withOpacity(0.9),
          strokeWidth: 0,
          zIndex: 10,
          geodesic: true,
        ),
      );
    });
  }

  Future<void> _getRoadDirections(LatLng destination) async {
    if (currentPosition == null) return;
    final url =
        "$baseUrl/get-directions?origin=${currentPosition!.latitude},${currentPosition!.longitude}&destination=${destination.latitude},${destination.longitude}";

    try {
      final response = await http.get(Uri.parse(url));
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK') {
        final polylinePoints = PolylinePoints();
        List<PointLatLng> result = polylinePoints.decodePolyline(
          data['routes'][0]['overview_polyline']['points'],
        );
        List<LatLng> polylineCoordinates = result
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        double initialBearing = 0;
        if (polylineCoordinates.length > 1) {
          initialBearing = Geolocator.bearingBetween(
            polylineCoordinates[0].latitude,
            polylineCoordinates[0].longitude,
            polylineCoordinates[1].latitude,
            polylineCoordinates[1].longitude,
          );
        }

        setState(() {
          polylines.clear();
          polylines.add(
            Polyline(
              polylineId: const PolylineId("road_route"),
              points: polylineCoordinates,
              color: Colors.blueAccent,
              width: 6,
              jointType: JointType.round,
            ),
          );
          markers.clear();
          markers.add(
            Marker(
              markerId: const MarkerId("selected_facility"),
              position: destination,
              onTap: () => setState(() => _showDetails = true),
              infoWindow: InfoWindow(
                title: _nearbyPlaces[_currentIndex]['name'],
              ),
            ),
          );
        });

        if (polylineCoordinates.length > 1) {
          _createDynamicArrowPolygon(
            polylineCoordinates[0],
            polylineCoordinates[1],
            initialBearing,
          );
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _showCurrentFacility() {
    if (_nearbyPlaces.isEmpty) return;
    _getRoadDirections(
      LatLng(
        _nearbyPlaces[_currentIndex]['geometry']['location']['lat'],
        _nearbyPlaces[_currentIndex]['geometry']['location']['lng'],
      ),
    );
  }

  void _nextPlace() => setState(() {
    _currentIndex = (_currentIndex + 1) % _nearbyPlaces.length;
    _showCurrentFacility();
  });
  void _prevPlace() => setState(() {
    _currentIndex =
        (_currentIndex - 1 + _nearbyPlaces.length) % _nearbyPlaces.length;
    _showCurrentFacility();
  });

  Future<void> _fetchNearby(String type) async {
    if (currentPosition == null) return;
    try {
      final res = await http.get(
        Uri.parse(
          "$baseUrl/places?lat=${currentPosition!.latitude}&lng=${currentPosition!.longitude}&type=$type",
        ),
      );
      if (res.statusCode == 200) {
        final List<dynamic> results = jsonDecode(res.body)['results'];
        setState(() {
          _nearbyPlaces = results;
          _currentIndex = 0;
          _currentType = type;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_nearby_places', jsonEncode(results));
        _showCurrentFacility();
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPlace = _nearbyPlaces.isNotEmpty
        ? _nearbyPlaces[_currentIndex]
        : null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 10, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.settings, color: Colors.black),
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
            onMapCreated: (c) async {
              mapController = c;
              setState(() async => _currentZoom = await c.getZoomLevel());
            },
            markers: markers,
            polylines: polylines,
            polygons: polygons,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onCameraMove: (pos) {
              _currentZoom = pos.zoom;
              if (_lastStart != null &&
                  _lastNext != null &&
                  _lastBearing != null) {
                _createDynamicArrowPolygon(
                  _lastStart!,
                  _lastNext!,
                  _lastBearing!,
                );
              }
            },
          ),
          // SOS Button
          Positioned(
            left: 20,
            top: 450,
            child: FloatingActionButton(
              heroTag: "sos_email",
              backgroundColor: Colors.red,
              onPressed: _sendSOSAlert,
              child: const Text(
                "SOS",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Safety Status Toggle
          Positioned(
            left: 20,
            top: 525,
            child: FloatingActionButton(
              heroTag: "status_toggle",
              backgroundColor: isSafe ? Colors.green : Colors.orange,
              onPressed: () => _updateSafetyStatus(!isSafe),
              child: Icon(
                isSafe ? Icons.check_circle : Icons.warning,
                color: Colors.white,
              ),
            ),
          ),
          // My Location Button
          Positioned(
            right: 20,
            top: 525,
            child: FloatingActionButton(
              heroTag: "loc",
              backgroundColor: Colors.white,
              onPressed: _recenterCamera,
              child: const Icon(Icons.my_location, color: Colors.blue),
            ),
          ),
          // Place Details Overlay
          if (_showDetails && currentPlace != null)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              currentPlace['name'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _showDetails = false),
                          ),
                        ],
                      ),
                      Text(currentPlace['vicinity'] ?? "Address not available"),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            onPressed: _makeCall,
                            icon: const Icon(Icons.call, color: Colors.green),
                            label: const Text("Call"),
                          ),
                          TextButton.icon(
                            onPressed: _launchNavigation,
                            icon: const Icon(
                              Icons.directions,
                              color: Colors.blue,
                            ),
                            label: const Text("Navigate"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Bottom Navigation Sheet
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
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
                  const SizedBox(height: 10),
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
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios),
                          onPressed: _prevPlace,
                        ),
                        Expanded(
                          child: Text(
                            _nearbyPlaces[_currentIndex]['name'],
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                          ),
                          onPressed: () =>
                              setState(() => _showDetails = !_showDetails),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call, color: Colors.green),
                          onPressed: _makeCall,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios),
                          onPressed: _nextPlace,
                        ),
                      ],
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
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
