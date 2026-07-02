import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/conversation.dart';

class ApiService {
  static String _baseUrl = 'http://localhost:8080';

  static void setBaseUrl(String url) {
    _baseUrl = url;
  }

  static String get baseUrl => _baseUrl;

  // ─── Config (single source of truth) ──────────────────────────────────

  /// Fetches the unified config from backend.
  /// Contains providers (with active status), models, agent settings.
  static Future<Map<String, dynamic>> getConfig() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/config'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
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
    final body = <String, dynamic>{
      'message': message,
    };
    if (conversationId != null) body['conversation_id'] = conversationId;
    if (model != null) body['model'] = model;
    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    if (history != null) {
      body['history'] = history.map((m) => m.toJson()).toList();
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/api/chat/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      try {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['content']?.toString() ?? 'Chat request failed: ${response.statusCode}');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Chat request failed: ${response.statusCode}');
      }
    }
  }

  static Stream<Map<String, dynamic>> streamMessage({
    required String message,
    int? conversationId,
    String? model,
    double? temperature,
    int? maxTokens,
    List<Message>? history,
  }) async* {
    final body = <String, dynamic>{
      'message': message,
    };
    if (conversationId != null) body['conversation_id'] = conversationId;
    if (model != null) body['model'] = model;
    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    if (history != null) {
      body['history'] = history.map((m) => m.toJson()).toList();
    }

    final request = http.Request('POST', Uri.parse('$_baseUrl/api/chat/stream'));
    request.headers['Content-Type'] = 'application/json';
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

  // ─── Conversations ────────────────────────────────────────────────────

  static Future<List<Conversation>> getConversations() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/conversations'));
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list.map((e) => Conversation.fromJson(e)).toList();
    }
    return [];
  }

  static Future<Conversation> getConversation(int id) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/conversations/$id'));
    if (response.statusCode == 200) {
      return Conversation.fromJson(jsonDecode(response.body));
    }
    throw Exception('Conversation not found');
  }

  static Future<void> deleteConversation(int id) async {
    await http.delete(Uri.parse('$_baseUrl/api/conversations/$id'));
  }

  // ─── Keys ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getKeys() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/keys'));
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    return [];
  }

  static Future<void> addKey(String platform, String key, {String? label}) async {
    await http.post(
      Uri.parse('$_baseUrl/api/keys'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'platform': platform,
        'key': key,
        if (label != null) 'label': label,
      }),
    );
  }

  static Future<void> deleteKey(int id) async {
    await http.delete(Uri.parse('$_baseUrl/api/keys/$id'));
  }
}
