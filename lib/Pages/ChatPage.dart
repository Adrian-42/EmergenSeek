import 'package:flutter/material.dart';
import 'package:emergenseek/services/socket_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatPage extends StatefulWidget {
  final String emergencyId;
  final String currentUserId;

  const ChatPage({
    super.key,
    required this.emergencyId,
    required this.currentUserId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoadingHistory = true;

  // Use your real base URL here
  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  void _initializeChat() {
    // 1. Connect and join the room
    SocketService().initSocket(widget.currentUserId);
    SocketService().startEmergencyStreaming(widget.emergencyId);

    // 2. Load the history from the database
    _loadChatHistory();

    // 3. Listen for new incoming messages
    SocketService().chatStream.listen((data) {
      if (mounted) {
        // RECENT FIX: Only add to list if the message is from the OTHER person.
        // We add our own messages immediately in _handleSend to avoid lag.
        if (data['senderId'] != widget.currentUserId) {
          setState(() {
            _messages.insert(0, {
              "text": data['text'] ?? data['message'] ?? "",
              "isMe": false,
            });
          });
        }
      }
    });
  }

  Future<void> _loadChatHistory() async {
    // RECENT FIX: Updated URL path to match backend: /emergency/chat/
    final url = "$baseUrl/emergency/chat/${widget.emergencyId}";

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        if (mounted) {
          setState(() {
            _messages.clear();
            // Backend sends oldest first now (due to .reverse() in Node.js)
            // But since our ListView is reversed, we insert at 0 to keep newest at bottom
            for (var item in data) {
              _messages.insert(0, {
                "text": item['text'] ?? item['message'] ?? "",
                "isMe": item['senderId'] == widget.currentUserId,
              });
            }
            _isLoadingHistory = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading chat history: $e");
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _handleSend() {
    if (_messageController.text.trim().isEmpty) return;
    final text = _messageController.text.trim();

    // RECENT FIX: Add to UI immediately so user sees their message
    setState(() {
      _messages.insert(0, {"text": text, "isMe": true});
    });

    // Send via socket (backend saves this to MongoDB)
    SocketService().sendMessage(widget.emergencyId, text, widget.currentUserId);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Chat"),
        backgroundColor: Colors.redAccent,
        actions: [
          if (_isLoadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 15),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_isLoadingHistory
                ? const Center(child: Text("No messages yet. Stay safe!"))
                : ListView.builder(
                    reverse: true, // Newest messages at the bottom
                    padding: const EdgeInsets.all(15),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      bool isMe = msg['isMe'] ?? false;

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.redAccent : Colors.grey[300],
                            borderRadius: BorderRadius.circular(15).copyWith(
                              bottomRight: isMe
                                  ? Radius.zero
                                  : const Radius.circular(15),
                              bottomLeft: isMe
                                  ? const Radius.circular(15)
                                  : Radius.zero,
                            ),
                          ),
                          child: Text(
                            msg['text'] ?? "",
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: "Type a message...",
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.redAccent,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _handleSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
