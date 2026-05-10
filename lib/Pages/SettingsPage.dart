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

  // --- VALIDATORS ---
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return "Required";
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(value) ? null : "Enter a valid email";
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return "Required";
    final regex = RegExp(r'^(09|\+639)\d{9}$');
    return regex.hasMatch(value) ? null : "Use 09xxxxxxxxx";
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId == null) return;

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

  Future<void> _updatePersonalPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    final response = await http.put(
      Uri.parse("$baseUrl/user/update-phone"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "phoneNumber": _personalPhoneController.text,
      }),
    );

    if (response.statusCode == 200) {
      // Optional: Save to local storage as well for offline speed
      await prefs.setString('userPhone', _personalPhoneController.text);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Phone saved to Database!")));
    }
  }

  // --- LOGIC: ADD/UPDATE CONTACTS ---
  // Update the contact dialog to include a Name field
  void _showContactDialog({int? index}) {
    final nameCtrl = TextEditingController(
      text: index != null ? _emergencyContacts[index]['name'] : '',
    );
    final emailCtrl = TextEditingController(
      text: index != null ? _emergencyContacts[index]['email'] : '',
    );
    final phoneCtrl = TextEditingController(
      text: index != null ? _emergencyContacts[index]['phone'] : '',
    );
    final dialogKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? "Add Contact" : "Edit Contact"),
        content: Form(
          key: dialogKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "Full Name"),
                  validator: (v) =>
                      v!.isEmpty ? "Name is required by database" : null,
                ),
                TextFormField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: "Email"),
                  validator: _validateEmail,
                ),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: "Phone"),
                  keyboardType: TextInputType.phone,
                  validator: _validatePhone,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (dialogKey.currentState!.validate()) {
                setState(() {
                  final newContact = {
                    "name": nameCtrl.text, // Added name
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
              }
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

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please login again.")),
      );
      return;
    }

    setState(() => _isLoading = true);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? "Error occurred")),
      );
      if (response.statusCode == 200) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network error. Try again.")),
      );
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
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _personalPhoneController,
                            validator: _validatePhone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: "My Phone Number",
                              prefixIcon: Icon(Icons.phone),
                              hintText: "09123456789",
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: _updatePersonalPhone,
                            child: const Text("Save Phone Number"),
                          ),
                        ],
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
                            validator: (v) => v!.isEmpty ? "Required" : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "New Password",
                            ),
                            validator: (v) =>
                                v!.length < 6 ? "Min 6 chars" : null,
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
