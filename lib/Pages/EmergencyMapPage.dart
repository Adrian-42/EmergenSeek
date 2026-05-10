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

class EmergencyMapPage extends StatefulWidget {
  const EmergencyMapPage({super.key});

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
  List<dynamic> _nearbyPlaces = [];
  int _currentIndex = 0;
  String _currentType = '';
  final String baseUrl = "https://emergenseek.onrender.com";

  // Persistent route data for dynamic scaling
  LatLng? _lastStart;
  LatLng? _lastNext;
  double? _lastBearing;
  double _currentZoom = 15.0;

  @override
  void initState() {
    super.initState();
    _initLocationTracking();
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

  // --- CALL LOGIC ---
  Future<void> _makeCall() async {
    if (_nearbyPlaces.isEmpty) return;
    final placeId = _nearbyPlaces[_currentIndex]['place_id'];

    // Some place results don't have phone numbers in the basic search.
    // If you need the phone number, you'd usually fetch Place Details.
    // For now, we'll try to get it from results or use a placeholder if unavailable.
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

  // --- SOS EMAIL LOGIC (SOLO) ---
  Future<void> _sendSOSAlert() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId == null) return;

    try {
      final response = await http.get(Uri.parse("$baseUrl/user/$userId"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> contacts = data['emergencyContacts'] ?? [];
        if (contacts.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No emergency contacts found.")),
          );
          return;
        }

        final List<String> emailList = contacts
            .map((c) => c['email'].toString())
            .where((e) => e.isNotEmpty)
            .toList();

        final String recipientString = emailList.join(',');
        final String subject = Uri.encodeComponent("EMERGENCY: SOS ALERT");
        String locationLink = currentPosition != null
            ? "https://www.google.com/maps?q=${currentPosition!.latitude},${currentPosition!.longitude}"
            : "Location not available";

        final String body = Uri.encodeComponent(
          "Automated SOS alert. Need help.\nLocation: $locationLink",
        );

        final Uri emailUri = Uri.parse(
          "mailto:$recipientString?subject=$subject&body=$body",
        );

        if (await canLaunchUrl(emailUri)) {
          await launchUrl(emailUri);
        }
      }
    } catch (e) {
      debugPrint("SOS Error: $e");
    }
  }

  // --- STATUS TOGGLE (SAFE/HELP) ---
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
            tilt: 0,
          ),
        ),
      );
    }
  }

  // --- DYNAMIC ARROW SCALING ---
  double _calculateDynamicSize(double zoom) {
    return 0.001 / math.pow(2, zoom - 15);
  }

  void _createDynamicArrowPolygon(LatLng start, LatLng next, double bearing) {
    _lastStart = start;
    _lastNext = next;
    _lastBearing = bearing;

    double arrowSizeDegrees = _calculateDynamicSize(_currentZoom);
    double bearingRad = bearing * math.pi / 180.0;

    double offset = arrowSizeDegrees * 0.05;
    double anchorLat = start.latitude + offset * math.cos(bearingRad);
    double anchorLng = start.longitude + offset * math.sin(bearingRad);
    LatLng anchor = LatLng(anchorLat, anchorLng);

    double peakLat = anchor.latitude + arrowSizeDegrees * math.cos(bearingRad);
    double peakLng = anchor.longitude + arrowSizeDegrees * math.sin(bearingRad);
    LatLng peak = LatLng(peakLat, peakLng);

    double sideOffset = arrowSizeDegrees * 0.6;
    double baseAngleOffsetRad = math.pi / 2;

    double bLeftLat =
        start.latitude + sideOffset * math.cos(bearingRad - baseAngleOffsetRad);
    double bLeftLng =
        start.longitude +
        sideOffset * math.sin(bearingRad - baseAngleOffsetRad);
    LatLng baseLeft = LatLng(bLeftLat, bLeftLng);

    double bRightLat =
        start.latitude + sideOffset * math.cos(bearingRad + baseAngleOffsetRad);
    double bRightLng =
        start.longitude +
        sideOffset * math.sin(bearingRad + baseAngleOffsetRad);
    LatLng baseRight = LatLng(bRightLat, bRightLng);

    setState(() {
      polygons.clear();
      polygons.add(
        Polygon(
          polygonId: const PolygonId("dynamic_arrow"),
          points: [baseLeft, peak, baseRight],
          fillColor: Colors.blue.withOpacity(0.9),
          strokeWidth: 0,
          zIndex: 10,
          geodesic: true,
        ),
      );
    });
  }

  // --- ROUTING ---
  Future<void> _getRoadDirections(LatLng destination) async {
    if (currentPosition == null) return;
    final origin = "${currentPosition!.latitude},${currentPosition!.longitude}";
    final dest = "${destination.latitude},${destination.longitude}";
    final url = "$baseUrl/get-directions?origin=$origin&destination=$dest";

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

  void _nextPlace() {
    if (_nearbyPlaces.isEmpty) return;
    setState(() => _currentIndex = (_currentIndex + 1) % _nearbyPlaces.length);
    _showCurrentFacility();
  }

  void _prevPlace() {
    if (_nearbyPlaces.isEmpty) return;
    setState(
      () => _currentIndex =
          (_currentIndex - 1 + _nearbyPlaces.length) % _nearbyPlaces.length,
    );
    _showCurrentFacility();
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
            icon: const Icon(Icons.settings),
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
              double zoom = await c.getZoomLevel();
              setState(() => _currentZoom = zoom);
            },
            markers: markers,
            polylines: polylines,
            polygons: polygons,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onCameraMove: (CameraPosition position) {
              _currentZoom = position.zoom;
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

          // SOS BUTTON (SEND EMAIL)
          Positioned(
            left: 20,
            top: 480,
            child: FloatingActionButton(
              heroTag: "sos_email",
              backgroundColor: Colors.red,
              child: const Text(
                "SOS",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _sendSOSAlert,
            ),
          ),

          // SAFETY TOGGLE BUTTON (SAFE / HELP)
          Positioned(
            left: 20,
            top: 550,
            child: FloatingActionButton(
              heroTag: "status_toggle",
              backgroundColor: isSafe ? Colors.green : Colors.orange,
              child: Icon(
                isSafe ? Icons.check_circle : Icons.warning,
                color: Colors.white,
              ),
              onPressed: () => _updateSafetyStatus(!isSafe),
            ),
          ),

          // LOCATION RECENTER BUTTON
          Positioned(
            right: 20,
            top: 550,
            child: FloatingActionButton(
              heroTag: "loc",
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Colors.blue),
              onPressed: _recenterCamera,
            ),
          ),

          // BOTTOM INFO PANEL
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
