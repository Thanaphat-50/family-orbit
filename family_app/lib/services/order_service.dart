import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

// =======================================================
// สั่งซื้อสินค้า (ผู้ซื้อ + ร้าน)
// ทุกคำสั่งคืน order ล่าสุด ปุ่มที่กดได้อยู่ใน order['actions']
// =======================================================

class OrderService {
  static const String baseUrl = ApiConfig.baseUrl;

  static const Duration _uploadTimeLimit = Duration(seconds: 90);

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ข้อมูลหน้าสั่งซื้อ: วิธีรับสินค้า วิธีจ่าย ค่าส่ง ผู้รับล่าสุด
  static Future<Map<String, dynamic>> getCheckout(int productId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(
        Uri.parse('$baseUrl/orders/checkout?product_id=$productId'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // items: [{product_id, variant_id, quantity}]
  // → groups (แยกตามร้าน) ราคาปัจจุบัน วิธีรับ/วิธีจ่าย ค่าส่ง ที่อยู่ที่บันทึกไว้
  static Future<Map<String, dynamic>> preview(
    List<Map<String, dynamic>> items,
  ) async {
    return _post('/orders/preview', {'items': items});
  }

  // fields: checkout_id, items, groups[{shop_id, delivery_method,
  //         payment_method, note}], address_id | recipient_name + recipient_phone,
  //         expected_total
  // 409 code=checkout_changed → ราคา/สต็อกเปลี่ยน (มีข้อมูลหน้าสรุปใหม่มาด้วย)
  static Future<Map<String, dynamic>> placeOrder(
    Map<String, dynamic> fields,
  ) async {
    return _post('/orders', fields);
  }

  // seller = false → ที่ฉันซื้อ / true → ลูกค้าของร้านฉัน
  // filter: todo (ร้านต้องจัดการ) / open / completed / cancelled
  static Future<Map<String, dynamic>> getOrders({
    required bool seller,
    String? filter,
    int page = 1,
  }) async {
    final headers = await _headers();

    final uri = Uri.parse(
      seller ? '$baseUrl/my-shop/orders' : '$baseUrl/orders',
    ).replace(queryParameters: {'page': '$page', 'filter': ?filter});

    final response = await ApiHelper.request(
      () => http.get(uri, headers: headers),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> getOrder(int orderId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(Uri.parse('$baseUrl/orders/$orderId'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // action: accept, confirm-payment, reject-slip, ship, received, cancel
  static Future<Map<String, dynamic>> act(
    int orderId,
    String action, [
    Map<String, dynamic> fields = const {},
  ]) {
    return _post('/orders/$orderId/$action', fields);
  }

  static Future<Map<String, dynamic>> uploadSlip(
    int orderId,
    String slipPath,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/orders/$orderId/slip'),
    )..headers.addAll(await _headers());

    request.files.add(await http.MultipartFile.fromPath('slip', slipPath));

    final response = await ApiHelper.request(
      () async => http.Response.fromStream(await request.send()),
      timeLimit: _uploadTimeLimit,
    );

    if (response.statusCode == 413) {
      return {
        'status': false,
        'message': 'รูปสลิปใหญ่เกินไป กรุณาเลือกรูปที่เล็กลง',
      };
    }

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> fields,
  ) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl$path'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode(fields),
      ),
    );

    return ApiHelper.decode(response);
  }
}
