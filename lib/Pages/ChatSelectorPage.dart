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

  // The base URL for your Render deployment
  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    _fetchResponders();
  }

  Future<void> _fetchResponders() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final url = Uri.parse(
        "$baseUrl/emergency/responders/${widget.emergencyId}",
      );
      debugPrint("📡 Fetching Responders from: $url");

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _responders = data is List ? data : (data['responders'] ?? []);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = "Server returned ${response.statusCode}.";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Connection Error: $e");
      if (mounted) {
        setState(() {
          _errorMessage =
              "Could not connect to server. Please check your internet.";
          _isLoading = false;
        });
      }
    }
  }

  // Helper to generate a consistent Room ID (Alphabetical sort)
  String _generateRoomId(String id1, String id2) {
    List<String> ids = [id1, id2];
    ids.sort(); // Ensures UserA_UserB is the same as UserB_UserA
    return ids.join("_");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Active Responders"),
        backgroundColor: Colors.redAccent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchResponders,
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _fetchResponders, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 10),
            Text(_errorMessage, textAlign: TextAlign.center),
            TextButton(onPressed: _fetchResponders, child: const Text("Retry")),
          ],
        ),
      );
    }

    // Filter out the current user if they are in the list
    final otherResponders = _responders
        .where((r) => r['_id'] != widget.currentUserId)
        .toList();

    if (otherResponders.isEmpty) {
      return ListView(
        // Wrap in ListView for RefreshIndicator to work
        children: const [
          SizedBox(height: 100),
          Center(
            child: Text(
              "No other responders found yet.\nWaiting for someone to join...",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      itemCount: otherResponders.length,
      itemBuilder: (context, index) {
        final responder = otherResponders[index];

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: const CircleAvatar(
              radius: 25,
              backgroundColor: Colors.blueAccent,
              child: Icon(Icons.person, color: Colors.white, size: 30),
            ),
            title: Text(
              responder['name'] ?? "Responder ${index + 1}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Available for private coordination"),
                if (responder['phoneNumber'] != null)
                  Text(
                    responder['phoneNumber'],
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            trailing: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.blueAccent,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatPage(
                    currentUserId: widget.currentUserId,
                    otherUserId: responder['_id'],
                    otherUserName: responder['name'] ?? "Responder",
                    emergencyId: widget.emergencyId,
                    // Pass a consistent roomId based on sorted IDs
                    roomId: _generateRoomId(
                      widget.currentUserId,
                      responder['_id'],
                    ),
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
