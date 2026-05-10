import 'package:flutter/material.dart';
import 'package:emergenseek/Pages/EmergencyMapPage.dart';
// Import your services and pages

class ResponderDashboard extends StatelessWidget {
  const ResponderDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Active Emergencies"),
        backgroundColor: Colors.redAccent,
      ),
      body: ListView.builder(
        itemCount: 5, // This will be driven by your MongoDB/Socket data later
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: const Icon(Icons.warning, color: Colors.red),
              title: Text("Emergency Alert #${index + 1}"),
              subtitle: const Text("Distance: 1.2km away"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Navigate to the shared map page but with 'responder' mode
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const EmergencyMapPage(isResponder: true),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
