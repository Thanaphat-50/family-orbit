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

  // scope: 'family' (ครอบครัว) หรือ 'community' (ชุมชน แบ่งหน้า)
  // category: กรองฟีดชุมชนตามหมวด (null = ทุกหมวด)
  // scope: family / community / mine (โพสต์ของฉัน)
  // userId: เฉพาะโพสต์ชุมชนของผู้ใช้คนนี้ (หน้าโปรไฟล์)
  static Future<Map<String, dynamic>> getPosts({
    String scope = 'family',
    int page = 1,
    String? category,
    int? userId,
  }) async {
    final headers = await _headers();

    final bool paged = scope == 'community' || scope == 'mine';

    final uri = Uri.parse('$baseUrl/posts').replace(
      queryParameters: {
        'scope': scope,
        if (paged) 'page': '$page',
        if (scope == 'community' && category != null) 'category': category,
        if (scope == 'community' && userId != null) 'user_id': '$userId',
      },
    );

    final response = await ApiHelper.request(
      () => http.get(uri, headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // GET ONE POST (เปิดจากการแจ้งเตือน)
  // ไม่พบ / ไม่มีสิทธิ์เห็น → status false + message
  // =====================================================

  static Future<Map<String, dynamic>> getPost(int postId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(Uri.parse('$baseUrl/posts/$postId'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // CREATE POST
  // visibility: 'family' (ค่าเริ่มต้น) หรือ 'community'
  // category: หมวดของโพสต์ชุมชน (general, qa, news, help, event)
  // imagePaths: ไฟล์รูปในเครื่อง (สูงสุด 10 รูป)
  //             มีรูป → ส่งแบบ multipart / ไม่มีรูป → JSON เหมือนเดิม
  // =====================================================

  static Future<Map<String, dynamic>> createPost(
    String content, {
    String visibility = 'family',
    String? category,
    List<String> imagePaths = const [],
  }) async {
    if (imagePaths.isNotEmpty) {
      return _createPostWithImages(
        content,
        visibility: visibility,
        category: category,
        imagePaths: imagePaths,
      );
    }

    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/posts'),
        headers: headers,
        body: jsonEncode({
          'content': content,
          'visibility': visibility,
          'category': ?category,
        }),
      ),
    );

    return ApiHelper.decode(response);
  }

  // อัปโหลดหลายรูปใช้เวลานานกว่า Request ปกติ
  static const Duration _uploadTimeLimit = Duration(seconds: 90);

  static Future<Map<String, dynamic>> _createPostWithImages(
    String content, {
    required String visibility,
    String? category,
    required List<String> imagePaths,
  }) async {
    final token = await AuthService.getToken();

    // ไม่ใส่ Content-Type เพราะ MultipartRequest สร้างให้เอง
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/posts'))
      ..headers.addAll({
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      })
      ..fields['content'] = content
      ..fields['visibility'] = visibility;

    if (category != null) {
      request.fields['category'] = category;
    }

    for (final path in imagePaths) {
      request.files.add(await http.MultipartFile.fromPath('images[]', path));
    }

    final response = await ApiHelper.request(
      () async => http.Response.fromStream(await request.send()),
      timeLimit: _uploadTimeLimit,
    );

    // ไฟล์รวมใหญ่เกินที่ Server รับได้
    if (response.statusCode == 413) {
      return {
        'status': false,
        'message': 'รูปมีขนาดรวมใหญ่เกินไป กรุณาเลือกรูปให้น้อยลง',
      };
    }

    return ApiHelper.decode(response);
  }

  // =====================================================
  // LIKE / UNLIKE (กดซ้ำ = ยกเลิก)
  // ตอบกลับ liked และ likes_count
  // =====================================================

  static Future<Map<String, dynamic>> toggleLike(int postId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () =>
          http.post(Uri.parse('$baseUrl/posts/$postId/like'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // REPORT POST (เฉพาะโพสต์ชุมชน)
  // reason: spam, inappropriate, harassment, scam, other
  // =====================================================

  static Future<Map<String, dynamic>> reportPost({
    required int postId,
    required String reason,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/posts/$postId/report'),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // REPORT COMMENT (เฉพาะความคิดเห็นในโพสต์ชุมชน)
  // =====================================================

  static Future<Map<String, dynamic>> reportComment({
    required int commentId,
    required String reason,
  }) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/comments/$commentId/report'),
        headers: headers,
        body: jsonEncode({'reason': reason}),
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // COMMUNITY: กฎชุมชน และการบล็อก
  // =====================================================

  static Future<Map<String, dynamic>> acceptCommunityTerms() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/community/accept-terms'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> getBlockedUsers() async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.get(Uri.parse('$baseUrl/blocks'), headers: headers),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> blockUser(int userId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.post(
        Uri.parse('$baseUrl/users/$userId/block'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  static Future<Map<String, dynamic>> unblockUser(int userId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(
        Uri.parse('$baseUrl/users/$userId/block'),
        headers: headers,
      ),
    );

    return ApiHelper.decode(response);
  }

  // =====================================================
  // DELETE POST
  // =====================================================

  static Future<Map<String, dynamic>> deletePost(int postId) async {
    final headers = await _headers();

    final response = await ApiHelper.request(
      () => http.delete(Uri.parse('$baseUrl/posts/$postId'), headers: headers),
    );

    // โพสต์ถูกลบไปแล้ว (เช่น กดลบซ้ำจากอีกเครื่อง)
    if (response.statusCode == 404) {
      return {'status': true, 'message': 'โพสต์นี้ถูกลบไปแล้ว'};
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
        body: jsonEncode({'content': content}),
      ),
    );

    return ApiHelper.decode(response);
  }
}
