import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emergenseek/services/socket_service.dart'; // Ensure this is imported

// Import your existing pages
import 'EmergencyMapPage.dart';
import 'responder_dashboard.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": emailController.text.trim(),
          "password": passwordController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // 1. Save Session Data
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('userId', data['userId']);
        await prefs.setString('role', data['role']);
        await prefs.setString('userName', data['name'] ?? "User");

        // --- THE CRITICAL FIX ---
        // Initialize the socket immediately using the userId from the response
        // This ensures the SocketService is ready before the next screen loads.
        SocketService().initSocket(data['userId']);
        // -------------------------

        if (!mounted) return;

        // 2. Role-Based Routing
        if (data['role'] == 'responder') {
          print("✅ Socket Initialized & Redirecting to Responder Dashboard...");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ResponderDashboard()),
          );
        } else {
          print("✅ Socket Initialized & Redirecting to Victim Map...");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const EmergencyMapPage(isResponder: false),
            ),
          );
        }
      } else {
        _showError(data['error'] ?? "Login Failed");
      }
    } catch (e) {
      print("Login Error: $e");
      _showError("Connection error. Is the server running?");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("EmergenSeek"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Form(
          key: _formKey,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shield_rounded, size: 80, color: Colors.red),
                  const SizedBox(height: 20),
                  const Text(
                    "Welcome Back",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "Login to your account",
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 40),

                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) =>
                        (value == null || !value.contains("@"))
                        ? "Enter a valid email"
                        : null,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    validator: (value) => (value == null || value.length < 6)
                        ? "Password must be at least 6 characters"
                        : null,
                    decoration: const InputDecoration(
                      labelText: "Password",
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 30),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isLoading ? null : loginUser,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "LOGIN",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?"),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, "/signup"),
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
