import 'dart:convert';
import 'dart:async';
import 'dart:io';
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
import 'package:emergenseek/Pages/ChatPage.dart';

class EmergencyMapPage extends StatefulWidget {
  final bool isResponder;
  final String activeEmergencyId; // Added to receive the victim/room ID

  const EmergencyMapPage({
    super.key,
    this.isResponder = false,
    this.activeEmergencyId = "",
  });

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
  bool isSendingSOS = false;
  List<dynamic> _nearbyPlaces = [];
  int _currentIndex = 0;
  String _currentType = '';
  final String baseUrl = "https://emergenseek.onrender.com";

  LatLng? _lastStart;
  LatLng? _lastNext;
  double? _lastBearing;
  double _currentZoom = 15.0;

  String? _currentUserId; // To store the logged-in user's ID

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadCachedPlaces();
    _initLocationTracking();
  }

  // Load user data for chat and SOS
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getString('userId');
    });
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
      _showSnackBar(
        "Phone number not available for this facility.",
        Colors.orange,
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

  // --- SOS LOGIC WITH SMS FALLBACK ---
  Future<void> _sendSOSAlert() async {
    if (currentPosition == null || isSendingSOS) return;

    setState(() => isSendingSOS = true);
    _showSnackBar("🚨 Alerting Emergency Contacts...", Colors.red);

    if (_currentUserId == null) {
      _showSnackBar("User ID not found.", Colors.red);
      setState(() => isSendingSOS = false);
      return;
    }

    final String googleMapsUrl =
        "https://www.google.com/maps/search/?api=1&query=${currentPosition!.latitude},${currentPosition!.longitude}";

    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/trigger-sos"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "userId": _currentUserId,
              "locationLink": googleMapsUrl,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _showSnackBar("✅ SOS Emails Sent!", Colors.green);
      } else if (responseData['fallbackToSms'] == true) {
        _triggerDirectSMS(responseData['phoneNumbers'], googleMapsUrl);
      } else {
        throw Exception("Server side error");
      }
    } catch (e) {
      debugPrint("Email SOS failed, attempting SMS fallback: $e");

      final userRes = await http.get(
        Uri.parse("$baseUrl/user/$_currentUserId"),
      );
      if (userRes.statusCode == 200) {
        final userData = jsonDecode(userRes.body);
        final List contacts = userData['emergencyContacts'] ?? [];
        final List<String> phones = contacts
            .map((c) => c['phone'].toString())
            .toList();

        if (phones.isNotEmpty) {
          _triggerDirectSMS(phones, googleMapsUrl);
        } else {
          _showSnackBar("❌ SOS Failed. No phone numbers found.", Colors.red);
        }
      }
    } finally {
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) setState(() => isSendingSOS = false);
      });
    }
  }

  Future<void> _triggerDirectSMS(List phoneNumbers, String locationLink) async {
    final String separator = Platform.isAndroid ? ',' : ';';
    final String recipients = phoneNumbers.join(separator);
    final String message = Uri.encodeComponent(
      "🚨 EMERGENCY SOS! I need help. My current location: $locationLink",
    );

    final Uri smsUri = Uri.parse("sms:$recipients?body=$message");

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
      _showSnackBar("⚠️ Email failed. SMS App Opened.", Colors.orange);
    } else {
      _showSnackBar("Could not launch SMS app.", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
    }
  }

  // --- STATUS TOGGLE (SAFE/HELP) ---
  Future<void> _updateSafetyStatus(bool value) async {
    if (_currentUserId == null) return;

    setState(() => isSafe = value);

    await http.put(
      Uri.parse("$baseUrl/user/status"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": _currentUserId,
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
            _currentUserId!,
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

  void _openChat() {
    // If we are a responder, the room ID is the activeEmergencyId passed in.
    // If we are the victim, the room ID is our own userId.
    String roomToJoin = widget.isResponder
        ? widget.activeEmergencyId
        : (_currentUserId ?? "");

    if (roomToJoin.isEmpty) {
      _showSnackBar("No active emergency chat available.", Colors.orange);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          emergencyId: roomToJoin,
          currentUserId: _currentUserId ?? "unknown",
        ),
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
      debugPrint("Fetch Error: $e. Using cached data.");
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
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.settings, color: Colors.black, size: 24),
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
          // Safety Guide Button
          Positioned(
            top: 80,
            left: 10,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SafetyGuidePage(),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.help_outline,
                  color: Colors.redAccent,
                  size: 25,
                ),
              ),
            ),
          ),
          // SOS Button
          Positioned(
            left: 20,
            top: 450,
            child: FloatingActionButton(
              heroTag: "sos_alert",
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
          // Chat Button
          Positioned(
            right: 20,
            top: 450,
            child: FloatingActionButton(
              heroTag: "chat_btn",
              backgroundColor: Colors.blueAccent,
              onPressed: _openChat,
              child: const Icon(Icons.chat),
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
          // Recenter Button
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
          // Facility Details Card
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
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              currentPlace['vicinity'] ??
                                  "Address not available",
                            ),
                          ),
                        ],
                      ),
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
          // Bottom Status and Search Panel
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
                          icon: Icon(
                            _showDetails ? Icons.info : Icons.info_outline,
                            color: Colors.blue,
                          ),
                          onPressed: () =>
                              setState(() => _showDetails = !_showDetails),
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

  @override
  void dispose() {
    _socketTimer?.cancel();
    mapController?.dispose();
    super.dispose();
  }
}
