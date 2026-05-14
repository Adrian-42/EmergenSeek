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
  String _victimAddress = "Fetching location details...";

  final TextEditingController _chatController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isChatExpanded = false; // Toggle for the dropdown animation

  double _currentZoom = 17.0;
  LatLng? _lastStart;
  LatLng? _lastNext;
  double? _lastBearing;
  String _myResponderId = "ACTUAL_LOGGED_IN_ID";

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
          _victimAddress = data['address'] ?? "No specific address provided";
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching victim details: $e");
      setState(() => _isLoading = false);
    }
  }

  void _setupTrackingAndChat() {
    SocketService().startEmergencyStreaming(widget.activeEmergencyId);

    _locationSubscription = SocketService().locationStream.listen((LatLng pos) {
      if (!mounted) return;
      _lastKnownVictimPos = pos;
      _getRoadDirections(pos);
    });

    _chatSubscription = SocketService().chatStream.listen((data) {
      // Check if message belongs to this emergency
      if (mounted && data['emergencyId'] == widget.activeEmergencyId) {
        setState(() {
          _messages.add({
            "text": data['text'] ?? data['message'],
            // Compare with actual logged-in ID instead of hardcoded string
            "isMe": data['senderId'] == _myResponderId,
          });
        });
      }
    });
  }

  Future<void> _makeDirectCall() async {
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

  void _recenterOnVictim() {
    if (_lastKnownVictimPos != null && _controller != null) {
      _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(_lastKnownVictimPos!, 18),
      );
    }
  }

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

  void _sendMessage() {
    if (_chatController.text.trim().isEmpty) return;

    final msg = _chatController.text.trim();
    // Pass the actual responder ID here
    SocketService().sendMessage(widget.activeEmergencyId, msg, _myResponderId);

    setState(() {
      _messages.add({"text": msg, "isMe": true});
      _chatController.clear();
    });
  }

  // --- DYNAMIC ARROW & ROUTING LOGIC (RETAINED) ---
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
    String recentChat = _messages.isNotEmpty
        ? _messages.last['text']
        : "No messages yet...";

    return Stack(
      children: [
        Scaffold(
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

              // --- INTEGRATED INFO & CHAT CARD ---
              Positioned(
                top: 20,
                left: 15,
                right: 15,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _isChatExpanded = !_isChatExpanded),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: Colors.redAccent,
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _victimName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                          ),
                                        ),
                                        Text(
                                          _victimPhoneNumber ?? "No Phone",
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    _isChatExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // COLLAPSED VS EXPANDED TOGGLE
                              AnimatedCrossFade(
                                firstChild: Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: Colors.blueAccent,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _victimAddress,
                                        style: const TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                secondChild: Row(
                                  children: [
                                    const Icon(
                                      Icons.chat_bubble_outline,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Recent: $recentChat",
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.green,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                crossFadeState: _isChatExpanded
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                duration: const Duration(milliseconds: 300),
                              ),
                            ],
                          ),
                        ),

                        // REVEALED CHAT SECTION
                        if (_isChatExpanded) ...[
                          const Divider(height: 1),
                          SizedBox(
                            height: 250,
                            child: Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(10),
                                    itemCount: _messages.length,
                                    itemBuilder: (context, i) =>
                                        _buildBubble(_messages[i]),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _chatController,
                                          decoration: InputDecoration(
                                            hintText: "Reply to victim...",
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.all(12),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.send,
                                          color: Colors.blueAccent,
                                        ),
                                        onPressed: _sendMessage,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Control Buttons
              Positioned(
                bottom: 30,
                left: 20,
                right: 20,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FloatingActionButton(
                        onPressed: _makeDirectCall,
                        backgroundColor: Colors.green,
                        child: const Icon(Icons.phone),
                        heroTag: "call_fab",
                      ),
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _recenterOnVictim,
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
                        onPressed: _markAsArrived,
                        icon: const Icon(Icons.check_circle),
                        label: const Text("ARRIVED"),
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
        ),

        if (_isLoading)
          Container(
            color: Colors.black54,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(25.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 20),
                      Text(
                        "Synchronizing Emergency Data...",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBubble(Map msg) {
    bool isMe = msg['isMe'];
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? Colors.blueAccent : Colors.grey[200],
          borderRadius: BorderRadius.circular(12).copyWith(
            bottomRight: isMe ? Radius.zero : const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
          ),
        ),
        child: Text(
          msg['text'],
          style: TextStyle(
            color: isMe ? Colors.white : Colors.black87,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
