import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

// =======================================================
// ตะกร้าสินค้า + ที่อยู่จัดส่งของฉัน
// cartCount ใช้แสดงตัวเลขบนไอคอนตะกร้า
// =======================================================

class CartService {
  static const String baseUrl = ApiConfig.baseUrl;

  static final ValueNotifier<int> cartCount = ValueNotifier<int>(0);

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final headers = await _headers();
    final Uri uri = Uri.parse('$baseUrl$path');
    final String? encoded = body == null ? null : jsonEncode(body);

    final response = await ApiHelper.request(
      () => switch (method) {
        'POST' => http.post(uri, headers: headers, body: encoded),
        'PATCH' => http.patch(uri, headers: headers, body: encoded),
        'PUT' => http.put(uri, headers: headers, body: encoded),
        'DELETE' => http.delete(uri, headers: headers),
        _ => http.get(uri, headers: headers),
      },
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // ตะกร้า
  // =====================================================

  static Future<Map<String, dynamic>> getCart() async {
    final result = await _send('GET', '/cart');

    final num? count = result['count'] as num?;

    if (count != null) cartCount.value = count.toInt();

    return result;
  }

  static Future<void> refreshCount() async {
    try {
      final result = await _send('GET', '/cart/count');

      final num? count = result['count'] as num?;

      if (count != null) cartCount.value = count.toInt();
    } catch (_) {
      // เน็ตหลุด → ใช้ตัวเลขเดิม
    }
  }

  static Future<Map<String, dynamic>> addToCart({
    required int productId,
    int? variantId,
    int quantity = 1,
  }) async {
    final result = await _send('POST', '/cart', {
      'product_id': productId,
      'variant_id': ?variantId,
      'quantity': quantity,
    });

    final num? count = result['count'] as num?;

    if (count != null) cartCount.value = count.toInt();

    return result;
  }

  static Future<Map<String, dynamic>> setQuantity(
    int cartItemId,
    int quantity,
  ) {
    return _send('PATCH', '/cart/$cartItemId', {'quantity': quantity});
  }

  static Future<Map<String, dynamic>> remove(int cartItemId) {
    return _send('DELETE', '/cart/$cartItemId');
  }

  // =====================================================
  // ที่อยู่จัดส่ง
  // fields: recipient_name, phone, address_line, subdistrict,
  //         district, province, postcode, is_default
  // =====================================================

  static Future<Map<String, dynamic>> getAddresses() {
    return _send('GET', '/addresses');
  }

  // addressId = null → เพิ่มใหม่
  static Future<Map<String, dynamic>> saveAddress(
    int? addressId,
    Map<String, dynamic> fields,
  ) {
    return addressId == null
        ? _send('POST', '/addresses', fields)
        : _send('PUT', '/addresses/$addressId', fields);
  }

  static Future<Map<String, dynamic>> deleteAddress(int addressId) {
    return _send('DELETE', '/addresses/$addressId');
  }
}
