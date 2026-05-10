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

  Stream<LatLng> get locationStream => _locationStreamController.stream;
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
        if (data['lat'] != null && data['lng'] != null) {
          double lat = double.parse(data['lat'].toString());
          double lng = double.parse(data['lng'].toString());
          _locationStreamController.add(LatLng(lat, lng));
        }
      } catch (e) {
        print('❌ Error parsing location data: $e');
      }
    });

    // Listener for chat messages
    _socket!.on('message_received', (data) {
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

  /// Shared messaging function for both roles
  void sendMessage(String emergencyId, String text, String senderId) {
    if (_socket?.connected ?? false) {
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
