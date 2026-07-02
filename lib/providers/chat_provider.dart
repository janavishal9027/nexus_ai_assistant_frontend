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

  /// Load config + conversations on startup.
  Future<void> initialize() async {
    try {
      await loadConfig();
    } catch (_) {}
    try {
      await loadConversations();
    } catch (_) {}
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

    _messages.add(Message(role: 'assistant', content: '', isStreaming: true));
    notifyListeners();

    try {
      final response = await ApiService.sendMessage(
        message: content,
        conversationId: _currentConversationId,
        model: _selectedModel == 'auto' ? null : _selectedModel,
      );

      if (response['conversation_id'] != null) {
        _currentConversationId = response['conversation_id'];
      } else if (response['conversationId'] != null) {
        _currentConversationId = response['conversationId'];
      }

      _messages.removeLast();
      _messages.add(Message(
        role: 'assistant',
        content: response['content'] ?? '',
        model: response['model'],
        platform: response['platform'],
      ));

      _currentModel = response['model'];
      _currentPlatform = response['platform'];

      await loadConversations();
    } catch (e) {
      _messages.removeLast();
      _error = e.toString();
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
