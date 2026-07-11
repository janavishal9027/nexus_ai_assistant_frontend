import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../screens/settings_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/guide_screen.dart';
import 'nav_tile.dart';

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
    if (widget.onOpenSettings != null) {
      widget.onOpenSettings!();
      _afterNav();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      _afterNav();
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
    // Browsing → nest branch chats under their parent (expandable); searching →
    // a flat list of matches.
    final rows = _query.isEmpty
        ? _treeRows(base)
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
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Text(
              'CONVERSATIONS',
              style: typography.body.xs.copyWith(
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
                color: colors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No conversations yet'
                          : 'No matching chats',
                      style: typography.body.sm
                          .copyWith(color: colors.mutedForeground),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 2),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final conv = row.conv;
                      final isSelected =
                          conv.id == chatProvider.currentConversationId;
                      return _ConversationTile(
                        conversation: conv,
                        isSelected: isSelected,
                        subtitle: _relativeTime(conv.updatedAt ?? conv.createdAt),
                        depth: row.depth,
                        hasChildren: row.hasChildren,
                        expanded: _expanded.contains(conv.id),
                        onToggleExpand: row.hasChildren
                            ? () => setState(() {
                                  if (!_expanded.remove(conv.id)) {
                                    _expanded.add(conv.id);
                                  }
                                })
                            : null,
                        onTap: () {
                          chatProvider.selectConversation(conv.id);
                          widget.onOpenChat?.call();
                          _afterNav();
                        },
                        onRename: () => _renameDialog(conv),
                        onDelete: () => _confirmDelete(conv),
                      );
                    },
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
  final bool hasChildren;
  final bool expanded;
  final VoidCallback? onToggleExpand;

  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.subtitle,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.depth = 0,
    this.hasChildren = false,
    this.expanded = false,
    this.onToggleExpand,
  });

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
        child: PopupMenuButton<String>(
            tooltip: 'Options',
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: Icon(Icons.more_horiz, color: colors.mutedForeground),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (v) {
              if (v == 'rename') {
                onRename();
              } else if (v == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'rename',
                height: 42,
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Rename'),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                height: 42,
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18),
                  SizedBox(width: 10),
                  Text('Delete'),
                ]),
              ),
            ],
          ),
        ),
      );

    return Padding(
      padding:
          EdgeInsets.only(left: 8.0 + depth * 12, right: 8, top: 2, bottom: 2),
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
          else if (depth > 0)
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
