import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

class ProfileService {
  static const String baseUrl = ApiConfig.baseUrl;

  // =====================================================
  // JSON HEADERS
  // =====================================================

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',

      'Content-Type': 'application/json',

      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // =====================================================
  // MULTIPART HEADERS
  // ไม่ใส่ Content-Type
  // เพราะ MultipartRequest จะสร้างให้เอง
  // =====================================================

  static Future<Map<String, String>> _multipartHeaders() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',

      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // =====================================================
  // GET PROFILE
  // =====================================================

  static Future<Map<String, dynamic>> getProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/profile'),

      headers: await _headers(),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // UPDATE NAME
  // =====================================================

  static Future<Map<String, dynamic>> updateProfile({
    required String name,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/profile'),

      headers: await _headers(),

      body: jsonEncode({'name': name}),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // UPDATE PASSWORD
  // =====================================================

  static Future<Map<String, dynamic>> updatePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/profile/password'),

      headers: await _headers(),

      body: jsonEncode({
        'current_password': currentPassword,

        'password': password,

        'password_confirmation': passwordConfirmation,
      }),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // UPLOAD PROFILE PHOTO
  // =====================================================

  static Future<Map<String, dynamic>> uploadProfilePhoto(
    String filePath,
  ) async {
    final request = http.MultipartRequest(
      'POST',

      Uri.parse('$baseUrl/profile/photo'),
    );

    request.headers.addAll(await _multipartHeaders());

    request.files.add(await http.MultipartFile.fromPath('photo', filePath));

    final streamedResponse = await request.send();

    final response = await http.Response.fromStream(streamedResponse);

    return ApiHelper.decode(response);
  }

  // =====================================================
  // DELETE PROFILE PHOTO
  // =====================================================

  static Future<Map<String, dynamic>> deleteProfilePhoto() async {
    final response = await http.delete(
      Uri.parse('$baseUrl/profile/photo'),

      headers: await _headers(),
    );

    return ApiHelper.decode(response);
  }
}
