import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../utils/app_feedback.dart';
import '../widgets/message_bubble.dart' show kContentMaxWidth;

/// Project landing page (ChatGPT-style): a header with the project name +
/// actions, a "New chat in <project>" composer, and Chats / Sources tabs. It's
/// shown in the main content area (the sidebar persists), like Profile/Guide.
class ProjectScreen extends StatefulWidget {
  final int projectId;
  final VoidCallback? onBack;

  /// Open one of the project's existing chats.
  final void Function(int conversationId) onOpenConversation;

  /// Start a new chat inside this project (opens the full chat page).
  final VoidCallback onNewChat;

  const ProjectScreen({
    super.key,
    required this.projectId,
    required this.onOpenConversation,
    required this.onNewChat,
    this.onBack,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  int _tab = 0; // 0 = Chats, 1 = Sources, 2 = Brain

  // Brain tab state (Part D Phase 4) — lazy-loaded when the tab is first opened.
  List<Map<String, dynamic>>? _brain;
  Map<String, dynamic>? _graph;
  bool _brainLoading = false;

  static const _kindOrder = ['goal', 'decision', 'convention', 'fact'];
  static const _kindLabel = {
    'goal': 'Goals',
    'decision': 'Decisions',
    'convention': 'Conventions',
    'fact': 'Facts',
  };
  static const _kindIcon = {
    'goal': Icons.flag_outlined,
    'decision': Icons.gavel_rounded,
    'convention': Icons.rule_rounded,
    'fact': Icons.lightbulb_outline_rounded,
  };

  void _selectTab(int i) {
    setState(() => _tab = i);
    if (i == 2 && _brain == null && !_brainLoading) _loadBrain();
  }

  Future<void> _loadBrain() async {
    setState(() => _brainLoading = true);
    try {
      final results = await Future.wait([
        ApiService.getProjectBrain(widget.projectId),
        ApiService.getProjectGraph(widget.projectId),
      ]);
      if (!mounted) return;
      setState(() {
        _brain = results[0] as List<Map<String, dynamic>>;
        _graph = results[1] as Map<String, dynamic>;
        _brainLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _brain = const [];
        _brainLoading = false;
      });
      showAppMessage(context, 'Could not load project brain: $e', isError: true);
    }
  }

  Future<void> _deleteBrainEntry(int entryId) async {
    try {
      await ApiService.deleteBrainEntry(widget.projectId, entryId);
      if (!mounted) return;
      setState(() => _brain?.removeWhere((e) => e['id'] == entryId));
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed: $e', isError: true);
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final base = '${_months[d.month - 1]} ${d.day}';
    return d.year == now.year ? base : '$base, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<ChatProvider>();
    final theme = Theme.of(context);

    // Resolve the live project so edits/deletes reflect immediately.
    final project = cp.projects.where((p) => p.id == widget.projectId).isEmpty
        ? null
        : cp.projects.firstWhere((p) => p.id == widget.projectId);
    if (project == null) {
      // Deleted (or not loaded yet) — bounce back to chat.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onBack?.call());
      return const SizedBox.shrink();
    }

    final convs = cp.conversations
        .where((c) => c.projectId == widget.projectId)
        .toList()
      ..sort((a, b) => (b.updatedAt ?? b.createdAt)
          .compareTo(a.updatedAt ?? a.createdAt));

    // The project page is a pure list of chat sessions (like the CONVERSATIONS
    // list). New chats are started with the "+" on the project row, which opens
    // the full chat page with the "New chat in <project>" banner.
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme, project.name, project.instructions),
          _tabs(theme, convs.length),
          Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.25)),
          Expanded(
            child: _tab == 0
                ? _chatsTab(theme, convs)
                : _tab == 1
                    ? _sourcesTab(theme)
                    : _brainTab(theme),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, String name, String? instructions) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: widget.onBack,
              tooltip: 'Back',
            ),
          Icon(Icons.folder_outlined,
              size: 24, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => showAppMessage(
                context, 'Project sharing is coming soon.'),
            icon: const Icon(Icons.ios_share_rounded, size: 15),
            label: const Text('Share'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: theme.colorScheme.onSurface,
              side: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Project options',
            icon: Icon(Icons.more_horiz, color: theme.colorScheme.onSurface),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  _editProject(focusInstructions: false);
                  break;
                case 'instructions':
                  _editProject(focusInstructions: true);
                  break;
                case 'delete':
                  _confirmDelete();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', height: 42, child: Row(children: [
                Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('Rename'),
              ])),
              PopupMenuItem(value: 'instructions', height: 42, child: Row(children: [
                Icon(Icons.tune_rounded, size: 18), SizedBox(width: 10), Text('Instructions'),
              ])),
              PopupMenuItem(value: 'delete', height: 42, child: Row(children: [
                Icon(Icons.delete_outline, size: 18), SizedBox(width: 10), Text('Delete'),
              ])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabs(ThemeData theme, int chatCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: Row(children: [
            _tabChip(theme, 'Chats', 0, count: chatCount),
            const SizedBox(width: 8),
            _tabChip(theme, 'Sources', 1),
            const SizedBox(width: 8),
            _tabChip(theme, 'Brain', 2),
            const Spacer(),
            _newChatButton(theme),
          ]),
        ),
      ),
    );
  }

  /// New-chat action: a labelled "New chat" on desktop / web, a compact round
  /// "+" on Android / iOS. Both open a fresh chat filed under this project.
  Widget _newChatButton(ThemeData theme) {
    final platform = theme.platform;
    final isMobile = !kIsWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    final primary = theme.colorScheme.primary;
    if (isMobile) {
      return SizedBox(
        width: 38,
        height: 38,
        child: IconButton.filled(
          onPressed: widget.onNewChat,
          tooltip: 'New chat',
          style: IconButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          icon: const Icon(Icons.add_rounded, size: 20),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: widget.onNewChat,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('New chat'),
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: theme.colorScheme.onPrimary,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _tabChip(ThemeData theme, String label, int index, {int? count}) {
    final selected = _tab == index;
    return InkWell(
      onTap: () => _selectTab(index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.onSurface.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          count != null && count > 0 ? '$label  $count' : label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _chatsTab(ThemeData theme, List<Conversation> convs) {
    if (convs.isEmpty) {
      return _emptyState(
        theme,
        Icons.chat_bubble_outline_rounded,
        'No chats yet',
        'Start one with the “+” on this project in the sidebar — it will be filed here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: convs.length,
      separatorBuilder: (_, __) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: theme.colorScheme.outline.withValues(alpha: 0.15)),
        ),
      ),
      itemBuilder: (context, i) => _chatRow(theme, convs[i]),
    );
  }

  Widget _chatRow(ThemeData theme, Conversation c) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
        child: InkWell(
          onTap: () => widget.onOpenConversation(c.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _dateLabel(c.updatedAt ?? c.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourcesTab(ThemeData theme) {
    return _emptyState(
      theme,
      Icons.folder_copy_outlined,
      'Sources',
      'Files added here give every chat in this project shared context. '
          'Project sources are coming soon.',
    );
  }

  // ── Brain tab (Part D Phase 4) ─────────────────────────────────────────────
  Widget _brainTab(ThemeData theme) {
    if (_brainLoading && _brain == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final brain = _brain ?? const [];
    if (brain.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadBrain,
        child: ListView(children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: _emptyState(
              theme,
              Icons.psychology_outlined,
              'No project brain yet',
              'As you chat inside this project, the assistant distils durable '
                  'facts, decisions, conventions and goals here — and feeds them '
                  'into every chat in this project automatically.',
            ),
          ),
        ]),
      );
    }

    // Group by kind, ordered goal → decision → convention → fact.
    final byKind = <String, List<Map<String, dynamic>>>{};
    for (final e in brain) {
      byKind.putIfAbsent((e['kind'] as String?) ?? 'fact', () => []).add(e);
    }
    final edges = ((_graph?['edges'] as List?) ?? const []).length;
    final nodes = ((_graph?['nodes'] as List?) ?? const []).length;

    final children = <Widget>[
      _brainHeader(theme, brain.length, edges, nodes),
      for (final k in _kindOrder)
        if (byKind[k] != null) ...[
          _kindHeader(theme, k, byKind[k]!.length),
          for (final e in byKind[k]!) _brainEntryRow(theme, e),
        ],
      const SizedBox(height: 24),
    ];

    return RefreshIndicator(
      onRefresh: _loadBrain,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: children
            .map((w) => Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: kContentMaxWidth),
                    child: w,
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _brainHeader(ThemeData theme, int entries, int edges, int nodes) {
    final facts = edges > 0
        ? '  ·  $edges linked fact${edges == 1 ? '' : 's'} across $nodes entit${nodes == 1 ? 'y' : 'ies'}'
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(children: [
        Icon(Icons.psychology_outlined,
            size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$entries thing${entries == 1 ? '' : 's'} learned$facts',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        IconButton(
          onPressed: _brainLoading ? null : _loadBrain,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          tooltip: 'Refresh',
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Widget _kindHeader(ThemeData theme, String kind, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(children: [
        Icon(_kindIcon[kind] ?? Icons.circle_outlined,
            size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          _kindLabel[kind] ?? kind,
          style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0.2),
        ),
        const SizedBox(width: 6),
        Text('$count',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  Widget _brainEntryRow(ThemeData theme, Map<String, dynamic> e) {
    final content = (e['content'] as String?) ?? '';
    final support = (e['support_count'] as int?) ?? 1;
    final id = e['id'] as int?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Icon(Icons.circle,
                size: 6, color: theme.colorScheme.onSurfaceVariant),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(content,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
            ),
          ),
          if (support > 1)
            Container(
              margin: const EdgeInsets.only(left: 8, top: 3),
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('×$support',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700)),
            ),
          IconButton(
            onPressed: id == null ? null : () => _deleteBrainEntry(id),
            icon: const Icon(Icons.close_rounded, size: 16),
            tooltip: 'Forget this',
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
      ThemeData theme, IconData icon, String title, String body) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 40,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(height: 14),
              Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6))),
            ],
          ),
        ),
      ),
    );
  }

  // ── Project actions ────────────────────────────────────────────────────────
  Future<void> _editProject({required bool focusInstructions}) async {
    final cp = context.read<ChatProvider>();
    final p = cp.projects.where((x) => x.id == widget.projectId);
    if (p.isEmpty) return;
    final project = p.first;
    final nameCtrl = TextEditingController(text: project.name);
    final descCtrl = TextEditingController(text: project.instructions ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(focusInstructions ? 'Project instructions' : 'Rename project'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              autofocus: !focusInstructions,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Project name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descCtrl,
              autofocus: focusInstructions,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Instructions (optional)',
                hintText: 'Standing instructions applied to every chat here…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      await cp.updateProject(project.id,
          name: name, instructions: descCtrl.text.trim());
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed: $e', isError: true);
    }
  }

  Future<void> _confirmDelete() async {
    final cp = context.read<ChatProvider>();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: const Text(
            'Choose what happens to the chats grouped under this project.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'keep'),
              child: const Text('Delete, keep chats')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (choice == null || choice == 'cancel') return;
    try {
      await cp.deleteProject(widget.projectId,
          deleteConversations: choice == 'all');
      if (mounted) widget.onBack?.call();
    } catch (e) {
      if (mounted) showAppMessage(context, 'Failed: $e', isError: true);
    }
  }
}
