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
}
