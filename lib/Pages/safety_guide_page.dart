import 'package:flutter/material.dart';

class SafetyGuidePage extends StatelessWidget {
  const SafetyGuidePage({super.key});

  final List<Map<String, dynamic>> _stationTips = const [
    {
      "title": "Hospital / Medical",
      "icon": Icons.local_hospital,
      "color": Colors.red,
      "tips": [
        "Apply pressure to any bleeding wounds using a clean cloth.",
        "Do not move someone with a suspected neck or back injury.",
        "Keep a list of your allergies and medications ready for the doctor.",
      ],
    },
    {
      "title": "Police Station",
      "icon": Icons.local_police,
      "color": Colors.blue,
      "tips": [
        "Stay in a well-lit, public area while waiting for a responder.",
        "Take note of descriptions: height, clothing, or plate numbers.",
        "Do not attempt to confront an armed individual yourself.",
      ],
    },
    {
      "title": "Fire Station",
      "icon": Icons.local_fire_department,
      "color": Colors.orange,
      "tips": [
        "Stay low to the ground to avoid inhaling toxic smoke.",
        "Check doors for heat with the back of your hand before opening.",
        "Once outside, stay outside. Never go back into a burning building.",
      ],
    },
  ];

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
            "Connecting you to nearby responders and life-saving facilities in real-time.",
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 30),

          // --- SECTION: STEPS ---
          _buildStep(
            number: "1",
            title: "Find Nearby Help",
            desc:
                "Use the category buttons (Medical, Police, Fire) to find the nearest emergency facilities. Navigate directly to them with one tap.",
            icon: Icons.map_outlined,
          ),
          _buildStep(
            number: "2",
            title: "Request Live Assistance",
            desc:
                "Switch your status to 'Help Needed'. This broadcasts your live location to active responders on the platform.",
            icon: Icons.record_voice_over_outlined,
          ),
          _buildStep(
            number: "3",
            title: "Direct Responder Chat",
            desc:
                "Once a responder is assigned, tap the Chat icon. You can coordinate your rescue and send details through our private channel.",
            icon: Icons.chat_bubble_outline,
          ),
          _buildStep(
            number: "4",
            title: "Real-Time Tracking",
            desc:
                "Responders see your live movement on their map. Keep the app open so they can find your exact position efficiently.",
            icon: Icons.track_changes,
          ),

          const Divider(height: 50),

          // --- SECTION: STATION REMINDERS ---
          const Text(
            "🚨 Station-Specific Reminders",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          ..._stationTips.map(
            (station) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ExpansionTile(
                leading: Icon(station['icon'], color: station['color']),
                title: Text(
                  station['title'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                children: (station['tips'] as List<String>)
                    .map(
                      (t) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.arrow_right, size: 18),
                        title: Text(t),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),

          const Divider(height: 50),

          // --- SECTION: EXPERT TIPS ---
          const Text(
            "💡 Pro Safety Tips",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          _buildTip("Keep 'High Accuracy' GPS enabled for precise tracking."),
          _buildTip(
            "Check your data connection before requesting a responder.",
          ),
          _buildTip(
            "Use the 'Navigate' button for the fastest route to a hospital.",
          ),
          _buildTip("Switch back to 'I am Safe' once help arrives."),
          _buildTip(
            "If a responder messages you, you will see a notification pop-up at the top of your map.",
          ),
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
            backgroundColor: Colors.blueAccent,
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
                    Icon(icon, size: 20, color: Colors.blueAccent),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: Colors.green,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
