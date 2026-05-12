import 'package:flutter/material.dart';

class SafetyGuidePage extends StatelessWidget {
  const SafetyGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("How EmergenSeek Works"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Welcome to EmergenSeek",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            "Your personal safety net in the palm of your hand. Follow these steps to ensure you're protected.",
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 30),

          _buildStep(
            number: "1",
            title: "Configure Contacts",
            desc:
                "Go to Profile and add your trusted emergency contacts. We will notify them via email if you are in danger.",
            icon: Icons.people_alt_outlined,
          ),
          _buildStep(
            number: "2",
            title: "Trigger the SOS",
            desc:
                "In an emergency, press the large SOS button. It instantly sends your live Google Maps location to your contacts.",
            icon: Icons.emergency_share,
          ),
          _buildStep(
            number: "3",
            title: "Stay or Move",
            desc:
                "Once triggered, your location updates in real-time. Responders can track your movement to find you faster.",
            icon: Icons.track_changes,
          ),
          _buildStep(
            number: "4",
            title: "Mark as Safe",
            desc:
                "Once the danger has passed, tap 'I am Safe' to stop the broadcast and notify the system.",
            icon: Icons.check_circle_outline,
          ),

          const Divider(height: 50),

          const Text(
            "💡 Expert Tips",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          _buildTip("Keep your GPS on 'High Accuracy' mode."),
          _buildTip("Ensure you have an active data plan for alerts."),
          _buildTip("Tell your contacts to whitelist emails from our domain."),
        ],
      ),
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String desc,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Colors.redAccent,
            radius: 14,
            child: Text(
              number,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(desc, style: const TextStyle(fontSize: 15, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(tip, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
