import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/resize_handle.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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
    _loadKeys();
    _loadRailWidth();
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
          onPressed: () => Navigator.of(context).pop(),
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              for (int i = 0; i < _nav.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_nav[i].label),
                    avatar: Icon(_nav[i].icon, size: 16),
                    selected: _section == i,
                    onSelected: (_) => setState(() => _section = i),
                  ),
                ),
            ],
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
    return Container(
      width: _railWidth,
      // Distinct panel background, matching the chat conversation sidebar.
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        children: [
          for (int i = 0; i < _nav.length; i++) _navTile(theme, i),
        ],
      ),
    );
  }

  Widget _navTile(ThemeData theme, int i) {
    final selected = _section == i;
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _section = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(_nav[i].icon,
                    size: 18,
                    color: selected ? primary : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 12),
                Text(
                  _nav[i].label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? primary : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
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
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                child: Text(initial,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_reset, size: 16),
                label: const Text('Change password'),
                onPressed: _showChangePasswordDialog,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Log out'),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  context.read<ChatProvider>().reset();
                  context.read<AuthProvider>().logout();
                  navigator.pop();
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text('Delete account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                ),
                onPressed: _showDeleteAccountDialog,
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
          TextField(
            controller: _serverUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'http://localhost:8080',
              prefixIcon: Icon(Icons.link, size: 18),
            ),
            onSubmitted: (value) {
              final messenger = ScaffoldMessenger.of(context);
              ApiService.setBaseUrl(value.trim());
              messenger.showSnackBar(const SnackBar(content: Text('Server URL updated')));
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
          action: FilledButton.icon(
            onPressed: _showAddKeyDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add key'),
          ),
        ),
        if (!_loading && _keys.isNotEmpty) ...[
          TextField(
            controller: _keySearchCtrl,
            onChanged: (v) => setState(() => _keyQuery = v),
            decoration: InputDecoration(
              hintText: 'Search keys by provider or label',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              suffixIcon: _keyQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Clear',
                      onPressed: () {
                        _keySearchCtrl.clear();
                        setState(() => _keyQuery = '');
                      },
                    ),
            ),
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
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ApiService.deleteKey(key['id']);
                await _loadKeys();
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                    content: Text('Could not remove key: '
                        '${e.toString().replaceFirst('Exception: ', '')}')));
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
              ),
            ],
          ],
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ],
    );
  }

  Widget _providerRow(ThemeData theme, String name, String description, bool active, int keyCount) {
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
                      final messenger = ScaffoldMessenger.of(this.context);
                      final navigator = Navigator.of(dialogContext);
                      setDialogState(() => submitting = true);
                      try {
                        await ApiService.addKey(
                          selectedPlatform,
                          keyController.text.trim(),
                          label: labelController.text.trim().isNotEmpty
                              ? labelController.text.trim()
                              : null,
                        );
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(content: Text('${selectedPlatform.toUpperCase()} key added')),
                        );
                        _loadKeys();
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red,
                            content: Text(
                                'Could not add key: ${e.toString().replaceFirst('Exception: ', '')}'),
                          ),
                        );
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

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: SizedBox(
            width: _dialogWidth(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Current password'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password (min 6)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
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
                      if (newCtrl.text.length < 6) {
                        setDialogState(() => error = 'New password must be at least 6 characters');
                        return;
                      }
                      if (newCtrl.text != confirmCtrl.text) {
                        setDialogState(() => error = 'Passwords do not match');
                        return;
                      }
                      final messenger = ScaffoldMessenger.of(this.context);
                      final navigator = Navigator.of(dialogContext);
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await ApiService.changePassword(currentCtrl.text, newCtrl.text);
                        navigator.pop();
                        messenger
                            .showSnackBar(const SnackBar(content: Text('Password updated')));
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
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete account'),
          content: const Text(
            'This permanently deletes your account, all your conversations, and your '
            'private API keys. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: submitting
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(this.context);
                      final settingsNavigator = Navigator.of(this.context);
                      final auth = this.context.read<AuthProvider>();
                      final chat = this.context.read<ChatProvider>();
                      setDialogState(() => submitting = true);
                      try {
                        await ApiService.deleteAccount();
                        Navigator.of(dialogContext).pop();
                        settingsNavigator.pop();
                        chat.reset();
                        await auth.logout();
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        messenger.showSnackBar(SnackBar(
                          backgroundColor: Colors.red,
                          content: Text('Could not delete account: '
                              '${e.toString().replaceFirst('Exception: ', '')}'),
                        ));
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
