import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emergenseek/services/socket_service.dart';

// Import your Pages
import 'Pages/login_page.dart';
import 'Pages/signup_page.dart';
import 'Pages/splash_screen.dart';
import 'Pages/EmergencyMapPage.dart';
import 'Pages/responder_dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // Required for SharedPreferences/Sockets
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/home_wrapper': (context) => const HomeWrapper(),
      },
    );
  }
}

/// This widget acts as the router and initializes global services
class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  // Updated to also fetch the userId for the Socket initialization
  Future<Map<String, String?>> _getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'role': prefs.getString('role'),
      'token': prefs.getString('token'),
      'userId': prefs.getString('userId'), // Ensure you save this during login!
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String?>>(
      future: _getUserSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.red)),
          );
        }

        final session = snapshot.data;
        final String? role = session?['role'];
        final String? token = session?['token'];
        final String? userId = session?['userId'];

        // 1. If no token, send to Login
        if (token == null || token.isEmpty) {
          return const LoginPage();
        }

        // 2. Initialize Socket Service before showing the dashboard/map
        // This prevents the "LateInitializationError"
        if (userId != null) {
          SocketService().initSocket(userId);
        }

        // 3. Redirect based on role
        if (role == 'responder') {
          return const ResponderDashboard();
        } else {
          return const EmergencyMapPage();
        }
      },
    );
  }
}
