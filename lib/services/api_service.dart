import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/knowledge_base.dart';
import '../models/chat_attachment.dart';
import '../models/clarify.dart';
import '../models/backend_status.dart';
import '../models/project.dart';

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

  // ─── Backend status probe (A.6) ───────────────────────────────────────
  /// Classify the backend's health: online / degraded (reachable, a dependency
  /// failing) / restarting (proxy 5xx) / unreachable (network/timeout).
  static Future<({BackendStatus status, String? detail})> probeHealth() async {
    try {
      final r = await http
          .get(Uri.parse('$_baseUrl/api/health'), headers: _headers(json: false))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final b = _tryJson(r.body);
        if ((b['status'] ?? 'healthy') == 'degraded') {
          final comps = (b['components'] as Map?) ?? const {};
          final down = comps.entries
              .where((e) => e.value != 'healthy')
              .map((e) => e.key)
              .join(', ');
          return (
            status: BackendStatus.degraded,
            detail: down.isNotEmpty ? '$down unavailable' : 'A dependency is failing',
          );
        }
        return (status: BackendStatus.online, detail: null);
      }
      if (r.statusCode == 502 || r.statusCode == 503 || r.statusCode == 504) {
        return (status: BackendStatus.restarting, detail: 'Server restarting (HTTP ${r.statusCode})');
      }
      return (status: BackendStatus.degraded, detail: 'Unexpected response (HTTP ${r.statusCode})');
    } on TimeoutException {
      return (status: BackendStatus.unreachable, detail: 'Connection timed out');
    } catch (_) {
      return (status: BackendStatus.unreachable, detail: 'Cannot reach the server');
    }
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

  /// Pre-flight clarification gate (chat-module A.2). Returns a blocking
  /// question if one is needed, else null. Fails open (null) on any error so a
  /// clarifier hiccup never blocks a chat.
  /// Pre-flight clarification (A.2). Returns the list of questions to ask (a
  /// request can be ambiguous in several ways); empty if nothing to clarify.
  static Future<List<ClarifyQuestion>> clarify({
    required String message,
    List<Message>? history,
    String? model,
  }) async {
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl/api/chat/clarify'),
        headers: _headers(),
        body: jsonEncode({
          'message': message,
          if (history != null) 'history': history.map((m) => m.toJson()).toList(),
          if (model != null) 'model': model,
        }),
      );
      if (r.statusCode == 200) {
        final b = _tryJson(r.body);
        if (b['clarify'] == true) {
          final list = (b['questions'] as List?) ?? const [];
          if (list.isNotEmpty) {
            return list
                .map((q) => ClarifyQuestion.fromJson(q as Map<String, dynamic>))
                .toList();
          }
          // Backward-compat: a single `question`.
          if (b['question'] != null) {
            return [ClarifyQuestion.fromJson(b['question'] as Map<String, dynamic>)];
          }
        }
      }
    } catch (_) {/* fail open */}
    return const [];
  }

  /// Post-turn follow-up suggestions (chat-module A.2 · Suggester). Fails open.
  static Future<List<String>> suggestFollowups({
    required int conversationId,
    String? model,
  }) async {
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl/api/chat/suggest'),
        headers: _headers(),
        body: jsonEncode({
          'conversation_id': conversationId,
          if (model != null) 'model': model,
        }),
      );
      if (r.statusCode == 200) {
        final list = (_tryJson(r.body)['suggestions'] as List?) ?? [];
        return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {/* fail open */}
    return [];
  }

  /// Persist a 👍/👎 on an assistant message (Part D memory — the Reflector
  /// learns what lands). rating: +1 up, -1 down, 0 clears. Fails open.
  static Future<void> submitFeedback({
    int? conversationId,
    int? messageIndex,
    required int rating,
    String? assistantText,
  }) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/chat/feedback'),
        headers: _headers(),
        body: jsonEncode({
          'conversation_id': conversationId,
          'message_index': messageIndex,
          'rating': rating,
          if (assistantText != null) 'assistant_text': assistantText,
        }),
      );
    } catch (_) {/* fail open */}
  }

  // ── Part D memory lifecycle (retention / export / purge) ──────────────────

  /// Counts + top skills for the "Memory & Privacy" view. Fails open.
  static Future<Map<String, dynamic>> getMemorySummary() async {
    try {
      final r = await http.get(Uri.parse('$_baseUrl/api/memory'), headers: _headers());
      if (r.statusCode == 200) return _tryJson(r.body);
    } catch (_) {/* fail open */}
    return {};
  }

  /// Full memory export (episodic + skills + feedback) as JSON. Null on failure.
  static Future<Map<String, dynamic>?> exportMemory() async {
    try {
      final r = await http.get(Uri.parse('$_baseUrl/api/memory/export'), headers: _headers());
      if (r.statusCode == 200) return _tryJson(r.body);
    } catch (_) {/* fail open */}
    return null;
  }

  /// Clear the user's memory. scope ∈ {all, episodic, skills, feedback}.
  static Future<bool> purgeMemory({String scope = 'all'}) async {
    try {
      final r = await http.delete(Uri.parse('$_baseUrl/api/memory?scope=$scope'),
          headers: _headers());
      return r.statusCode == 200;
    } catch (_) {/* fail open */}
    return false;
  }

  /// Backend document triage (A.4): is this content export-worthy and in which
  /// formats? Fails open (document:false, empty).
  static Future<({bool document, String? format, List<String> formats})>
      documentDecision(String content) async {
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl/api/chat/document-decision'),
        headers: _headers(),
        body: jsonEncode({'content': content}),
      );
      if (r.statusCode == 200) {
        final b = _tryJson(r.body);
        return (
          document: b['document'] == true,
          format: b['format'] as String?,
          formats: ((b['formats'] as List?) ?? []).map((e) => e.toString()).toList(),
        );
      }
    } catch (_) {/* fail open */}
    return (document: false, format: null, formats: const <String>[]);
  }

  /// Generate a downloadable document (A.4) from answer content. Returns the
  /// file bytes and the server's suggested filename.
  /// Export answer [content] to a downloadable file. [clean] true (the
  /// in-response download) strips the chat wrapper to just the requested
  /// document; false (the Export menu) keeps the whole response.
  static Future<({Uint8List bytes, String filename})> exportDocument({
    required String content,
    required String format,
    String? title,
    bool clean = true,
  }) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/chat/export'),
      headers: _headers(),
      body: jsonEncode({
        'content': content,
        'format': format,
        'clean': clean,
        if (title != null) 'title': title,
      }),
    );
    if (r.statusCode == 200) {
      final fn = r.headers['x-filename'] ?? 'document';
      return (bytes: r.bodyBytes, filename: fn);
    }
    throw Exception(_tryJson(r.body)['detail']?.toString() ??
        'Export failed (HTTP ${r.statusCode})');
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
    List<ChatAttachment>? attachments,
  }) async* {
    final body = <String, dynamic>{'message': message};
    if (conversationId != null) body['conversation_id'] = conversationId;
    if (model != null) body['model'] = model;
    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    if (history != null) body['history'] = history.map((m) => m.toJson()).toList();
    if (deepResearch) body['deep_research'] = true;
    if (webSearch) body['web_search'] = true;
    if (attachments != null && attachments.isNotEmpty) {
      body['attachments'] = attachments.map((a) => a.toJson()).toList();
    }

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

  /// Branch a conversation's history (messages up to index [upTo], inclusive)
  /// into another chat — a brand-new one ([targetConversationId] null) or an
  /// existing target. Returns the target conversation id.
  static Future<int> branchConversation(int id, int upTo,
      {int? targetConversationId}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/conversations/$id/branch'),
      headers: _headers(),
      body: jsonEncode({
        'up_to': upTo,
        if (targetConversationId != null)
          'target_conversation_id': targetConversationId,
      }),
    );
    if (response.statusCode == 200) {
      return (jsonDecode(response.body)['conversation_id'] as num).toInt();
    }
    throw Exception('Failed to branch conversation (HTTP ${response.statusCode})');
  }

  /// Promote a branch to a top-level chat (clears its parent link), so it
  /// survives when its parent is deleted.
  static Future<void> detachConversation(int id) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/conversations/$id/detach'),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to detach conversation (HTTP ${response.statusCode})');
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

  /// Adds a provider key. Returns the response body, which includes
  /// `models_synced` (how many of that provider's models were synced) and
  /// `sync_error` (non-null if the model fetch failed).
  static Future<Map<String, dynamic>> addKey(String platform, String key,
      {String? label}) async {
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
    try {
      final body = jsonDecode(response.body);
      return body is Map<String, dynamic> ? body : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> deleteKey(int id) async {
    await http.delete(Uri.parse('$_baseUrl/api/keys/$id'), headers: _headers(json: false));
  }

  // ─── Knowledge Base (RAG) ─────────────────────────────────────────────
  static Future<List<KnowledgeBase>> listKnowledgeBases() async {
    final r = await http.get(Uri.parse('$_baseUrl/api/kb'), headers: _headers(json: false));
    if (r.statusCode == 200) {
      return (jsonDecode(r.body) as List)
          .map((e) => KnowledgeBase.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static Future<KnowledgeBase> createKnowledgeBase(String name, {String? description}) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/kb'),
      headers: _headers(),
      body: jsonEncode({'name': name, if (description != null) 'description': description}),
    );
    if (r.statusCode == 200) return KnowledgeBase.fromJson(jsonDecode(r.body));
    throw Exception(_tryJson(r.body)['detail']?.toString() ?? 'Failed to create (HTTP ${r.statusCode})');
  }

  static Future<KnowledgeBase> getKnowledgeBase(int id) async {
    final r = await http.get(Uri.parse('$_baseUrl/api/kb/$id'), headers: _headers(json: false));
    if (r.statusCode == 200) return KnowledgeBase.fromJson(jsonDecode(r.body));
    throw Exception('Knowledge base not found');
  }

  static Future<void> updateKnowledgeBase(int id, {String? name, String? description}) async {
    final r = await http.patch(
      Uri.parse('$_baseUrl/api/kb/$id'),
      headers: _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      }),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Failed to update (HTTP ${r.statusCode})');
    }
  }

  static Future<void> deleteKnowledgeBase(int id) async {
    final r = await http.delete(Uri.parse('$_baseUrl/api/kb/$id'), headers: _headers(json: false));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Failed to delete (HTTP ${r.statusCode})');
    }
  }

  static Future<List<KbDocument>> listDocuments(int kbId) async {
    final r = await http.get(Uri.parse('$_baseUrl/api/kb/$kbId/documents'), headers: _headers(json: false));
    if (r.statusCode == 200) {
      return (jsonDecode(r.body) as List)
          .map((e) => KbDocument.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Upload a document (multipart). Returns the created document + job id.
  static Future<Map<String, dynamic>> uploadDocument(
      int kbId, String filename, List<int> bytes) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/api/kb/$kbId/documents'));
    if (isAuthenticated) req.headers['Authorization'] = 'Bearer $_authToken';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
      return jsonDecode(body) as Map<String, dynamic>;
    }
    throw Exception(_tryJson(body)['detail']?.toString() ??
        'Upload failed (HTTP ${streamed.statusCode})');
  }

  static Future<IngestionJob> getDocumentJob(int kbId, int docId) async {
    final r = await http.get(
        Uri.parse('$_baseUrl/api/kb/$kbId/documents/$docId/job'),
        headers: _headers(json: false));
    if (r.statusCode == 200) return IngestionJob.fromJson(jsonDecode(r.body));
    throw Exception('No ingestion job');
  }

  static Future<void> deleteDocument(int kbId, int docId) async {
    final r = await http.delete(
        Uri.parse('$_baseUrl/api/kb/$kbId/documents/$docId'),
        headers: _headers(json: false));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Failed to delete document (HTTP ${r.statusCode})');
    }
  }

  static Future<void> reingestDocument(int kbId, int docId) async {
    final r = await http.post(
        Uri.parse('$_baseUrl/api/kb/$kbId/documents/$docId/reingest'),
        headers: _headers(json: false));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Failed to re-ingest (HTTP ${r.statusCode})');
    }
  }

  static Future<List<SourceChunk>> searchKnowledgeBase(int kbId, String query, {int? topK}) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/kb/$kbId/search'),
      headers: _headers(),
      body: jsonEncode({'query': query, if (topK != null) 'top_k': topK}),
    );
    if (r.statusCode == 200) {
      final list = (jsonDecode(r.body)['sources'] as List?) ?? [];
      return list.map((e) => SourceChunk.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception(_tryJson(r.body)['detail']?.toString() ?? 'Search failed (HTTP ${r.statusCode})');
  }

  /// Grounded streaming chat against a KB. Yields SSE events: the first carries
  /// `sources` (citations), then `content` deltas, then a final `done` event
  /// with `conversationId`.
  static Stream<Map<String, dynamic>> streamKbChat({
    required int kbId,
    required String query,
    int? conversationId,
    String? model,
    List<Message>? history,
  }) async* {
    final body = <String, dynamic>{'query': query};
    if (conversationId != null) body['conversation_id'] = conversationId;
    if (model != null) body['model'] = model;
    if (history != null) body['history'] = history.map((m) => m.toJson()).toList();

    final request = http.Request('POST', Uri.parse('$_baseUrl/api/kb/$kbId/chat/stream'));
    request.headers.addAll(_headers());
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        final err = await response.stream.bytesToString();
        throw Exception(_tryJson(err)['error']?.toString() ??
            'Chat failed (HTTP ${response.statusCode})');
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

  static Future<List<Conversation>> listKbConversations(int kbId) async {
    final r = await http.get(
        Uri.parse('$_baseUrl/api/kb/$kbId/conversations'), headers: _headers(json: false));
    if (r.statusCode == 200) {
      return (jsonDecode(r.body) as List).map((e) => Conversation.fromJson(e)).toList();
    }
    return [];
  }

  static Future<Conversation> getKbConversation(int kbId, int convId) async {
    final r = await http.get(
        Uri.parse('$_baseUrl/api/kb/$kbId/conversations/$convId'),
        headers: _headers(json: false));
    if (r.statusCode == 200) return Conversation.fromJson(jsonDecode(r.body));
    throw Exception('Conversation not found');
  }

  // ─── Projects (A.7) ────────────────────────────────────────────────────
  static Future<List<Project>> listProjects() async {
    final r = await http.get(Uri.parse('$_baseUrl/api/projects'), headers: _headers(json: false));
    if (r.statusCode == 200) {
      return (jsonDecode(r.body) as List)
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static Future<Project> createProject(String name, {String? instructions}) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/projects'),
      headers: _headers(),
      body: jsonEncode({'name': name, if (instructions != null) 'instructions': instructions}),
    );
    if (r.statusCode == 200) return Project.fromJson(jsonDecode(r.body));
    throw Exception(_tryJson(r.body)['detail']?.toString() ?? 'Failed to create project');
  }

  static Future<void> updateProject(int id, {String? name, String? instructions}) async {
    final r = await http.patch(
      Uri.parse('$_baseUrl/api/projects/$id'),
      headers: _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (instructions != null) 'instructions': instructions,
      }),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Failed to update project (HTTP ${r.statusCode})');
    }
  }

  static Future<void> deleteProject(int id, {bool deleteConversations = false}) async {
    final r = await http.delete(
      Uri.parse('$_baseUrl/api/projects/$id?delete_conversations=$deleteConversations'),
      headers: _headers(json: false),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Failed to delete project (HTTP ${r.statusCode})');
    }
  }

  /// Group a conversation under a project, or ungroup it ([projectId] null).
  static Future<void> assignConversationToProject(int conversationId, int? projectId) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/conversations/$conversationId/assign'),
      headers: _headers(),
      body: jsonEncode({'project_id': projectId}),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Failed to move conversation (HTTP ${r.statusCode})');
    }
  }

  /// The project's auto-learned "brain": facts / decisions / conventions /
  /// goals the assistant distilled from the project's chats (Part D Phase 4).
  static Future<List<Map<String, dynamic>>> getProjectBrain(int projectId) async {
    final r = await http.get(Uri.parse('$_baseUrl/api/projects/$projectId/brain'),
        headers: _headers(json: false));
    if (r.statusCode == 200) {
      final entries = (jsonDecode(r.body) as Map<String, dynamic>)['entries'];
      return (entries as List? ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// Prune a single brain entry.
  static Future<void> deleteBrainEntry(int projectId, int entryId) async {
    final r = await http.delete(
      Uri.parse('$_baseUrl/api/projects/$projectId/brain/$entryId'),
      headers: _headers(json: false),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Failed to delete brain entry (HTTP ${r.statusCode})');
    }
  }

  /// The project's content knowledge graph: {nodes:[...], edges:[...]}.
  static Future<Map<String, dynamic>> getProjectGraph(int projectId) async {
    final r = await http.get(Uri.parse('$_baseUrl/api/projects/$projectId/graph'),
        headers: _headers(json: false));
    if (r.statusCode == 200) {
      return (jsonDecode(r.body) as Map).cast<String, dynamic>();
    }
    return const {'nodes': [], 'edges': []};
  }
}
