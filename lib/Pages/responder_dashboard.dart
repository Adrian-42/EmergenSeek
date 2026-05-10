import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:emergenseek/Pages/EmergencyMapPage.dart';
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
    _fetchInitialEmergencies(); // Fetch existing help requests
    _listenForEmergencies(); // Listen for new real-time requests
  }

  /// Fetches users who currently have their SOS toggle turned "ON"
  Future<void> _fetchInitialEmergencies() async {
    try {
      // Assuming your backend has an endpoint to get active emergencies
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

      // Listen for NEW alerts
      socketInstance.on('new_emergency_alert', (data) {
        if (mounted) {
          setState(() {
            bool exists = activeEmergencies.any(
              (e) => e['userId'] == data['userId'],
            );
            if (!exists) {
              activeEmergencies.insert(0, data);
            }
          });
        }
      });

      // Listen for when a user is marked "Safe"
      socketInstance.on('status_changed', (data) {
        if (data['isSafe'] == true && mounted) {
          setState(() {
            activeEmergencies.removeWhere((e) => e['userId'] == data['userId']);
          });
        }
      });
    } catch (e) {
      debugPrint("Socket not ready yet: $e");
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
          // Visual indicator that the responder is "Live"
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 15.0),
              child: Row(
                children: [
                  const Text(
                    "LIVE",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
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
                itemCount: activeEmergencies.length,
                itemBuilder: (context, index) {
                  final alert = activeEmergencies[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    elevation: 4,
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
                        alert['userName'] ?? alert['name'] ?? 'Unknown User',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text("ID: ${alert['userId'] ?? alert['_id']}"),
                          const Text(
                            "STATUS: SOS TRIGGERED",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EmergencyMapPage(
                              isResponder: true,
                              activeEmergencyId:
                                  alert['userId'] ?? alert['_id'],
                            ),
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

  Widget _buildEmptyState() {
    return ListView(
      // Wrap in ListView so RefreshIndicator still works
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
