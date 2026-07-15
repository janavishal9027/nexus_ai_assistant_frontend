import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../models/project.dart';
import '../providers/chat_provider.dart';
import '../utils/app_feedback.dart';
import '../screens/settings_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/guide_screen.dart';
import 'nav_tile.dart';

/// Responsive dialog content width: full-width-ish on phones, capped on desktop.
double _dialogWidth(BuildContext context) {
  final w = MediaQuery.of(context).size.width - 88;
  if (w < 260) return 260;
  return w < 400 ? w : 400;
}

/// A clearly-bordered, filled input with a visible floating label.
InputDecoration _fieldDecoration(BuildContext context, String label, {String? hint}) {
  final theme = Theme.of(context);
  final primary = theme.colorScheme.primary;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
    labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
    floatingLabelStyle: TextStyle(color: primary, fontWeight: FontWeight.w600),
    hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.55)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: primary, width: 1.6),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}

/// Unified navigation sidebar (Forui): brand header, quick actions (New chat /
/// Search), the CONVERSATIONS list (each with a relative time + overflow menu),
/// and a bottom nav (Profile / Settings) with a simple collapse control.
class Sidebar extends StatefulWidget {
  final VoidCallback? onClose;
  final bool isDrawer;
  final double width;

  final VoidCallback? onOpenChat;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenGuide;
  final void Function(Project project)? onOpenProject;
  final String activeView;

