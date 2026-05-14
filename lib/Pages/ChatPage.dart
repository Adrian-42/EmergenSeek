import 'package:flutter/material.dart';
import 'package:emergenseek/services/socket_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String? _currentUserName;

  final String baseUrl = "https://emergenseek.onrender.com";

  @override
  void initState() {
    super.initState();

    List<String> ids = [widget.currentUserId, widget.otherUserId];
    ids.sort();
    roomId = ids.join("_");

    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserName = prefs.getString('userName') ?? "Resident";

    SocketService().initSocket(widget.currentUserId);

    Future.delayed(const Duration(milliseconds: 500), () {
      // USE THE PRIVATE JOIN EVENT
      SocketService().socket.emit("join_private_chat", roomId);
    });

    _loadChatHistory();

    SocketService().chatStream.listen((data) {
      if (mounted) {
        // Now checking against our unique pair roomId
        if (data['roomId'] == roomId) {
          final incomingSenderId = data['senderId'] is Map
              ? data['senderId']['_id'].toString()
              : data['senderId'].toString();

          setState(() {
            bool isMe = incomingSenderId == widget.currentUserId.toString();
            if (!isMe) {
              _messages.insert(0, {
                "text": data['text'] ?? data['message'] ?? "",
                "isMe": false,
                "timestamp":
                    data['timestamp'] ?? DateTime.now().toIso8601String(),
              });
            }
          });
        }
      }
    });
  }

  Future<void> _loadChatHistory() async {
    final url = "$baseUrl/chat-history/$roomId";
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 15),
          ); // Increased timeout for Render wake-up

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _messages.clear();
            for (var item in data) {
              final senderId = item['senderId'] is Map
                  ? item['senderId']['_id']
                  : item['senderId'];

              _messages.insert(0, {
                "text": item['text'] ?? item['message'] ?? "",
                "isMe": senderId.toString() == widget.currentUserId.toString(),
                "timestamp":
                    item['timestamp'] ??
                    item['createdAt'] ??
                    DateTime.now().toIso8601String(),
              });
            }
            _isLoadingHistory = false;
          });
        }
      } else {
        debugPrint("Server returned ${response.statusCode}. Starting fresh.");
        if (mounted) setState(() => _isLoadingHistory = false);
      }
    } catch (e) {
      debugPrint("Error loading history: $e");
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _handleSend() {
    if (_messageController.text.trim().isEmpty) return;
    final text = _messageController.text.trim();
    final now = DateTime.now().toIso8601String();

    setState(() {
      _messages.insert(0, {"text": text, "isMe": true, "timestamp": now});
    });

    final payload = {
      "roomId": roomId,
      "emergencyId": widget.emergencyId,
      "senderId": widget.currentUserId,
      "receiverId": widget.otherUserId,
      "text": text,
      "senderName": _currentUserName,
      "timestamp": now,
    };

    if (SocketService().socket.connected) {
      SocketService().socket.emit("send_private_message", payload);
    }
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              "Private Secure Chat",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
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
      body: Container(
        color: const Color(0xFFF5F5F5),
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty && !_isLoadingHistory
                  ? const Center(
                      child: Text("No messages yet. Send a greeting!"),
                    )
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
                          timeStr = DateFormat('hh:mm a').format(dt);
                        } catch (e) {
                          timeStr = "Just now";
                        }

                        return _buildChatBubble(msg['text'], isMe, timeStr);
                      },
                    ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isMe, String time) {
    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(top: 5, bottom: 2),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isMe ? Colors.redAccent : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
              borderRadius: BorderRadius.circular(15).copyWith(
                bottomRight: isMe ? Radius.zero : const Radius.circular(15),
                bottomLeft: isMe ? const Radius.circular(15) : Radius.zero,
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            time,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onSubmitted: (_) => _handleSend(), // Send on keyboard 'enter'
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _handleSend,
              child: const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.redAccent,
                child: Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
