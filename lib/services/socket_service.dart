import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  // Changed to nullable to prevent LateInitializationError
  IO.Socket? _socket;

  // Safe getter: if the socket isn't ready, it returns a dummy or triggers init
  IO.Socket get socket {
    if (_socket == null) {
      throw Exception("Socket not initialized. Call initSocket() first.");
    }
    return _socket!;
  }

  // Streams for UI updates
  final _locationStreamController = StreamController<LatLng>.broadcast();
  final _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<LatLng> get locationStream => _locationStreamController.stream;
  Stream<Map<String, dynamic>> get messageStream =>
      _messageStreamController.stream;

  void initSocket(String userId) {
    // Prevent multiple initializations
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

    _socket!.onConnect((_) => print('✅ Connected to EmergenSeek Socket'));

    // --- LISTENERS ---
    _socket!.on('location_received', (data) {
      if (data['lat'] != null && data['lng'] != null) {
        _locationStreamController.add(
          LatLng(data['lat'].toDouble(), data['lng'].toDouble()),
        );
      }
    });

    _socket!.on('message_received', (data) {
      _messageStreamController.add(data);
    });

    _socket!.onConnectError((err) => print('❌ Connection Error: $err'));
    _socket!.onDisconnect((_) => print('🔌 Disconnected from Server'));
  }

  void startEmergencyStreaming(String emergencyId) {
    socket.emit('join_emergency', emergencyId);
  }

  void sendLiveLocation(String emergencyId, double lat, double lng) {
    if (_socket?.connected ?? false) {
      _socket!.emit('update_location', {
        'emergencyId': emergencyId,
        'lat': lat,
        'lng': lng,
      });
    }
  }

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
    _socket?.dispose();
    _socket = null;
  }
}