  const Sidebar({
    super.key,
    this.onClose,
    this.isDrawer = false,
    this.width = 260,
    this.onOpenChat,
    this.onOpenProfile,
    this.onOpenSettings,
    this.onOpenGuide,
    this.onOpenProject,
    this.activeView = 'chat',
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  String _query = '';
  // Branch parents whose child (branch) chats are currently expanded.
  final Set<int> _expanded = {};
  // Whole "Projects" section collapsed via its header chevron.
  bool _projectsOpen = true;
  // Individual projects whose chat list is expanded inline. Tapping a project
  // row toggles it (collapsed by default) — its chats show/hide underneath.
  final Set<int> _expandedProjects = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (_query != _searchController.text) {
        setState(() => _query = _searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _afterNav() {
    if (widget.isDrawer) widget.onClose?.call();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  void _goSettings() {
    // Close the drawer FIRST (mobile), then open Settings. Doing it the other
    // way round pops the just-pushed Settings route when the drawer closes
    // (they share one Navigator) — which is why Settings wouldn't open from the
    // side navigation on Android/iOS.
    _afterNav();
    if (widget.onOpenSettings != null) {
      widget.onOpenSettings!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
  }

  void _goProfile() {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!();
      _afterNav();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      _afterNav();
    }
  }

  void _goGuide() {
    if (widget.onOpenGuide != null) {
      widget.onOpenGuide!();
      _afterNav();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const GuideScreen()),
      );
      _afterNav();
    }
  }

  static String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt.toLocal());
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
    return '${(d.inDays / 30).floor()}mo';
  }

  /// Flatten conversations into display rows, nesting branch chats under their
  /// parent. Only children whose parent is present are nested; expanded parents
  /// reveal their branches right below them.
  List<({Conversation conv, int depth, bool hasChildren})> _treeRows(
      List<Conversation> all) {
    final ids = {for (final c in all) c.id};
    final childrenByParent = <int, List<Conversation>>{};
    for (final c in all) {
      final p = c.parentId;
      if (p != null && ids.contains(p)) {
        childrenByParent.putIfAbsent(p, () => []).add(c);
      }
    }
    final rows = <({Conversation conv, int depth, bool hasChildren})>[];
    // Recursively emit a chat, then (if expanded) its branches, their branches,
    // and so on — so a branch of a branch still shows, nested one level deeper.
    void addNode(Conversation c, int depth) {
      final kids = childrenByParent[c.id] ?? const <Conversation>[];
      rows.add((conv: c, depth: depth, hasChildren: kids.isNotEmpty));
      if (kids.isNotEmpty && _expanded.contains(c.id)) {
        for (final k in kids) {
          addNode(k, depth + 1);
        }
      }
    }

    for (final c in all) {
      final p = c.parentId;
      if (p != null && ids.contains(p)) continue; // nested under its parent
      addNode(c, 0);
    }
    return rows;
  }

  Future<void> _renameDialog(Conversation conv) async {
    final ctrl = TextEditingController(text: conv.title);
    final chat = context.read<ChatProvider>();
    final title = await showAdaptiveDialog<String>(
      context: context,
      builder: (ctx) => FDialog(
        direction: Axis.horizontal,
        title: const Text('Rename chat'),
        body: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FTextField(
            control: FTextFieldControl.managed(controller: ctrl),
            autofocus: true,
            hint: 'Title',
            onSubmit: (v) => Navigator.of(ctx).pop(v),
          ),
        ),
        actions: [
          FButton(
              variant: FButtonVariant.outline,
              onPress: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FButton(
              onPress: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (title != null && title.trim().isNotEmpty && title.trim() != conv.title) {
      await chat.renameConversation(conv.id, title.trim());
    }
  }

  /// Confirm before deleting. If the chat has branches, deleting it also deletes
  /// them — the dialog lists each branch with a checkbox so the user can uncheck
  /// any they want to keep (an unchecked branch becomes its own top-level chat).
  Future<void> _confirmDelete(Conversation conv) async {
    final chat = context.read<ChatProvider>();
    final colors = context.theme.colors;
    final muted = colors.mutedForeground;
    final children =
        chat.conversations.where((c) => c.parentId == conv.id).toList();

    if (children.isEmpty) {
      final confirmed = await showAdaptiveDialog<bool>(
        context: context,
        builder: (ctx) => FDialog(
          direction: Axis.horizontal,
          title: const Text('Delete chat?'),
          body: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'This will permanently delete '),
                  TextSpan(
                      text: conv.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: '.'),
                ])),
                const SizedBox(height: 10),
                Text("Once deleted, this chat can't be restored.",
                    style: TextStyle(fontSize: 13, color: muted)),
              ],
            ),
          ),
          actions: [
            FButton(
                variant: FButtonVariant.outline,
                onPress: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FButton(
                variant: FButtonVariant.destructive,
                onPress: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete')),
          ],
        ),
      );
      if (confirmed == true) await chat.deleteConversation(conv.id);
      return;
    }

    // Has branches → checkbox dialog. Checked = delete; unchecked = keep (that
    // branch is promoted to its own top-level chat).
    final toDelete = {for (final c in children) c.id};
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => FDialog(
          direction: Axis.horizontal,
          title: const Text('Delete chat?'),
          body: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Deleting '),
                  TextSpan(
                      text: conv.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(
                      text:
                          ' also deletes its ${children.length} branch${children.length == 1 ? '' : 'es'} below.'),
                ])),
                const SizedBox(height: 4),
                Text('Uncheck a branch to keep it — it becomes its own chat.',
                    style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final c in children)
                          _childCheckRow(
                              colors, c.title, toDelete.contains(c.id), () {
                            setLocal(() {
                              if (!toDelete.remove(c.id)) toDelete.add(c.id);
                            });
                          }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FButton(
                variant: FButtonVariant.outline,
                onPress: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FButton(
                variant: FButtonVariant.destructive,
                onPress: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      // Promote (detach) the branches the user unchecked, then delete the parent
      // (which cascades the still-checked branches).
      for (final c in children) {
        if (!toDelete.contains(c.id)) {
          await chat.detachConversation(c.id);
        }
      }
      await chat.deleteConversation(conv.id);
    }
  }

  Widget _childCheckRow(
      FColors colors, String title, bool checked, VoidCallback onToggle) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            Icon(checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: checked ? colors.primary : colors.mutedForeground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colors.foreground)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Projects (A.7) ───────────────────────────────────────────────────────
  /// Collapsible "Projects" section header (title-case + chevron), per the
  /// requested design. Tapping it hides/shows the whole project list.
  Widget _projectsHeader(FTypography typography, FColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _projectsOpen = !_projectsOpen),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(children: [
            Text('Projects',
                style: typography.body.sm.copyWith(
                    fontWeight: FontWeight.w700, color: colors.foreground)),
            const SizedBox(width: 3),
            Icon(
                _projectsOpen
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 17,
                color: colors.mutedForeground),
          ]),
        ),
      ),
    );
  }

  Widget _sectionLabel(FTypography typography, FColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
      child: Text(text,
          style: typography.body.xs.copyWith(
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
            color: colors.mutedForeground,
          )),
    );
  }

  /// CONVERSATIONS header that doubles as a drop target: dragging a chat that's
  /// in a project here removes it from the project (un-groups it). The reverse
  /// of dropping a chat onto a project row.
  Widget _conversationsHeader(
      BuildContext context, FTypography typography, FColors colors) {
    return DragTarget<Conversation>(
      onWillAcceptWithDetails: (d) => d.data.projectId != null,
      onAcceptWithDetails: (d) => _assignProject(context, d.data, null),
      builder: (context, candidate, rejected) {
        if (candidate.isEmpty) {
          return _sectionLabel(typography, colors, 'CONVERSATIONS');
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.primary.withValues(alpha: 0.6)),
          ),
          child: Row(children: [
            Icon(Icons.outbox_outlined, size: 14, color: colors.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Drop to remove from project',
                  overflow: TextOverflow.ellipsis,
                  style: typography.body.xs.copyWith(
                      fontWeight: FontWeight.w700, color: colors.primary)),
            ),
          ]),
        );
      },
    );
  }

  Widget _convTile(BuildContext context, ChatProvider chatProvider,
      ({Conversation conv, int depth, bool hasChildren}) row,
      {int extraDepth = 0, bool plainIndent = false}) {
    final conv = row.conv;
    final tile = _ConversationTile(
      conversation: conv,
      isSelected: conv.id == chatProvider.currentConversationId,
      subtitle: _relativeTime(conv.updatedAt ?? conv.createdAt),
      depth: row.depth + extraDepth,
      plainIndent: plainIndent,
      hasChildren: row.hasChildren,
      expanded: _expanded.contains(conv.id),
      onToggleExpand: row.hasChildren
          ? () => setState(() {
                if (!_expanded.remove(conv.id)) _expanded.add(conv.id);
              })
          : null,
      onTap: () {
        chatProvider.selectConversation(conv.id);
        widget.onOpenChat?.call();
        _afterNav();
      },
      onRename: () => _renameDialog(conv),
      onDelete: () => _confirmDelete(conv),
      projects: chatProvider.projects,
      onAssignProject: (pid) => _assignProject(context, conv, pid),
      onMoveToNewProject: () => _moveToNewProject(context, conv),
    );
    // Drag a chat onto a project row to file it there (alongside the "Move to
    // project" menu). Long-press to start so the list still scrolls normally.
    if (chatProvider.projects.isEmpty) return tile;
    return LongPressDraggable<Conversation>(
      data: conv,
      delay: const Duration(milliseconds: 220),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      hapticFeedbackOnStart: true,
      feedback: _dragChip(context, conv),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  /// The little floating label shown under the pointer while dragging a chat.
  Widget _dragChip(BuildContext context, Conversation conv) {
    final colors = context.theme.colors;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.drive_file_move_outline,
              size: 15, color: colors.primaryForeground),
          const SizedBox(width: 7),
          Flexible(
            child: Text(conv.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: colors.primaryForeground,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  // A project row; when expanded, its chats are nested underneath. Tapping the
  // row toggles expansion (collapsed by default) — "Open project" (its page)
  // lives in the ⋯ menu.
  List<Widget> _projectBlock(
      BuildContext context, ChatProvider chatProvider, Project p) {
    final expanded = _expandedProjects.contains(p.id);
    final row = _projectRow(context, chatProvider, p);
    if (!expanded) return [row];
    final convs = chatProvider.conversations
        .where((c) => c.projectId == p.id)
        .toList()
      ..sort((a, b) =>
          (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt));
    return [
      row,
      if (convs.isEmpty)
        _projectEmptyHint(context)
      else
        for (final c in convs)
          _convTile(context, chatProvider,
              (conv: c, depth: 0, hasChildren: false),
              extraDepth: 1, plainIndent: true),
    ];
  }

  /// Shown under an expanded project that has no chats yet.
  Widget _projectEmptyHint(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Padding(
      padding: const EdgeInsets.only(left: 46, right: 8, top: 1, bottom: 4),
      child: Text('No chats yet',
          style: typography.body.xs
              .copyWith(color: colors.mutedForeground, fontStyle: FontStyle.italic)),
    );
  }

  // A project is a single row that toggles its chat list. The row is highlighted
  // while it holds the currently-open chat, and is a drop target for dragged chats.
  Widget _projectRow(BuildContext context, ChatProvider chatProvider, Project p) {
    final isActive = chatProvider.conversations.any(
        (c) => c.projectId == p.id && c.id == chatProvider.currentConversationId);
    // Drop target: a chat dragged here is moved into this project.
    return DragTarget<Conversation>(
      onWillAcceptWithDetails: (d) => d.data.projectId != p.id,
      onAcceptWithDetails: (d) {
        _assignProject(context, d.data, p.id);
        // Reveal the freshly-filed chat by expanding the project.
        setState(() => _expandedProjects.add(p.id));
      },
      builder: (context, candidate, rejected) => _ProjectTile(
        project: p,
        isActive: isActive,
        dropHighlight: candidate.isNotEmpty,
        onToggle: () => setState(() {
          if (!_expandedProjects.remove(p.id)) _expandedProjects.add(p.id);
        }),
        onOpen: () {
          widget.onOpenProject?.call(p);
          _afterNav();
        },
        onNewChat: () => _newChatInProject(context, p),
        onRename: () => _createProjectDialog(context, existing: p),
        onInstructions: () => _instructionsDialog(context, p),
        onDelete: () => _confirmDeleteProject(context, p),
      ),
    );
  }

  Future<void> _assignProject(
      BuildContext context, Conversation conv, int? projectId) async {
    try {
      await context.read<ChatProvider>().assignToProject(conv.id, projectId);
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Failed: $e');
    }
  }

  /// Start a new chat that will live inside [p]. Opens the (empty) chat; it's
  /// filed under the project as soon as the first message is sent.
  void _newChatInProject(BuildContext context, Project p) {
    context.read<ChatProvider>().startNewChatInProject(p.id);
    widget.onOpenChat?.call();
    _afterNav();
  }

  /// Returns the created/edited project's id (null if cancelled or failed) so
  /// callers can chain — e.g. create a project and immediately move a chat in.
  Future<int?> _createProjectDialog(BuildContext context, {Project? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.instructions ?? '');
    final isEdit = existing != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Rename project' : 'New project'),
        content: SizedBox(
          width: _dialogWidth(context),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration(context, 'Project name',
                    hint: 'e.g. Marketing site')),
            const SizedBox(height: 18),
            TextField(
                controller: descCtrl,
                minLines: 3,
                maxLines: 5,
                decoration: _fieldDecoration(
                    context, 'Project instructions (optional)',
                    hint: 'Standing instructions applied to every chat here…')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isEdit ? 'Save' : 'Create')),
        ],
      ),
    );
    if (ok != true) return null;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return null;
    final prov = context.read<ChatProvider>();
    try {
      if (isEdit) {
        await prov.updateProject(existing.id,
            name: name, instructions: descCtrl.text.trim());
        return existing.id;
      } else {
        final p = await prov.createProject(name, instructions: descCtrl.text.trim());
        return p.id;
      }
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Failed: $e');
      return null;
    }
  }

  /// "New project" from a chat's Move-to-project submenu: create it, then move
  /// this conversation straight into it.
  Future<void> _moveToNewProject(BuildContext context, Conversation conv) async {
    final id = await _createProjectDialog(context);
    if (id != null && context.mounted) {
      await _assignProject(context, conv, id);
    }
  }

  Future<void> _instructionsDialog(BuildContext context, Project p) async {
    final ctrl = TextEditingController(text: p.instructions ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${p.name} · instructions'),
        content: SizedBox(
          width: _dialogWidth(context),
          child: TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 5,
              maxLines: 10,
              decoration: _fieldDecoration(context, 'Instructions',
                  hint: 'Standing instructions applied to every chat in this project…'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<ChatProvider>()
          .updateProject(p.id, instructions: ctrl.text.trim());
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Failed: $e');
    }
  }

  Future<void> _confirmDeleteProject(BuildContext context, Project p) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: Text(p.conversationCount > 0
            ? 'This project has ${p.conversationCount} chat(s). Keep them '
                '(move to ungrouped) or delete them too?'
            : 'Delete this project?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          if (p.conversationCount > 0)
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'keep'),
                child: const Text('Keep chats')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () =>
                Navigator.pop(ctx, p.conversationCount > 0 ? 'delete' : 'keep'),
            child: Text(p.conversationCount > 0 ? 'Delete chats too' : 'Delete'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      await context.read<ChatProvider>()
          .deleteProject(p.id, deleteConversations: choice == 'delete');
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final chatProvider = context.watch<ChatProvider>();

    final base = _query.isEmpty
        ? chatProvider.conversations
        : chatProvider.conversations
            .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    final projects = chatProvider.projects;
    // Browsing → grouped chats live under their project; only ungrouped chats
    // show in the flat CONVERSATIONS list (branch chats nest under parents).
    // Searching → a flat list of matches across everything.
    final ungrouped =
        _query.isEmpty ? base.where((c) => c.projectId == null).toList() : base;
    final rows = _query.isEmpty
        ? _treeRows(ungrouped)
        : [for (final c in base) (conv: c, depth: 0, hasChildren: false)];

    return Container(
      width: widget.isDrawer ? null : widget.width,
      color: colors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brandHeader(colors, typography),
          const SizedBox(height: 4),
          // Quick actions
          _navItem(colors, typography,
              icon: Icons.create_new_folder_outlined,
              label: 'New project',
              onTap: () => _createProjectDialog(context)),
          _navItem(colors, typography,
              icon: Icons.add_rounded,
              label: 'New chat',
              onTap: () {
                chatProvider.startNewChat();
                widget.onOpenChat?.call();
                _afterNav();
              }),
          _navItem(colors, typography,
              icon: Icons.search_rounded,
              label: 'Search chats',
              selected: _searchOpen,
              onTap: _toggleSearch),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: FTextField(
                control: FTextFieldControl.managed(controller: _searchController),
                autofocus: true,
                hint: 'Search chats…',
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 2),
              children: [
                // Projects (A.7): grouped chats live here, not in the flat list.
                if (_query.isEmpty && projects.isNotEmpty) ...[
                  _projectsHeader(typography, colors),
                  if (_projectsOpen)
                    for (final p in projects)
                      ..._projectBlock(context, chatProvider, p),
                  const SizedBox(height: 12),
                ],
                _conversationsHeader(context, typography, colors),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        _query.isEmpty
                            ? 'No conversations yet'
                            : 'No matching chats',
                        style: typography.body.sm
                            .copyWith(color: colors.mutedForeground),
                      ),
                    ),
                  )
                else
                  for (final row in rows) _convTile(context, chatProvider, row),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: colors.border,
          ),
          const SizedBox(height: 2),
          _navItem(colors, typography,
              icon: Icons.menu_book_outlined,
              label: 'Setup guide',
              selected: widget.activeView == 'guide',
              onTap: _goGuide),
          _navItem(colors, typography,
              icon: Icons.person_outline,
              label: 'Profile',
              selected: widget.activeView == 'profile',
              onTap: _goProfile),
          Row(
            children: [
              Expanded(
                child: _navItem(colors, typography,
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    selected: widget.activeView == 'settings',
                    onTap: _goSettings),
              ),
              if (widget.onClose != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: widget.onClose,
                    child: Icon(Icons.chevron_left, size: 20, color: colors.mutedForeground),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _brandHeader(FColors colors, FTypography typography) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 8),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 28, color: colors.primary),
          const SizedBox(width: 10),
          Text('Nexus AI',
              style: typography.body.lg.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _navItem(FColors colors, FTypography typography,
      {required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: NavTile(
        icon: icon,
        label: label,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

/// A conversation row: title + relative time + an overflow (…) menu offering
/// Rename / Delete.
class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool isSelected;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final int depth;
  // Project-child chats indent without the branch "subdirectory" arrow glyph.
  final bool plainIndent;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final List<Project> projects;
  final void Function(int? projectId) onAssignProject;
  final VoidCallback onMoveToNewProject;

  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.subtitle,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onAssignProject,
    required this.onMoveToNewProject,
    this.depth = 0,
    this.plainIndent = false,
    this.hasChildren = false,
    this.expanded = false,
    this.onToggleExpand,
    this.projects = const [],
  });

  /// The "⋯" options menu: Rename, Delete, and a cascading **Move to project**
  /// submenu whose first entry creates a brand-new project (and moves this chat
  /// into it). Uses MenuAnchor/SubmenuButton so the submenu cascades on desktop
  /// and opens inline on mobile — no divider, matching the requested design.
  Widget _optionsMenu(BuildContext context, FColors colors) {
    final current = conversation.projectId;
    final menuStyle = MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(Color(0xFF1F1F1F)),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.45)),
      elevation: const WidgetStatePropertyAll(8),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      )),
    );
    final itemStyle = MenuItemButton.styleFrom(
      foregroundColor: colors.foreground,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: const Size(184, 42),
    );

    return MenuAnchor(
      style: menuStyle,
      builder: (context, controller, _) => IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: 18,
        tooltip: 'Options',
        icon: Icon(Icons.more_horiz, color: colors.mutedForeground),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        MenuItemButton(
          style: itemStyle,
          leadingIcon:
              Icon(Icons.edit_outlined, size: 18, color: colors.mutedForeground),
          onPressed: onRename,
          child: const Text('Rename'),
        ),
        MenuItemButton(
          style: itemStyle,
          leadingIcon: Icon(Icons.delete_outline,
              size: 18, color: colors.mutedForeground),
          onPressed: onDelete,
          child: const Text('Delete'),
        ),
        SubmenuButton(
          style: itemStyle,
          menuStyle: menuStyle,
          leadingIcon: Icon(Icons.drive_file_move_outline,
              size: 18, color: colors.mutedForeground),
          menuChildren: [
            // Create a new project and move this chat straight into it.
            MenuItemButton(
              style: itemStyle,
              leadingIcon:
                  Icon(Icons.add_rounded, size: 18, color: colors.primary),
              onPressed: onMoveToNewProject,
              child: Text('New project',
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.w600)),
            ),
            // Existing projects (the current one is checked + disabled).
            for (final p in projects)
              MenuItemButton(
                style: itemStyle,
                leadingIcon: Icon(
                    p.id == current
                        ? Icons.check_rounded
                        : Icons.folder_outlined,
                    size: 18,
                    color:
                        p.id == current ? colors.primary : colors.mutedForeground),
                onPressed:
                    p.id == current ? null : () => onAssignProject(p.id),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            // Detach from its current project.
            if (current != null)
              MenuItemButton(
                style: itemStyle,
                leadingIcon: Icon(Icons.folder_off_outlined,
                    size: 18, color: colors.mutedForeground),
                onPressed: () => onAssignProject(null),
                child: const Text('Remove from project'),
              ),
          ],
          child: const Text('Move to project'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final tile = NavTile(
      label: conversation.title,
      subtitle: subtitle,
      selected: isSelected,
      onTap: onTap,
      dense: true,
      trailing: SizedBox(
        width: 26,
        height: 26,
        child: _optionsMenu(context, colors),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
          left: (plainIndent ? 18.0 : 8.0) + depth * 12,
          right: 8,
          top: 2,
          bottom: 2),
      child: Row(
        children: [
          if (hasChildren)
            GestureDetector(
              onTap: onToggleExpand,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                    expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    size: 18,
                    color: colors.mutedForeground),
              ),
            )
          else if (depth > 0 && !plainIndent)
            Padding(
              padding: const EdgeInsets.only(right: 4, left: 2),
              child: Icon(Icons.subdirectory_arrow_right,
                  size: 14, color: colors.mutedForeground),
            ),
          Expanded(child: tile),
        ],
      ),
    );
  }
}

