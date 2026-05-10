import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emergenseek/Pages/responderMapPage.dart'; // Updated Import
import 'package:emergenseek/services/socket_service.dart';

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

  /// Clears user session and cleans up resources
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    SocketService().dispose();

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  /// Fetches users who currently have SOS active from the database
  Future<void> _fetchInitialEmergencies() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/active-emergencies"));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
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

      // Handle NEW incoming emergency alerts
      socketInstance.on('new_emergency_alert', (data) {
        if (mounted) {
          setState(() {
            String newId = data['userId'] ?? data['_id'];
            bool exists = activeEmergencies.any(
              (e) => (e['userId'] ?? e['_id']) == newId,
            );

            if (!exists) {
              activeEmergencies.insert(0, data);
            }
          });
        }
      });

      // Remove emergencies when a user marks themselves as "Safe"
      socketInstance.on('status_changed', (data) {
        if (data['isSafe'] == true && mounted) {
          setState(() {
            String safeId = data['userId'] ?? data['_id'];
            activeEmergencies.removeWhere(
              (e) => (e['userId'] ?? e['_id']) == safeId,
            );
          });
        }
      });
    } catch (e) {
      // If socket isn't ready yet, retry shortly
      debugPrint("Socket initializing... retrying listener: $e");
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
                      alert['userId'] ?? alert['_id'] ?? 'unknown';
                  final String victimName =
                      alert['userName'] ?? alert['name'] ?? 'Unknown User';

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
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        // NAVIGATE TO THE SPECIALIZED RESPONDER MAP
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
