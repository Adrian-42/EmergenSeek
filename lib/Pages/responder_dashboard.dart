import 'package:flutter/material.dart';
import 'package:emergenseek/Pages/EmergencyMapPage.dart';
import 'package:emergenseek/services/socket_service.dart';

class ResponderDashboard extends StatefulWidget {
  const ResponderDashboard({super.key});

  @override
  State<ResponderDashboard> createState() => _ResponderDashboardState();
}

class _ResponderDashboardState extends State<ResponderDashboard> {
  // This list will hold real-time emergencies received via Socket.io
  List<Map<String, dynamic>> activeEmergencies = [];

  @override
  void initState() {
    super.initState();
    _listenForEmergencies();
  }

  void _listenForEmergencies() {
    // We listen for the 'new_emergency_alert' event we added to the backend
    SocketService().socket.on('new_emergency_alert', (data) {
      if (mounted) {
        setState(() {
          // Check if this emergency is already in our list to avoid duplicates
          bool exists = activeEmergencies.any(
            (e) => e['userId'] == data['userId'],
          );
          if (!exists) {
            activeEmergencies.insert(0, data); // Add new alerts to the top
          }
        });
      }
    });

    // Optional: Listen for when a victim turns their toggle back to "Safe"
    SocketService().socket.on('status_changed', (data) {
      if (data['isSafe'] == true && mounted) {
        setState(() {
          activeEmergencies.removeWhere((e) => e['userId'] == data['userId']);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Active Emergencies"),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        actions: [
          // Indicator to show the responder is online
          const Padding(
            padding: EdgeInsets.all(15.0),
            child: CircleAvatar(backgroundColor: Colors.green, radius: 5),
          ),
        ],
      ),
      body: activeEmergencies.isEmpty
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
                      "Emergency: ${alert['userName'] ?? 'Unknown User'}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 5),
                        Text("User ID: ${alert['userId']}"),
                        const Text(
                          "Action: Immediate response required",
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      // Pass the real userId to the Map Page
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EmergencyMapPage(
                            isResponder: true,
                            activeEmergencyId:
                                alert['userId'], // This is crucial!
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 15),
          const Text(
            "No active emergencies nearby",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const Text(
            "Monitoring for signals...",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
