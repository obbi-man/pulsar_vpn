import 'dart:convert';

import 'package:http/http.dart' as http;

/// HTTP client for the Pulsar API-only Next.js backend.
class PulsarApi {
  PulsarApi({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = _normalizeBase(
          baseUrl ??
              const String.fromEnvironment(
                'PULSAR_API_BASE',
                defaultValue: 'http://127.0.0.1:43127',
              ),
        ),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? _cookie;

  static String _normalizeBase(String raw) {
    var b = raw.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }

  bool get isLoggedIn => _cookie != null && _cookie!.isNotEmpty;

  void clearSession() => _cookie = null;

  Map<String, String> _headers({bool jsonBody = false}) {
    final h = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) h['Content-Type'] = 'application/json';
    if (_cookie != null) h['Cookie'] = _cookie!;
    return h;
  }

  void _captureCookie(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    // Keep name=value only.
    final part = raw.split(';').first.trim();
    if (part.contains('=')) {
      _cookie = part;
    }
  }

  Future<Map<String, dynamic>> demoLogin({
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/auth/demo-login'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'email': email, 'password': password}),
    );
    _captureCookie(res);
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw PulsarApiException(body['error']?.toString() ?? 'Ошибка входа');
    }
    return body;
  }

  Future<void> logout() async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/api/auth/logout'),
        headers: _headers(),
      );
    } finally {
      clearSession();
    }
  }

  Future<Map<String, dynamic>> getPlan() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/billing/plan'),
      headers: _headers(),
    );
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw PulsarApiException(body['error']?.toString() ?? 'Ошибка тарифа');
    }
    return body;
  }

  Future<Map<String, dynamic>> startCheckout() async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/billing/checkout'),
      headers: _headers(jsonBody: true),
      body: '{}',
    );
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw PulsarApiException(body['error']?.toString() ?? 'Checkout failed');
    }
    return body;
  }

  Future<Map<String, dynamic>> confirmCheckout(String sessionId) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/billing/confirm'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'sessionId': sessionId}),
    );
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw PulsarApiException(body['error']?.toString() ?? 'Confirm failed');
    }
    return body;
  }

  Future<Map<String, dynamic>> listUsers() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/api/users'),
      headers: _headers(),
    );
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw PulsarApiException(body['error']?.toString() ?? 'Ошибка загрузки');
    }
    return body;
  }

  Future<Map<String, dynamic>> createUser(String name) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/users'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'name': name}),
    );
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw PulsarApiException(
        body['error']?.toString() ?? 'Не удалось создать пользователя',
        limitReached: body['limitReached'] == true,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> setupServer({
    required String ip,
    required String password,
    String login = 'root',
    int port = 22,
    String? name,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/api/server/setup'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'ip': ip,
        'port': port,
        'login': login,
        'password': password,
        if (name != null && name.isNotEmpty) 'name': name,
      }),
    );
    final body = _decode(res);
    if (res.statusCode >= 400) {
      throw PulsarApiException(
        body['error']?.toString() ?? 'Ошибка setup VPS',
        details: body['details']?.toString(),
      );
    }
    return body;
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return {};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }
}

class PulsarApiException implements Exception {
  PulsarApiException(this.message, {this.limitReached = false, this.details});
  final String message;
  final bool limitReached;
  final String? details;

  @override
  String toString() => message;
}
