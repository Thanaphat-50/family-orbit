import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

class NotificationService {
  static const String baseUrl = ApiConfig.baseUrl;

  // =====================================================
  // HEADERS
  // =====================================================

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // =====================================================
  // GET NOTIFICATIONS (ใหม่ล่าสุดก่อน ครั้งละ 20)
  // beforeId = id ของรายการสุดท้ายที่มีแล้ว → โหลดชุดที่เก่ากว่า
  // =====================================================

  static Future<Map<String, dynamic>> getNotifications({int? beforeId}) async {
    final headers = await _headers();

    final Uri uri = Uri.parse('$baseUrl/notifications').replace(
      queryParameters: {if (beforeId != null) 'before_id': '$beforeId'},
    );

    final response = await ApiHelper.request(
      () => http.get(uri, headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // UNREAD COUNT
  // GET /api/notifications/unread-count
  // =====================================================

  static Future<int> getUnreadCount() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(
        Uri.parse('$baseUrl/notifications/unread-count'),
        headers: headers,
      ),
    );

    final dynamic count = ApiHelper.decode(response)['count'];

    if (count is num) return count.toInt();

    return int.tryParse('${count ?? ''}') ?? 0;
  }

  // =====================================================
  // MARK ONE AS READ
  // PATCH /api/notifications/{id}/read
  // =====================================================

  static Future<Map<String, dynamic>> markAsRead(int notificationId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.patch(
        Uri.parse('$baseUrl/notifications/$notificationId/read'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // READ ALL
  // PATCH /api/notifications/read-all
  // =====================================================

  static Future<Map<String, dynamic>> markAllAsRead() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.patch(
        Uri.parse('$baseUrl/notifications/read-all'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // DELETE ONE
  // DELETE /api/notifications/{id}
  // =====================================================

  static Future<Map<String, dynamic>> deleteNotification(
    int notificationId,
  ) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(
        Uri.parse('$baseUrl/notifications/$notificationId'),
        headers: headers,
      ),
    );

    // ถูกลบไปแล้ว (เช่น ลบซ้ำจากอีกเครื่อง)
    if (response.statusCode == 404) {
      return {'status': true};
    }

    return ApiHelper.decode(response);
  }

  // =====================================================
  // DELETE ALL READ
  // DELETE /api/notifications/read
  // =====================================================

  static Future<Map<String, dynamic>> clearRead() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(
        Uri.parse('$baseUrl/notifications/read'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }
}
