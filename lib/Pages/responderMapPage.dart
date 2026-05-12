import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:emergenseek/services/socket_service.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class ResponderMapPage extends StatefulWidget {
  final String activeEmergencyId;
  const ResponderMapPage({super.key, required this.activeEmergencyId});

  @override
  State<ResponderMapPage> createState() => _ResponderMapPageState();
}

class _ResponderMapPageState extends State<ResponderMapPage> {
  GoogleMapController? _controller;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {};
  StreamSubscription? _locationSubscription;
  LatLng? _lastKnownVictimPos;
  Position? _currentPosition;
  String? _victimPhoneNumber; // Store phone number here

  double _currentZoom = 17.0;
  LatLng? _lastStart;
  LatLng? _lastNext;
  double? _lastBearing;

  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    _fetchVictimDetails(); // Fetch phone number on load
    _setupTracking();
  }

  /// Fetches victim info (phone number) from the backend
  Future<void> _fetchVictimDetails() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/user/${widget.activeEmergencyId}"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _victimPhoneNumber = data['phoneNumber'] ?? data['phone'];
        });
      }
    } catch (e) {
      debugPrint("Error fetching victim details: $e");
    }
  }

  /// Launches the phone dialer
  Future<void> _callVictim() async {
    if (_victimPhoneNumber == null || _victimPhoneNumber!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone number not available")),
      );
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: _victimPhoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  // --- ARROW CALCULATION LOGIC ---
  double _calculateDynamicSize(double zoom) {
    if (zoom >= 18) return 0.0001;
    if (zoom >= 17) return 0.0002;
    if (zoom >= 16) return 0.0004;
    return 0.0008;
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
      _polygons.clear();
      _polygons.add(
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

  // --- ROUTING LOGIC ---
  Future<void> _getRoadDirections(LatLng destination) async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint("Could not get current location: $e");
    }

    if (_currentPosition == null) return;

    final origin =
        "${_currentPosition!.latitude},${_currentPosition!.longitude}";
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
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId("road_route"),
              points: polylineCoordinates,
              color: Colors.blueAccent,
              width: 6,
              jointType: JointType.round,
            ),
          );

          _markers.add(
            Marker(
              markerId: const MarkerId("victim"),
              position: destination,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
              infoWindow: const InfoWindow(title: "VICTIM LOCATION"),
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
      debugPrint("Routing error: ${e.toString()}");
    }
  }

  void _setupTracking() {
    SocketService().startEmergencyStreaming(widget.activeEmergencyId);

    _locationSubscription = SocketService().locationStream.listen((LatLng pos) {
      if (!mounted) return;
      _lastKnownVictimPos = pos;
      _getRoadDirections(pos);
      _controller?.animateCamera(CameraUpdate.newLatLng(pos));
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  void _openInGoogleMaps() async {
    if (_lastKnownVictimPos == null) return;

    final url =
        'google.navigation:q=${_lastKnownVictimPos!.latitude},${_lastKnownVictimPos!.longitude}&mode=d';
    final fallbackUrl =
        'https://www.google.com/maps/dir/?api=1&destination=${_lastKnownVictimPos!.latitude},${_lastKnownVictimPos!.longitude}&travelmode=driving';

    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        await launchUrl(
          Uri.parse(fallbackUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint("Could not launch Google Maps: $e");
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
            onCameraMove: (position) {
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
            markers: _markers,
            polylines: _polylines,
            polygons: _polygons,
            myLocationEnabled: true,
          ),
          // --- BOTTOM CONTROL PANEL ---
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // CALL BUTTON (Circular Floating style)
                Align(
                  alignment: Alignment.centerRight,
                  child: FloatingActionButton(
                    onPressed: _callVictim,
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.phone, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 15),
                // NAVIGATION BUTTON
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openInGoogleMaps,
                    icon: const Icon(Icons.navigation),
                    label: const Text("NAVIGATE TO VICTIM"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
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
