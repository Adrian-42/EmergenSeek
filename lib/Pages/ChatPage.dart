import 'package:flutter/material.dart';
import 'package:emergenseek/services/socket_service.dart';

class ChatPage extends StatefulWidget {
  final String
  emergencyId; // The ID of the emergency room (usually victim's userId)
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

  @override
  void initState() {
    super.initState();
    // 1. Connect and join the room
    SocketService().initSocket(widget.currentUserId);
    SocketService().startEmergencyStreaming(widget.emergencyId);

    // 2. Listen for incoming messages
    SocketService().chatStream.listen((data) {
      if (mounted) {
        setState(() {
          // Add to start of list for 'reverse' ListView
          _messages.insert(0, {
            "text": data['text'] ?? "",
            "isMe": data['senderId'] == widget.currentUserId,
          });
        });
      }
    });
  }

  void _handleSend() {
    if (_messageController.text.trim().isEmpty) return;

    final text = _messageController.text.trim();

    // 3. Send message via the service
    SocketService().sendMessage(widget.emergencyId, text, widget.currentUserId);

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Chat"),
        backgroundColor: Colors.redAccent,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true, // Newest messages at bottom
              padding: const EdgeInsets.all(15),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                bool isMe = msg['isMe'];

                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.redAccent : Colors.grey[300],
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      msg['text'],
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: "Describe your situation...",
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.redAccent),
            onPressed: _handleSend,
          ),
        ],
      ),
    );
  }
}
