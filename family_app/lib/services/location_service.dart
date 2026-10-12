import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import '../config/api_config.dart';

class LocationService {
  static const String baseUrl = ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> updateLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final token = await AuthService.getToken();

    final response = await http.post(
      Uri.parse('$baseUrl/location'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
      }),
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getFamilyLocations() async {
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/family/locations'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return jsonDecode(response.body);
  }
}