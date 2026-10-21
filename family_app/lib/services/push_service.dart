import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_helper.dart';
import 'auth_service.dart';

// =======================================================
// แจ้งเตือนเด้ง (Firebase Cloud Messaging)
//
// - เข้าหน้าหลัก → ขอสิทธิ์แจ้งเตือน แล้วลงทะเบียนเครื่องกับ Firebase
//   Firebase ให้รหัสเครื่อง (FID) มาทาง onRegistered → ส่งให้ Server เก็บไว้
//   (Server ผูกรหัสเครื่องกับการล็อกอินครั้งนั้น)
// - ออกจากระบบ / Session หมดอายุ → Server เลิกส่งมาเครื่องนี้เอง
//   แอปไม่ต้องยกเลิกกับ Firebase (ถ้าเน็ตหลุดกลางทาง เครื่องจะค้างสถานะ)
// - ตอนปิดแอป/อยู่เบื้องหลัง Android แสดงแจ้งเตือนให้เอง
//   ตอนเปิดแอปอยู่ หน้าหลักแสดงเป็นแถบข้อความแทน
// Firebase ใช้ไม่ได้ (เช่น ไม่มี google-services.json) → ข้ามทั้งหมด
// =======================================================

class PushService {
  static const String baseUrl = ApiConfig.baseUrl;

  static StreamSubscription<String>? _registered;

  // รหัสเครื่องที่ Firebase ให้มาแล้ว (ล็อกอินบัญชีใหม่ → ส่งซ้ำได้ทันที)
  static String? _deviceId;

  static bool get available => Firebase.apps.isNotEmpty;

  static FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  // =====================================================
  // ลงทะเบียนเครื่องนี้ (เรียกทุกครั้งที่เข้าหน้าหลัก)
  // =====================================================

  static Future<void> register() async {
    if (!available) return;

    try {
      // Android 13+ จะถามผู้ใช้ครั้งแรก (ไม่อนุญาต = ไม่เด้ง แต่ยังเห็นในแอป)
      await _messaging.requestPermission();

      _registered ??= _messaging.onRegistered.listen((deviceId) {
        _deviceId = deviceId;
        _sendDeviceId(deviceId).catchError((_) {});
      });

      // ออกจากระบบแล้วล็อกอินใหม่โดยไม่ปิดแอป → onRegistered อาจไม่มาอีก
      final String? known = _deviceId;
      if (known != null) await _sendDeviceId(known);

      await _messaging.register();
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  static Future<void> _sendDeviceId(String deviceId) async {
    final headers = await _headers();

    if (!headers.containsKey('Authorization')) return;

    await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/device-tokens'),
        headers: headers,
        body: jsonEncode({'token': deviceId, 'platform': _platform}),
      ),
    );
  }

  // =====================================================
  // กดแจ้งเตือน / แจ้งเตือนเข้าตอนเปิดแอป
  // =====================================================

  // แจ้งเตือนที่ใช้เปิดแอป (ตอนแอปปิดอยู่) — ได้ครั้งเดียว
  static Future<Map<String, dynamic>?> takeInitialMessage() async {
    if (!available) return null;

    final RemoteMessage? message = await _messaging.getInitialMessage();

    return message?.data;
  }

  // กดแจ้งเตือนตอนแอปอยู่เบื้องหลัง
  static Stream<RemoteMessage> get onOpened =>
      available ? FirebaseMessaging.onMessageOpenedApp : const Stream.empty();

  // แจ้งเตือนเข้าขณะเปิดแอปอยู่
  static Stream<RemoteMessage> get onForeground =>
      available ? FirebaseMessaging.onMessage : const Stream.empty();
}
