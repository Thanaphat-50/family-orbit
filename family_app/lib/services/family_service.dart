import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

class FamilyService {
  static const String baseUrl = ApiConfig.baseUrl;

  // =====================================================
  // Header
  // =====================================================

  static Future<Map<String, String>>
      _headers({
    bool json = false,
  }) async {
    final token =
        await AuthService.getToken();

    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] =
          'Bearer $token';
    }

    if (json) {
      headers['Content-Type'] =
          'application/json';
    }

    return headers;
  }

  // =====================================================
  // ดู Family ปัจจุบัน
  // =====================================================

  static Future<Map<String, dynamic>>
      getCurrentFamily() async {
    final headers =
        await _headers();

    final response =
        await ApiHelper.request(
      () => http.get(
        Uri.parse(
          '$baseUrl/families/current',
        ),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // สร้าง Family
  // =====================================================

  static Future<Map<String, dynamic>>
      createFamily({
    required String name,
  }) async {
    final headers =
        await _headers(json: true);

    final response =
        await ApiHelper.request(
      () => http.post(
        Uri.parse(
          '$baseUrl/families',
        ),
        headers: headers,
        body: jsonEncode({
          'name': name,
        }),
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // Join Family
  // =====================================================

  static Future<Map<String, dynamic>>
      joinFamily({
    required String inviteCode,
  }) async {
    final headers =
        await _headers(json: true);

    final response =
        await ApiHelper.request(
      () => http.post(
        Uri.parse(
          '$baseUrl/families/join',
        ),
        headers: headers,
        body: jsonEncode({
          'invite_code': inviteCode,
        }),
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // เปลี่ยนชื่อ Family
  // =====================================================

  static Future<Map<String, dynamic>>
      updateFamilyName({
    required int familyId,
    required String name,
  }) async {
    final headers =
        await _headers(json: true);

    final response =
        await ApiHelper.request(
      () => http.put(
        Uri.parse(
          '$baseUrl/families/$familyId',
        ),
        headers: headers,
        body: jsonEncode({
          'name': name,
        }),
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // สร้าง Invite Code ใหม่
  // =====================================================

  static Future<Map<String, dynamic>>
      regenerateInviteCode() async {
    final headers =
        await _headers();

    final response =
        await ApiHelper.request(
      () => http.post(
        Uri.parse(
          '$baseUrl/families/regenerate-code',
        ),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // นำ Member ออก
  // =====================================================

  static Future<Map<String, dynamic>>
      removeMember({
    required int userId,
  }) async {
    final headers =
        await _headers();

    final response =
        await ApiHelper.request(
      () => http.delete(
        Uri.parse(
          '$baseUrl/families/members/$userId',
        ),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // ออกจาก Family
  // =====================================================

  static Future<Map<String, dynamic>>
      leaveFamily() async {
    final headers =
        await _headers();

    final response =
        await ApiHelper.request(
      () => http.post(
        Uri.parse(
          '$baseUrl/families/leave',
        ),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // โอน Owner
  // =====================================================

  static Future<Map<String, dynamic>>
      transferOwner({
    required int userId,
  }) async {
    final headers =
        await _headers();

    final response =
        await ApiHelper.request(
      () => http.post(
        Uri.parse(
          '$baseUrl/families/transfer-owner/$userId',
        ),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // ลบ Family
  // =====================================================

  static Future<Map<String, dynamic>>
      deleteFamily() async {
    final headers =
        await _headers();

    final response =
        await ApiHelper.request(
      () => http.delete(
        Uri.parse(
          '$baseUrl/families/current',
        ),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }
}