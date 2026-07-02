import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import '../models/conversation.dart';

/// Max width of the conversation reading column (messages + input align to it).
const double kContentMaxWidth = 768;

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

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
              child: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(width: 10),
          ],
          // Message content
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Content
                  if (message.isStreaming && message.content.isEmpty)
                    const _TypingIndicator()
                  else if (isUser)
                    Text(
                      message.content,
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.5,
                      ),
                    )
                  else
                    _MessageContent(message: message),
                  // Footer: copy (left) + model name (bottom-right)
                  if (!isUser && message.content.isNotEmpty && !message.isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: message.content));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Icon(
                              Icons.copy,
                              size: 14,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                            ),
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
            ),
          ),
              if (isUser) const SizedBox(width: 10),
            ],
          ),
        ),
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
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
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
