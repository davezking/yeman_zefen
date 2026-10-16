import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Returns a Firebase ID token, or null when nobody is signed in yet (first
/// launch offline). [forceRefresh] asks Firebase for a new token instead of
/// the cached one.
typedef IdTokenProvider = Future<String?> Function({bool forceRefresh});

/// An error from the API. The server always answers `{ "error": { "code", "message" } }`.
sealed class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status});

  /// The server's snake_case code, or a local one (`network_error`, `bad_response`).
  final String code;
  final String message;

  /// The HTTP status, or null when no response arrived.
  final int? status;

  @override
  String toString() => '$runtimeType($code${status == null ? '' : ', $status'}): $message';
}

/// No usable response: offline, DNS failure, timeout.
class NetworkException extends ApiException {
  const NetworkException(String message) : super('network_error', message);
}

/// 401, still rejected after one token refresh.
class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.code, super.message) : super(status: 401);
}

class ForbiddenException extends ApiException {
  const ForbiddenException(super.code, super.message) : super(status: 403);
}

class NotFoundException extends ApiException {
  const NotFoundException(super.code, super.message) : super(status: 404);
}

class RateLimitedException extends ApiException {
  const RateLimitedException(super.code, super.message, {this.retryAfter}) : super(status: 429);

  /// From the `Retry-After` header, when the server sent one.
  final Duration? retryAfter;
}

/// Any other 4xx (validation errors, conflicts).
class RequestException extends ApiException {
  const RequestException(super.code, super.message, {required int status}) : super(status: status);
}

class ServerException extends ApiException {
  const ServerException(super.code, super.message, {required int status}) : super(status: status);
}

/// The API client for the Worker. Attaches `Authorization: Bearer <ID token>`,
/// and on a 401 refreshes the token once and retries once.
///
/// It only ever talks to [baseUrl], so the token never goes to another host
/// (the CDN that serves manifests and clips gets a plain client).
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.idToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
       _client = client ?? http.Client();

  final String baseUrl;
  final IdTokenProvider idToken;
  final Duration timeout;
  final http.Client _client;

  Future<Object?> getJson(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Object?> postJson(String path, {Object? body}) => _send('POST', path, body: body);

  Future<Object?> putJson(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<Object?> deleteJson(String path) => _send('DELETE', path);

  Future<Object?> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    var (res, sentToken) = await _attempt(method, path, query, body, forceRefresh: false);
    // A refresh only helps when a token was sent. With no user there is no
    // token to refresh, and the same request would just fail again.
    if (res.statusCode == 401 && sentToken) {
      res = (await _attempt(method, path, query, body, forceRefresh: true)).$1;
    }
    return _decode(res);
  }

  /// Sends one request. Returns the response and whether a token was attached.
  Future<(http.Response, bool)> _attempt(
    String method,
    String path,
    Map<String, String>? query,
    Object? body, {
    required bool forceRefresh,
  }) async {
    final String? token;
    try {
      token = await idToken(forceRefresh: forceRefresh);
    } catch (e) {
      // Refreshing a token needs the network.
      throw NetworkException('Could not get an ID token: $e');
    }
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query?.isEmpty ?? true ? null : query);
    final request = http.Request(method, uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final res = await http.Response.fromStream(await _client.send(request).timeout(timeout)).timeout(timeout);
      return (res, token != null);
    } on TimeoutException {
      throw NetworkException('$method $path timed out');
    } on http.ClientException catch (e) {
      throw NetworkException(e.message);
    } catch (e) {
      // dart:io SocketException and friends. Not imported here so the client
      // also compiles for web.
      throw NetworkException('$method $path failed: $e');
    }
  }

  Object? _decode(http.Response res) {
    final status = res.statusCode;
    final text = utf8.decode(res.bodyBytes);
    if (status >= 200 && status < 300) {
      if (text.isEmpty) return null;
      try {
        return jsonDecode(text);
      } on FormatException {
        throw BadResponseException('The server sent a response that is not JSON', status: status);
      }
    }
    var code = 'http_$status';
    var message = 'The server answered $status';
    try {
      final error = (jsonDecode(text) as Map<String, dynamic>)['error'] as Map<String, dynamic>;
      code = error['code'] as String? ?? code;
      message = error['message'] as String? ?? message;
    } catch (_) {
      // Not our error shape (a proxy or CDN error page). Keep the defaults.
    }
    if (status == 401) throw UnauthorizedException(code, message);
    if (status == 403) throw ForbiddenException(code, message);
    if (status == 404) throw NotFoundException(code, message);
    if (status == 429) {
      final seconds = int.tryParse(res.headers['retry-after'] ?? '');
      throw RateLimitedException(code, message, retryAfter: seconds == null ? null : Duration(seconds: seconds));
    }
    if (status >= 500) throw ServerException(code, message, status: status);
    throw RequestException(code, message, status: status);
  }

  void close() => _client.close();
}

/// A 2xx response the app cannot use: not JSON, or not the expected shape.
class BadResponseException extends ServerException {
  const BadResponseException(String message, {required super.status}) : super('bad_response', message);
}
