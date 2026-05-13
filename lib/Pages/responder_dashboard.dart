import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emergenseek/services/socket_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:emergenseek/Pages/responderMapPage.dart';

class ResponderDashboard extends StatefulWidget {
  const ResponderDashboard({super.key});

  @override
  State<ResponderDashboard> createState() => _ResponderDashboardState();
}

class _ResponderDashboardState extends State<ResponderDashboard> {
  List<Map<String, dynamic>> activeEmergencies = [];
  bool isLoading = true;
  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    _fetchInitialEmergencies();
    _listenForEmergencies();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    SocketService().dispose();

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      debugPrint("Could not launch $launchUri");
    }
  }

  Future<void> _fetchInitialEmergencies() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/active-emergencies"));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        debugPrint("REST API DATA: $data");

        if (mounted) {
          setState(() {
            activeEmergencies = List<Map<String, dynamic>>.from(data);
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching initial emergencies: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _listenForEmergencies() {
    try {
      final socketInstance = SocketService().socket;

      socketInstance.on('new_emergency_alert', (data) {
        debugPrint("SOCKET DATA RECEIVED: $data");

        if (mounted) {
          setState(() {
            String newId = (data['userId'] ?? data['_id'] ?? 'unknown')
                .toString();
            bool exists = activeEmergencies.any(
              (e) => (e['userId'] ?? e['_id'] ?? 'unknown').toString() == newId,
            );

            if (!exists) {
              activeEmergencies.insert(0, Map<String, dynamic>.from(data));
            }
          });
        }
      });

      socketInstance.on('status_changed', (data) {
        if (data['isSafe'] == true && mounted) {
          setState(() {
            String safeId = (data['userId'] ?? data['_id'] ?? 'unknown')
                .toString();
            activeEmergencies.removeWhere(
              (e) =>
                  (e['userId'] ?? e['_id'] ?? 'unknown').toString() == safeId,
            );
          });
        }
      });
    } catch (e) {
      debugPrint("Socket initializing error: $e");
      Future.delayed(const Duration(seconds: 2), _listenForEmergencies);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Active Emergencies"),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        actions: [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Text(
                    "LIVE",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 5),
                  CircleAvatar(backgroundColor: Colors.green, radius: 4),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchInitialEmergencies,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : activeEmergencies.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
                padding: const EdgeInsets.only(top: 10),
                itemCount: activeEmergencies.length,
                itemBuilder: (context, index) {
                  final alert = activeEmergencies[index];

                  final String victimId =
                      (alert['userId'] ?? alert['_id'] ?? 'unknown').toString();
                  final String victimName =
                      (alert['userName'] ?? alert['name'] ?? 'Unknown User')
                          .toString();

                  String victimPhone = 'N/A';
                  if (alert['phoneNumber'] != null &&
                      alert['phoneNumber'].toString().isNotEmpty) {
                    victimPhone = alert['phoneNumber'].toString();
                  } else if (alert['phone'] != null &&
                      alert['phone'].toString().isNotEmpty) {
                    victimPhone = alert['phone'].toString();
                  } else if (alert['user'] != null &&
                      alert['user']['phoneNumber'] != null) {
                    victimPhone = alert['user']['phoneNumber'].toString();
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(15),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.red,
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        victimName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            "ID: $victimId",
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.phone,
                                size: 14,
                                color: victimPhone == 'N/A'
                                    ? Colors.grey
                                    : Colors.green,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                "Phone: $victimPhone",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: victimPhone == 'N/A'
                                      ? Colors.grey
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            "SOS ACTIVE - NEEDS ASSISTANCE",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (victimPhone != 'N/A')
                            IconButton(
                              icon: const Icon(
                                Icons.phone,
                                color: Colors.green,
                              ),
                              onPressed: () => _makePhoneCall(victimPhone),
                            ),
                          const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      ),
                      onTap: () {
                        // FIX: Navigating to ResponderMapPage with the ID
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ResponderMapPage(activeEmergencyId: victimId),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Confirm logout from responder session?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: _logout,
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        const Center(
          child: Column(
            children: [
              Icon(Icons.shield_outlined, size: 80, color: Colors.grey),
              SizedBox(height: 15),
              Text(
                "No active emergencies",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                "Monitoring for signals...",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
