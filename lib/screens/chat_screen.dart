import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/sidebar.dart';
import '../widgets/resize_handle.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  bool _sidebarOpen = true;

  // Drag-resizable conversation sidebar width (persisted).
  static const double _minSidebar = 220, _maxSidebar = 420;
  static const String _sidebarPrefKey = 'chat_sidebar_width';
  double _sidebarWidth = 260;

  @override
  void initState() {
    super.initState();
    _loadSidebarWidth();
    // Load this account's config + conversations once the screen is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ChatProvider>().initialize();
    });
  }

  Future<void> _loadSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble(_sidebarPrefKey);
    if (w != null && mounted) {
      setState(() => _sidebarWidth = w.clamp(_minSidebar, _maxSidebar));
    }
  }

  Future<void> _saveSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sidebarPrefKey, _sidebarWidth);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      body: Builder(
        builder: (scaffoldContext) => Row(
          children: [
            // Single left rail (Chat / Settings / Profile) on desktop.
            if (isWide)
              _NavRail(onChatTap: () => setState(() => _sidebarOpen = !_sidebarOpen)),
            // Conversation sidebar — shown when expanded. Collapsing it leaves
            // just the single left rail (no second collapsed rail); the rail's
            // Chat icon re-opens it. Drag the handle on its right edge to resize.
            if (isWide && _sidebarOpen) ...[
              Sidebar(
                width: _sidebarWidth,
                onClose: () => setState(() => _sidebarOpen = false),
              ),
              ResizeHandle(
                onDrag: (dx) => setState(() =>
                    _sidebarWidth = (_sidebarWidth + dx).clamp(_minSidebar, _maxSidebar)),
                onDragEnd: _saveSidebarWidth,
              ),
            ],
            // Main chat area
            Expanded(
              child: _buildChatArea(scaffoldContext, isWide),
            ),
          ],
        ),
      ),
      // Mobile drawer
      drawer: isWide
          ? null
          : Drawer(
              child: Sidebar(
                isDrawer: true,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
    );
  }

  Widget _buildChatArea(BuildContext context, bool isWide) {
    final theme = Theme.of(context);
    final chatProvider = context.watch<ChatProvider>();

    return Column(
      children: [
        // Top bar
        _buildTopBar(context, theme, isWide, chatProvider),
        // Divider
        Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        // Messages
        Expanded(
          child: chatProvider.messages.isEmpty
              ? _buildEmptyState(theme)
              : _buildMessageList(chatProvider),
        ),
        // Error display
        if (chatProvider.error != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chatProvider.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: chatProvider.clearError,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        // Input
        ChatInput(
          onSend: (text) {
            chatProvider.sendMessage(text);
            _scrollToBottom();
          },
          isLoading: chatProvider.isLoading,
          onStop: chatProvider.stopGeneration,
          deepResearch: chatProvider.deepResearch,
          onToggleDeepResearch: chatProvider.toggleDeepResearch,
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, ThemeData theme, bool isWide, ChatProvider chatProvider) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Menu button (mobile only — desktop uses the collapsed rail)
          if (!isWide)
            IconButton(
              icon: const Icon(Icons.menu, size: 20),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: 'Menu',
            ),
          const SizedBox(width: 4),
          // Model selector — capped width so it sizes to content but never
          // overflows (long names ellipsize). Kept inflexible so the Spacer
          // below is the sole flex child.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: _buildModelSelector(theme, chatProvider),
          ),
          // Sole flex child: eats all remaining space so the trailing
          // badge + settings sit flush against the top-right corner.
          const Spacer(),
          // Provider badge
          if (chatProvider.currentPlatform != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 12, color: theme.colorScheme.primary),
                    const SizedBox(width: 3),
                    Text(
                      chatProvider.currentPlatform!,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Settings — on desktop this lives in the left nav rail instead, so
          // only show the top-bar gear on narrow (mobile) layouts.
          if (!isWide)
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              tooltip: 'Settings',
            ),
        ],
      ),
    );
  }

  Widget _buildModelSelector(ThemeData theme, ChatProvider chatProvider) {
    final models = chatProvider.availableModels;

    return PopupMenuButton<String>(
      onSelected: chatProvider.setSelectedModel,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                chatProvider.selectedModel == 'auto'
                    ? 'Auto'
                    : _shortenModelName(chatProvider.selectedModel),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[
          const PopupMenuItem(
            value: 'auto',
            child: Text('Auto (Best Available)'),
          ),
          const PopupMenuDivider(),
        ];

        if (!chatProvider.hasActiveProviders) {
          items.add(const PopupMenuItem(
            enabled: false,
            value: '',
            child: Text('Add API keys in Settings to unlock models',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          ));
        } else {
          // Group by platform
          String? lastPlatform;
          for (final model in models) {
            if (model['platformName'] != lastPlatform) {
              lastPlatform = model['platformName'];
              items.add(PopupMenuItem(
                enabled: false,
                value: '',
                child: Text(
                  (lastPlatform ?? '').toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ));
            }
            items.add(PopupMenuItem(
              value: model['id']?.toString() ?? '',
              child: Text(model['name']?.toString() ?? 'Unknown', style: const TextStyle(fontSize: 13)),
            ));
          }
        }

        return items;
      },
    );
  }

  String _shortenModelName(String modelId) {
    // Show just the display name if possible
    final chatProvider = context.read<ChatProvider>();
    for (final m in chatProvider.availableModels) {
      if (m['id'] == modelId) return m['name']?.toString() ?? modelId;
    }
    // Fallback: last segment
    final parts = modelId.split('/');
    return parts.last.replaceAll(':free', '');
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Nexus AI',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '300+ Free AI Models • Auto Fallback • No Rate Limits',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),
          // Suggestion chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _SuggestionChip(
                icon: Icons.code,
                label: 'Write a Python script',
                onTap: () => context.read<ChatProvider>().sendMessage(
                    'Write a Python script that generates a random password'),
              ),
              _SuggestionChip(
                icon: Icons.lightbulb_outline,
                label: 'Explain something',
                onTap: () => context.read<ChatProvider>().sendMessage(
                    'Explain quantum computing in simple terms'),
              ),
              _SuggestionChip(
                icon: Icons.edit_note,
                label: 'Help me write',
                onTap: () => context.read<ChatProvider>().sendMessage(
                    'Help me write a professional email to request time off'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(ChatProvider chatProvider) {
    _scrollToBottom();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: chatProvider.messages.length,
      itemBuilder: (context, index) {
        return MessageBubble(message: chatProvider.messages[index]);
      },
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim far-left navigation rail (desktop): brand, Chat (active), Settings, and
/// the account avatar (Profile). Keeps the conversation sidebar to its right.
class _NavRail extends StatelessWidget {
  final VoidCallback onChatTap;
  const _NavRail({required this.onChatTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final acct = context.watch<AuthProvider>().account;
    final initial = (acct != null && acct.displayName.isNotEmpty)
        ? acct.displayName[0].toUpperCase()
        : '?';

    return Container(
      width: 56,
      color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFEFEFF1),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Icon(Icons.auto_awesome, size: 22, color: theme.colorScheme.primary),
          const SizedBox(height: 18),
          _RailIcon(
              icon: Icons.forum_outlined, tooltip: 'Chat — toggle sidebar', selected: true, onTap: onChatTap),
          _RailIcon(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Tooltip(
              message: 'Profile',
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                  child: Text(initial,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _RailIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon,
                  size: 20,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
        ),
      ),
    );
  }
}
