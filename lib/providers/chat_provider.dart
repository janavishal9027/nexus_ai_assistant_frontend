import 'dart:async';
import 'package:flutter/material.dart';
import '../models/conversation.dart';
import '../models/chat_attachment.dart';
import '../models/clarify.dart';
import '../models/project.dart';
import '../services/api_service.dart';

class ChatProvider extends ChangeNotifier {
  // Config from backend (single source of truth)
  Map<String, dynamic> _config = {};
  List<Map<String, dynamic>> _providers = [];

  // Conversations
  List<Conversation> _conversations = [];
  int? _currentConversationId;
  List<Message> _messages = [];

  // Projects (A.7)
  List<Project> _projects = [];
  List<Project> get projects => _projects;
  // A chat started "in a project": the conversation record doesn't exist until
  // the first message is sent, so remember the target project and assign the
  // conversation to it once the backend creates it.
  int? _pendingProjectId;
  int? get pendingProjectId => _pendingProjectId;

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
  // A "new chat" branch that hasn't been saved yet — it's created on the backend
  // only when the user actually sends a message, so branching without asking
  // anything never leaves a duplicate chat behind.
  int? _pendingBranchSource;
  int? _pendingBranchUpTo;

  // In-flight generation control (cancel / timeout).
  StreamSubscription<Map<String, dynamic>>? _activeSub;
  Completer<void>? _turnCompleter;
  bool _stopped = false;
  bool get isGenerating => _isLoading;
  // The message list the in-flight stream writes to. When it matches the
  // on-screen list, the current view is the one generating (A.5 · #4).
  List<Message>? _streamMessagesRef;
  bool get isBusyHere => _isLoading && identical(_streamMessagesRef, _messages);

