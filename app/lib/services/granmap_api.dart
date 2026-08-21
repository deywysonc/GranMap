import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/academic.dart';
import '../models/personal_data.dart';
import '../models/user.dart';
import '../positioning/magnetic_fingerprint_matcher.dart';

class GranMapApi {
  final http.Client _client;
  final String baseUrl;

  GranMapApi({http.Client? client, this.baseUrl = ApiConfig.baseUrl})
    : _client = client ?? http.Client();

  Future<bool> health() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> fetchCourses() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/courses'))
        .timeout(const Duration(seconds: 4));

    _ensureSuccess(response);
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map((item) => (item['name'] ?? '') as String)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchCurrentMap() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/maps/current'))
        .timeout(const Duration(seconds: 6));
    _ensureSuccess(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchRouteClosures() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/navigation/closures'))
        .timeout(const Duration(seconds: 4));
    _ensureSuccess(response);
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchPositioningAnchors() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/positioning/anchors'))
        .timeout(const Duration(seconds: 4));
    _ensureSuccess(response);
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchNotifications(
    String token, {
    bool unreadOnly = false,
  }) async {
    final response = await _client
        .get(
          Uri.parse(
            '$baseUrl/me/notifications?unread_only=${unreadOnly ? 'true' : 'false'}',
          ),
          headers: _authHeaders(token),
        )
        .timeout(const Duration(seconds: 4));
    _ensureSuccess(response);
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> markNotificationRead(String token, int notificationId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/me/notifications/$notificationId/read'),
      headers: _authHeaders(token),
    );
    _ensureSuccess(response);
  }

  Future<void> markAllNotificationsRead(String token) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/me/notifications/read-all'),
      headers: _authHeaders(token),
    );
    _ensureSuccess(response);
  }

  Future<int> uploadMagneticFingerprints({
    required String token,
    required int mapVersionId,
    required List<Map<String, dynamic>> samples,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/positioning/fingerprints/batch'),
          headers: _authHeaders(token, json: true),
          body: jsonEncode({
            'map_version_id': mapVersionId,
            'samples': samples,
          }),
        )
        .timeout(const Duration(seconds: 12));
    _ensureSuccess(response);
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (data['created'] as num).toInt();
  }

  Future<List<MagneticFingerprint>> fetchMagneticReferences() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/positioning/fingerprints/reference'))
        .timeout(const Duration(seconds: 6));
    _ensureSuccess(response);
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(MagneticFingerprint.fromJson)
        .toList(growable: false);
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    required String course,
    required int semester,
    required String group,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'email': email,
            'password': password,
            'course_name': course,
            'semester': semester,
            'group_name': group,
          }),
        )
        .timeout(const Duration(seconds: 6));

    _ensureSuccess(response);
    return AuthResult.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 6));

    _ensureSuccess(response);
    return AuthResult.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<AppUser> fetchMe(String token) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/auth/me'), headers: _authHeaders(token))
        .timeout(const Duration(seconds: 4));

    _ensureSuccess(response);
    return AppUser.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<AppUser> updateMe({
    required String token,
    required String name,
    required String course,
    required int semester,
    required String group,
  }) async {
    final response = await _client
        .put(
          Uri.parse('$baseUrl/auth/me'),
          headers: _authHeaders(token, json: true),
          body: jsonEncode({
            'name': name,
            'course_name': course,
            'semester': semester,
            'group_name': group,
          }),
        )
        .timeout(const Duration(seconds: 5));

    _ensureSuccess(response);
    return AppUser.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> logout(String token) async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: _authHeaders(token),
      );
    } catch (_) {
      // O logout local continua sendo executado mesmo sem internet.
    }
  }

  Future<List<AcademicClass>> fetchMySchedule(String token) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/me/schedule'), headers: _authHeaders(token))
        .timeout(const Duration(seconds: 5));

    _ensureSuccess(response);
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map(AcademicClass.fromApi)
        .toList(growable: false);
  }

  Future<List<String>> fetchFavorites(String token) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/me/favorites'), headers: _authHeaders(token))
        .timeout(const Duration(seconds: 4));

    _ensureSuccess(response);
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return data.map((item) => item.toString()).toList(growable: false);
  }

  Future<void> addFavorite(String token, String poiId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/me/favorites/$poiId'),
      headers: _authHeaders(token),
    );
    _ensureSuccess(response);
  }

  Future<void> removeFavorite(String token, String poiId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/me/favorites/$poiId'),
      headers: _authHeaders(token),
    );
    _ensureSuccess(response);
  }

  Future<List<Map<String, dynamic>>> fetchProposals({String? token}) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/proposals'),
          headers: token == null ? null : _authHeaders(token),
        )
        .timeout(const Duration(seconds: 4));

    _ensureSuccess(response);
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createProposal({
    required String token,
    required String subject,
    required String fromRoom,
    required String toRoom,
    required String reason,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/proposals'),
          headers: _authHeaders(token, json: true),
          body: jsonEncode({
            'subject': subject,
            'from_room': fromRoom,
            'to_room': toRoom,
            'reason': reason,
          }),
        )
        .timeout(const Duration(seconds: 5));

    _ensureSuccess(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> voteProposal({
    required String token,
    required int proposalId,
    required bool agrees,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/proposals/$proposalId/votes'),
          headers: _authHeaders(token, json: true),
          body: jsonEncode({'agrees': agrees}),
        )
        .timeout(const Duration(seconds: 4));

    _ensureSuccess(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<NavigationHistoryItem>> fetchHistory(String token) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/me/history'), headers: _authHeaders(token))
        .timeout(const Duration(seconds: 4));

    _ensureSuccess(response);
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map(NavigationHistoryItem.fromJson)
        .toList(growable: false);
  }

  Future<void> addHistory(String token, NavigationHistoryItem item) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/me/history'),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'poi_id': item.poiId, 'poi_name': item.poiName}),
    );
    _ensureSuccess(response);
  }

  Map<String, String> _authHeaders(String token, {bool json = false}) {
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String message = 'Erro ${response.statusCode}';
    try {
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      message = (decoded['detail'] ?? message).toString();
    } catch (_) {}

    throw ApiException(message, response.statusCode);
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}
