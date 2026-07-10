import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';

class ApiService {
  static String _baseUrl = 'http://localhost:8080';
  static const _tokenPrefsKey = 'auth_token';
  static const _baseUrlPrefsKey = 'base_url';

  /// JWT bearer token for the authenticated account. Attached to every request
  /// (HTTP + WebSocket). Loaded from shared_preferences at startup.
  static String? _authToken;

  static String? get authToken => _authToken;
  static bool get isAuthenticated => _authToken != null && _authToken!.isNotEmpty;

  /// Update the backend base URL and persist it (so it survives restarts and can
  /// be set before login — important on Android where `localhost` is the device).
  static Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlPrefsKey, _baseUrl);
  }

  /// Load a previously-saved base URL. Call once at startup before any request.
  /// With no saved value, defaults to the Android-emulator host alias on Android
  /// (`localhost` there resolves to the device, not the host machine).
  static Future<void> loadBaseUrlFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_baseUrlPrefsKey);
    if (saved != null && saved.trim().isNotEmpty) {
      _baseUrl = saved.trim();
    } else if (Platform.isAndroid) {
      _baseUrl = 'http://10.0.2.2:8080';
    }
  }

  static String get baseUrl => _baseUrl;

  /// ws:// (or wss://) base derived from the HTTP base URL.
  static String get _wsBase {
    if (_baseUrl.startsWith('https')) return _baseUrl.replaceFirst('https', 'wss');
    if (_baseUrl.startsWith('http')) return _baseUrl.replaceFirst('http', 'ws');
    return 'ws://$_baseUrl';
  }

  // ─── Auth token management ────────────────────────────────────────────
  static Future<void> loadTokenFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString(_tokenPrefsKey);
  }

  static Future<void> setAuthToken(String token) async {
    _authToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenPrefsKey, token);
  }

  static Future<void> clearAuthToken() async {
    _authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenPrefsKey);
  }

  static Map<String, String> _headers({bool json = true}) {
    final h = <String, String>{};
    if (json) h['Content-Type'] = 'application/json';
    if (isAuthenticated) h['Authorization'] = 'Bearer $_authToken';
    return h;
  }

  static Map<String, dynamic> _tryJson(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  // ─── Authentication ───────────────────────────────────────────────────

  /// Signup → persists the returned token and returns {token, account}.
  static Future<Map<String, dynamic>> signup(String email, String password, {String? name}) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );
    return _handleAuthResponse(r);
  }

  /// Login → persists the returned token and returns {token, account}.
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _handleAuthResponse(r);
  }

  static Future<Map<String, dynamic>> _handleAuthResponse(http.Response r) async {
    final body = _tryJson(r.body);
    if (r.statusCode == 200) {
      await setAuthToken(body['token'] as String);
      return body;
    }
    throw Exception(body['detail']?.toString() ?? 'Request failed (HTTP ${r.statusCode})');
  }

  /// Returns the current account for a stored token, or null if missing/expired.
  static Future<Map<String, dynamic>?> getMe() async {
    if (!isAuthenticated) return null;
    try {
      final r = await http.get(Uri.parse('$_baseUrl/api/auth/me'), headers: _headers(json: false));
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (_) {}
    return null;
  }

  static Future<void> logout() => clearAuthToken();

  /// Change the current account's password.
  static Future<void> changePassword(String currentPassword, String newPassword) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/auth/change-password'),
      headers: _headers(),
      body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword}),
    );
    if (r.statusCode != 200) {
      throw Exception(_tryJson(r.body)['detail']?.toString() ?? 'Failed (HTTP ${r.statusCode})');
    }
  }

  /// Permanently delete the current account and all its data. Clears the token.
  static Future<void> deleteAccount() async {
    final r = await http.delete(Uri.parse('$_baseUrl/api/auth/me'), headers: _headers(json: false));
    if (r.statusCode != 200) {
      throw Exception(_tryJson(r.body)['detail']?.toString() ?? 'Failed (HTTP ${r.statusCode})');
    }
    await clearAuthToken();
  }

  /// Update the current account's name and/or email. Returns the updated account.
  static Future<Map<String, dynamic>> updateProfile({String? name, String? email}) async {
    final r = await http.patch(
      Uri.parse('$_baseUrl/api/auth/me'),
      headers: _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (email != null) 'email': email,
      }),
    );
    if (r.statusCode == 200) return jsonDecode(r.body);
    throw Exception(_tryJson(r.body)['detail']?.toString() ?? 'Failed (HTTP ${r.statusCode})');
  }

  // ─── Config (single source of truth) ──────────────────────────────────
  static Future<Map<String, dynamic>> getConfig() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/config'), headers: _headers(json: false));
    if (response.statusCode == 200) return jsonDecode(response.body);
    return {};
  }

  // ─── Chat ─────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> sendMessage({
    required String message,
    int? conversationId,
    String? model,
    double? temperature,
    int? maxTokens,
    List<Message>? history,
  }) async {
    final body = <String, dynamic>{'message': message};
    if (conversationId != null) body['conversation_id'] = conversationId;
    if (model != null) body['model'] = model;
    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    if (history != null) body['history'] = history.map((m) => m.toJson()).toList();

    final response = await http.post(
      Uri.parse('$_baseUrl/api/chat/send'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    try {
      final errorBody = jsonDecode(response.body);
      throw Exception(errorBody['content']?.toString() ??
          errorBody['detail']?.toString() ??
          'Chat request failed: ${response.statusCode}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Chat request failed: ${response.statusCode}');
    }
  }

  static Stream<Map<String, dynamic>> streamMessage({
    required String message,
    int? conversationId,
    String? model,
    double? temperature,
    int? maxTokens,
    List<Message>? history,
    bool deepResearch = false,
    bool webSearch = false,
  }) async* {
    final body = <String, dynamic>{'message': message};
    if (conversationId != null) body['conversation_id'] = conversationId;
    if (model != null) body['model'] = model;
    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    if (history != null) body['history'] = history.map((m) => m.toJson()).toList();
    if (deepResearch) body['deep_research'] = true;
    if (webSearch) body['web_search'] = true;

    final request = http.Request('POST', Uri.parse('$_baseUrl/api/chat/stream'));
    request.headers.addAll(_headers());
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Stream request failed: ${response.statusCode}');
      }
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data:')) {
            final data = line.substring(5).trim();
            if (data.isEmpty) continue;
            try {
              yield jsonDecode(data);
            } catch (_) {}
          }
        }
      }
    } finally {
      client.close();
    }
  }

  // ─── Agent orchestration (WebSocket) ──────────────────────────────────

  /// Streams a chat turn through the Agent Gateway WebSocket, yielding typed
  /// events: {type: plan_created|tool_start|tool_end|token|done|error, ...}.
  /// Authenticates with the stored JWT via the ?token= query param.
  static Stream<Map<String, dynamic>> streamAgentMessage({
    required String message,
    int? conversationId,
    String? model,
    bool deepResearch = false,
    bool webSearch = false,
  }) async* {
    final sessionId = const Uuid().v4();
    final url = '$_wsBase/api/agent/ws/$sessionId?token=${Uri.encodeComponent(_authToken ?? '')}';
    final ws = await WebSocket.connect(url);
    try {
      ws.add(jsonEncode({
        'type': 'chat',
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        if (model != null) 'model': model,
        if (deepResearch) 'deep_research': true,
        if (webSearch) 'web_search': true,
      }));

      await for (final raw in ws) {
        if (raw is! String) continue;
        Map<String, dynamic> evt;
        try {
          evt = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final type = evt['type'];
        if (type == 'ping') {
          ws.add(jsonEncode({'type': 'pong'}));
          continue;
        }
        yield evt;
        if (type == 'done' || type == 'error') break;
      }
    } finally {
      await ws.close();
    }
  }

  // ─── Conversations ────────────────────────────────────────────────────
  static Future<List<Conversation>> getConversations() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/conversations'), headers: _headers(json: false));
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list.map((e) => Conversation.fromJson(e)).toList();
    }
    return [];
  }

  static Future<Conversation> getConversation(int id) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/conversations/$id'), headers: _headers(json: false));
    if (response.statusCode == 200) {
      return Conversation.fromJson(jsonDecode(response.body));
    }
    throw Exception('Conversation not found');
  }

  static Future<void> deleteConversation(int id) async {
    final response = await http.delete(Uri.parse('$_baseUrl/api/conversations/$id'), headers: _headers(json: false));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to delete conversation (HTTP ${response.statusCode})');
    }
  }

  /// Rename a conversation's title.
  static Future<void> renameConversation(int id, String title) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/api/conversations/$id'),
      headers: _headers(),
      body: jsonEncode({'title': title}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to rename conversation (HTTP ${response.statusCode})');
    }
  }

  /// Keep only the first [keep] messages of a conversation, deleting the rest.
  /// Used when editing an earlier message so the edited turn replaces the old
  /// exchange (and stays replaced after a reload).
  static Future<void> truncateConversation(int id, int keep) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/conversations/$id/truncate'),
      headers: _headers(),
      body: jsonEncode({'keep': keep}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to truncate conversation (HTTP ${response.statusCode})');
    }
  }

  // ─── Keys ─────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getKeys() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/keys/'), headers: _headers(json: false));
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    return [];
  }

  static Future<void> addKey(String platform, String key, {String? label}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/keys/'),
      headers: _headers(),
      body: jsonEncode({'platform': platform, 'key': key, if (label != null) 'label': label}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = 'Failed to add key (HTTP ${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] != null) detail = body['detail'].toString();
      } catch (_) {}
      throw Exception(detail);
    }
  }

  static Future<void> deleteKey(int id) async {
    await http.delete(Uri.parse('$_baseUrl/api/keys/$id'), headers: _headers(json: false));
  }
}
