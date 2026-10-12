import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import '../config/api_config.dart';

class PostService {
  static const String baseUrl = ApiConfig.baseUrl;

  static Future<Map<String, dynamic>> getPosts() async {
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/posts'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createPost(
    String content,
  ) async {
    final token = await AuthService.getToken();

    final response = await http.post(
      Uri.parse('$baseUrl/posts'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'content': content,
      }),
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deletePost(
    int postId,
  ) async {
    final token = await AuthService.getToken();

    final response = await http.delete(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createComment({
    required int postId,
    required String content,
  }) async {
    final token = await AuthService.getToken();

    final response = await http.post(
      Uri.parse('$baseUrl/posts/$postId/comments'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'content': content,
      }),
    );

    return jsonDecode(response.body);
  }

}