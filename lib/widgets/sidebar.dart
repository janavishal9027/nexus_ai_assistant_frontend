import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';

/// Expanded sidebar (260px): brand + collapse button, New chat / Search chats
/// actions, and the conversation list.
class Sidebar extends StatefulWidget {
  final VoidCallback? onClose;

  /// When shown inside the mobile Drawer we pop it after navigating; on a wide
  /// layout the panel stays open (we only collapse via the header button).
  final bool isDrawer;

  /// Panel width on the wide (desktop) layout — driven by the drag handle.
  final double width;

  const Sidebar({super.key, this.onClose, this.isDrawer = false, this.width = 260});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  String _query = '';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatProvider = context.watch<ChatProvider>();

    final conversations = _query.isEmpty
        ? chatProvider.conversations
        : chatProvider.conversations
            .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    // Exact number of models available to use (from providers with API keys).
    final modelCount = chatProvider.availableModels.length;

    return Container(
      width: widget.isDrawer ? null : widget.width,
      color: isDark ? const Color(0xFF171717) : const Color(0xFFF9F9F9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: panel title + collapse button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Row(
              children: [
                Icon(Icons.forum_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Chats',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.menu_open),
                    iconSize: 20,
                    tooltip: 'Collapse sidebar',
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          // Actions
          _SidebarAction(
            icon: Icons.edit_square,
            label: 'New chat',
            onTap: () {
              chatProvider.startNewChat();
              _afterNav();
            },
          ),
          _SidebarAction(
            icon: Icons.search,
            label: 'Search chats',
            onTap: _toggleSearch,
          ),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          // Conversation list
          Expanded(
            child: conversations.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No conversations yet'
                          : 'No matching chats',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
                      final isSelected =
                          conv.id == chatProvider.currentConversationId;
                      return _ConversationTile(
                        conversation: conv,
                        isSelected: isSelected,
                        onTap: () {
                          chatProvider.selectConversation(conv.id);
                          _afterNav();
                        },
                        onDelete: () {
                          chatProvider.deleteConversation(conv.id);
                        },
                      );
                    },
                  ),
          ),
          // Footer
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Nexus AI',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  modelCount > 0
                      ? '$modelCount Free Model${modelCount == 1 ? '' : 's'}'
                      : 'No models — add a key',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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

/// Collapsed rail (~60px): icon-only strip shown when the sidebar is closed on
/// a wide layout. Clicking the panel/search/chats icons re-expands it.
class CollapsedSidebar extends StatelessWidget {
  final VoidCallback onOpen;

  const CollapsedSidebar({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatProvider = context.read<ChatProvider>();

    return Container(
      width: 60,
      color: isDark ? const Color(0xFF171717) : const Color(0xFFF9F9F9),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _RailButton(
            icon: Icons.view_sidebar_outlined,
            tooltip: 'Expand sidebar',
            onTap: onOpen,
          ),
          const SizedBox(height: 4),
          _RailButton(
            icon: Icons.edit_square,
            tooltip: 'New chat',
            onTap: chatProvider.startNewChat,
          ),
          _RailButton(
            icon: Icons.search,
            tooltip: 'Search chats',
            onTap: onOpen,
          ),
          _RailButton(
            icon: Icons.chat_bubble_outline,
            tooltip: 'Chats',
            onTap: onOpen,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}

class _SidebarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 12),
                Text(label, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                if (isSelected)
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
