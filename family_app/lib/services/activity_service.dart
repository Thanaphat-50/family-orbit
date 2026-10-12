import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_helper.dart';
import 'auth_service.dart';
import '../config/api_config.dart';

class ActivityService {
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
  // GET ACTIVITIES
  // =====================================================

  static Future<Map<String, dynamic>>
      getActivities() async {
    final response =
        await http.get(
      Uri.parse(
        '$baseUrl/activities',
      ),

      headers:
          await _headers(),
    );

    return ApiHelper.decode(
      response,
    );
  }

  // =====================================================
  // CREATE
  // =====================================================

  static Future<Map<String, dynamic>>
      createActivity({
    required String title,
    String? description,
    DateTime? activityDate,
    String visibility = 'private',
  }) async {
    final response =
        await http.post(
      Uri.parse(
        '$baseUrl/activities',
      ),

      headers:
          await _headers(),

      body: jsonEncode(
        {
          'title':
              title,

          'description':
              description,

          'activity_date':
              activityDate
                  ?.toIso8601String(),

          'visibility':
              visibility,
        },
      ),
    );

    return ApiHelper.decode(
      response,
    );
  }

  // =====================================================
  // TOGGLE
  // =====================================================

  static Future<Map<String, dynamic>>
      toggleActivity(
    int activityId,
  ) async {
    final response =
        await http.patch(
      Uri.parse(
        '$baseUrl/activities/'
        '$activityId/toggle',
      ),

      headers:
          await _headers(),
    );

    return ApiHelper.decode(
      response,
    );
  }

  // =====================================================
  // UPDATE VISIBILITY
  // =====================================================

  static Future<Map<String, dynamic>>
      updateVisibility({
    required int activityId,
    required String visibility,
  }) async {
    final response =
        await http.patch(
      Uri.parse(
        '$baseUrl/activities/'
        '$activityId/visibility',
      ),

      headers:
          await _headers(),

      body: jsonEncode(
        {
          'visibility':
              visibility,
        },
      ),
    );

    return ApiHelper.decode(
      response,
    );
  }

  // =====================================================
  // DELETE
  // =====================================================

  static Future<Map<String, dynamic>>
      deleteActivity(
    int activityId,
  ) async {
    final response =
        await http.delete(
      Uri.parse(
        '$baseUrl/activities/'
        '$activityId',
      ),

      headers:
          await _headers(),
    );

    return ApiHelper.decode(
      response,
    );
  }
}