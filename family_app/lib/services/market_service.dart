import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'post_service.dart' show CommentMediaFile;
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
    List<String> deliveryMethods = const [],
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

    // ไม่ส่งเลย = ไม่ระบุวิธีรับสินค้า
    for (int i = 0; i < deliveryMethods.length; i++) {
      request.fields['delivery_methods[$i]'] = deliveryMethods[i];
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
  // ตลาด (ฝั่งผู้ซื้อ)
  // =====================================================

  // q: คำค้น, category / province: ตัวกรอง (null = ทั้งหมด)
  static Future<Map<String, dynamic>> getMarketProducts({
    String? q,
    String? category,
    String? province,
    int page = 1,
  }) async {
    final headers = await _headers();

    final uri = Uri.parse('$baseUrl/market/products').replace(
      queryParameters: {
        'page': '$page',
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'category': ?category,
        'province': ?province,
      },
    );

    final response = await ApiHelper.request(
      () => http.get(uri, headers: headers),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> getMarketProduct(int productId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(
        Uri.parse('$baseUrl/market/products/$productId'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // ร้านแนะนำ (ร้านที่เช่าพื้นที่) สำหรับแบนเนอร์ด้านบนตลาด
  // ร้านละมี preview_images (รูปสินค้าล่าสุดไม่เกิน 3 รูป)
  static Future<Map<String, dynamic>> getFeaturedShops() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(Uri.parse('$baseUrl/market/featured'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> getMarketShop(int shopId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(
        Uri.parse('$baseUrl/market/shops/$shopId'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // target: 'products' หรือ 'shops'
  static Future<Map<String, dynamic>> report({
    required String target,
    required int id,
    required String reason,
    String? details,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/market/$target/$id/report'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'reason': reason,
          if (details != null && details.isNotEmpty) 'details': details,
        }),
      ),
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

  // =====================================================
  // รูปหน้าร้าน + วิดีโอแนะนำร้าน
  // =====================================================

  static Future<Map<String, dynamic>> updateShopMedia({
    List<String> newImagePaths = const [],
    List<int> removeImageIds = const [],
    CommentMediaFile? video,
    bool removeVideo = false,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/my-shop/media'),
    )..headers.addAll(await _headers());

    for (int i = 0; i < removeImageIds.length; i++) {
      request.fields['remove_image_ids[$i]'] = '${removeImageIds[i]}';
    }

    for (final path in newImagePaths) {
      request.files.add(await http.MultipartFile.fromPath('images[]', path));
    }

    if (video != null) {
      await _addVideo(request, video);
    } else if (removeVideo) {
      request.fields['remove_video'] = '1';
    }

    return _sendUpload(request);
  }

  // =====================================================
  // วิดีโอแนะนำสินค้า
  // =====================================================

  static Future<Map<String, dynamic>> uploadProductVideo(
    int productId,
    CommentMediaFile video,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/my-shop/products/$productId/video'),
    )..headers.addAll(await _headers());

    await _addVideo(request, video);

    return _sendUpload(request);
  }

  static Future<Map<String, dynamic>> deleteProductVideo(int productId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(
        Uri.parse('$baseUrl/my-shop/products/$productId/video'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // สินค้าช่องแนะนำ (category = null → ทุกหมวด)
  // =====================================================

  // fill: เติมด้วยสินค้ายอดนิยมจนครบ limit (ป้าย "แนะนำ" เฉพาะที่ชำระเงิน)
  static Future<Map<String, dynamic>> getFeaturedProducts({
    String? category,
    bool fill = false,
    int? limit,
  }) async {
    final headers = await _headers();

    final uri = Uri.parse('$baseUrl/market/featured-products').replace(
      queryParameters: {
        'category': ?category,
        if (fill) 'fill': '1',
        if (limit != null) 'limit': '$limit',
      },
    );

    final response = await ApiHelper.request(
      () => http.get(uri, headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // รีวิวร้าน
  // =====================================================

  static Future<Map<String, dynamic>> getShopReviews(
    int shopId, {
    int page = 1,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(
        Uri.parse('$baseUrl/market/shops/$shopId/reviews?page=$page'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> saveShopReview(
    int shopId, {
    required int rating,
    String? comment,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/market/shops/$shopId/reviews'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'rating': rating, 'comment': comment}),
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> deleteShopReview(int shopId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(
        Uri.parse('$baseUrl/market/shops/$shopId/reviews'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // ช่องแนะนำสินค้า (โอนพร้อมเพย์ + แนบสลิป)
  // =====================================================

  static Future<Map<String, dynamic>> getPromotionInfo(int productId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(
        Uri.parse('$baseUrl/my-shop/products/$productId/promotion'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> createPromotion(
    int productId,
    String plan,
  ) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/my-shop/products/$productId/promotion'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'plan': plan}),
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> uploadPromotionSlip(
    int promotionId,
    String slipPath,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/my-shop/promotions/$promotionId/slip'),
    )..headers.addAll(await _headers());

    request.files.add(await http.MultipartFile.fromPath('slip', slipPath));

    return _sendUpload(request);
  }

  static Future<Map<String, dynamic>> cancelPromotion(int promotionId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/my-shop/promotions/$promotionId/cancel'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> getMyPromotions() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () =>
          http.get(Uri.parse('$baseUrl/my-shop/promotions'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // HELPERS
  // =====================================================

  static Future<void> _addVideo(
    http.MultipartRequest request,
    CommentMediaFile video,
  ) async {
    request.files.add(await http.MultipartFile.fromPath('video', video.path));

    if (video.thumbnailPath != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'video_thumbnail',
          video.thumbnailPath!,
        ),
      );
    }
  }

  static Future<Map<String, dynamic>> _sendUpload(
    http.MultipartRequest request,
  ) async {
    final response = await ApiHelper.request(
      () async => http.Response.fromStream(await request.send()),
      timeLimit: _uploadTimeLimit,
    );

    if (response.statusCode == 413) {
      return {
        'status': false,
        'message': 'ไฟล์ใหญ่เกินไป กรุณาเลือกไฟล์ที่เล็กลง',
      };
    }

    return ApiHelper.decode(response);
  }
}
