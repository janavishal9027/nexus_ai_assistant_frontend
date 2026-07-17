import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/clarify_panel.dart';
import '../widgets/connectivity_indicator.dart';
import '../widgets/sidebar.dart';
import '../widgets/resize_handle.dart';
import '../models/project.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'guide_screen.dart';
import 'project_screen.dart';

/// Which panel the main content area shows (master-detail with the sidebar).
/// Settings is a separate full-screen route, so it isn't a view here.
enum _MainView { chat, profile, guide, project }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  bool _sidebarOpen = true;
  // The main content area shows chat, profile, guide, or a project page
  // (sidebar persists). Settings opens as its own full-screen route.
  _MainView _view = _MainView.chat;
  Project? _activeProject; // the project shown when _view == project

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
        // Jump instead of glide when the user asked for less motion.
        if (context.read<SettingsProvider>().reduceAnimations) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          return;
        }
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
      // Android/iOS: the system back gesture/button steps back to the chat from
      // the in-content views (Profile / Guide / Project), which are view swaps
      // rather than routes — otherwise back would exit the app.
      body: PopScope(
        canPop: _view == _MainView.chat,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _view != _MainView.chat) {
            setState(() => _view = _MainView.chat);
          }
        },
        // Full SafeArea: keeps the top bar below the status bar AND lifts the
        // composer clear of the bottom system navigation bar (gesture / 3-button)
        // on mobile. It collapses automatically while the keyboard is open;
        // no-op on desktop.
        child: SafeArea(child: Builder(
        builder: (scaffoldContext) => Row(
          children: [
            // Unified conversation sidebar (brand, nav, conversations, bottom
            // nav + collapse). Collapsing hides it; the top-bar button reopens
            // it. Drag the handle on its right edge to resize.
            if (isWide && _sidebarOpen) ...[
              Sidebar(
                width: _sidebarWidth,
                onClose: () => setState(() => _sidebarOpen = false),
                activeView: _viewName,
                onOpenChat: () => setState(() => _view = _MainView.chat),
                onOpenProfile: () => setState(() => _view = _MainView.profile),
                onOpenSettings: _openSettingsRoute,
                onOpenGuide: () => setState(() => _view = _MainView.guide),
                onOpenProject: _openProject,
              ),
              ResizeHandle(
                onDrag: (dx) => setState(() =>
                    _sidebarWidth = (_sidebarWidth + dx).clamp(_minSidebar, _maxSidebar)),
                onDragEnd: _saveSidebarWidth,
              ),
            ] else if (isWide)
              // Collapsed: a slim icon rail (not hidden), with an expand control.
              CollapsedSidebar(
                activeView: _viewName,
                onExpand: () => setState(() => _sidebarOpen = true),
                onNewChat: () {
                  context.read<ChatProvider>().startNewChat();
                  setState(() => _view = _MainView.chat);
                },
                onSearch: () => setState(() => _sidebarOpen = true),
                onGuide: () => setState(() => _view = _MainView.guide),
                onProfile: () => setState(() => _view = _MainView.profile),
                onSettings: _openSettingsRoute,
              ),
            // Main content: chat or embedded profile.
            Expanded(
              child: _mainContent(scaffoldContext, isWide),
            ),
          ],
        ),
      )),
      ),
      // Mobile drawer
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(child: Sidebar(
                isDrawer: true,
                onClose: () => Navigator.of(context).pop(),
                activeView: _viewName,
                onOpenChat: () => setState(() => _view = _MainView.chat),
                onOpenProfile: () => setState(() => _view = _MainView.profile),
                onOpenSettings: _openSettingsRoute,
                onOpenGuide: () => setState(() => _view = _MainView.guide),
                onOpenProject: _openProject,
              )),
            ),
    );
  }

  String get _viewName => switch (_view) {
        _MainView.profile => 'profile',
        _MainView.guide => 'guide',
        _MainView.project => 'project',
        _MainView.chat => 'chat',
      };

  void _backToChat() => setState(() => _view = _MainView.chat);

  void _openProject(Project p) => setState(() {
        _activeProject = p;
        _view = _MainView.project;
      });

  /// Settings opens as its own full-screen page (its own sub-navigation looks
  /// cramped embedded next to the main sidebar), unlike Profile which is shown
  /// inline in the main content area.
  void _openSettingsRoute() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  /// Jump straight to Settings → API Keys (used by the no-keys onboarding to
  /// guide a fresh install to add its first provider key).
  void _openApiKeys() {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const SettingsScreen(initialSection: 2)),
    );
  }

  /// The main panel: chat, or the embedded Profile screen whose back button
  /// returns here (keeping the sidebar in place).
  Widget _mainContent(BuildContext context, bool isWide) {
    switch (_view) {
      case _MainView.profile:
        return ProfileScreen(onBack: _backToChat);
      case _MainView.guide:
        return GuideScreen(onBack: _backToChat);
      case _MainView.project:
        return ProjectScreen(
          projectId: _activeProject!.id,
          onBack: _backToChat,
          onOpenConversation: (id) {
            context.read<ChatProvider>().selectConversation(id);
            setState(() => _view = _MainView.chat);
          },
          onNewChat: () {
            context.read<ChatProvider>().startNewChatInProject(_activeProject!.id);
            setState(() => _view = _MainView.chat);
          },
        );
      case _MainView.chat:
        return _buildChatArea(context, isWide);
    }
  }

  Widget _buildChatArea(BuildContext context, bool isWide) {
    final theme = Theme.of(context);
    final chatProvider = context.watch<ChatProvider>();
    // Fresh install with no provider keys → lock chat and guide the user to
    // add at least one key. Gate on configLoaded so we don't flash the locked
    // state during the initial load.
    final noKeys =
        chatProvider.configLoaded && chatProvider.activeProviders.isEmpty;

    return LayoutBuilder(builder: (context, constraints) {
      // Real available height for the chat column — the Scaffold has already
      // subtracted the keyboard here (unlike MediaQuery inside the body). Cap
      // the Clarifier panel to half of it so the messages/empty-state region
      // above always keeps room to shrink into instead of overflowing.
      final availH = constraints.maxHeight;
      final clarifyMax = availH.isFinite ? availH * 0.5 : 480.0;
      return Column(
      children: [
        // Top bar
        _buildTopBar(context, theme, isWide, chatProvider),
        // Divider
        Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        // Messages, over the chosen chat wallpaper (Settings → Personalization).
        Expanded(
          child: _ChatBackground(
            child: noKeys
                ? _buildNoKeysState(theme)
                : chatProvider.messages.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildMessageList(chatProvider),
          ),
        ),
        // Error display (hidden while locked — the onboarding covers it)
        if (!noKeys && chatProvider.error != null)
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
        // Clarifier (A.2): while a blocking question is pending, it REPLACES the
        // composer (it has its own input + Submit) — this frees the space that
        // otherwise overflowed with the keyboard open.
        if (chatProvider.pendingClarify.isNotEmpty)
          ClarifyPanel(
            questions: chatProvider.pendingClarify,
            maxHeight: clarifyMax,
          )
        else ...[
          if (chatProvider.pendingProjectId != null)
            _pendingProjectBar(context, chatProvider),
          if (chatProvider.clarifyChecking) _clarifyCheckingIndicator(context),
          ChatInput(
            onSend: (text, attachments) {
              chatProvider.sendUserMessage(text, attachments: attachments);
              _scrollToBottom();
            },
            isLoading: chatProvider.isBusyHere || chatProvider.clarifyChecking,
            onStop: chatProvider.stopGeneration,
            deepResearch: chatProvider.deepResearch,
            onToggleDeepResearch: chatProvider.toggleDeepResearch,
            webSearch: chatProvider.webSearch,
            onToggleWebSearch: chatProvider.toggleWebSearch,
            locked: noKeys,
            onLockedTap: _openApiKeys,
          ),
        ],
      ],
      );
    });
  }

  /// Slim banner shown above the composer when a new chat is bound to a project
  /// (started via a project's "New chat"). It's filed there on first send; the
  /// "×" cancels the binding back to a normal new chat.
  Widget _pendingProjectBar(BuildContext context, ChatProvider cp) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    var name = 'project';
    for (final p in cp.projects) {
      if (p.id == cp.pendingProjectId) {
        name = p.name;
        break;
      }
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              Icon(Icons.folder_open_rounded, size: 15, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('New chat in “$name”',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: primary, fontWeight: FontWeight.w600)),
              ),
              InkWell(
                onTap: cp.startNewChat,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded,
                      size: 15, color: primary.withValues(alpha: 0.8)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Slim "understanding your request…" line shown while the Clarifier gate runs.
  Widget _clarifyCheckingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
          child: Row(
            children: [
              SizedBox(
                width: 13, height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Text('Understanding your request…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ThemeData theme, bool isWide, ChatProvider chatProvider) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Menu button (mobile only)
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
          // Device connectivity (green Online / red Offline) — shown on every
          // platform, so mobile matches desktop.
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: ConnectivityIndicator(),
          ),
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
          // Settings lives only in the side navigation (drawer on mobile, nav
          // rail on desktop) — no duplicate top-bar gear here.
        ],
      ),
    );
  }

  Widget _buildModelSelector(ThemeData theme, ChatProvider chatProvider) {
    final models = chatProvider.availableModels;

    return PopupMenuButton<String>(
      onSelected: chatProvider.setSelectedModel,
      offset: const Offset(0, 40),
      constraints:
          const BoxConstraints(maxHeight: 460, minWidth: 300, maxWidth: 360),
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
                _selectedLabel(chatProvider.selectedModel),
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
        final primary = theme.colorScheme.primary;
        final selected = chatProvider.selectedModel;
        // Number of models per provider, for the section headers.
        final modelCounts = <String, int>{};
        for (final m in models) {
          final p = m['platform']?.toString() ?? '';
          modelCounts[p] = (modelCounts[p] ?? 0) + 1;
        }
        final items = <PopupMenuEntry<String>>[
          PopupMenuItem(
            value: 'auto',
            height: 42,
            child: Row(children: [
              Icon(Icons.auto_awesome, size: 15, color: primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Auto (Best Available)',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (selected == 'auto')
                Icon(Icons.check, size: 15, color: primary),
            ]),
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
          return items;
        }

        // Group by provider: a header, a provider-scoped "Auto", then the
        // provider's chat models (smallest → largest, from the backend).
        String? lastPlatform;
        for (final model in models) {
          final platform = model['platform']?.toString() ?? '';
          final platformName = model['platformName']?.toString() ?? '';
          if (platform != lastPlatform) {
            lastPlatform = platform;
            items.add(PopupMenuItem(
              enabled: false,
              value: '',
              height: 30,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      platformName.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5)),
                    ),
                  ),
                  Text(
                    '${modelCounts[platform] ?? 0} models',
                    style: TextStyle(
                        fontSize: 10,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                  ),
                ],
              ),
            ));
            final pAuto = 'auto:$platform';
            items.add(PopupMenuItem(
              value: pAuto,
              height: 40,
              child: Row(children: [
                Icon(Icons.auto_awesome, size: 14, color: primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Auto · best $platformName model',
                      style: const TextStyle(fontSize: 12.5)),
                ),
                if (selected == pAuto)
                  Icon(Icons.check, size: 14, color: primary),
              ]),
            ));
          }
          items.add(_modelMenuItem(theme, model, selected));
        }
        return items;
      },
    );
  }

  /// A single model row: name + parameter-size badge + cost badge (+ check).
  PopupMenuItem<String> _modelMenuItem(
      ThemeData theme, Map<String, dynamic> model, String selected) {
    final id = model['id']?.toString() ?? '';
    final name = model['name']?.toString() ?? 'Unknown';
    final pb = model['param_billions'];
    final cost = model['cost']?.toString() ?? '';
    final isSel = id == selected;
    return PopupMenuItem<String>(
      value: id,
      height: 40,
      child: Row(children: [
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w400)),
        ),
        const SizedBox(width: 6),
        _sizeBadge(theme, pb, model['tier']?.toString()),
        const SizedBox(width: 6),
        _costBadge(theme, cost),
        if (isSel) ...[
          const SizedBox(width: 4),
          Icon(Icons.check, size: 14, color: theme.colorScheme.primary),
        ],
      ]),
    );
  }

  /// Size badge: the parameter count when it's known (e.g. "8B", "120B", "1T"),
  /// otherwise the size tier (Frontier / Large / Medium / Small) — closed models
  /// like Claude, GPT and Grok don't publish parameter counts, so every model
  /// still shows a size indicator instead of a blank.
  Widget _sizeBadge(ThemeData theme, dynamic pb, String? tier) {
    String? label;
    if (pb is num) {
      if (pb >= 1000) {
        final t = pb / 1000;
        label = t == t.roundToDouble()
            ? '${t.toStringAsFixed(0)}T'
            : '${t.toStringAsFixed(1)}T';
      } else {
        label = '${pb.round()}B';
      }
    } else if (tier != null && tier.isNotEmpty) {
      label = tier;
    }
    if (label == null) return const SizedBox.shrink();
    return Text(label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)));
  }

  /// Colored billing hint: Free (teal), Credit (amber) or Paid (blue).
  Widget _costBadge(ThemeData theme, String cost) {
    final Color c;
    final String label;
    switch (cost) {
      case 'free':
        c = const Color(0xFF10A37F);
        label = 'Free';
        break;
      case 'credit':
        c = const Color(0xFFF59E0B);
        label = 'Credit';
        break;
      case 'paid':
        c = const Color(0xFF3B82F6);
        label = 'Paid';
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c)),
    );
  }

  /// Label for the selector button: "Auto", "Groq · Auto", or a model name.
  String _selectedLabel(String selected) {
    if (selected == 'auto') return 'Auto';
    if (selected.startsWith('auto:')) {
      final plat = selected.substring(5);
      final p = context.read<ChatProvider>().providers.firstWhere(
          (x) => x['id']?.toString() == plat,
          orElse: () => const <String, dynamic>{});
      return '${p['name']?.toString() ?? plat} · Auto';
    }
    return _shortenModelName(selected);
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

  /// Shown when the account has no active provider keys: chat is locked, so
  /// guide the user to add their first key.
  Widget _buildNoKeysState(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.vpn_key_outlined, size: 34, color: primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Add a provider to start chatting',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Nexus AI routes your messages across LLM providers, but it needs '
                'at least one API key first. Most have a free tier — Groq is fast '
                'and free to start.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openApiKeys,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add API Key'),
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen(initialSection: 3)),
                ),
                child: Text('See supported providers',
                    style: TextStyle(color: primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      // Scrollable so it shrinks gracefully (instead of overflowing) when the
      // Clarifier panel + keyboard squeeze this Expanded region on mobile.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
          // Dynamic, LLM-generated suggestion chips — refreshed per new chat
          // (keyed on the provider's newChatNonce so a fresh set loads each time).
          _StarterChips(
            key: ValueKey(context.watch<ChatProvider>().newChatNonce),
          ),
        ],
        ),
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
        final msg = chatProvider.messages[index];
        return MessageBubble(
          key: ValueKey('msg_$index'),
          message: msg,
          index: index,
          // Only user messages are editable; the bubble shows the control.
          onEdit: msg.role == 'user' ? chatProvider.editAndResend : null,
        );
      },
    );
  }
}

