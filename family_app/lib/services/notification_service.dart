import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

class NotificationService {
  static const String baseUrl = ApiConfig.baseUrl;

  // =====================================================
  // HEADERS
  // =====================================================

  static Future<Map<String, String>>
      _headers() async {
    final token =
        await AuthService.getToken();

    return {
      'Accept': 'application/json',
      'Content-Type':
          'application/json',

      if (token != null)
        'Authorization':
            'Bearer $token',
    };
  }

  // =====================================================
  // GET NOTIFICATIONS
  // GET /api/notifications
  // =====================================================

  static Future<Map<String, dynamic>>
      getNotifications() async {
    final response =
        await http.get(
      Uri.parse(
        '$baseUrl/notifications',
      ),
      headers:
          await _headers(),
    );

    return ApiHelper.decode(
      response,
    );
  }

  // =====================================================
  // UNREAD COUNT
  // GET /api/notifications/unread-count
  // =====================================================

  static Future<int>
      getUnreadCount() async {
    final response =
        await http.get(
      Uri.parse(
        '$baseUrl/notifications/unread-count',
      ),
      headers:
          await _headers(),
    );

    final result =
        ApiHelper.decode(
      response,
    );

    final dynamic count =
        result['unread_count'] ??
            result['count'] ??
            result['data'];

    if (count is num) {
      return count.toInt();
    }

    if (count is String) {
      return int.tryParse(count) ??
          0;
    }

    if (count is Map) {
      final value =
          count['unread_count'] ??
              count['count'];

      if (value is num) {
        return value.toInt();
      }

      return int.tryParse(
            value?.toString() ?? '',
          ) ??
          0;
    }

    return 0;
  }

  // =====================================================
  // MARK ONE AS READ
  // PATCH /api/notifications/{id}/read
  // =====================================================

  static Future<Map<String, dynamic>>
      markAsRead(
    int notificationId,
  ) async {
    final response =
        await http.patch(
      Uri.parse(
        '$baseUrl/notifications/'
        '$notificationId/read',
      ),
      headers:
          await _headers(),
    );

    return ApiHelper.decode(
      response,
    );
  }

  // =====================================================
  // READ ALL
  // PATCH /api/notifications/read-all
  // =====================================================

  static Future<Map<String, dynamic>>
      markAllAsRead() async {
    final response =
        await http.patch(
      Uri.parse(
        '$baseUrl/notifications/read-all',
      ),
      headers:
          await _headers(),
    );

    return ApiHelper.decode(
      response,
    );
  }
}