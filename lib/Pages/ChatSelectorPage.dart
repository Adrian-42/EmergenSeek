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
  String _errorMessage = "";

  // Verify if the endpoint should be /emergency/responders/ or /emergencies/responders/
  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    _fetchResponders();
  }

  Future<void> _fetchResponders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final url = Uri.parse(
        "$baseUrl/emergency/responders/${widget.emergencyId}",
      );
      debugPrint("Fetching from: $url");

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          // Ensure we are getting a list. If the backend returns an object with a list,
          // adjust this (e.g., data['responders'])
          _responders = data is List ? data : (data['responders'] ?? []);
          _isLoading = false;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _errorMessage = "Responder list not found (404). Check emergency ID.";
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Server error: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Connection Error: $e");
      setState(() {
        _errorMessage = "Could not connect to the server.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Active Responders"),
        backgroundColor: Colors.redAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchResponders,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (_responders.isEmpty) {
      return const Center(child: Text("Waiting for a responder to join..."));
    }

    return ListView.builder(
      itemCount: _responders.length,
      itemBuilder: (context, index) {
        final responder = _responders[index];

        // Skip showing yourself in the list
        if (responder['_id'] == widget.currentUserId) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ListTile(
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
          ),
        );
      },
    );
  }
}
