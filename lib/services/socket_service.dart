import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;

  // Streams to notify the UI when new data arrives
  final _locationStreamController = StreamController<LatLng>.broadcast();
  final _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<LatLng> get locationStream => _locationStreamController.stream;
  Stream<Map<String, dynamic>> get messageStream =>
      _messageStreamController.stream;

  void initSocket(String userId) {
    socket = IO.io(
      'https://emergenseek.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect() // Changed to true for better reliability
          .setQuery({
            'userId': userId,
          }) // Useful for the server to identify who connected
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print('✅ Connected to EmergenSeek Socket');
    });

    // --- LISTENERS ---

    // Listen for incoming location updates (For Responders)
    socket.on('location_received', (data) {
      if (data['lat'] != null && data['lng'] != null) {
        _locationStreamController.add(
          LatLng(data['lat'].toDouble(), data['lng'].toDouble()),
        );
      }
    });

    // Listen for incoming chat messages (Two-way)
    socket.on('message_received', (data) {
      _messageStreamController.add(data);
    });

    socket.onConnectError((err) => print('❌ Connection Error: $err'));
    socket.onDisconnect((_) => print('🔌 Disconnected from Server'));
  }

  // Victim: Call this when SOS is triggered
  void startEmergencyStreaming(String emergencyId) {
    socket.emit('join_emergency', emergencyId);
  }

  // Victim: Stream your GPS to the room
  void sendLiveLocation(String emergencyId, double lat, double lng) {
    if (socket.connected) {
      socket.emit('update_location', {
        'emergencyId': emergencyId,
        'lat': lat,
        'lng': lng,
      });
    }
  }

  // Responder & Victim: Two-way Chat
  void sendMessage(String emergencyId, String text, String senderId) {
    if (socket.connected) {
      socket.emit('send_message', {
        'emergencyId': emergencyId,
        'senderId': senderId,
        'text': text,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  void dispose() {
    _locationStreamController.close();
    _messageStreamController.close();
    socket.dispose();
  }
}
