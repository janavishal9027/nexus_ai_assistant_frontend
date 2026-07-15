import 'dart:async';
import 'dart:io' show Platform, Process;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../utils/app_feedback.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../models/chat_attachment.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../services/exporter.dart';

/// Max width of the conversation reading column (messages + input align to it).
const double kContentMaxWidth = 768;

/// Export formats (A.4): key → (label, icon).
const Map<String, (String, IconData)> _kFormatMeta = {
  'markdown': ('Markdown (.md)', Icons.notes_rounded),
  'word': ('Word (.docx)', Icons.description_outlined),
  'pdf': ('PDF', Icons.picture_as_pdf_outlined),
  'excel': ('Excel (.xlsx)', Icons.table_chart_outlined),
  'csv': ('CSV', Icons.grid_on_rounded),
  'text': ('Text (.txt)', Icons.text_snippet_outlined),
  'powerpoint': ('PowerPoint (.pptx)', Icons.slideshow_outlined),
  'zip': ('Project archive (.zip)', Icons.folder_zip_outlined),
};

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
  int _feedback = 0; // 0 = none, 1 = good, -1 = bad (local, per message)
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

  // ── Assistant response actions ──────────────────────────────────────────
  Widget _actionIcon(ThemeData theme, IconData icon, String tooltip,
      VoidCallback onTap,
      {bool active = false, IconData? activeIcon}) {
    final color = active
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.45);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child:
              Icon(active ? (activeIcon ?? icon) : icon, size: 15, color: color),
        ),
      ),
    );
  }

  void _setFeedback(int v) {
    setState(() => _feedback = _feedback == v ? 0 : v);
    if (_feedback == 1) {
      showAppMessage(context, 'Thanks for the feedback');
    } else if (_feedback == -1) {
      showAppMessage(context, "Thanks — we'll try to do better");
    }
  }

  void _retry() {
    final idx = widget.index;
    if (idx == null) return;
    final provider = context.read<ChatProvider>();
    if (provider.isLoading) {
      showAppMessage(context, 'Please wait for the current reply to finish');
      return;
    }
    provider.regenerate(idx, modelId: provider.modelIdForName(message.model));
  }

  // ── Export (A.4) ─────────────────────────────────────────────────────────
  String _exportTitle() {
    for (final line in message.content.split('\n')) {
      final t = line.replaceAll(RegExp(r'^#+\s*'), '').replaceAll('*', '').trim();
      if (t.isNotEmpty) return t.length > 50 ? t.substring(0, 50) : t;
    }
    return 'document';
  }

  Future<void> _export() async {
    final content = message.content;
    if (content.trim().isEmpty) return;
    // Backend-authoritative triage: which formats apply + the suggested one.
    List<String> formats = const ['markdown', 'word', 'pdf', 'text'];
    String? suggested;
    try {
      final dec = await ApiService.documentDecision(content);
      if (dec.formats.isNotEmpty) formats = dec.formats;
      suggested = dec.format;
    } catch (_) {/* fall back to prose formats */}
    if (!mounted) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ExportSheet(formats: formats, suggested: suggested),
    );
    if (choice == null || !mounted) return;
    showAppMessage(context, 'Preparing ${_kFormatMeta[choice]?.$1 ?? choice}…');
    try {
      final res = await ApiService.exportDocument(
          content: content, format: choice, title: _exportTitle());
      if (!mounted) return;
      await saveExport(context, res.bytes, res.filename);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Export failed: $e');
    }
  }

  // ── Share (Nexus AI) ─────────────────────────────────────────────────────
  Future<void> _openUrl(String url) async {
    try {
      if (Platform.isWindows) {
        // rundll32's FileProtocolHandler opens the default browser and accepts
        // far longer URLs than `cmd /c start` (which is capped near 8191 chars).
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else {
        // Android / iOS: dart:io Process isn't available in the mobile sandbox;
        // hand the URL to the OS (opens the browser or target app, e.g. WhatsApp).
        final ok = await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication);
        if (!ok) {
          await Clipboard.setData(ClipboardData(text: url));
          if (mounted) showAppMessage(context, 'Link copied — paste to share');
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) showAppMessage(context, 'Link copied — paste to share');
    }
  }

  /// Share the FULL response text to a social URL. If the resulting URL would be
  /// too long for the OS to launch, copy the whole text to the clipboard (so
  /// nothing is lost) and share as much as still fits.
  Future<void> _openShare(String base, String rawText) async {
    const maxUrl = 28000; // safely under Windows' ~32767 command-line limit
    var body = rawText;
    if (base.length + Uri.encodeComponent(body).length > maxUrl) {
      await Clipboard.setData(ClipboardData(text: rawText));
      while (body.isNotEmpty &&
          base.length + Uri.encodeComponent(body).length > maxUrl) {
        body = body.substring(0, (body.length * 0.85).floor());
      }
      if (mounted) {
        showAppMessage(context,
            'Long response — full text copied to clipboard; paste to include all');
      }
    }
    await _openUrl('$base${Uri.encodeComponent(body)}');
  }

  void _share() =>
      showDialog(context: context, builder: (ctx) => _shareDialog(ctx));

  Widget _shareDialog(BuildContext ctx) {
    final theme = Theme.of(ctx);
    final text = message.content;
    final tagged = '$text\n\n— shared from Nexus AI';
    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.auto_awesome,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Share via Nexus AI',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(ctx).pop()),
              ]),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(text,
                        style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.75))),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _shareTarget(
                      theme, Icons.copy, 'Copy', const Color(0xFF10A37F), () {
                    Clipboard.setData(ClipboardData(text: tagged));
                    Navigator.of(ctx).pop();
                    showAppMessage(context, 'Response copied — share anywhere');
                  }),
                  _shareTarget(theme, Icons.chat, 'WhatsApp',
                      const Color(0xFF25D366), () {
                    _openShare('https://wa.me/?text=', text);
                    Navigator.of(ctx).pop();
                  },
                      glyph: const FaIcon(FontAwesomeIcons.whatsapp,
                          color: Colors.white, size: 24)),
                  _shareTarget(theme, Icons.business_center, 'LinkedIn',
                      const Color(0xFF0A66C2), () {
                    _openShare(
                        'https://www.linkedin.com/feed/?shareActive=true&text=',
                        text);
                    Navigator.of(ctx).pop();
                  },
                      glyph: const FaIcon(FontAwesomeIcons.linkedinIn,
                          color: Colors.white, size: 22)),
                  _shareTarget(theme, Icons.forum, 'Reddit',
                      const Color(0xFFFF4500), () {
                    _openShare(
                        'https://www.reddit.com/submit?title=Nexus%20AI&text=',
                        text);
                    Navigator.of(ctx).pop();
                  },
                      glyph: const FaIcon(FontAwesomeIcons.redditAlien,
                          color: Colors.white, size: 22)),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: Text('Only this response is shared — not your whole chat.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.4))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareTarget(ThemeData theme, IconData icon, String label, Color color,
      VoidCallback onTap, {Widget? glyph}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: glyph ?? Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ── Branch (dropdown of chats) ───────────────────────────────────────────
  Widget _branchButton(ThemeData theme) {
    final provider = context.read<ChatProvider>();
    final currentId = provider.currentConversationId;
    final color = theme.colorScheme.onSurface.withValues(alpha: 0.45);
    return PopupMenuButton<int>(
      tooltip: 'Branch to another chat',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(maxHeight: 340, minWidth: 220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (v) => _doBranch(v == -1 ? null : v),
      itemBuilder: (ctx) {
        final convos = provider.conversations;
        return <PopupMenuEntry<int>>[
          PopupMenuItem<int>(
            value: -1,
            height: 42,
            child: Row(children: [
              Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('New chat', style: TextStyle(fontSize: 13)),
            ]),
          ),
          const PopupMenuDivider(),
          for (final c in convos)
            if (c.id != currentId)
              PopupMenuItem<int>(
                value: c.id,
                height: 40,
                child: Text(c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
        ];
      },
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(Icons.call_split, size: 15, color: color),
      ),
    );
  }

  Future<void> _doBranch(int? targetId) async {
    final idx = widget.index;
    if (idx == null) return;
    final provider = context.read<ChatProvider>();
    final newId = await provider.branchTo(idx, targetId: targetId);
    if (!mounted) return;
    if (targetId == null) {
      // Deferred: the new branch is saved only once the user asks something.
      showAppMessage(context, 'New branch — ask a question to save it');
    } else if (newId != null) {
      showAppMessage(context, 'Branched into the chat');
    }
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
  /// Thumbnails (images) and file chips shown inside a sent user bubble.
  Widget _bubbleAttachments(List<ChatAttachment> atts) {
    return Padding(
      padding: EdgeInsets.only(bottom: message.content.isNotEmpty ? 8 : 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.end,
        children: [
          for (final a in atts)
            if (a.isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(a.bytes,
                    width: 130, height: 130, fit: BoxFit.cover),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.description_outlined,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.attachments != null && message.attachments!.isNotEmpty)
                    _bubbleAttachments(message.attachments!),
                  if (message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: const TextStyle(color: Colors.white, height: 1.5),
                    ),
                ],
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
        PopupMenuItem<String>(
            value: 'retry', height: 44,
            child: item(Icons.refresh_rounded, 'Retry')),
        if (_canEdit)
          PopupMenuItem<String>(
              value: 'edit', height: 44, child: item(Icons.edit_outlined, 'Edit')),
      ],
    );
    if (!mounted) return;
    if (selected == 'copy') {
      _copy();
    } else if (selected == 'retry') {
      _retryUser();
    } else if (selected == 'edit') {
      _startEdit();
    }
  }

  /// Re-send this user turn as-is (text + attachments), regenerating the reply.
  void _retryUser() {
    final idx = widget.index;
    if (idx == null) return;
    final provider = context.read<ChatProvider>();
    if (provider.isLoading) {
      showAppMessage(context, 'Please wait for the current reply to finish');
      return;
    }
    provider.retryUserTurn(idx);
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

  /// Map the agent's live activity to a phase label for the typing indicator
  /// (chat-module A.2 `stage`). Null → fall back to the rotating word.
  String? _stageFromActivity(AgentActivity? a) {
    if (a == null) return null;
    for (final t in a.tools) {
      if (t.running) {
        final n = t.name.toLowerCase();
        if (n.contains('web') || n.contains('search')) return 'Searching the web';
        if (n.contains('retriev') || n.contains('rag') || n.contains('ground')) {
          return 'Retrieving context';
        }
        return 'Using ${t.name}';
      }
    }
    if (a.planSteps.isNotEmpty) return 'Planning';
    return null;
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
            _TypingIndicator(stage: _stageFromActivity(message.activity))
          else
            _MessageContent(message: message),
          // Footer: response actions (copy / good / bad / share / retry /
          // branch) on the left, the model badge on the right.
          if (message.content.isNotEmpty && !message.isStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _actionIcon(theme, Icons.copy, 'Copy', _copy),
                  _actionIcon(theme, Icons.thumb_up_outlined, 'Good response',
                      () => _setFeedback(1),
                      active: _feedback == 1, activeIcon: Icons.thumb_up),
                  _actionIcon(theme, Icons.thumb_down_outlined, 'Bad response',
                      () => _setFeedback(-1),
                      active: _feedback == -1, activeIcon: Icons.thumb_down),
                  _actionIcon(theme, Icons.ios_share, 'Share', _share),
                  _actionIcon(
                      theme, Icons.file_download_outlined, 'Export', _export),
                  _actionIcon(
                      theme, Icons.refresh, 'Retry (same model)', _retry),
                  _branchButton(theme),
                  const SizedBox(width: 6),
                  if (message.model != null)
                    Expanded(
                      child: Text(
                        message.model!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
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
  /// When set (from the agent's live activity), shows a concrete phase label
  /// (e.g. "Searching the web", "Planning") instead of the rotating word.
  final String? stage;
  const _TypingIndicator({this.stage});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _timer;
  int _elapsed = 0; // seconds waiting for the first token

  // Playful, ever-changing status words (à la Claude's "Ruminating…").
  // Shuffled per response so it doesn't always start the same, then advances
  // to the next word every ~2 seconds.
  static const _thinkingWords = <String>[
    'Ruminating', 'Booping', 'Percolating', 'Pondering', 'Noodling',
    'Mulling', 'Cogitating', 'Marinating', 'Simmering', 'Brewing',
    'Conjuring', 'Tinkering', 'Whirring', 'Musing', 'Puzzling',
    'Synthesizing', 'Wrangling', 'Finessing', 'Untangling', 'Concocting',
    'Spelunking', 'Divining', 'Vibing', 'Scheming',
  ];
  late final List<String> _words = List<String>.of(_thinkingWords)..shuffle();

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
    // A concrete stage (from agent activity) wins; otherwise keep the playful,
    // ever-changing word rotating the whole time (Claude style).
    final stage = widget.stage;
    if (stage != null && stage.isNotEmpty) return '$stage…';
    return '${_words[(_elapsed ~/ 2) % _words.length]}…';
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

/// Bottom sheet listing the export formats (A.4); the backend-suggested format
/// is tagged.
class _ExportSheet extends StatelessWidget {
  final List<String> formats;
  final String? suggested;
  const _ExportSheet({required this.formats, this.suggested});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text('Export as…',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          for (final f in formats)
            ListTile(
              dense: true,
              leading: Icon(_kFormatMeta[f]?.$2 ?? Icons.insert_drive_file_outlined,
                  color: theme.colorScheme.primary),
              title: Text(_kFormatMeta[f]?.$1 ?? f),
              trailing: f == suggested
                  ? Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Suggested',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.primary)),
                    )
                  : null,
              onTap: () => Navigator.pop(context, f),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
