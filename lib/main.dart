import 'package:flutter/material.dart';
import 'Pages/login_page.dart';
import 'Pages/signup_page.dart';
import 'Pages/splash_screen.dart';

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
      theme: ThemeData(primarySwatch: Colors.red),
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
      },
    );
  }
}
