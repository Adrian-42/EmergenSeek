import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emergenseek/Pages/EmergencyMapPage.dart';
import 'package:emergenseek/Pages/responder_dashboard.dart';
import 'package:emergenseek/Pages/login_page.dart';

class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  Future<String?> _getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getUserRole(),
      builder: (context, snapshot) {
        // While checking storage, show a loading spinner
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final String? role = snapshot.data;

        // 1. If no role is found, they aren't logged in
        if (role == null) {
          return const LoginPage();
        }

        // 2. If they are a responder, send them to the dashboard
        if (role == "responder") {
          return const ResponderDashboard();
        }

        // 3. Default to the Emergency Map for victims
        return const EmergencyMapPage(isResponder: false);
      },
    );
  }
}
