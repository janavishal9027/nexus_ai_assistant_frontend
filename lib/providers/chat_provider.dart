import 'dart:async';
import 'package:flutter/material.dart';
import '../models/conversation.dart';
import '../services/api_service.dart';

class ChatProvider extends ChangeNotifier {
  // Config from backend (single source of truth)
  Map<String, dynamic> _config = {};
  List<Map<String, dynamic>> _providers = [];

  // Conversations
  List<Conversation> _conversations = [];
  int? _currentConversationId;
  List<Message> _messages = [];

  // UI state
  bool _isLoading = false;
  bool _configLoaded = false;
  String? _error;
  String? _currentModel;
  String? _currentPlatform;
  String _selectedModel = 'auto';
  // Deep Research mode: routes only to large (>=400B) models and always
  // gathers live web context for a thorough, cited answer.
  bool _deepResearch = false;
  // Web Search mode: forces a live web search for this turn. Mutually
  // exclusive with Deep Research (only one mode active at a time).
  bool _webSearch = false;

  // In-flight generation control (cancel / timeout).
  StreamSubscription<Map<String, dynamic>>? _activeSub;
  Completer<void>? _turnCompleter;
  bool _stopped = false;
  bool get isGenerating => _isLoading;

  // Getters
  Map<String, dynamic> get config => _config;
  List<Map<String, dynamic>> get providers => _providers;
  List<Map<String, dynamic>> get activeProviders =>
      _providers.where((p) => p['active'] == true).toList();
  List<Conversation> get conversations => _conversations;
  int? get currentConversationId => _currentConversationId;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get configLoaded => _configLoaded;
  String? get error => _error;
  String? get currentModel => _currentModel;
  String? get currentPlatform => _currentPlatform;
  String get selectedModel => _selectedModel;
  bool get deepResearch => _deepResearch;
  bool get webSearch => _webSearch;

  /// Get all models from active (keyed) providers only.
  List<Map<String, dynamic>> get availableModels {
    final models = <Map<String, dynamic>>[];
    for (final provider in activeProviders) {
      final providerModels = provider['models'] as List? ?? [];
      for (final model in providerModels) {
        if (model is Map<String, dynamic>) {
          models.add({
            ...model,
            'platform': provider['id']?.toString() ?? '',
            'platformName': provider['name']?.toString() ?? '',
          });
        }
      }
    }
    return models;
  }

  /// Check if there are any usable providers (have keys).
  bool get hasActiveProviders => activeProviders.isNotEmpty;

  void setSelectedModel(String model) {
    _selectedModel = model;
    notifyListeners();
  }

  void toggleDeepResearch() {
    _deepResearch = !_deepResearch;
    if (_deepResearch) _webSearch = false; // modes are mutually exclusive
    notifyListeners();
  }

  void toggleWebSearch() {
    _webSearch = !_webSearch;
    if (_webSearch) _deepResearch = false; // modes are mutually exclusive
    notifyListeners();
  }

  /// Load config + conversations for the current account. Resets first so
  /// switching accounts never shows the previous user's data.
  Future<void> initialize() async {
    reset();
    try {
      await loadConfig();
    } catch (_) {}
    try {
      await loadConversations();
    } catch (_) {}
  }

  /// Clear all per-account state (used on login/logout / account switch).
  void reset() {
    _conversations = [];
    _messages = [];
    _currentConversationId = null;
    _currentModel = null;
    _currentPlatform = null;
    _error = null;
    notifyListeners();
  }

