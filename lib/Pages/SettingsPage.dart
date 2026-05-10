import 'dart:convert';
import 'package:emergenseek/Pages/home_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final String baseUrl = "https://emergenseek.onrender.com";

  // Form Keys
  final _contactFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // --- PERSISTENCE: LOAD DATA ---
  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load local data first for immediate display
    setState(() {
      _emailController.text = prefs.getString('emergencyEmail') ?? '';
      _phoneController.text = prefs.getString('emergencyPhone') ?? '';
    });

    // Fetch latest data from server to keep it dynamic
    final userId = prefs.getString('userId');
    if (userId != null) {
      try {
        final response = await http.get(Uri.parse("$baseUrl/user/$userId"));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> contacts = data['emergencyContacts'] ?? [];
          if (contacts.isNotEmpty) {
            setState(() {
              _emailController.text =
                  contacts[0]['email'] ?? _emailController.text;
              _phoneController.text =
                  contacts[0]['phone'] ?? _phoneController.text;
            });
            // Update local cache to match server
            await prefs.setString('emergencyEmail', _emailController.text);
            await prefs.setString('emergencyPhone', _phoneController.text);
          }
        }
      } catch (e) {
        debugPrint("Sync error: $e");
      }
    }
  }

  // --- LOGIC: UPDATE EMERGENCY CONTACTS ---
  Future<void> _updateContacts() async {
    if (!_contactFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    try {
      // Update locally
      await prefs.setString('emergencyEmail', _emailController.text);
      await prefs.setString('emergencyPhone', _phoneController.text);

      // Update server
      if (userId != null) {
        await http.put(
          Uri.parse("$baseUrl/user/update-contacts"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "userId": userId,
            "emergencyContacts": [
              {"email": _emailController.text, "phone": _phoneController.text},
            ],
          }),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Emergency contacts updated!")),
      );
    } catch (e) {
      debugPrint("Update error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: CHANGE PASSWORD ---
  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    try {
      final response = await http.put(
        Uri.parse("$baseUrl/user/change-password"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "oldPassword": _oldPasswordController.text,
          "newPassword": _newPasswordController.text,
        }),
      );

      if (response.statusCode == 200) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password changed successfully!")),
        );
      } else {
        final error = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error['message'] ?? "Failed to change password"),
          ),
        );
      }
    } catch (e) {
      debugPrint("Password error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: LOGOUT ---
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();

    // COMPLETELY clear all user data
    await prefs.clear();

    if (mounted) {
      // Navigate to a clean slate. This forces HomeWrapper to rebuild.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeWrapper()),
        (route) => false,
      );
    }
  }

  // --- VALIDATORS ---
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return "Required";
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(value) ? null : "Enter a valid email";
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return "Required";
    // Philippine Regex: Supports 09xxxxxxxxx or +639xxxxxxxxx
    final regex = RegExp(r'^(09|\+639)\d{9}$');
    return regex.hasMatch(value) ? null : "Invalid PH format (09123456789)";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- EMERGENCY CONTACT SECTION ---
                  const Text(
                    "Emergency Contacts",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _contactFormKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: "Contact Email",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: "Contact Phone (PH)",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone_android),
                            hintText: "09xxxxxxxxx",
                          ),
                          keyboardType: TextInputType.phone,
                          validator: _validatePhone,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _updateContacts,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Save Contacts"),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(),
                  ),

                  // --- PASSWORD SECTION ---
                  const Text(
                    "Security",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _passwordFormKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _oldPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "Current Password",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (v) => v!.isEmpty ? "Required" : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "New Password",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_reset),
                          ),
                          validator: (v) =>
                              v!.length < 6 ? "Minimum 6 characters" : null,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _changePassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black87,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Update Password"),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- LOGOUT SECTION ---
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text(
                        "Logout",
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
