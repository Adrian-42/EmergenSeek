import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your Pages
import 'Pages/login_page.dart';
import 'Pages/signup_page.dart';
import 'Pages/splash_screen.dart';
import 'Pages/EmergencyMapPage.dart';
import 'Pages/responder_dashboard.dart';

void main() {
  runApp(const EmergenseekApp());
}

class EmergenseekApp extends StatelessWidget {
  const EmergenseekApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Emergenseek",
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true, // Recommended for modern Flutter UI
      ),
      // The app starts with the SplashScreen
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/home_wrapper': (context) => const HomeWrapper(),
      },
    );
  }
}

/// This widget acts as the router between Victim and Responder views
class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  Future<Map<String, String?>> _getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {'role': prefs.getString('role'), 'token': prefs.getString('token')};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String?>>(
      future: _getUserSession(),
      builder: (context, snapshot) {
        // Show a loading indicator while reading SharedPreferences
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.red)),
          );
        }

        final session = snapshot.data;
        final String? role = session?['role'];
        final String? token = session?['token'];

        // 1. Check if user is logged in (has a token)
        if (token == null || token.isEmpty) {
          return const LoginPage();
        }

        // 2. Redirect based on role
        if (role == 'responder') {
          return const ResponderDashboard();
        } else {
          // Default to Victim view (Map)
          return const EmergencyMapPage(isResponder: false);
        }
      },
    );
  }
}
