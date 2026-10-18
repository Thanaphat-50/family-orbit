import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

class MarketService {
  static const String baseUrl = ApiConfig.baseUrl;

  // อัปโหลดรูปใช้นานกว่า Request ปกติ
  static const Duration _uploadTimeLimit = Duration(seconds: 90);

  // =====================================================
  // HEADERS
  // =====================================================

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // =====================================================
  // ร้านของฉัน
  // ยังไม่มีร้าน → shop = null
  // =====================================================

  static Future<Map<String, dynamic>> getMyShop() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(Uri.parse('$baseUrl/my-shop'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // สมัครเปิดร้าน (isNew) หรือแก้ไขข้อมูลร้าน
  // fields: name, description, category, phone, line_id,
  //         province, district
  // logoPath: รูปโลโก้ใหม่ในเครื่อง (ไม่เปลี่ยน = null)
  // =====================================================

  static Future<Map<String, dynamic>> saveShop({
    required bool isNew,
    required Map<String, String> fields,
    String? logoPath,
    bool removeLogo = false,
  }) async {
    // ไม่ใส่ Content-Type เพราะ MultipartRequest สร้างให้เอง
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(isNew ? '$baseUrl/my-shop' : '$baseUrl/my-shop/update'),
          )
          ..headers.addAll(await _headers())
          ..fields.addAll(fields);

    if (isNew) {
      request.fields['accept_terms'] = '1';
    }

    if (removeLogo) {
      request.fields['remove_logo'] = '1';
    }

    if (logoPath != null) {
      request.files.add(await http.MultipartFile.fromPath('logo', logoPath));
    }

    final response = await ApiHelper.request(
      () async => http.Response.fromStream(await request.send()),
      timeLimit: _uploadTimeLimit,
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // สินค้าในร้านของฉัน
  // =====================================================

  static Future<Map<String, dynamic>> getMyProducts() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(Uri.parse('$baseUrl/my-shop/products'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // productId = null → เพิ่มสินค้าใหม่
  // fields: title, description, price (ว่าง = สอบถามราคา), category
  // newImagePaths: รูปใหม่ในเครื่อง, removeImageIds: รูปเดิมที่เอาออก
  static Future<Map<String, dynamic>> saveProduct({
    int? productId,
    required Map<String, String> fields,
    List<String> newImagePaths = const [],
    List<int> removeImageIds = const [],
  }) async {
    final Uri uri = productId == null
        ? Uri.parse('$baseUrl/my-shop/products')
        : Uri.parse('$baseUrl/my-shop/products/$productId/update');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(await _headers())
      ..fields.addAll(fields);

    for (int i = 0; i < removeImageIds.length; i++) {
      request.fields['remove_image_ids[$i]'] = '${removeImageIds[i]}';
    }

    for (final path in newImagePaths) {
      request.files.add(await http.MultipartFile.fromPath('images[]', path));
    }

    final response = await ApiHelper.request(
      () async => http.Response.fromStream(await request.send()),
      timeLimit: _uploadTimeLimit,
    );

    if (response.statusCode == 413) {
      return {
        'status': false,
        'message': 'รูปมีขนาดรวมใหญ่เกินไป กรุณาเลือกรูปให้น้อยลง',
      };
    }

    return ApiHelper.decode(response);
  }

  // status: 'active' (แสดง) / 'hidden' (ซ่อน)
  static Future<Map<String, dynamic>> setProductStatus(
    int productId,
    String status,
  ) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.patch(
        Uri.parse('$baseUrl/my-shop/products/$productId/status'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> deleteProduct(int productId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(
        Uri.parse('$baseUrl/my-shop/products/$productId'),
        headers: headers,
      ),
    );

    // ถูกลบไปแล้ว (เช่น กดลบซ้ำ)
    if (response.statusCode == 404) {
      return {'status': true, 'message': 'ลบสินค้าแล้ว'};
    }

    return ApiHelper.decode(response);
  }
}
