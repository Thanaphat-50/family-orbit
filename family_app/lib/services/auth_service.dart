import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class AuthService {
  static const String baseUrl = ApiConfig.baseUrl;

  static const FlutterSecureStorage _storage =
      FlutterSecureStorage();

  static const String _tokenKey = 'token';

  // =====================================================
  // Register
  // =====================================================

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/register',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation':
            passwordConfirmation,
      }),
    );

    final decoded =
        jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      return {
        'status': false,
        'message':
            'ข้อมูลที่ได้รับจาก Server ไม่ถูกต้อง',
      };
    }

    final data = decoded;

    if (data['token'] != null) {
      await _storage.write(
        key: _tokenKey,
        value: data['token'].toString(),
      );
    }

    return data;
  }

  // =====================================================
  // Login
  // =====================================================

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/login',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final decoded =
        jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      return {
        'status': false,
        'message':
            'ข้อมูลที่ได้รับจาก Server ไม่ถูกต้อง',
      };
    }

    final data = decoded;

    if (data['token'] != null) {
      await _storage.write(
        key: _tokenKey,
        value: data['token'].toString(),
      );
    }

    return data;
  }

  // =====================================================
  // บันทึก Token (เช่น เข้าสู่ระบบด้วย Google / LINE / Facebook)
  // =====================================================

  static Future<void> saveToken(String token) async {
    await _storage.write(
      key: _tokenKey,
      value: token,
    );
  }

  // =====================================================
  // อ่าน Token
  // =====================================================

  static Future<String?> getToken() async {
    return await _storage.read(
      key: _tokenKey,
    );
  }

  // =====================================================
  // เช็ก User ปัจจุบัน
  // =====================================================

  static Future<Map<String, dynamic>?>
      getCurrentUser() async {
    final token = await getToken();

    if (token == null) {
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/user',
        ),
        headers: {
          'Accept': 'application/json',
          'Authorization':
              'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }

      if (response.statusCode == 401) {
        await clearToken();

        return null;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // =====================================================
  // ลบ Token ในเครื่อง
  // =====================================================

  static Future<void> clearToken() async {
    await _storage.delete(
      key: _tokenKey,
    );
  }

  // =====================================================
  // Logout
  // =====================================================

  static Future<void> logout() async {
    final token = await getToken();

    try {
      if (token != null) {
        await http.post(
          Uri.parse(
            '$baseUrl/logout',
          ),
          headers: {
            'Accept': 'application/json',
            'Authorization':
                'Bearer $token',
          },
        );
      }
    } catch (_) {
      // Server ปิดก็ยัง Logout ในเครื่องได้
    } finally {
      await clearToken();
    }
  }
}