/// Icon-only rail shown when the sidebar is collapsed on a wide layout.
class CollapsedSidebar extends StatelessWidget {
  final String activeView;
  final VoidCallback onExpand;
  final VoidCallback onNewChat;
  final VoidCallback onSearch;
  final VoidCallback onGuide;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  const CollapsedSidebar({
    super.key,
    required this.activeView,
    required this.onExpand,
    required this.onNewChat,
    required this.onSearch,
    required this.onGuide,
    required this.onProfile,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      width: 56,
      color: colors.secondary,
      child: Column(
        children: [
          const SizedBox(height: 14),
          _railIcon(colors, Icons.auto_awesome, 'Expand sidebar', onExpand,
              color: colors.primary),
          const SizedBox(height: 10),
          _railIcon(colors, Icons.add_rounded, 'New chat', onNewChat),
          _railIcon(colors, Icons.search_rounded, 'Search chats', onSearch),
          const Spacer(),
          _railIcon(colors, Icons.menu_book_outlined, 'Setup guide', onGuide),
          _railIcon(colors, Icons.person_outline, 'Profile', onProfile,
              selected: activeView == 'profile'),
          _railIcon(colors, Icons.settings_outlined, 'Settings', onSettings,
              selected: activeView == 'settings'),
          _railIcon(colors, Icons.chevron_right, 'Expand sidebar', onExpand),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _railIcon(FColors colors, IconData icon, String tooltip, VoidCallback onTap,
      {bool selected = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 9),
      child: FButton.icon(
        variant: selected ? FButtonVariant.secondary : FButtonVariant.ghost,
        onPress: onTap,
        child: Icon(icon,
            size: 20,
            color: color ?? (selected ? colors.primary : colors.mutedForeground)),
      ),
    );
  }
}

/// A project row (A.7): folder icon + name + a "+" new-chat button and an
/// overflow menu (Open project / Rename / Instructions / Delete). Tapping the
/// row toggles its inline chat list (collapsed by default); the project holding
/// the currently-open chat is highlighted.
class _ProjectTile extends StatefulWidget {
  final Project project;
  final bool isActive;
  // A chat is currently being dragged over this project (drop target active).
  final bool dropHighlight;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onNewChat;
  final VoidCallback onRename;
  final VoidCallback onInstructions;
  final VoidCallback onDelete;

  const _ProjectTile({
    required this.project,
    required this.onToggle,
    required this.onOpen,
    required this.onNewChat,
    required this.onRename,
    required this.onInstructions,
    required this.onDelete,
    this.isActive = false,
    this.dropHighlight = false,
  });

  @override
  State<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<_ProjectTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final p = widget.project;
    final active = widget.isActive;
    final drop = widget.dropHighlight;
    final Color? bg = drop
        ? colors.primary.withValues(alpha: 0.28)
        : active
            ? colors.primary.withValues(alpha: 0.12)
            : (_hovered ? colors.border.withValues(alpha: 0.55) : null);
    // Actions are always visible; brighten them on hover / active so they read
    // clearly against the tinted row background.
    final iconColor =
        (_hovered || active) ? colors.foreground : colors.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onToggle, // expand / collapse the chat list
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: drop
                  ? Border.all(color: colors.primary, width: 1.5)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              Icon(Icons.folder_outlined, size: 18, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.body.sm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: active ? colors.primary : colors.foreground)),
              ),
              // "+" new chat in this project — always visible.
              _miniButton(iconColor, Icons.add_rounded, 'New chat in project',
                  widget.onNewChat),
              SizedBox(
                width: 24,
                height: 24,
                child: PopupMenuButton<String>(
                  tooltip: 'Project options',
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  icon: Icon(Icons.more_horiz, color: iconColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onSelected: (v) {
                    if (v == 'open') widget.onOpen();
                    if (v == 'newchat') widget.onNewChat();
                    if (v == 'rename') widget.onRename();
                    if (v == 'instructions') widget.onInstructions();
                    if (v == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', height: 42, child: Row(children: [
                      Icon(Icons.open_in_new_rounded, size: 18), SizedBox(width: 10), Text('Open project'),
                    ])),
                    PopupMenuItem(value: 'newchat', height: 42, child: Row(children: [
                      Icon(Icons.add_rounded, size: 18), SizedBox(width: 10), Text('New chat'),
                    ])),
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
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _miniButton(
      Color color, IconData icon, String tooltip, VoidCallback onTap) {
    return SizedBox(
      width: 26,
      height: 26,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: 16,
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onTap,
      ),
    );
  }
}
