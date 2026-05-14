import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:emergenseek/Pages/ChatPage.dart';

class ChatSelectorPage extends StatefulWidget {
  final String emergencyId;
  final String currentUserId;

  const ChatSelectorPage({
    super.key,
    required this.emergencyId,
    required this.currentUserId,
  });

  @override
  State<ChatSelectorPage> createState() => _ChatSelectorPageState();
}

class _ChatSelectorPageState extends State<ChatSelectorPage> {
  List<dynamic> _responders = [];
  bool _isLoading = true;
  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    _fetchResponders();
  }

  Future<void> _fetchResponders() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/emergency/responders/${widget.emergencyId}"),
      );
      if (response.statusCode == 200) {
        setState(() {
          _responders = json.decode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Active Responders"),
        backgroundColor: Colors.redAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _responders.isEmpty
          ? const Center(child: Text("Waiting for a responder to join..."))
          : ListView.builder(
              itemCount: _responders.length,
              itemBuilder: (context, index) {
                final responder = _responders[index];
                if (responder['_id'] == widget.currentUserId)
                  return const SizedBox.shrink();

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(responder['name'] ?? "Unknown Responder"),
                  subtitle: const Text("Tap to chat privately"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatPage(
                          currentUserId: widget.currentUserId,
                          otherUserId: responder['_id'],
                          otherUserName: responder['name'] ?? "Responder",
                          emergencyId: widget.emergencyId,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