  /// Load the unified config from backend.
  Future<void> loadConfig() async {
    try {
      _config = await ApiService.getConfig();
      _providers = (_config['providers'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];
      _configLoaded = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to connect to backend: $e';
      notifyListeners();
    }
  }

  Future<void> loadConversations() async {
    try {
      _conversations = await ApiService.getConversations();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> selectConversation(int id) async {
    try {
      _currentConversationId = id;
      final conv = await ApiService.getConversation(id);
      _messages = conv.messages ?? [];
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void startNewChat() {
    _currentConversationId = null;
    _messages = [];
    _currentModel = null;
    _currentPlatform = null;
    _error = null;
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    _messages.add(Message(role: 'user', content: content));
    _isLoading = true;
    _stopped = false;
    _error = null;
    notifyListeners();

    // Live agent activity (plan steps + tools) surfaced during streaming.
    final activity = AgentActivity();

    // Placeholder assistant message that we update as events stream in.
    _messages.add(Message(role: 'assistant', content: '', isStreaming: true, activity: activity));
    final assistantIndex = _messages.length - 1;
    notifyListeners();

    final buffer = StringBuffer();
    String? model;
    String? platform;
    // Repaint at most ~16fps while streaming so we don't re-parse the whole
    // markdown/code on every token (fast providers emit 100+ tokens/sec).
    DateTime lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

    // Replace the placeholder with the latest streamed text + activity.
    void updateAssistant({required bool streaming}) {
      if (assistantIndex >= _messages.length) return;
      _messages[assistantIndex] = Message(
        role: 'assistant',
        content: buffer.toString(),
        model: model,
        platform: platform,
        isStreaming: streaming,
        activity: activity.isEmpty ? null : activity,
      );
    }

    // Apply one normalized agent event to the streaming message.
    void handleEvent(Map<String, dynamic> evt) {
      if (evt['model'] != null) model = evt['model'].toString();
      if (evt['platform'] != null) platform = evt['platform'].toString();
      switch (evt['type']) {
        case 'plan_created':
          final subs = (evt['subtasks'] as List?) ?? [];
          activity.planSteps = subs
              .map((s) => (s is Map ? s['description']?.toString() : s?.toString()) ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          updateAssistant(streaming: true);
          notifyListeners();
          break;
        case 'tool_start':
          activity.tools.add(ToolActivity(name: evt['tool_name']?.toString() ?? 'tool'));
          updateAssistant(streaming: true);
          notifyListeners();
          break;
        case 'tool_end':
          final name = evt['tool_name']?.toString();
          final dur = (evt['duration_ms'] as num?)?.toDouble();
          for (final t in activity.tools.reversed) {
            if (t.name == name && t.running) {
              t.running = false;
              t.durationMs = dur;
              break;
            }
          }
          updateAssistant(streaming: true);
          notifyListeners();
          break;
        case 'token':
          final piece = evt['content']?.toString() ?? '';
          if (piece.isNotEmpty) {
            buffer.write(piece);
            final now = DateTime.now();
            if (now.difference(lastPaint).inMilliseconds >= 60) {
              updateAssistant(streaming: true);
              notifyListeners();
              lastPaint = now;
            }
          }
          break;
        case 'done':
          if (evt['model'] != null) model = evt['model'].toString();
          if (evt['platform'] != null) platform = evt['platform'].toString();
          final cid = evt['conversation_id'] ?? evt['conversationId'];
          if (cid != null) {
            _currentConversationId = cid is int ? cid : int.tryParse(cid.toString());
          }
          break;
        case 'error':
          throw Exception(evt['message']?.toString() ?? 'Agent error');
      }
    }

    final modelArg = _selectedModel == 'auto' ? null : _selectedModel;
    int received = 0;

    // Consume a normalized event stream via a cancelable subscription. A 45s
    // inter-event timeout catches a hung/very-slow provider (e.g. all models
    // rate-limited) instead of leaving the UI spinning indefinitely.
    Future<void> consume(Stream<Map<String, dynamic>> src) {
      final completer = Completer<void>();
      _turnCompleter = completer;
      _activeSub = src
          .timeout(const Duration(seconds: 45), onTimeout: (sink) {
            sink.addError(TimeoutException('The model took too long to respond.'));
          })
          .listen(
        (evt) {
          received++;
          try {
            handleEvent(evt);
          } catch (e) {
            if (!completer.isCompleted) completer.completeError(e);
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      return completer.future;
    }

    try {
      try {
        // Primary path: Agent Gateway WebSocket (plan + tools + tokens).
        await consume(ApiService.streamAgentMessage(
          message: content,
          conversationId: _currentConversationId,
          model: modelArg,
          deepResearch: _deepResearch,
          webSearch: _webSearch,
        ));
      } catch (wsErr) {
        // Fall back to SSE only if the WebSocket produced nothing and the user
        // didn't cancel (prevents a duplicated answer / a fallback after stop).
        if (_stopped || received > 0) rethrow;
        await consume(_sseAsEvents(ApiService.streamMessage(
          message: content,
          conversationId: _currentConversationId,
          model: modelArg,
          deepResearch: _deepResearch,
          webSearch: _webSearch,
        )));
      }

      // Finalize the streamed message.
      updateAssistant(streaming: false);
      _currentModel = model;
      _currentPlatform = platform;
      await loadConversations();
    } catch (e) {
      if (_stopped) {
        // User cancelled: keep whatever streamed so far, drop an empty bubble.
        if (buffer.isNotEmpty) {
          updateAssistant(streaming: false);
        } else if (assistantIndex < _messages.length &&
            _messages[assistantIndex].role == 'assistant') {
          _messages.removeAt(assistantIndex);
        }
      } else {
        if (buffer.isEmpty &&
            assistantIndex < _messages.length &&
            _messages[assistantIndex].role == 'assistant') {
          _messages.removeAt(assistantIndex);
        } else {
          updateAssistant(streaming: false);
        }
        _error = _friendlyError(e);
      }
    } finally {
      await _activeSub?.cancel();
      _activeSub = null;
      _turnCompleter = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Edit an earlier user message and re-run the turn. Truncates the
  /// conversation at [index] (dropping the old message and its reply — on the
  /// backend too, so a reload stays consistent), then resends the edited text.
  Future<void> editAndResend(int index, String newText) async {
    if (_isLoading) return;
    final text = newText.trim();
    if (text.isEmpty) return;
    if (index < 0 || index >= _messages.length) return;

    final cid = _currentConversationId;
    if (cid != null) {
      try {
        await ApiService.truncateConversation(cid, index);
      } catch (_) {
        // Non-fatal: still resend locally even if backend truncation failed.
      }
    }
    // Drop the old user message at `index` and everything after it.
    _messages.removeRange(index, _messages.length);
    notifyListeners();

    await sendMessage(text);
  }

  /// Cancel an in-flight generation. Closes the socket immediately (works even
  /// if no tokens have arrived yet) and keeps any partial text already streamed.
  Future<void> stopGeneration() async {
    if (!_isLoading) return;
    _stopped = true;
    await _activeSub?.cancel();
    if (_turnCompleter != null && !_turnCompleter!.isCompleted) {
      _turnCompleter!.completeError(Exception('stopped'));
    }
  }

  /// Normalize the legacy SSE chunk stream into the same typed events the
  /// WebSocket path emits, so a single handler covers both.
  Stream<Map<String, dynamic>> _sseAsEvents(Stream<Map<String, dynamic>> sse) async* {
    await for (final chunk in sse) {
      if (chunk['error'] != null) {
        yield {'type': 'error', 'message': chunk['error'].toString()};
        return;
      }
      final piece = chunk['content']?.toString() ?? '';
      if (piece.isNotEmpty) {
        yield {
          'type': 'token',
          'content': piece,
          'model': chunk['model'],
          'platform': chunk['platform'],
        };
      }
      if (chunk['done'] == true) {
        yield {
          'type': 'done',
          'conversation_id': chunk['conversationId'] ?? chunk['conversation_id'],
          'model': chunk['model'],
          'platform': chunk['platform'],
        };
      }
    }
  }

  /// Turn raw errors into short, actionable guidance for the chat error banner.
  String _friendlyError(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    final lower = s.toLowerCase();
    if (e is TimeoutException || lower.contains('too long')) {
      return 'The model took too long to respond — it may be rate-limited. Try again, '
          'pick a specific model, or add a faster provider (e.g. Groq) in Settings.';
    }
    if (lower.contains('exhausted') ||
        s.contains('429') ||
        lower.contains('quota') ||
        lower.contains('rate limit') ||
        lower.contains('generation failed')) {
      return 'All available models are busy or rate-limited right now. Try again, or add '
          'another provider (Groq is fast and free) in Settings.';
    }
    return s.isEmpty ? 'Something went wrong. Please try again.' : s;
  }

  Future<void> deleteConversation(int id) async {
    try {
      await ApiService.deleteConversation(id);
      _conversations.removeWhere((c) => c.id == id);
      if (_currentConversationId == id) {
        startNewChat();
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> renameConversation(int id, String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    try {
      await ApiService.renameConversation(id, t);
      await loadConversations();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
