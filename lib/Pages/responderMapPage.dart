import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:emergenseek/services/socket_service.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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
  StreamSubscription? _chatSubscription;

  LatLng? _lastKnownVictimPos;
  Position? _currentPosition;
  String? _victimPhoneNumber;
  String _victimName = "Victim";

  final TextEditingController _chatController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];

  double _currentZoom = 17.0;
  LatLng? _lastStart;
  LatLng? _lastNext;
  double? _lastBearing;

  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    _fetchVictimDetails();
    _setupTrackingAndChat();
  }

  Future<void> _fetchVictimDetails() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/user/${widget.activeEmergencyId}"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _victimPhoneNumber = data['phoneNumber'] ?? data['phone'];
          _victimName = data['fullName'] ?? data['name'] ?? "Victim";
        });
      }
    } catch (e) {
      debugPrint("Error fetching victim details: $e");
    }
  }

  void _setupTrackingAndChat() {
    // Start streaming for this specific emergency
    SocketService().startEmergencyStreaming(widget.activeEmergencyId);

    // Listen for Victim Location Updates
    _locationSubscription = SocketService().locationStream.listen((LatLng pos) {
      if (!mounted) return;
      _lastKnownVictimPos = pos;
      _getRoadDirections(pos);
    });

    // Listen for Real-time Chat Messages
    _chatSubscription = SocketService().chatStream.listen((data) {
      if (mounted) {
        setState(() {
          _messages.add({
            "text": data['message'],
            "isMe":
                data['senderId'] ==
                "REPLACE_WITH_YOUR_RESPONDER_ID", // Compare IDs
          });
        });
      }
    });
  }

  // --- INTERNAL NAVIGATION LOGIC ---
  void _recenterOnVictim() {
    if (_lastKnownVictimPos != null && _controller != null) {
      _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(_lastKnownVictimPos!, 18),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Waiting for victim's location...")),
      );
    }
  }

  // --- BACKEND ACTION: ARRIVED ---
  Future<void> _markAsArrived() async {
    try {
      final response = await http.patch(
        Uri.parse("$baseUrl/emergency/status/${widget.activeEmergencyId}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"status": "arrived"}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text("Arrival Confirmed"),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error marking arrival: $e");
    }
  }

  // --- BACKEND ACTION: SEND CHAT ---
  void _sendMessage() {
    if (_chatController.text.trim().isEmpty) return;

    final msg = _chatController.text.trim();
    SocketService().emitChatMessage(widget.activeEmergencyId, msg);

    setState(() {
      _messages.add({"text": msg, "isMe": true});
      _chatController.clear();
    });
  }

  // --- DYNAMIC ARROW & ROUTING LOGIC (Preserved) ---
  double _calculateDynamicSize(double zoom) {
    if (zoom >= 18) return 0.0001;
    if (zoom >= 17) return 0.0002;
    return 0.0004;
  }

  void _createDynamicArrowPolygon(LatLng start, LatLng next, double bearing) {
    _lastStart = start;
    _lastNext = next;
    _lastBearing = bearing;
    double arrowSizeDegrees = _calculateDynamicSize(_currentZoom);
    double bearingRad = bearing * math.pi / 180.0;

    double peakLat = (start.latitude) + arrowSizeDegrees * math.cos(bearingRad);
    double peakLng =
        (start.longitude) + arrowSizeDegrees * math.sin(bearingRad);

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
        ),
      );
    });
  }

  Future<void> _getRoadDirections(LatLng destination) async {
    _currentPosition = await Geolocator.getCurrentPosition();
    final url =
        "$baseUrl/get-directions?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=${destination.latitude},${destination.longitude}";

    try {
      final response = await http.get(Uri.parse(url));
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK') {
        List<PointLatLng> result = PolylinePoints().decodePolyline(
          data['routes'][0]['overview_polyline']['points'],
        );
        List<LatLng> coords = result
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId("route"),
              points: coords,
              color: Colors.blueAccent,
              width: 6,
            ),
          };
          _markers.add(
            Marker(
              markerId: const MarkerId("victim"),
              position: destination,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            ),
          );
        });

        if (coords.length > 1) {
          double bearing = Geolocator.bearingBetween(
            coords[0].latitude,
            coords[0].longitude,
            coords[1].latitude,
            coords[1].longitude,
          );
          _createDynamicArrowPolygon(coords[0], coords[1], bearing);
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _chatSubscription?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Tracking $_victimName"),
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
            onCameraMove: (pos) {
              _currentZoom = pos.zoom;
              if (_lastStart != null)
                _createDynamicArrowPolygon(
                  _lastStart!,
                  _lastNext!,
                  _lastBearing!,
                );
            },
            markers: _markers,
            polylines: _polylines,
            polygons: _polygons,
            myLocationEnabled: true,
          ),

          // Control Panel
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FloatingActionButton.extended(
                      onPressed: _openChatModal,
                      label: const Text("CHAT"),
                      icon: const Icon(Icons.chat),
                      heroTag: "c1",
                    ),
                    FloatingActionButton(
                      onPressed: () {},
                      backgroundColor: Colors.green,
                      child: const Icon(Icons.phone),
                      heroTag: "c2",
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _recenterOnVictim, // Now strictly internal navigation
                    icon: const Icon(Icons.gps_fixed),
                    label: const Text("NAVIGATE"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _markAsArrived, // Dynamic Backend Call
                    icon: const Icon(Icons.check_circle),
                    label: const Text("I HAVE ARRIVED"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
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

  void _openChatModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _buildChatSheet(),
    );
  }

  Widget _buildChatSheet() {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: 400,
        color: Colors.white,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                "Emergency Chat",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  return ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _buildBubble(_messages[i]),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      decoration: const InputDecoration(hintText: "Type..."),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(Map msg) {
    bool isMe = msg['isMe'];
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          msg['text'],
          style: TextStyle(color: isMe ? Colors.white : Colors.black),
        ),
      ),
    );
  }
}
