import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

class PostService {
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
  // GET POSTS
  // =====================================================

  static Future<Map<String, dynamic>> getPosts() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(
        Uri.parse('$baseUrl/posts'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // CREATE POST
  // =====================================================

  static Future<Map<String, dynamic>> createPost(
    String content,
  ) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/posts'),
        headers: headers,
        body: jsonEncode({
          'content': content,
        }),
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // DELETE POST
  // =====================================================

  static Future<Map<String, dynamic>> deletePost(
    int postId,
  ) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(
        Uri.parse('$baseUrl/posts/$postId'),
        headers: headers,
      ),
    );

    // โพสต์ถูกลบไปแล้ว (เช่น กดลบซ้ำจากอีกเครื่อง)
    if (response.statusCode == 404) {
      return {
        'status': true,
        'message': 'โพสต์นี้ถูกลบไปแล้ว',
      };
    }

    return ApiHelper.decode(response);
  }

  // =====================================================
  // CREATE COMMENT
  // =====================================================

  static Future<Map<String, dynamic>> createComment({
    required int postId,
    required String content,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/posts/$postId/comments'),
        headers: headers,
        body: jsonEncode({
          'content': content,
        }),
      ),
    );

    return ApiHelper.decode(response);
  }
}
