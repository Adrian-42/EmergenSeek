// lib/services/places_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class PlacesService {
  // Generic method to fetch nearby places of any type
  static Future<List> getNearbyPlaces(
    double lat,
    double lng,
    String type,
  ) async {
    final url = Uri.parse(
      'http://localhost:3000/places?lat=$lat&lng=$lng&type=$type',
    );

    final response = await http.get(url);
    final data = jsonDecode(response.body);

    return data['results'];
  }
}