  // ── Clarifier (chat-module A.2) ─────────────────────────────────────────
  // A blocking clarifying question raised before the answer, plus the parked
  // original inputs so the turn can resume once it's answered.
  // A turn can be ambiguous in several ways, so the clarifier may ask more than
  // one question; the panel shows them together and we resume once answered.
  List<ClarifyQuestion> _pendingClarify = [];
  String? _clarifyOriginal;
  List<ChatAttachment>? _clarifyAttachments;
  bool _clarifyChecking = false;
  // Export format(s) the user asked for on THIS turn; applied to the finished
  // answer so its bubble offers one-click downloads. Consumed each turn.
  List<String>? _pendingDownloadFormats;
  List<ClarifyQuestion> get pendingClarify => _pendingClarify;
  bool get clarifyChecking => _clarifyChecking;

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
    try {
      await loadProjects();
    } catch (_) {}
  }

  /// Clear all per-account state (used on login/logout / account switch).
  void reset() {
    _conversations = [];
    _projects = [];
    _messages = [];
    _currentConversationId = null;
    _currentModel = null;
    _currentPlatform = null;
    _pendingProjectId = null;
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

  Future<void> loadProjects() async {
    try {
      _projects = await ApiService.listProjects();
      notifyListeners();
    } catch (_) {/* non-fatal */}
  }

  Future<Project> createProject(String name, {String? instructions}) async {
    final p = await ApiService.createProject(name, instructions: instructions);
    await loadProjects();
    return p;
  }

  Future<void> updateProject(int id, {String? name, String? instructions}) async {
    await ApiService.updateProject(id, name: name, instructions: instructions);
    await loadProjects();
  }

  Future<void> deleteProject(int id, {bool deleteConversations = false}) async {
    await ApiService.deleteProject(id, deleteConversations: deleteConversations);
    // If the current chat was deleted with the project, reset to a new chat.
    if (deleteConversations &&
        _currentConversationId != null &&
        _conversations.any((c) =>
            c.id == _currentConversationId && c.projectId == id)) {
      startNewChat();
    }
    await loadProjects();
    await loadConversations();
  }

  Future<void> assignToProject(int conversationId, int? projectId) async {
    await ApiService.assignConversationToProject(conversationId, projectId);
    await loadProjects();
    await loadConversations();
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
    _pendingBranchSource = null;
    _pendingBranchUpTo = null;
    _clearClarify();
    try {
      _currentConversationId = id;
      final conv = await ApiService.getConversation(id);
      _messages = _withDerivedDownloads(conv.messages ?? []);
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Server history has no `downloadFormats` (it isn't persisted), so re-derive
  /// each assistant message's download format(s) from the user turn that
  /// produced it — the format the user asked for (named directly, or folded in
  /// as "Doc format: PDF"). This makes the one-click download buttons show on
  /// EVERY device / after reload, not only where the turn originally ran.
  List<Message> _withDerivedDownloads(List<Message> msgs) {
    final out = <Message>[];
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.role == 'assistant' &&
          m.content.trim().isNotEmpty &&
          i > 0 &&
          msgs[i - 1].role == 'user') {
        final fmts = _documentIntent(msgs[i - 1].content).formats;
        out.add(fmts.isEmpty ? m : m.copyWith(downloadFormats: fmts));
      } else {
        out.add(m);
      }
    }
    return out;
  }

  void startNewChat() {
    _currentConversationId = null;
    _pendingBranchSource = null;
    _pendingBranchUpTo = null;
    _pendingProjectId = null;
    _clearClarify();
    _messages = [];
    _currentModel = null;
    _currentPlatform = null;
    _error = null;
    notifyListeners();
  }

  /// Start a fresh chat that will belong to [projectId]. The conversation is
  /// created on first send; it's then auto-assigned to the project (see the
  /// send flow). Until then it's an unsaved draft, like a new branch chat.
  void startNewChatInProject(int projectId) {
    startNewChat();
    _pendingProjectId = projectId;
    notifyListeners();
  }

  /// Entry point the composer calls. Runs the Clarifier pre-flight gate: if a
  /// required detail is missing it raises a blocking question (docked panel);
  /// otherwise it sends normally. The existing sendMessage flow is untouched.
  Future<void> sendUserMessage(String content, {List<ChatAttachment>? attachments}) async {
    if (_clarifyChecking) return;
    if (_isLoading) {
      // A stream is still running (possibly for another chat) — one at a time.
      _error = 'Please wait for the current response to finish.';
      notifyListeners();
      return;
    }
    // A fresh send from the composer abandons any unanswered clarify panel.
    _pendingClarify = [];
    _clarifyOriginal = null;
    _clarifyAttachments = null;
    _pendingDownloadFormats = null;
    final hasAttachments = attachments != null && attachments.isNotEmpty;
    final text = content.trim();

    // Explicitly-named download format(s) → remember them so the finished answer
    // offers a one-click download (no need to ask which format).
    final intent = _documentIntent(content);
    _pendingDownloadFormats = intent.formats.isEmpty ? null : intent.formats;

    // Clarifier pre-flight (text turns): a request can be underspecified in
    // several ways, so this may return MORE THAN ONE question (e.g. language +
    // which spaces + output format). Attachments usually resolve ambiguity, so
    // the clarifier is skipped there — but a download-without-a-format still asks.
    if (text.isNotEmpty && !hasAttachments) {
      _clarifyChecking = true;
      notifyListeners();
      final modelArg = _selectedModel == 'auto' ? null : _selectedModel;
      final questions = await ApiService.clarify(
        message: content,
        history: _messages.where((m) => !m.isStreaming).toList(),
        model: modelArg,
      );
      _clarifyChecking = false;
      if (questions.isNotEmpty) {
        _pendingClarify = questions;
        _clarifyOriginal = content;
        _clarifyAttachments = attachments;
        notifyListeners();
        return;
      }
      notifyListeners();
    } else if (intent.ambiguous) {
      _pendingClarify = [_formatClarifyQuestion()];
      _clarifyOriginal = content;
      _clarifyAttachments = attachments;
      notifyListeners();
      return;
    }
    await sendMessage(content, attachments: attachments);
  }

  /// Answer the docked clarify panel. [answers] holds one reply per pending
  /// question (blank = unanswered). Each non-empty answer is folded into the
  /// message as "Header: answer"; a "format" question also selects the download
  /// format(s). Then the turn runs.
  Future<void> submitClarifications(List<String> answers) async {
    final qs = _pendingClarify;
    final orig = _clarifyOriginal ?? '';
    final atts = _clarifyAttachments;
    _pendingClarify = [];
    _clarifyOriginal = null;
    _clarifyAttachments = null;
    notifyListeners();

    final tags = <String>[];
    for (var i = 0; i < qs.length; i++) {
      final a = (i < answers.length ? answers[i] : '').trim();
      if (a.isEmpty) continue;
      tags.add('${qs[i].header}: $a');
      // A format question drives the one-click download(s) on the answer.
      if (qs[i].header.toLowerCase().contains('format')) {
        _pendingDownloadFormats = _formatsFromAnswer(a);
      }
    }
    final composed = tags.isEmpty ? orig : '$orig\n\n${tags.join('\n')}';
    await sendMessage(composed, attachments: atts);
  }

  /// Dismiss the panel and answer the original message anyway (the answer still
  /// has the Export menu / any explicitly-named download buttons).
  Future<void> dismissClarification() async {
    final orig = _clarifyOriginal ?? '';
    final atts = _clarifyAttachments;
    _pendingClarify = [];
    _clarifyOriginal = null;
    _clarifyAttachments = null;
    notifyListeners();
    final hasAtts = atts != null && atts.isNotEmpty;
    if (orig.trim().isNotEmpty || hasAtts) {
      await sendMessage(orig, attachments: atts);
    }
  }

  void _clearClarify() {
    _pendingClarify = [];
    _clarifyOriginal = null;
    _clarifyAttachments = null;
    _clarifyChecking = false;
  }

  // ── Downloadable-document intent (A.4) ────────────────────────────────────
  /// Read the user's request for a downloadable-document intent: which export
  /// format(s) they named, and whether they clearly want a download but named
  /// none (→ ambiguous, ask which).
  ({bool wants, List<String> formats, bool ambiguous}) _documentIntent(
      String message) {
    final t = message.toLowerCase();
    // Format → keyword pattern. Order sets the button order on the answer.
    const patterns = <String, String>{
      'word': r'\.docx|\bdocx\b|word document|word format|word file|ms ?word|'
          r'microsoft word|\bin word\b|\bas word\b',
      'pdf': r'\.pdf|\bpdf\b',
      'excel': r'\.xlsx|\bxlsx\b|\bexcel\b|spreadsheet',
      'csv': r'\.csv|\bcsv\b',
      'powerpoint': r'\.pptx|\bpptx\b|power ?point|slide deck|\bslides\b',
      'markdown': r'\.md\b|markdown',
      'text': r'\.txt|text file|plain text',
      'zip': r'\.zip|zip file|zip archive|\bzip\b',
    };
    final formats = <String>[
      for (final e in patterns.entries)
        if (RegExp(e.value).hasMatch(t)) e.key,
    ];

    // A clear "make me a file to download" intent, even without a named format.
    final downloadIntent = RegExp(
            r'download|downloadable|\bexport\b|save (it|this|them) as|'
            r'as a (file|document)|in .{0,12}format')
        .hasMatch(t);
    final wants = formats.isNotEmpty || downloadIntent;
    return (wants: wants, formats: formats, ambiguous: downloadIntent && formats.isEmpty);
  }

  ClarifyQuestion _formatClarifyQuestion() => ClarifyQuestion(
        header: 'Download format',
        question: 'Which format would you like to download?',
        multiSelect: true,
        options: [
          ClarifyOption(label: 'Word (.docx)', description: 'Editable document'),
          ClarifyOption(label: 'PDF', description: 'Portable, print-ready'),
          ClarifyOption(label: 'Excel (.xlsx)', description: 'Tables / spreadsheet'),
          ClarifyOption(label: 'PowerPoint', description: 'Slide deck'),
          ClarifyOption(label: 'Markdown', description: 'Plain .md'),
          ClarifyOption(label: 'Text', description: 'Plain .txt'),
        ],
      );

  /// Map a format-chooser answer (comma-joined labels, or a free-typed reply)
  /// to export format keys. Defaults to Word + PDF if nothing recognizable.
  List<String> _formatsFromAnswer(String answer) {
    final t = answer.toLowerCase();
    final formats = <String>[];
    void add(String f) {
      if (!formats.contains(f)) {
        formats.add(f);
      }
    }

    if (t.contains('word') || t.contains('docx')) add('word');
    if (t.contains('pdf')) add('pdf');
    if (t.contains('excel') || t.contains('xlsx')) add('excel');
    if (t.contains('power') || t.contains('pptx')) add('powerpoint');
    if (t.contains('markdown') || t.contains('.md')) add('markdown');
    if (t.contains('text') || t.contains('txt')) add('text');
    if (t.contains('csv')) add('csv');
    if (t.contains('zip')) add('zip');
    if (formats.isEmpty) {
      add('word');
      add('pdf');
    }
    return formats;
  }

  Future<void> sendMessage(String content, {List<ChatAttachment>? attachments}) async {
    final hasAttachments = attachments != null && attachments.isNotEmpty;
    if (content.trim().isEmpty && !hasAttachments) return;

    // Materialize a pending "new chat" branch on the first message: create the
    // branch on the backend now (copying the history up to the branch point) so
    // it only becomes a real conversation once the user actually asks something.
    if (_pendingBranchSource != null) {
      try {
        _currentConversationId = await ApiService.branchConversation(
            _pendingBranchSource!, _pendingBranchUpTo!);
        await loadConversations(); // surface the new branch in the sidebar
      } catch (_) {
        _currentConversationId = null; // fall back to a plain new chat
      }
      _pendingBranchSource = null;
      _pendingBranchUpTo = null;
    }

    _messages.add(Message(role: 'user', content: content, attachments: attachments));
    _isLoading = true;
    _stopped = false;
    _error = null;
    notifyListeners();

    // Live agent activity (plan steps + tools) surfaced during streaming.
    final activity = AgentActivity();

    // Placeholder assistant message that we update as events stream in.
    _messages.add(Message(role: 'assistant', content: '', isStreaming: true, activity: activity));
    final assistantIndex = _messages.length - 1;
    // Capture THIS turn's message list. If the user switches conversations
    // mid-stream, `_messages` is reassigned but the stream keeps writing here
    // (parked off-screen) and still persists to the backend — no corruption,
    // and the `done` event won't yank the current conversation id (A.5 · #4).
    final ownMessages = _messages;
    _streamMessagesRef = ownMessages;
    notifyListeners();

    final buffer = StringBuffer();
    String? model;
    String? platform;
    // Repaint at most ~16fps while streaming so we don't re-parse the whole
    // markdown/code on every token (fast providers emit 100+ tokens/sec).
    DateTime lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

    // Replace the placeholder with the latest streamed text + activity.
    void updateAssistant({required bool streaming}) {
      if (assistantIndex >= ownMessages.length) return;
      ownMessages[assistantIndex] = Message(
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
      // Bind to THIS conversation as soon as the backend reveals its id (an
      // early "conversation"/meta event, and again on "done"). Doing it up front
      // — not only on success — means a turn that fails mid-stream still binds
      // the conversation, so a Retry re-runs it in the SAME chat instead of
      // spawning a duplicate session.
      final cidAny = evt['conversation_id'] ?? evt['conversationId'];
      if (cidAny != null && identical(_messages, ownMessages)) {
        _currentConversationId =
            cidAny is int ? cidAny : int.tryParse(cidAny.toString());
      }
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
          // model / platform / conversation id already captured above. The
          // adoption guard there keeps a background (switched-away) stream from
          // yanking the user back to the old chat.
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
      if (hasAttachments) {
        // Attachments (images/documents) are only handled by the SSE multimodal
        // endpoint — the Agent WebSocket path has no attachment support.
        await consume(_sseAsEvents(ApiService.streamMessage(
          message: content,
          conversationId: _currentConversationId,
          model: modelArg,
          deepResearch: _deepResearch,
          webSearch: _webSearch,
          attachments: attachments,
        )));
      } else {
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
      }

      // Finalize the streamed message.
      updateAssistant(streaming: false);
      // Offer one-click downloads for the format(s) the user asked for (A.4).
      if (_pendingDownloadFormats != null &&
          _pendingDownloadFormats!.isNotEmpty &&
          buffer.isNotEmpty &&
          assistantIndex < ownMessages.length &&
          identical(_messages, ownMessages)) {
        ownMessages[assistantIndex] = ownMessages[assistantIndex]
            .copyWith(downloadFormats: _pendingDownloadFormats);
      }
      _currentModel = model;
      _currentPlatform = platform;
      await loadConversations();
      // A chat started "in a project" — now that its conversation exists, move
      // it into the target project. Guard on identical(_messages, ownMessages)
      // so a background (switched-away) turn doesn't grab the pending target.
      if (_pendingProjectId != null &&
          _currentConversationId != null &&
          identical(_messages, ownMessages)) {
        final pid = _pendingProjectId!;
        _pendingProjectId = null;
        await assignToProject(_currentConversationId!, pid);
      }
    } catch (e) {
      if (_stopped) {
        // User cancelled: keep whatever streamed so far, drop an empty bubble.
        if (buffer.isNotEmpty) {
          updateAssistant(streaming: false);
        } else if (assistantIndex < ownMessages.length &&
            ownMessages[assistantIndex].role == 'assistant') {
          ownMessages.removeAt(assistantIndex);
        }
      } else {
        if (buffer.isEmpty &&
            assistantIndex < ownMessages.length &&
            ownMessages[assistantIndex].role == 'assistant') {
          ownMessages.removeAt(assistantIndex);
        } else {
          updateAssistant(streaming: false);
        }
        // Surface the error only if this turn's conversation is on screen.
        if (identical(_messages, ownMessages)) _error = _friendlyError(e);
      }
    } finally {
      await _activeSub?.cancel();
      _activeSub = null;
      _turnCompleter = null;
      if (identical(_streamMessagesRef, ownMessages)) _streamMessagesRef = null;
      _pendingDownloadFormats = null; // consumed by this turn (success or not)
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

    // Re-offer downloads if the (edited) request still names a format.
    final fmts = _documentIntent(text).formats;
    _pendingDownloadFormats = fmts.isEmpty ? null : fmts;
    await sendMessage(text);
  }

  /// Re-send an earlier USER turn exactly as it was — same text AND attachments
  /// — dropping its old reply. Used by the user-message "Retry" option (e.g. to
  /// re-run a turn after adding a working provider). Note: attachments only
  /// survive for messages still in memory; a turn reloaded from the server has
  /// no attachments to resend.
  Future<void> retryUserTurn(int userIndex) async {
    if (_isLoading) return;
    if (userIndex < 0 || userIndex >= _messages.length) return;
    final msg = _messages[userIndex];
    if (msg.role != 'user') return;
    final text = msg.content;
    final atts = msg.attachments;

    final cid = _currentConversationId;
    if (cid != null) {
      try {
        await ApiService.truncateConversation(cid, userIndex);
      } catch (_) {/* non-fatal: still resend locally */}
    }
    _messages.removeRange(userIndex, _messages.length);
    notifyListeners();
    // Re-offer downloads if the original request named a format.
    final fmts = _documentIntent(text).formats;
    _pendingDownloadFormats = fmts.isEmpty ? null : fmts;
    await sendMessage(text, attachments: atts);
  }

  /// Retry an assistant reply: re-run the user turn that produced the message at
  /// [assistantIndex], optionally pinned to [modelId] (its original model) so it
  /// regenerates with the same model. The user's global model choice is restored
  /// afterwards.
  Future<void> regenerate(int assistantIndex, {String? modelId}) async {
    if (_isLoading) return;
    if (assistantIndex <= 0 || assistantIndex >= _messages.length) return;
    final userIndex = assistantIndex - 1;
    if (_messages[userIndex].role != 'user') return;
    final userText = _messages[userIndex].content;
    final prev = _selectedModel;
    if (modelId != null && modelId.isNotEmpty) _selectedModel = modelId;
    try {
      await editAndResend(userIndex, userText);
    } finally {
      _selectedModel = prev;
      notifyListeners();
    }
  }

  /// Resolve a model's display name (as shown on a message badge) back to its
  /// id, so a retry can request the same model. Null if it can't be found.
  String? modelIdForName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final m in availableModels) {
      if (m['name']?.toString() == name || m['id']?.toString() == name) {
        return m['id']?.toString();
      }
    }
    return null;
  }

  /// Branch this conversation's history (up to message index [messageIndex],
  /// inclusive) into another chat — a brand-new one ([targetId] null) or an
  /// existing target — then switch to it. Returns the target conversation id.
  Future<int?> branchTo(int messageIndex, {int? targetId}) async {
    final cid = _currentConversationId;
    if (cid == null) return null;
    if (targetId != null) {
      // Branch into an existing chat: append immediately and switch to it.
      try {
        final newId = await ApiService.branchConversation(cid, messageIndex,
            targetConversationId: targetId);
        await loadConversations();
        await selectConversation(newId);
        return newId;
      } catch (_) {
        _error = 'Could not branch this chat';
        notifyListeners();
        return null;
      }
    }
    // New-chat branch: DON'T create a conversation yet. Open the copied history
    // as an unsaved draft; it's saved (and appears in the sidebar) only when the
    // user actually sends a message — so an empty branch never clutters the list.
    final upto = (messageIndex + 1).clamp(0, _messages.length);
    _pendingBranchSource = cid;
    _pendingBranchUpTo = messageIndex;
    _currentConversationId = null;
    _messages = _messages.sublist(0, upto);
    _error = null;
    notifyListeners();
    return null;
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
      final cid = chunk['conversationId'] ?? chunk['conversation_id'];
      if (chunk['error'] != null) {
        // Carry the conversation id on errors so a failed turn still binds this
        // chat (Retry then reuses it instead of creating a duplicate).
        yield {
          'type': 'error',
          'message': chunk['error'].toString(),
          if (cid != null) 'conversation_id': cid,
        };
        return;
      }
      // Early meta chunk (empty content, not done) just carries the id — surface
      // it so the client binds the conversation before any tokens arrive.
      if (cid != null && chunk['done'] != true) {
        yield {'type': 'meta', 'conversation_id': cid};
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
          'conversation_id': cid,
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
      await loadConversations(); // reflect cascade-deleted branches
      if (_currentConversationId != null &&
          !_conversations.any((c) => c.id == _currentConversationId)) {
        startNewChat();
      } else {
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Promote a branch to a top-level chat (used when the user unchecks a branch
  /// in the parent's delete dialog so it survives instead of being deleted).
  Future<void> detachConversation(int id) async {
    try {
      await ApiService.detachConversation(id);
    } catch (_) {}
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