/// Paints the chat wallpaper behind the message list (Settings →
/// Personalization). Built-ins are gradients — no assets, and they adapt to
/// light/dark. A custom image is device-local; if its file has gone (deleted,
/// or the setting synced from another device) this falls back to no wallpaper
/// rather than showing a broken image.
class _ChatBackground extends StatelessWidget {
  const _ChatBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    if (!s.hasWallpaper) return child;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (s.wallpaper == Wallpaper.custom) {
      final path = s.wallpaperPath;
      if (path == null || !File(path).existsSync()) return child;
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(path), fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          // Keep bubbles legible over an arbitrary photo.
          Container(
            color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.45),
          ),
          child,
        ],
      );
    }

    final gradient = SettingsProvider.gradientFor(s.wallpaper, isDark);
    if (gradient == null) return child;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: child,
    );
  }
}

/// Empty-state starter chips. On mount it asks the backend for 3 fresh,
/// LLM-generated starters (a current-tech/coding task, a globally-relevant
/// idea, a writing task) tailored per new chat. Shows a sensible default set
/// while loading / on failure so chips are always present.
class _StarterChips extends StatefulWidget {
  const _StarterChips({super.key});

  @override
  State<_StarterChips> createState() => _StarterChipsState();
}

class _StarterChipsState extends State<_StarterChips> {
  // Shown immediately while the dynamic set loads (and if the fetch fails).
  static const List<Map<String, String>> _defaults = [
    {
      'category': 'code',
      'label': 'Build a REST API',
      'prompt':
          'Show me how to build a small REST API with one CRUD endpoint, with runnable code.'
    },
    {
      'category': 'idea',
      'label': 'Fresh ideas',
      'prompt':
          'Brainstorm 5 fresh ideas relevant to what is trending in the world right now.'
    },
    {
      'category': 'write',
      'label': 'Help me write',
      'prompt': 'Help me write a clear, professional email.'
    },
  ];

  List<Map<String, String>> _items = _defaults;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final model = context.read<ChatProvider>().selectedModel;
    final items = await ApiService.getStarters(model: model);
    if (!mounted || items.length < 3) return;
    setState(() => _items = items.take(3).toList());
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'code':
        return Icons.code;
      case 'write':
        return Icons.edit_note;
      case 'idea':
      default:
        return Icons.lightbulb_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final it in _items)
          _SuggestionChip(
            icon: _iconFor(it['category'] ?? 'idea'),
            label: it['label'] ?? '',
            onTap: () =>
                context.read<ChatProvider>().sendMessage(it['prompt'] ?? ''),
          ),
      ],
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

