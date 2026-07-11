import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/resize_handle.dart';
import '../widgets/nav_tile.dart';
import '../utils/app_feedback.dart';

class SettingsScreen extends StatefulWidget {
  /// Which section to open on (index into `_nav`): 0=Account … 3=Providers.
  final int initialSection;

  /// When provided, the screen is embedded in the main content area
  /// (master-detail): the back button returns to chat via this callback instead
  /// of popping a route.
  final VoidCallback? onBack;

  const SettingsScreen({super.key, this.initialSection = 0, this.onBack});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>> _keys = [];
  bool _loading = true;
  int _section = 0;
  String _keyQuery = '';

  // Drag-resizable section-nav width (persisted).
  static const double _minRail = 180, _maxRail = 360;
  static const String _railPrefKey = 'settings_rail_width';
  double _railWidth = 220;
  final _keySearchCtrl = TextEditingController();
  final _serverUrlController = TextEditingController(text: ApiService.baseUrl);

  // Editable account profile (name / email) shown in the Account section.
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _savingProfile = false;
  String? _profileError;
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _nav = <({IconData icon, String label})>[
    (icon: Icons.account_circle_outlined, label: 'Account'),
    (icon: Icons.dns_outlined, label: 'Server'),
    (icon: Icons.key_outlined, label: 'API Keys'),
    (icon: Icons.hub_outlined, label: 'Providers'),
    (icon: Icons.info_outline, label: 'About'),
  ];

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection.clamp(0, _nav.length - 1);
    _keySearchCtrl.addListener(() {
      if (_keyQuery != _keySearchCtrl.text) {
        setState(() => _keyQuery = _keySearchCtrl.text);
      }
    });
    final acct = context.read<AuthProvider>().account;
    _nameCtrl.text = acct?.name ?? '';
    _emailCtrl.text = acct?.email ?? '';
    _loadKeys();
    _loadRailWidth();
  }

  Future<void> _saveProfile() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _profileError = 'Email is required');
      return;
    }
    if (!_emailRe.hasMatch(email)) {
      setState(() => _profileError = 'Enter a valid email address');
      return;
    }
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      await context
          .read<AuthProvider>()
          .updateProfile(name: _nameCtrl.text.trim(), email: email);
      if (mounted) showAppMessage(this.context, 'Profile updated');
    } catch (e) {
      setState(() => _profileError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _loadRailWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble(_railPrefKey);
    if (w != null && mounted) {
      setState(() => _railWidth = w.clamp(_minRail, _maxRail));
    }
  }

  Future<void> _saveRailWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_railPrefKey, _railWidth);
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _keySearchCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    setState(() => _loading = true);
    try {
      _keys = await ApiService.getKeys();
      await context.read<ChatProvider>().loadConfig(); // refresh active status
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
      ),
      body: isWide ? _wideLayout(theme) : _narrowLayout(theme),
    );
  }

  // ─── Layouts ──────────────────────────────────────────────────────────
  Widget _wideLayout(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _navRail(theme),
        ResizeHandle(
          onDrag: (dx) => setState(
              () => _railWidth = (_railWidth + dx).clamp(_minRail, _maxRail)),
          onDragEnd: _saveRailWidth,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _sectionBody(theme, _section),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrowLayout(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.25)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _section,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: theme.colorScheme.primary),
                items: [
                  for (int i = 0; i < _nav.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Row(
                        children: [
                          Icon(_nav[i].icon,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Text(_nav[i].label,
                              style: theme.textTheme.titleSmall),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _section = v ?? 0),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.15)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _sectionBody(theme, _section),
          ),
        ),
      ],
    );
  }

  Widget _navRail(ThemeData theme) {
    final colors = context.theme.colors;
    return Container(
      width: _railWidth,
      color: colors.secondary,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        children: [
          for (int i = 0; i < _nav.length; i++) _navTile(i),
        ],
      ),
    );
  }

  Widget _navTile(int i) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: NavTile(
        icon: _nav[i].icon,
        label: _nav[i].label,
        selected: _section == i,
        onTap: () => setState(() => _section = i),
      ),
    );
  }

  Widget _sectionBody(ThemeData theme, int i) {
    switch (i) {
      case 0:
        return _accountSection(theme);
      case 1:
        return _serverSection(theme);
      case 2:
        return _apiKeysSection(theme);
      case 3:
        return _providersSection(theme);
      default:
        return _aboutSection(theme);
    }
  }

  // ─── Reusable pieces ──────────────────────────────────────────────────
  Widget _header(ThemeData theme, String title, String subtitle, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                  ),
              ],
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, List<Widget> children, {EdgeInsets? padding}) {
    return FCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  // ─── Sections ─────────────────────────────────────────────────────────
  Widget _accountSection(ThemeData theme) {
    final acct = context.watch<AuthProvider>().account;
    final initial = (acct != null && acct.displayName.isNotEmpty)
        ? acct.displayName[0].toUpperCase()
        : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, 'Account', 'Manage your profile and session'),
        _card(theme, [
          Row(
            children: [
              FAvatar.raw(
                size: 48,
                child: Text(initial,
                    style: context.theme.typography.body.lg.copyWith(
                        color: context.theme.colors.primary,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(acct?.displayName ?? 'Account',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (acct?.email != null)
                      Text(acct!.email,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          // Editable profile details.
          FTextField(
            control: FTextFieldControl.managed(controller: _nameCtrl),
            label: const Text('Name'),
            hint: 'Your name',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          FTextField.email(
            control: FTextFieldControl.managed(controller: _emailCtrl),
            label: const Text('Email'),
            hint: 'you@example.com',
          ),
          if (_profileError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: context.theme.colors.destructive),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_profileError!,
                      style: TextStyle(
                          color: context.theme.colors.destructive, fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              onPress: _savingProfile ? null : _saveProfile,
              prefix: _savingProfile
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.theme.colors.primaryForeground))
                  : const Icon(Icons.save_outlined, size: 16),
              child: const Text('Save changes'),
            ),
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FButton(
                variant: FButtonVariant.outline,
                onPress: _showChangePasswordDialog,
                prefix: const Icon(Icons.lock_reset, size: 16),
                child: const Text('Change password'),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () {
                  final navigator = Navigator.of(context);
                  context.read<ChatProvider>().reset();
                  context.read<AuthProvider>().logout();
                  navigator.pop();
                },
                prefix: const Icon(Icons.logout, size: 16),
                child: const Text('Log out'),
              ),
              FButton(
                variant: FButtonVariant.destructive,
                onPress: _showDeleteAccountDialog,
                prefix: const Icon(Icons.delete_forever, size: 16),
                child: const Text('Delete account'),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  Widget _serverSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, 'Server Connection', 'Where the app sends chat requests'),
        _card(theme, [
          FTextField(
            control: FTextFieldControl.managed(controller: _serverUrlController),
            keyboardType: TextInputType.url,
            label: const Text('Backend URL'),
            hint: 'http://localhost:8080',
            onSubmit: (value) {
              ApiService.setBaseUrl(value.trim());
              showAppMessage(context, 'Server URL updated');
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Press Enter to save. The backend handles LLM routing and fallback. '
            'On an Android emulator use http://10.0.2.2:8080; on a phone use your PC\'s LAN IP.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), height: 1.4),
          ),
        ]),
      ],
    );
  }

  Widget _apiKeysSection(ThemeData theme) {
    final query = _keyQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _keys
        : _keys
            .where((k) =>
                (k['platform'] ?? '').toString().toLowerCase().contains(query) ||
                (k['label'] ?? '').toString().toLowerCase().contains(query))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          theme,
          'API Keys',
          'Bring your own provider keys — they stay private to your account',
          action: FButton(
            onPress: _showAddKeyDialog,
            prefix: const Icon(Icons.add, size: 18),
            child: const Text('Add key'),
          ),
        ),
        if (!_loading && _keys.isNotEmpty) ...[
          FTextField(
            control: FTextFieldControl.managed(controller: _keySearchCtrl),
            hint: 'Search keys by provider or label',
          ),
          const SizedBox(height: 12),
        ],
        _card(
          theme,
          [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_keys.isEmpty)
              _emptyKeys(theme)
            else if (filtered.isEmpty)
              _noMatch(theme)
            else
              for (int i = 0; i < filtered.length; i++) ...[
                if (i > 0)
                  Divider(height: 20, color: theme.colorScheme.outline.withValues(alpha: 0.12)),
                _keyTile(theme, filtered[i]),
              ],
          ],
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        const SizedBox(height: 10),
        Text(
          'Tip: Groq is the fastest free provider. Add a Tavily key to enable web search.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  Widget _noMatch(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          'No keys match "${_keyQuery.trim()}"',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  Widget _emptyKeys(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.vpn_key_outlined,
                size: 34, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text('No API keys yet',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 4),
            Text(
              'Add an LLM key (OpenRouter, Groq, NVIDIA, HuggingFace, Google)\n'
              'or a Tavily key for web search.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyTile(ThemeData theme, Map<String, dynamic> key) {
    final platform = (key['platform'] ?? '').toString();
    final maskedKey = (key['maskedKey'] ?? '****').toString();
    final label = (key['label'] ?? '').toString();
    final enabled = key['enabled'] == true;
    final statusColor = enabled ? Colors.green : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _platformIcon(platform),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(platform.toUpperCase(),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (label.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('· $label',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                    ],
                  ],
                ),
                Text(maskedKey,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontFamily: 'monospace',
                        fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(enabled ? 'Active' : 'Disabled',
                style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Remove key',
            onPressed: () async {
              try {
                await ApiService.deleteKey(key['id']);
                await _loadKeys();
              } catch (e) {
                if (!mounted) return;
                showAppMessage(
                    context,
                    'Could not remove key: '
                    '${e.toString().replaceFirst('Exception: ', '')}',
                    isError: true);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _providersSection(ThemeData theme) {
    final providers = context.watch<ChatProvider>().providers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, 'Supported Providers', 'A green check means you have an active key'),
        _card(
          theme,
          [
            for (int i = 0; i < providers.length; i++) ...[
              if (i > 0)
                Divider(height: 20, color: theme.colorScheme.outline.withValues(alpha: 0.12)),
              _providerRow(
                theme,
                (providers[i]['name'] ?? '').toString(),
                (providers[i]['description'] ?? '').toString(),
                providers[i]['active'] == true,
                (providers[i]['key_count'] ?? 0) as int,
                (providers[i]['models'] as List?)?.length ?? 0,
              ),
            ],
          ],
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ],
    );
  }

  Widget _providerRow(ThemeData theme, String name, String description,
      bool active, int keyCount, int modelCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(description,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ),
          if (modelCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$modelCount model${modelCount == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
          ],
          if (active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$keyCount key${keyCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  static const String _appVersion = '1.0.0';

  Widget _aboutSection(ThemeData theme) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, 'About', 'How Nexus AI works'),

        // ── App identity ──────────────────────────────────────────────
        _card(theme, [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nexus AI',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('One chat for 300+ free AI models',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('v$_appVersion',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),

        // ── How it works ──────────────────────────────────────────────
        _sectionLabel(theme, 'How it works'),
        _card(theme, [
          Text(
            'Nexus AI uses a fallback routing system inspired by FreeLLMAPI. When a model '
            'reaches its rate limit or is unavailable, the system automatically tries the next '
            'free model — so you always get a response.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6, color: muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.bolt, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('300+ free models · auto fallback · your keys stay private',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),

        // ── Features ──────────────────────────────────────────────────
        _sectionLabel(theme, 'Features'),
        _card(theme, [
          _featureRow(theme, Icons.alt_route, 'Smart fallback routing',
              'Automatically switches providers on rate limits or errors.'),
          _featureDivider(theme),
          _featureRow(theme, Icons.smart_toy_outlined, 'Agent orchestration',
              'Plans steps and uses tools when a task needs more than a single reply.'),
          _featureDivider(theme),
          _featureRow(theme, Icons.travel_explore, 'Live web search',
              'Add a Tavily key to let the assistant pull in fresh information.'),
          _featureDivider(theme),
          _featureRow(theme, Icons.bolt_outlined, 'Streaming responses',
              'Answers stream in token-by-token as the model generates them.'),
          _featureDivider(theme),
          _featureRow(theme, Icons.vpn_key_outlined, 'Bring your own keys',
              'Add provider keys that stay private to your account.'),
          _featureDivider(theme),
          _featureRow(theme, Icons.lock_outline, 'Private, per-account data',
              'Your conversations and keys are scoped to your login only.'),
        ]),
        const SizedBox(height: 16),

        // ── Supported providers ───────────────────────────────────────
        _sectionLabel(theme, 'Supported providers'),
        _card(theme, [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in const [
                'OpenRouter',
                'Groq',
                'NVIDIA',
                'Hugging Face',
                'Google',
                'Mistral',
                'Cerebras',
                'SambaNova',
                'Vercel',
                'Z.ai',
                'Tavily',
              ])
                _providerChip(theme, p),
            ],
          ),
        ]),
        const SizedBox(height: 20),

        // ── Footer ────────────────────────────────────────────────────
        Center(
          child: Column(
            children: [
              Text('Nexus AI · v$_appVersion',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 2),
              Text('Flutter client · FastAPI backend',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
    );
  }

  Widget _featureRow(ThemeData theme, IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureDivider(ThemeData theme) {
    return Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.12));
  }

  Widget _providerChip(ThemeData theme, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.18)),
      ),
      child: Text(name,
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
    );
  }

  Widget _platformIcon(String platform) {
    IconData icon;
    Color color;
    switch (platform) {
      case 'openrouter':
        icon = Icons.router;
        color = Colors.blue;
        break;
      case 'groq':
        icon = Icons.flash_on;
        color = Colors.orange;
        break;
      case 'nvidia':
        icon = Icons.memory;
        color = Colors.green;
        break;
      case 'huggingface':
        icon = Icons.pets;
        color = Colors.yellow;
        break;
      case 'google':
        icon = Icons.auto_awesome;
        color = Colors.lightBlue;
        break;
      case 'mistral':
        icon = Icons.air;
        color = const Color(0xFFFF7000);
        break;
      case 'cerebras':
        icon = Icons.speed;
        color = const Color(0xFFEF4444);
        break;
      case 'sambanova':
        icon = Icons.hub;
        color = const Color(0xFFA855F7);
        break;
      case 'vercel':
        icon = Icons.change_history;
        color = const Color(0xFF94A3B8);
        break;
      case 'zai':
        icon = Icons.hexagon;
        color = const Color(0xFF6366F1);
        break;
      case 'tavily':
        icon = Icons.travel_explore;
        color = Colors.teal;
        break;
      default:
        icon = Icons.api;
        color = Colors.grey;
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 17, color: color),
    );
  }

  // ─── Dialogs (unchanged behavior) ─────────────────────────────────────
  /// Fixed modal width so dialogs don't grow as you type/paste a long value.
  /// Clamped to the window so it never overflows on a narrow (phone) screen.
  double _dialogWidth(BuildContext context) {
    final available = MediaQuery.of(context).size.width - 80;
    return available < 400 ? available : 400;
  }

  void _showAddKeyDialog() {
    final providers = context.read<ChatProvider>().providers;
    // LLM providers from config, plus non-LLM keys the app supports
    // (Tavily powers the web-search tool — provided here, not in the backend).
    final options = <Map<String, String>>[
      for (final p in providers)
        {'id': p['id']?.toString() ?? '', 'name': p['name']?.toString() ?? ''},
      {'id': 'tavily', 'name': 'Tavily (Web Search)'},
    ];
    String selectedPlatform = options.first['id']!;
    final keyController = TextEditingController();
    final labelController = TextEditingController();

    bool submitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add API Key'),
          content: SizedBox(
            width: _dialogWidth(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedPlatform,
                  isExpanded: true,
                  items: options
                      .map((o) => DropdownMenuItem(
                            value: o['id'],
                            child: Text(o['name'] ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedPlatform = v!),
                  decoration: const InputDecoration(labelText: 'Provider'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    hintText: 'My key',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (keyController.text.trim().isEmpty) return;
                      final navigator = Navigator.of(dialogContext);
                      setDialogState(() => submitting = true);
                      try {
                        final res = await ApiService.addKey(
                          selectedPlatform,
                          keyController.text.trim(),
                          label: labelController.text.trim().isNotEmpty
                              ? labelController.text.trim()
                              : null,
                        );
                        navigator.pop();
                        if (mounted) {
                          final synced =
                              (res['models_synced'] as num?)?.toInt() ?? 0;
                          final err = res['sync_error']?.toString();
                          final hasErr = err != null && err.isNotEmpty;
                          final name = selectedPlatform.toUpperCase();
                          showAppMessage(
                            this.context,
                            hasErr
                                ? '$name key added, but model sync failed — try again shortly'
                                : synced > 0
                                    ? '$name added — $synced models synced'
                                    : '$name key added',
                            isError: hasErr,
                          );
                        }
                        _loadKeys();
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        if (mounted) {
                          showAppMessage(
                              this.context,
                              'Could not add key: ${e.toString().replaceFirst('Exception: ', '')}',
                              isError: true);
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool submitting = false;
    String? error;

    showAdaptiveDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => FDialog(
          title: const Text('Change password'),
          body: SizedBox(
            width: _dialogWidth(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                FTextField.password(
                  control: FTextFieldControl.managed(controller: currentCtrl),
                  label: const Text('Current password'),
                ),
                const SizedBox(height: 10),
                FTextField.password(
                  control: FTextFieldControl.managed(controller: newCtrl),
                  label: const Text('New password (min 6)'),
                ),
                const SizedBox(height: 10),
                FTextField.password(
                  control: FTextFieldControl.managed(controller: confirmCtrl),
                  label: const Text('Confirm new password'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: TextStyle(
                          color: context.theme.colors.destructive, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            FButton(
              variant: FButtonVariant.outline,
              onPress: submitting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FButton(
              onPress: submitting
                  ? null
                  : () async {
                      if (newCtrl.text.length < 6) {
                        setDialogState(() => error = 'New password must be at least 6 characters');
                        return;
                      }
                      if (newCtrl.text != confirmCtrl.text) {
                        setDialogState(() => error = 'Passwords do not match');
                        return;
                      }
                      final navigator = Navigator.of(dialogContext);
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await ApiService.changePassword(currentCtrl.text, newCtrl.text);
                        navigator.pop();
                        if (mounted) showAppMessage(this.context, 'Password updated');
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          error = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    bool submitting = false;
    showAdaptiveDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => FDialog(
          title: const Text('Delete account'),
          body: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'This permanently deletes your account, all your conversations, and your '
              'private API keys. This cannot be undone.',
            ),
          ),
          actions: [
            FButton(
              variant: FButtonVariant.outline,
              onPress: submitting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FButton(
              variant: FButtonVariant.destructive,
              onPress: submitting
                  ? null
                  : () async {
                      final settingsNavigator = Navigator.of(this.context);
                      final auth = this.context.read<AuthProvider>();
                      final chat = this.context.read<ChatProvider>();
                      setDialogState(() => submitting = true);
                      try {
                        await ApiService.deleteAccount();
                        Navigator.of(dialogContext).pop();
                        // Pushed route: close Settings. Embedded: AuthGate swaps
                        // the home when logout fires, so nothing to pop.
                        if (widget.onBack == null) settingsNavigator.pop();
                        chat.reset();
                        await auth.logout();
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        if (mounted) {
                          showAppMessage(
                              this.context,
                              'Could not delete account: '
                              '${e.toString().replaceFirst('Exception: ', '')}',
                              isError: true);
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
