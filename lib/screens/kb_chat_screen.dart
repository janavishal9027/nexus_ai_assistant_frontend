import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/conversation.dart';
import '../models/knowledge_base.dart';
import '../services/api_service.dart';

/// A single turn in a grounded KB conversation.
class _Turn {
  final String role; // 'user' | 'assistant'
  String content;
  List<SourceChunk> sources = const [];
  bool streaming;
  String? model;
  String? error;
  _Turn(this.role, this.content, {this.streaming = false});
}

/// Grounded chat against one Knowledge Base: streams a cited answer built only
/// from retrieved document chunks, and shows the sources behind each answer.
class KbChatScreen extends StatefulWidget {
  final KnowledgeBase kb;
  const KbChatScreen({super.key, required this.kb});

  @override
  State<KbChatScreen> createState() => _KbChatScreenState();
}

class _KbChatScreenState extends State<KbChatScreen> {
  final List<_Turn> _turns = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int? _conversationId;
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _newChat() {
    setState(() {
      _turns.clear();
      _conversationId = null;
    });
  }

  Future<void> _send() async {
    final query = _input.text.trim();
    if (query.isEmpty || _sending) return;
    _input.clear();

    final assistant = _Turn('assistant', '', streaming: true);
    setState(() {
      _turns.add(_Turn('user', query));
      _turns.add(assistant);
      _sending = true;
    });
    _scrollToEnd();

    // Prior turns as history (exclude the two we just added).
    final history = <Message>[];
    for (final t in _turns.sublist(0, _turns.length - 2)) {
      history.add(Message(role: t.role, content: t.content));
    }

    try {
      await for (final evt in ApiService.streamKbChat(
        kbId: widget.kb.id,
        query: query,
        conversationId: _conversationId,
        history: history,
      )) {
        if (evt['sources'] is List) {
          assistant.sources = (evt['sources'] as List)
              .map((e) => SourceChunk.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (evt['content'] is String && (evt['content'] as String).isNotEmpty) {
          assistant.content += evt['content'] as String;
        }
        if (evt['model'] is String) assistant.model = evt['model'] as String;
        if (evt['error'] != null) {
          assistant.error = evt['error'].toString();
        }
        if (evt['conversationId'] != null) {
          _conversationId = (evt['conversationId'] as num).toInt();
        }
        if (mounted) setState(() {});
        _scrollToEnd();
      }
    } catch (e) {
      assistant.error = e.toString();
    } finally {
      assistant.streaming = false;
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.kb.name, style: const TextStyle(fontSize: 16)),
            Text('Grounded chat · cited answers',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _turns.isEmpty ? null : _newChat,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _turns.isEmpty
                  ? _emptyState(theme)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount: _turns.length,
                      itemBuilder: (_, i) => _turnWidget(theme, _turns[i]),
                    ),
            ),
            _inputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 52, color: theme.colorScheme.primary),
            const SizedBox(height: 14),
            Text('Ask “${widget.kb.name}”',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Answers are generated only from the documents in this knowledge '
              'base, with citations to the exact sources used.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _turnWidget(ThemeData theme, _Turn turn) {
    final isUser = turn.role == 'user';
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(turn.content, style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(turn.error!, style: TextStyle(color: Colors.red.shade300)),
            )
          else if (turn.content.isEmpty && turn.streaming)
            Row(children: [
              SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
              const SizedBox(width: 10),
              Text('Searching the knowledge base…',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ])
          else
            MarkdownBody(
              data: turn.content,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyLarge,
                code: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          if (turn.sources.isNotEmpty && !turn.streaming) _sourcesBar(theme, turn.sources),
        ],
      ),
    );
  }

  Widget _sourcesBar(ThemeData theme, List<SourceChunk> sources) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.menu_book_outlined, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('${sources.length} source${sources.length == 1 ? '' : 's'}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in sources)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('[${s.index}] ${s.documentName}',
                      style: theme.textTheme.labelSmall),
                  avatar: CircleAvatar(
                    radius: 9,
                    backgroundColor: theme.colorScheme.primary,
                    child: Text('${s.index}',
                        style: const TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                  onPressed: () => _showSource(theme, s),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSource(ThemeData theme, SourceChunk s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Row(children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: theme.colorScheme.primary,
                child: Text('${s.index}',
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.documentName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Passage ${s.ordinal + 1} · relevance ${s.score.toStringAsFixed(3)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const Divider(height: 24),
            SelectableText(s.text, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _inputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.15))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Ask about your documents…',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            elevation: 0,
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}
