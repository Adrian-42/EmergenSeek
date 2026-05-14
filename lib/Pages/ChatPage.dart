import 'package:flutter/material.dart';
import 'package:emergenseek/services/socket_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // FIX: This was missing
import 'chatSelectorPage.dart';

class ChatPage extends StatefulWidget {
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;
  final String emergencyId;

  const ChatPage({
    super.key,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    required this.emergencyId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoadingHistory = true;
  late String roomId;

  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();
    // Unique Room ID logic
    List<String> ids = [widget.currentUserId, widget.otherUserId];
    ids.sort();
    roomId = ids.join("_");
    _initializeChat();
  }

  void _initializeChat() {
    SocketService().initSocket(widget.currentUserId);
    SocketService().socket.emit("join_private_chat", roomId);
    _loadChatHistory();

    SocketService().chatStream.listen((data) {
      if (mounted) {
        if (data['roomId'] == roomId) {
          if (data['senderId'] != widget.currentUserId) {
            setState(() {
              _messages.insert(0, {
                "text": data['text'] ?? data['message'] ?? "",
                "isMe": false,
                "timestamp": data['timestamp'] ?? DateTime.now().toString(),
              });
            });
          }
        }
      }
    });
  }

  Future<void> _loadChatHistory() async {
    final url = "$baseUrl/chat-history/$roomId";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _messages.clear();
            for (var item in data) {
              _messages.insert(0, {
                "text": item['text'] ?? item['message'] ?? "",
                "isMe": item['senderId'] == widget.currentUserId,
                "timestamp": item['timestamp'],
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
    final now = DateTime.now().toString();

    setState(() {
      _messages.insert(0, {"text": text, "isMe": true, "timestamp": now});
    });

    final payload = {
      "roomId": roomId,
      "senderId": widget.currentUserId,
      "receiverId": widget.otherUserId,
      "text": text,
      "timestamp": now,
    };

    SocketService().socket.emit("send_private_message", payload);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherUserName),
            const Text(
              "Private Secure Chat",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: "Switch Responder",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatSelectorPage(
                    emergencyId: widget.emergencyId,
                    currentUserId: widget.currentUserId,
                  ),
                ),
              );
            },
          ),
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
                ? const Center(child: Text("No messages yet. Send a greeting!"))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(15),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      bool isMe = msg['isMe'] ?? false;

                      String timeStr = "";
                      try {
                        DateTime dt = DateTime.parse(msg['timestamp']);
                        // DateFormat now works because of the import
                        timeStr = DateFormat('hh:mm a').format(dt);
                      } catch (e) {
                        timeStr = "";
                      }

                      return Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(top: 5, bottom: 2),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.redAccent
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(15)
                                    .copyWith(
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
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
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
