import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../utils/app_feedback.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import '../models/conversation.dart';

/// Max width of the conversation reading column (messages + input align to it).
const double kContentMaxWidth = 768;

class MessageBubble extends StatefulWidget {
  final Message message;
  final int? index;
  final void Function(int index, String newText)? onEdit;

  const MessageBubble({super.key, required this.message, this.index, this.onEdit});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _editing = false;
  bool _hovering = false;
  late final TextEditingController _editCtrl =
      TextEditingController(text: widget.message.content);

  Message get message => widget.message;
  bool get _canEdit => widget.index != null && widget.onEdit != null;

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  void _startEdit() {
    _editCtrl.text = message.content;
    setState(() => _editing = true);
  }

  void _cancelEdit() => setState(() => _editing = false);

  void _submitEdit() {
    final text = _editCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _editing = false);
    widget.onEdit?.call(widget.index!, text);
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    showAppMessage(context, 'Copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      // Center the conversation in a fixed-width reading column so lines don't
      // stretch the full window width (keeps text comfortably readable).
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                // Assistant avatar
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 16, color: Color(0xFF8B5CF6)),
                ),
                const SizedBox(width: 10),
              ],
              // Message content
              Flexible(
                child: isUser
                    ? (_editing ? _editor(theme) : _userBubble(theme))
                    : _assistantBubble(theme),
              ),
              if (isUser) const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }

  // ── User message: bubble + WhatsApp-style options menu ──────────────────
  Widget _userBubble(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        // Long-press (touch) or right-click (desktop) opens the options menu.
        onLongPressStart: (d) => _showOptionsMenu(d.globalPosition),
        onSecondaryTapDown: (d) => _showOptionsMenu(d.globalPosition),
        child: Stack(
          children: [
            Container(
              // Extra right padding reserves room for the top-right chevron so
              // it never sits on top of the text (keeps a clear gap).
              padding: const EdgeInsets.fromLTRB(14, 10, 30, 10),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(
                message.content,
                style: const TextStyle(color: Colors.white, height: 1.5),
              ),
            ),
            // Down-chevron at the top-right corner (WhatsApp-Web style): fades
            // in on hover and opens the options menu. A gradient of the bubble
            // colour masks any text behind it so it stays readable.
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _hovering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: IgnorePointer(
                  ignoring: !_hovering,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _showOptionsMenu(d.globalPosition),
                    child: Container(
                      width: 34,
                      height: 28,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(top: 1, right: 3),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            primary,
                            primary.withValues(alpha: 0.0),
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// WhatsApp-style popup at the press location: Copy, and (for your own
  /// messages) Edit.
  Future<void> _showOptionsMenu(Offset globalPos) async {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final screen = MediaQuery.of(context).size;
    Widget item(IconData icon, String label) => Row(
          children: [
            Icon(icon, size: 18, color: onSurface.withValues(alpha: 0.8)),
            const SizedBox(width: 12),
            Text(label),
          ],
        );
    final selected = await showMenu<String>(
      context: context,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & screen,
      ),
      items: [
        PopupMenuItem<String>(
            value: 'copy', height: 44, child: item(Icons.copy, 'Copy')),
        if (_canEdit)
          PopupMenuItem<String>(
              value: 'edit', height: 44, child: item(Icons.edit_outlined, 'Edit')),
      ],
    );
    if (!mounted) return;
    if (selected == 'copy') {
      _copy();
    } else if (selected == 'edit') {
      _startEdit();
    }
  }

  // ── User message: inline editor ─────────────────────────────────────────
  Widget _editor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.6), width: 1.4),
          ),
          child: TextField(
            controller: _editCtrl,
            autofocus: true,
            maxLines: null,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            decoration: const InputDecoration.collapsed(
                hintText: 'Edit your message'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _cancelEdit,
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _submitEdit,
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Send'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Assistant message: content + copy + model footer (unchanged) ────────
  Widget _assistantBubble(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Agent activity: planner steps + live tool runs
          if (message.activity != null)
            _AgentActivityView(activity: message.activity!),
          // Content
          if (message.isStreaming && message.content.isEmpty)
            const _TypingIndicator()
          else
            _MessageContent(message: message),
          // Footer: copy (left) + model name (bottom-right)
          if (message.content.isNotEmpty && !message.isStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: _copy,
                    borderRadius: BorderRadius.circular(4),
                    child: Icon(Icons.copy,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                  ),
                  const Spacer(),
                  if (message.model != null)
                    Text(
                      message.model!,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  final Message message;

  const _MessageContent({required this.message});

  @override
  Widget build(BuildContext context) {
    // Split into text vs. fenced-code segments and render each separately.
    // Text goes through a plain MarkdownBody (NO custom element builders — a
    // custom `pre` builder crashes flutter_markdown on some real-world content
    // with '_inlines.isEmpty' assertions); each code block is rendered by our
    // own _CodeBlock widget (highlighting + language label + copy button).
    final segments = _splitSegments(message.content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seg in segments)
          if (seg.isCode)
            _CodeBlock(code: seg.text, language: seg.language)
          else
            _MarkdownText(data: seg.text),
      ],
    );
  }
}

class _Segment {
  final bool isCode;
  final String text;
  final String language;
  const _Segment(this.isCode, this.text, this.language);
}

// Matches a fenced code block: ```lang\n ... \n```
final _fenceRe = RegExp(r'```[ \t]*([A-Za-z0-9_+\-#.]*)[ \t]*\r?\n([\s\S]*?)```');

List<_Segment> _splitSegments(String content) {
  final segments = <_Segment>[];
  var last = 0;
  for (final m in _fenceRe.allMatches(content)) {
    if (m.start > last) {
      final text = content.substring(last, m.start);
      if (text.trim().isNotEmpty) segments.add(_Segment(false, text, ''));
    }
    segments.add(
      _Segment(true, (m.group(2) ?? '').trimRight(), (m.group(1) ?? '').trim()),
    );
    last = m.end;
  }
  if (last < content.length) {
    final rest = content.substring(last);
    if (rest.trim().isNotEmpty) segments.add(_Segment(false, rest, ''));
  }
  if (segments.isEmpty) segments.add(_Segment(false, content, ''));
  return segments;
}

/// Plain markdown (no custom element builders → robust). Handles inline `code`,
/// lists, tables, headings, blockquotes; fenced code is split out upstream.
class _MarkdownText extends StatelessWidget {
  final String data;

  const _MarkdownText({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: theme.textTheme.bodyMedium?.copyWith(
          height: 1.6,
          color: theme.colorScheme.onSurface,
        ),
        // Inline `code` — neutral, readable pill.
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor:
              isDark ? const Color(0xFF2B2B2B) : const Color(0xFFEDEDED),
          color: isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A),
        ),
        // Fallback box for any stray/unclosed fence that slips through.
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3),
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.06),
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        h1: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        h2: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        listBullet: theme.textTheme.bodyMedium,
        blockSpacing: 10,
        tableBorder: TableBorder.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  final String code;
  final String language;

  const _CodeBlock({required this.code, required this.language});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  static const _aliases = {
    'py': 'python',
    'js': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'sh': 'bash',
    'shell': 'bash',
    'zsh': 'bash',
    'yml': 'yaml',
    'c++': 'cpp',
    'c#': 'csharp',
    'html': 'xml',
    'md': 'markdown',
  };

  String get _lang {
    if (widget.language.isEmpty) return 'plaintext';
    final l = widget.language.toLowerCase();
    return _aliases[l] ?? l;
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeTheme = isDark ? atomOneDarkTheme : githubTheme;
    final bodyBg = codeTheme['root']?.backgroundColor ??
        (isDark ? const Color(0xFF282C34) : Colors.white);
    final headerBg = isDark ? const Color(0xFF1B1F24) : const Color(0xFFECECEC);
    final fg = isDark ? Colors.white60 : Colors.black54;
    final label = widget.language.isEmpty ? 'code' : widget.language;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bodyBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: language + copy
          Container(
            color: headerBg,
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                    color: fg,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copy,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_copied ? Icons.check : Icons.copy,
                            size: 13, color: fg),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: TextStyle(fontSize: 11, color: fg),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body: horizontally scrollable so long lines don't wrap/overflow
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              widget.code,
              language: _lang,
              theme: codeTheme,
              padding: const EdgeInsets.all(12),
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the agent's plan steps and the tools it ran (live), shown above the
/// assistant's answer while orchestration is in progress and after it finishes.
class _AgentActivityView extends StatelessWidget {
  final AgentActivity activity;

  const _AgentActivityView({required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activity.planSteps.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.checklist_rounded, size: 14, color: primary),
                const SizedBox(width: 6),
                Text(
                  'Plan',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (int i = 0; i < activity.planSteps.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 2),
                child: Text(
                  '${i + 1}. ${activity.planSteps[i]}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
          ],
          if (activity.planSteps.isNotEmpty && activity.tools.isNotEmpty)
            const SizedBox(height: 8),
          if (activity.tools.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in activity.tools) _ToolChip(tool: t)],
            ),
        ],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final ToolActivity tool;

  const _ToolChip({required this.tool});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = tool.running;
    final color = running ? theme.colorScheme.primary : Colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            )
          else
            Icon(Icons.check_circle, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            tool.name,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
            ),
          ),
          if (!running && tool.durationMs != null) ...[
            const SizedBox(width: 4),
            Text(
              '${tool.durationMs!.round()}ms',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _timer;
  int _elapsed = 0; // seconds waiting for the first token

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    // Tick once a second so the user sees progress (not a frozen UI) while the
    // provider is slow to send its first token.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _status {
    if (_elapsed >= 20) return 'Still working — the provider may be rate-limited';
    if (_elapsed >= 8) return 'Working — the model may be busy';
    return 'Thinking';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final delay = index * 0.2;
                final value = (_controller.value - delay).clamp(0.0, 1.0);
                final opacity = (value < 0.5) ? value * 2 : (1 - value) * 2;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity.clamp(0.3, 1.0),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: subtle, shape: BoxShape.circle),
                    ),
                  ),
                );
              }),
            );
          },
        ),
        const SizedBox(width: 10),
        Text(
          '$_status  ${_elapsed}s',
          style: theme.textTheme.bodySmall?.copyWith(color: subtle, fontSize: 12),
        ),
      ],
    );
  }
}
