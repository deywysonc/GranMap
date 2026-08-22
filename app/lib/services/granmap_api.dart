import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/academic.dart';
import '../models/personal_data.dart';
import '../models/user.dart';
import '../positioning/magnetic_fingerprint_matcher.dart';

class GranMapApi {
  static const _defaultTimeout = Duration(seconds: 6);

  final http.Client _client;
  final String baseUrl;
  int _requestSequence = 0;

  GranMapApi({http.Client? client, this.baseUrl = ApiConfig.baseUrl})
    : _client = client ?? http.Client();

  Future<bool> health() async {
    try {
      final response = await _request(
        'GET',
        '/health',
        timeout: const Duration(seconds: 3),
        retryable: true,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> fetchAppConfig() async {
    final response = await _request('GET', '/app-config', retryable: true);
    _ensureSuccess(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<String>> fetchCourses() async {
    final response = await _request(
      'GET',
      '/courses',
      timeout: const Duration(seconds: 4),
      retryable: true,
    );

    _ensureSuccess(response);
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map((item) => (item['name'] ?? '') as String)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchCurrentMap() async {
    final result = await fetchCurrentMapConditional();
    return result.data!;
  }

  Future<MapPublicationFetch> fetchCurrentMapConditional({String? etag}) async {
    final response = await _request(
      'GET',
      '/maps/current',
      headers: etag == null ? null : {'If-None-Match': etag},
      retryable: true,
    );
    if (response.statusCode == 304) {
      return MapPublicationFetch(
        notModified: true,
        etag: response.headers['etag'] ?? etag,
      );
    }
    _ensureSuccess(response);
    return MapPublicationFetch(
      data: jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      etag: response.headers['etag'],
    );
  }

  Future<List<Map<String, dynamic>>> fetchRouteClosures() async {
    final response = await _request(
      'GET',
      '/navigation/closures',
      timeout: const Duration(seconds: 4),
      retryable: true,
    );
    _ensureSuccess(response);
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchPositioningAnchors() async {
    final response = await _request(
      'GET',
      '/positioning/anchors',
      timeout: const Duration(seconds: 4),
      retryable: true,
    );
    _ensureSuccess(response);
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchNotifications(
    String token, {
    bool unreadOnly = false,
  }) async {
    final response = await _request(
      'GET',
      '/me/notifications?unread_only=${unreadOnly ? 'true' : 'false'}',
      headers: _authHeaders(token),
      timeout: const Duration(seconds: 4),
      retryable: true,
    );
    _ensureSuccess(response);
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> markNotificationRead(String token, int notificationId) async {
    final response = await _request(
      'POST',
      '/me/notifications/$notificationId/read',
      headers: _authHeaders(token),
      idempotencyKey: 'notification-read-$notificationId',
    );
    _ensureSuccess(response);
  }

  Future<void> markAllNotificationsRead(String token) async {
    final response = await _request(
      'POST',
      '/me/notifications/read-all',
      headers: _authHeaders(token),
      idempotencyKey: 'notifications-read-all',
    );
    _ensureSuccess(response);
  }

  Future<int> uploadMagneticFingerprints({
    required String token,
    required int mapVersionId,
    required List<Map<String, dynamic>> samples,
  }) async {
    final response = await _request(
      'POST',
      '/positioning/fingerprints/batch',
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'map_version_id': mapVersionId, 'samples': samples}),
      timeout: const Duration(seconds: 12),
    );
    _ensureSuccess(response);
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (data['created'] as num).toInt();
  }

  Future<List<MagneticFingerprint>> fetchMagneticReferences() async {
    final response = await _request(
      'GET',
      '/positioning/fingerprints/reference',
      retryable: true,
    );
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
    final response = await _request(
      'POST',
      '/auth/register',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'course_name': course,
        'semester': semester,
        'group_name': group,
      }),
    );

    _ensureSuccess(response);
    return AuthResult.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _request(
      'POST',
      '/auth/login',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    _ensureSuccess(response);
    return AuthResult.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    final response = await _request(
      'POST',
      '/auth/password-reset/request',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    _ensureSuccess(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    final response = await _request(
      'POST',
      '/auth/password-reset/confirm',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'new_password': newPassword}),
    );
    _ensureSuccess(response);
  }

  Future<AppUser> fetchMe(String token) async {
    final response = await _request(
      'GET',
      '/auth/me',
      headers: _authHeaders(token),
      timeout: const Duration(seconds: 4),
      retryable: true,
    );

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
    final response = await _request(
      'PUT',
      '/auth/me',
      headers: _authHeaders(token, json: true),
      body: jsonEncode({
        'name': name,
        'course_name': course,
        'semester': semester,
        'group_name': group,
      }),
      timeout: const Duration(seconds: 5),
    );

    _ensureSuccess(response);
    return AppUser.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> logout(String token) async {
    try {
      await _request(
        'POST',
        '/auth/logout',
        headers: _authHeaders(token),
        timeout: const Duration(seconds: 4),
      );
    } catch (_) {
      // O logout local continua sendo executado mesmo sem internet.
    }
  }

  Future<List<AcademicClass>> fetchMySchedule(String token) async {
    final response = await _request(
      'GET',
      '/me/schedule',
      headers: _authHeaders(token),
      timeout: const Duration(seconds: 5),
      retryable: true,
    );

    _ensureSuccess(response);
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map(AcademicClass.fromApi)
        .toList(growable: false);
  }

  Future<List<String>> fetchFavorites(String token) async {
    final response = await _request(
      'GET',
      '/me/favorites',
      headers: _authHeaders(token),
      timeout: const Duration(seconds: 4),
      retryable: true,
    );

    _ensureSuccess(response);
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return data.map((item) => item.toString()).toList(growable: false);
  }

  Future<void> addFavorite(String token, String poiId) async {
    final response = await _request(
      'POST',
      '/me/favorites/$poiId',
      headers: _authHeaders(token),
      idempotencyKey: 'favorite-add-$poiId',
    );
    _ensureSuccess(response);
  }

  Future<void> removeFavorite(String token, String poiId) async {
    final response = await _request(
      'DELETE',
      '/me/favorites/$poiId',
      headers: _authHeaders(token),
      idempotencyKey: 'favorite-remove-$poiId',
    );
    _ensureSuccess(response);
  }

  Future<List<Map<String, dynamic>>> fetchProposals({String? token}) async {
    final response = await _request(
      'GET',
      '/proposals',
      headers: token == null ? null : _authHeaders(token),
      timeout: const Duration(seconds: 4),
      retryable: true,
    );

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
    String? idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/proposals',
      headers: _authHeaders(token, json: true),
      body: jsonEncode({
        'subject': subject,
        'from_room': fromRoom,
        'to_room': toRoom,
        'reason': reason,
      }),
      timeout: const Duration(seconds: 5),
      idempotencyKey: idempotencyKey,
    );

    _ensureSuccess(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> voteProposal({
    required String token,
    required int proposalId,
    required bool agrees,
    String? idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/proposals/$proposalId/votes',
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'agrees': agrees}),
      timeout: const Duration(seconds: 4),
      idempotencyKey: idempotencyKey,
    );

    _ensureSuccess(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<NavigationHistoryItem>> fetchHistory(String token) async {
    final response = await _request(
      'GET',
      '/me/history',
      headers: _authHeaders(token),
      timeout: const Duration(seconds: 4),
      retryable: true,
    );

    _ensureSuccess(response);
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map(NavigationHistoryItem.fromJson)
        .toList(growable: false);
  }

  Future<void> addHistory(String token, NavigationHistoryItem item) async {
    final response = await _request(
      'POST',
      '/me/history',
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'poi_id': item.poiId, 'poi_name': item.poiName}),
      idempotencyKey:
          'history-${item.poiId}-${item.visitedAt.millisecondsSinceEpoch}',
    );
    _ensureSuccess(response);
  }

  Future<List<Map<String, dynamic>>> fetchSessions(String token) async {
    final response = await _request(
      'GET',
      '/auth/sessions',
      headers: _authHeaders(token),
      retryable: true,
    );
    _ensureSuccess(response);
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> revokeSession(String token, int sessionId) async {
    final response = await _request(
      'DELETE',
      '/auth/sessions/$sessionId',
      headers: _authHeaders(token),
      idempotencyKey: 'session-revoke-$sessionId',
    );
    _ensureSuccess(response);
  }

  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _request(
      'POST',
      '/auth/change-password',
      headers: _authHeaders(token, json: true),
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    _ensureSuccess(response);
  }

  Future<Map<String, dynamic>> exportAccount(String token) async {
    final response = await _request(
      'GET',
      '/auth/export',
      headers: _authHeaders(token),
      retryable: true,
    );
    _ensureSuccess(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> deleteAccount({
    required String token,
    required String password,
  }) async {
    final response = await _request(
      'DELETE',
      '/auth/me',
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'password': password}),
    );
    _ensureSuccess(response);
  }

  Map<String, String> _authHeaders(String token, {bool json = false}) {
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = _defaultTimeout,
    bool retryable = false,
    String? idempotencyKey,
  }) async {
    final requestId =
        'gm-${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'X-Request-ID': requestId,
      'X-GranMap-App-Version': ApiConfig.appVersion,
      'X-GranMap-App-Build': '${ApiConfig.appBuild}',
      ...?headers,
      if (idempotencyKey != null && idempotencyKey.isNotEmpty)
        'Idempotency-Key': idempotencyKey,
    };
    final attempts = retryable || idempotencyKey != null ? 3 : 1;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        final future = switch (method) {
          'GET' => _client.get(uri, headers: requestHeaders),
          'POST' => _client.post(uri, headers: requestHeaders, body: body),
          'PUT' => _client.put(uri, headers: requestHeaders, body: body),
          'DELETE' => _client.delete(uri, headers: requestHeaders, body: body),
          _ => throw ArgumentError.value(method, 'method'),
        };
        final response = await future.timeout(timeout);
        if (_shouldRetryStatus(response.statusCode) && attempt < attempts) {
          await Future<void>.delayed(_retryDelay(response, attempt));
          continue;
        }
        return response;
      } on TimeoutException catch (error) {
        if (attempt < attempts) {
          await Future<void>.delayed(_retryDelay(null, attempt));
          continue;
        }
        throw ApiException(
          'O servidor demorou para responder. Tente novamente.',
          0,
          kind: ApiFailureKind.timeout,
          requestId: requestId,
          cause: error,
        );
      } on http.ClientException catch (error) {
        if (attempt < attempts) {
          await Future<void>.delayed(_retryDelay(null, attempt));
          continue;
        }
        throw ApiException(
          'Sem conexão com o GranMap. Confira sua internet.',
          0,
          kind: ApiFailureKind.network,
          requestId: requestId,
          cause: error,
        );
      }
    }
    throw ApiException(
      'Não foi possível concluir a requisição.',
      0,
      kind: ApiFailureKind.unknown,
      requestId: requestId,
    );
  }

  bool _shouldRetryStatus(int statusCode) =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  Duration _retryDelay(http.Response? response, int attempt) {
    final retryAfter = int.tryParse(response?.headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter.clamp(1, 10));
    }
    return Duration(milliseconds: 250 * (1 << (attempt - 1)));
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String message = 'Erro ${response.statusCode}';
    try {
      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      message = (decoded['detail'] ?? message).toString();
    } catch (_) {}

    final status = response.statusCode;
    final kind = switch (status) {
      401 => ApiFailureKind.unauthorized,
      409 => ApiFailureKind.conflict,
      429 => ApiFailureKind.rateLimited,
      >= 500 => ApiFailureKind.server,
      >= 400 => ApiFailureKind.validation,
      _ => ApiFailureKind.unknown,
    };
    throw ApiException(
      message,
      status,
      kind: kind,
      requestId: response.headers['x-request-id'],
      retryAfter: int.tryParse(response.headers['retry-after'] ?? ''),
    );
  }

  void dispose() => _client.close();
}

enum ApiFailureKind {
  network,
  timeout,
  unauthorized,
  validation,
  conflict,
  rateLimited,
  server,
  unknown,
}

class MapPublicationFetch {
  final Map<String, dynamic>? data;
  final String? etag;
  final bool notModified;

  const MapPublicationFetch({this.data, this.etag, this.notModified = false});
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final ApiFailureKind kind;
  final String? requestId;
  final int? retryAfter;
  final Object? cause;

  const ApiException(
    this.message,
    this.statusCode, {
    this.kind = ApiFailureKind.unknown,
    this.requestId,
    this.retryAfter,
    this.cause,
  });

  @override
  String toString() => message;
}
