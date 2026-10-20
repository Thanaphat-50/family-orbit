import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

// =======================================================
// ตั้งค่าของผู้ใช้ (เก็บที่ Server)
// - location_sharing: แชร์ตำแหน่งกับครอบครัว
// - notifications:    เปิด/ปิดการแจ้งเตือนแต่ละประเภท
// =======================================================

class SettingsService {
  static const String baseUrl = ApiConfig.baseUrl;

  // ค่าล่าสุดที่รู้ (null = ยังไม่ได้โหลด → ถือว่าเปิดแชร์)
  // หน้าอื่น เช่น แผนที่ ฟังค่านี้ได้
  static final ValueNotifier<bool?> locationSharing = ValueNotifier<bool?>(
    null,
  );

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // GET /api/settings
  static Future<Map<String, dynamic>> getSettings() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(Uri.parse('$baseUrl/settings'), headers: headers),
    );

    final result = ApiHelper.decode(response);

    _remember(result);

    return result;
  }

  // PUT /api/settings (ส่งเฉพาะค่าที่เปลี่ยน)
  static Future<Map<String, dynamic>> updateSettings({
    bool? locationSharing,
    Map<String, bool>? notifications,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.put(
        Uri.parse('$baseUrl/settings'),
        headers: headers,
        body: jsonEncode({
          'location_sharing': ?locationSharing,
          'notifications': ?notifications,
        }),
      ),
    );

    final result = ApiHelper.decode(response);

    _remember(result);

    return result;
  }

  static void _remember(Map<String, dynamic> result) {
    final dynamic settings = result['settings'];

    if (result['status'] == true && settings is Map) {
      locationSharing.value = settings['location_sharing'] != false;
    }
  }
}
