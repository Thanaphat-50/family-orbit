import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() {
    return message;
  }
}

class SessionExpiredException extends ApiException {
  SessionExpiredException()
      : super(
          'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่',
        );
}

class ApiHelper {
  static const Duration timeout =
      Duration(seconds: 10);

  // ฟังก์ชันนี้จะถูกกำหนดจาก main.dart
  static Future<void> Function()? onUnauthorized;

  static bool _handlingUnauthorized = false;

  // =====================================================
  // จัดการเมื่อ Token หมดอายุ
  // =====================================================

  static Future<void> _handleUnauthorized() async {
    if (_handlingUnauthorized) {
      return;
    }

    _handlingUnauthorized = true;

    try {
      if (onUnauthorized != null) {
        await onUnauthorized!();
      }
    } finally {
      await Future.delayed(
        const Duration(seconds: 1),
      );

      _handlingUnauthorized = false;
    }
  }

  // =====================================================
  // ส่ง Request
  // timeLimit: เวลารอสูงสุดของ Request นี้
  // (เช่น อัปโหลดรูปใช้นานกว่าปกติ)
  // =====================================================

  static Future<http.Response> request(
    Future<http.Response> Function() action, {
    Duration? timeLimit,
  }) async {
    try {
      return await action().timeout(timeLimit ?? timeout);
    } on SocketException {
      throw ApiException(
        'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้\n'
        'กรุณาตรวจสอบว่า Laravel Server เปิดอยู่',
      );
    } on TimeoutException {
      throw ApiException(
        'เซิร์ฟเวอร์ตอบสนองช้าเกินไป กรุณาลองใหม่',
      );
    } on http.ClientException {
      throw ApiException(
        'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้',
      );
    } catch (e) {
      if (e is ApiException) {
        rethrow;
      }

      throw ApiException(
        'เกิดข้อผิดพลาดในการเชื่อมต่อ',
      );
    }
  }

  // =====================================================
  // แปลง Response เป็น JSON
  // =====================================================

  static Map<String, dynamic> decode(
    http.Response response,
  ) {
    Map<String, dynamic>? data;

    try {
      if (response.body.trim().isNotEmpty) {
        final decoded =
            jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      }
    } catch (_) {
      data = null;
    }

    // ===================================================
    // Token หมดอายุ / ไม่มีสิทธิ์ Login
    // ===================================================

    if (response.statusCode == 401) {
      _handleUnauthorized();

      throw SessionExpiredException();
    }

    // ===================================================
    // Server Error
    // ===================================================

    if (response.statusCode >= 500) {
      throw ApiException(
        'เซิร์ฟเวอร์เกิดข้อผิดพลาด กรุณาลองใหม่ภายหลัง',
      );
    }

    if (data != null) {
      return data;
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300) {
      return {
        'status': true,
      };
    }

    throw ApiException(
      'ไม่สามารถอ่านข้อมูลจากเซิร์ฟเวอร์ได้',
    );
  }
}