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
    var received = 0;

    try {
      try {
        // Primary path: Agent Gateway WebSocket (plan + tools + tokens).
        await for (final evt in ApiService.streamAgentMessage(
          message: content,
          conversationId: _currentConversationId,
          model: modelArg,
        )) {
          received++;
          handleEvent(evt);
        }
      } catch (wsErr) {
        // Fall back to the SSE endpoint only if the WebSocket produced nothing
        // (prevents a duplicated answer when the socket fails mid-stream).
        if (received > 0) rethrow;
        await for (final chunk in ApiService.streamMessage(
          message: content,
          conversationId: _currentConversationId,
          model: modelArg,
        )) {
          if (chunk['error'] != null) throw Exception(chunk['error'].toString());
          if (chunk['model'] != null) model = chunk['model'].toString();
          if (chunk['platform'] != null) platform = chunk['platform'].toString();
          final piece = chunk['content']?.toString() ?? '';
          if (piece.isNotEmpty) handleEvent({'type': 'token', 'content': piece});
          if (chunk['done'] == true) {
            handleEvent({
              'type': 'done',
              'conversation_id': chunk['conversationId'] ?? chunk['conversation_id'],
              'model': chunk['model'],
              'platform': chunk['platform'],
            });
          }
        }
      }

      // Finalize the streamed message.
      updateAssistant(streaming: false);
      _currentModel = model;
      _currentPlatform = platform;
      await loadConversations();
    } catch (e) {
      // Drop the (possibly partial) assistant placeholder on failure.
      if (assistantIndex < _messages.length &&
          _messages[assistantIndex].role == 'assistant') {
        _messages.removeAt(assistantIndex);
      }
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
