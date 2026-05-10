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

  final _personalFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  final TextEditingController _personalPhoneController =
      TextEditingController();
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  List<dynamic> _emergencyContacts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    if (userId != null) {
      try {
        final response = await http.get(Uri.parse("$baseUrl/user/$userId"));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            _personalPhoneController.text = data['phoneNumber'] ?? '';
            _emergencyContacts = data['emergencyContacts'] ?? [];
          });
        }
      } catch (e) {
        debugPrint("Load error: $e");
      }
    }
  }

  // --- LOGIC: ADD/UPDATE CONTACTS ---
  void _showContactDialog({int? index}) {
    final emailCtrl = TextEditingController(
      text: index != null ? _emergencyContacts[index]['email'] : '',
    );
    final phoneCtrl = TextEditingController(
      text: index != null ? _emergencyContacts[index]['phone'] : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? "Add Contact" : "Edit Contact"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: "Phone"),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                final newContact = {
                  "email": emailCtrl.text,
                  "phone": phoneCtrl.text,
                };
                if (index == null) {
                  _emergencyContacts.add(newContact);
                } else {
                  _emergencyContacts[index] = newContact;
                }
              });
              _syncContacts();
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _syncContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    await http.put(
      Uri.parse("$baseUrl/user/update-contacts"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "emergencyContacts": _emergencyContacts,
      }),
    );
  }

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

      final result = jsonDecode(response.body);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result['message'])));
      if (response.statusCode == 200) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeWrapper()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Settings"),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSectionHeader("Personal Information"),
                  _buildCard(
                    child: Form(
                      key: _personalFormKey,
                      child: TextFormField(
                        controller: _personalPhoneController,
                        decoration: const InputDecoration(
                          labelText: "My Phone Number",
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                    ),
                  ),

                  _buildSectionHeader("Emergency Contacts"),
                  _buildCard(
                    child: Column(
                      children: [
                        ..._emergencyContacts.asMap().entries.map((entry) {
                          int idx = entry.key;
                          var contact = entry.value;
                          return ListTile(
                            title: Text(contact['email']),
                            subtitle: Text(contact['phone']),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(
                                  () => _emergencyContacts.removeAt(idx),
                                );
                                _syncContacts();
                              },
                            ),
                            onTap: () => _showContactDialog(index: idx),
                          );
                        }),
                        TextButton.icon(
                          onPressed: () => _showContactDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text("Add New Contact"),
                        ),
                      ],
                    ),
                  ),

                  _buildSectionHeader("Security"),
                  _buildCard(
                    child: Form(
                      key: _passwordFormKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _oldPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "Old Password",
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "New Password",
                            ),
                          ),
                          const SizedBox(height: 15),
                          ElevatedButton(
                            onPressed: _changePassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black87,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Update Password"),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text(
                      "Logout",
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
        ),
      ),
    ),
  );

  Widget _buildCard({required Widget child}) => Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}
