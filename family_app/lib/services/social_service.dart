import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

// =======================================================
// แชร์ / ติดตาม / แนะนำคนที่ชอบคล้ายกัน / ประวัติการใช้งาน
// =======================================================

class SocialService {
  static const String baseUrl = ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // channel: external (ส่งต่อไปแอปอื่น) / community (แชร์ซ้ำในชุมชน) / family (ส่งให้ครอบครัว)
  // ตอบ post_id (โพสต์ต้นฉบับ), shares_count และ post (โพสต์ใหม่ ถ้าแชร์ในแอป)
  static Future<Map<String, dynamic>> sharePost(
    int postId, {
    required String channel,
    String? content,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/posts/$postId/share'),
        headers: headers,
        body: jsonEncode({
          'channel': channel,
          if (content != null && content.trim().isNotEmpty)
            'content': content.trim(),
        }),
      ),
    );

    return ApiHelper.decode(response);
  }

  // ตอบ is_following และ followers_count
  static Future<Map<String, dynamic>> setFollowing(
    int userId,
    bool follow,
  ) async {
    final headers = await _headers();

    final Uri uri = Uri.parse('$baseUrl/users/$userId/follow');

    final response = await ApiHelper.request(
      () => follow
          ? http.post(uri, headers: headers)
          : http.delete(uri, headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // users: [{id, name, profile_image_url, followers_count, reason}]
  static Future<Map<String, dynamic>> suggestions() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(Uri.parse('$baseUrl/users/suggestions'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // items: [{id, type, channel, excerpt, created_at, post, target_user}]
  // counts: {like, comment, share, follow}
  // type: like / comment / share / follow (ไม่ส่ง = ทุกประเภท)
  static Future<Map<String, dynamic>> history({
    int page = 1,
    String? type,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(
        Uri.parse('$baseUrl/me/history')
            .replace(queryParameters: {'page': '$page', 'type': ?type}),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> clearHistory({String? type}) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(
        Uri.parse('$baseUrl/me/history')
            .replace(queryParameters: {'type': ?type}),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }
}
