import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  // Streams for UI updates
  final _locationStreamController = StreamController<LatLng>.broadcast();
  final _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters for the streams
  Stream<LatLng> get locationStream => _locationStreamController.stream;

  // Aliasing messageStream to chatStream to match your Page code
  Stream<Map<String, dynamic>> get chatStream =>
      _messageStreamController.stream;
  Stream<Map<String, dynamic>> get messageStream =>
      _messageStreamController.stream;

  // Safe getter for the socket instance
  IO.Socket get socket {
    if (_socket == null) {
      throw Exception("Socket not initialized. Call initSocket(userId) first.");
    }
    return _socket!;
  }

  void initSocket(String userId) {
    if (_socket != null) return;

    _socket = IO.io(
      'https://emergenseek.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setQuery({'userId': userId})
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      print('✅ Connected to EmergenSeek Socket: $userId');
    });

    // --- LISTENERS ---

    // Listener for live location updates (Used by Responders)
    _socket!.on('location_received', (data) {
      try {
        // Updated to check for both 'lat'/'lng' and 'latitude'/'longitude'
        var latVal = data['lat'] ?? data['latitude'];
        var lngVal = data['lng'] ?? data['longitude'];

        if (latVal != null && lngVal != null) {
          double lat = double.parse(latVal.toString());
          double lng = double.parse(lngVal.toString());
          _locationStreamController.add(LatLng(lat, lng));
        }
      } catch (e) {
        print('❌ Error parsing location data: $e');
      }
    });

    _socket!.on('new_notification_$userId', (data) {
      print("🔔 Private Notification Received: ${data['text']}");
      _messageStreamController.add(data); // Push to the stream so the UI reacts
    });

    // Listener for chat messages
    _socket!.on('message_received', (data) {
      print("📩 Message Received: ${data['text']}");
      _messageStreamController.add(data);
    });

    _socket!.onConnectError((err) => print('❌ Connection Error: $err'));
    _socket!.onDisconnect((_) => print('🔌 Disconnected from Server'));
  }

  /// Called by Responders to join a specific victim's emergency room
  void startEmergencyStreaming(String emergencyId) {
    if (_socket?.connected ?? false) {
      print('📡 Joining Emergency Room: $emergencyId');
      _socket!.emit('join_emergency', emergencyId);
    }
  }

  /// Called by Citizens/Victims to push their live location to responders
  void sendLiveLocation(String userId, double lat, double lng) {
    if (_socket?.connected ?? false) {
      _socket!.emit('update_location', {
        'emergencyId': userId, // In your logic, the userId is the room ID
        'lat': lat,
        'lng': lng,
      });
    }
  }

  /// Alias for sendMessage to fix the "emitChatMessage isn't defined" error
  void emitChatMessage(String emergencyId, String text) {
    // Note: It's better to pass the actual ID, but keeping your signature
    sendMessage(emergencyId, text, "responder_internal_id");
  }

  void sendPrivateMessage(Map<String, dynamic> payload) {
    if (_socket?.connected ?? false) {
      print("📤 Sending Private Message: ${payload['text']}");
      // This must match the backend .on("send_private_message")
      _socket!.emit('send_private_message', payload);
    }
  }

  /// Shared messaging function for both roles
  void sendMessage(String emergencyId, String text, String senderId) {
    if (_socket?.connected ?? false) {
      print("📤 Sending Message: $text to Room: $emergencyId");
      _socket!.emit('send_message', {
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
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
