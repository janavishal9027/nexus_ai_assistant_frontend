import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/exporter.dart';
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
  int? _testingKeyId;   // key currently being probed against its provider
  int _section = 0;
  String _keyQuery = '';
  // Memory & Privacy section (Part D).
  Map<String, dynamic>? _memory;
  bool _memoryLoading = false;
  // The user's memory switches; defaults all-on until the summary loads.
  Map<String, bool> _memPrefs = const {
    'recall_enabled': true,
    'record_enabled': true,
    'reflect_enabled': true,
    'graph_enabled': true,
  };
  // Personal memory graph (Part D Phase 5) — loaded lazily when expanded.
  List<Map> _memGraphEdges = const [];
  bool _memGraphLoading = false;
  bool _memGraphLoaded = false;

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

  // NB: these indices are referenced positionally elsewhere — the "Add key" FAB
  // below and chat_screen.dart's no-keys onboarding both hard-code 2 (API Keys).
  // Append new sections; don't insert.
  final _nav = <({IconData icon, String label})>[
    (icon: Icons.account_circle_outlined, label: 'Account'),
    (icon: Icons.dns_outlined, label: 'Server'),
    (icon: Icons.key_outlined, label: 'API Keys'),
    (icon: Icons.hub_outlined, label: 'Providers'),
    (icon: Icons.psychology_outlined, label: 'Memory'),
    (icon: Icons.palette_outlined, label: 'Personalization'),
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

  /// Probe a key against its provider now, rather than making the user infer
  /// its health from a chat that quietly fell back to another provider.
  Future<void> _testKey(int keyId) async {
    setState(() => _testingKeyId = keyId);
    final res = await ApiService.testKey(keyId);
    if (!mounted) return;
    setState(() => _testingKeyId = null);
    await _loadKeys();
    if (!mounted) return;
    final ok = res['ok'] == true;
    final err = (res['error'] ?? '').toString();
    showAppMessage(
      context,
      ok ? 'Key works' : (err.isEmpty ? 'Key check failed' : err),
      isError: !ok,
    );
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
      // Mobile: a bottom "Add key" FAB on the API Keys section (index 2), so it
      // never overlaps the header text.
      floatingActionButton: (!isWide && _section == 2)
          ? FloatingActionButton(
              onPressed: _showAddKeyDialog,
              tooltip: 'Add key',
              shape: const CircleBorder(),
              child: const Icon(Icons.add),
            )
          : null,
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
      case 4:
        return _memorySection(theme);
      case 5:
        return _personalizationSection(theme);
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
          // On wide layouts the button sits in the header; on mobile it moves to
          // a bottom FAB (avoids overlapping the description text).
          action: MediaQuery.of(context).size.width >= 720
              ? FButton(
                  onPress: _showAddKeyDialog,
                  prefix: const Icon(Icons.add, size: 18),
                  child: const Text('Add key'),
                )
              : null,
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
        // Clearance so the mobile "Add key" FAB never covers the last item.
        if (MediaQuery.of(context).size.width < 720) const SizedBox(height: 72),
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

  /// Turn a provider's raw error into something a person can act on. The full
  /// text is still shown as a tooltip.
  static (String, String) _explainKeyError(String status, String? raw) {
    final e = (raw ?? '').toLowerCase();
    if (e.contains('more credits') ||
        e.contains('402') ||
        e.contains('insufficient credit') ||
        e.contains('out of credit')) {
      return ('Out of credits', 'Top up this provider to use its models.');
    }
    if (e.contains('insufficient balance')) {
      return ('No balance', 'This provider account has no balance left.');
    }
    if (e.contains('credit card') || e.contains('customer_verification')) {
      return ('Card required', 'This provider needs a card on file.');
    }
    if (e.contains('reported as leaked')) {
      return ('Key leaked', 'This key was flagged as public. Replace it.');
    }
    if (e.contains('401') ||
        e.contains('invalid api key') ||
        e.contains('unauthorized') ||
        e.contains('authentication')) {
      return ('Invalid key', 'The provider rejected this key.');
    }
    if (e.contains('permission') || e.contains('403')) {
      return ('No permission', 'This key lacks access to these models.');
    }
    if (status == 'limited') {
      return ('Rate limited', 'Quota reached — it should recover on its own.');
    }
    if (status == 'healthy') return ('Healthy', 'Last call succeeded.');
    if (status == 'unknown') return ('Untested', 'Not used yet — hit Test.');
    return ('Error', raw ?? 'Unknown problem.');
  }

  Widget _keyTile(ThemeData theme, Map<String, dynamic> key) {
    final platform = (key['platform'] ?? '').toString();
    final maskedKey = (key['maskedKey'] ?? '****').toString();
    final label = (key['label'] ?? '').toString();
    final enabled = key['enabled'] == true;
    final status = (key['status'] ?? 'unknown').toString();
    final rawError = key['lastError'] as String?;
    final (badge, detail) = _explainKeyError(status, rawError);
    // Health, not just on/off: a key can be enabled and still be out of credits,
    // which is exactly the case the old "Active" badge hid.
    final Color statusColor = !enabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
        : switch (status) {
            'healthy' => const Color(0xFF10A37F),
            'limited' => Colors.orange,
            'error' => Colors.red,
            _ => theme.colorScheme.onSurface.withValues(alpha: 0.5),
          };
    final testing = _testingKeyId == key['id'];

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
                // Why it's unhealthy — the whole point of the exercise.
                if (enabled && (status == 'error' || status == 'limited'))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detail,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: statusColor, fontSize: 11)),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: rawError ?? detail,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(enabled ? badge : 'Disabled',
                  style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
            ),
          ),
          IconButton(
            icon: testing
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering, size: 18),
            tooltip: 'Test this key',
            onPressed: testing ? null : () => _testKey(key['id']),
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

  // ── Memory & Privacy (Part D) ─────────────────────────────────────────────
  Widget _memorySection(ThemeData theme) {
    if (_memory == null && !_memoryLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMemory());
    }
    final counts = (_memory?['counts'] as Map?) ?? const {};
    final skills = ((_memory?['skills'] as List?) ?? const []).cast<Map>();
    final graphCount = (counts['graph'] as int?) ?? 0;
    // A Column, NOT a ListView: both layouts already wrap _sectionBody in a
    // SingleChildScrollView, and a vertical viewport inside one gets unbounded
    // height and renders nothing. Every other section returns a Column too.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, 'Memory & Privacy', 'What Nexus AI remembers about you'),
        const SizedBox(height: 10),
        if (_memoryLoading) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 6),
        Row(children: [
          _memStat(theme, '${counts['episodic'] ?? 0}', 'memories'),
          _memStat(theme, '${counts['skills'] ?? 0}', 'skills'),
          _memStat(theme, '${counts['feedback'] ?? 0}', 'feedback'),
          _memStat(theme, '$graphCount', 'connections'),
          _memStat(theme, '${counts['knowledge'] ?? 0}', 'facts'),
        ]),
        const SizedBox(height: 18),

        // ── Controls: the user's actual privacy levers ─────────────────────
        _sectionLabel(theme, 'What Nexus AI may do'),
        _memSwitch(
          theme,
          key: 'record_enabled',
          title: 'Remember my chats',
          subtitle: 'Save exchanges so they can be recalled in later chats. '
              'Off means nothing new is learned or stored.',
        ),
        _memSwitch(
          theme,
          key: 'recall_enabled',
          title: 'Use memory in replies',
          subtitle: 'Bring what it knows about you into the prompt. Off means '
              'each chat starts fresh — what is stored is kept, just not used.',
        ),
        _memSwitch(
          theme,
          key: 'reflect_enabled',
          title: 'Learn skills about me',
          subtitle: 'Distil your chats and 👍/👎 into durable preferences.',
          // Reflection reads the stored log, so it can't run without recording.
          dependsOn: 'record_enabled',
        ),
        _memSwitch(
          theme,
          key: 'graph_enabled',
          title: 'Build my personal graph',
          subtitle: 'Track the people, orgs and tools you mention, and how they '
              'connect.',
          dependsOn: 'record_enabled',
        ),
        const SizedBox(height: 18),

        if (skills.isNotEmpty) ...[
          _sectionLabel(theme, 'What I know about you'),
          ...skills.take(12).map((s) => _skillTile(theme, s)),
          const SizedBox(height: 18),
        ],

        // ── Personal memory graph (Part D Phase 5) ─────────────────────────
        if (graphCount > 0) ...[
          _sectionLabel(theme, 'People, orgs & tools'),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text('$graphCount connection${graphCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodyMedium),
              subtitle: Text('How the people, orgs and tools you mention relate',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              onExpansionChanged: (open) {
                if (open && !_memGraphLoaded) _loadMemoryGraph();
              },
              children: [
                if (_memGraphLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                else if (_memGraphEdges.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nothing to show yet.',
                        style: theme.textTheme.bodySmall),
                  )
                else
                  ..._memGraphEdges.take(50).map((e) => _memEdgeTile(theme, e)),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _exportMemory,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Export my memory'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _clearMemory,
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              label: const Text('Clear my memory', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.4))),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          'Nexus AI keeps durable, per-account memory to personalize help — recent '
          'exchanges, skills it distils about you, and the people/orgs/tools you '
          'mention. Recall is scoped to your account; you can turn any of it off, '
          'or export or clear it anytime. Raw exchanges are dropped after a year; '
          'what you clear is gone immediately.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }

  /// One memory switch. [dependsOn] greys the row out when its parent switch is
  /// off, so the UI can't imply a layer runs when its input isn't being written.
  Widget _memSwitch(ThemeData theme, {
    required String key,
    required String title,
    required String subtitle,
    String? dependsOn,
  }) {
    final blocked = dependsOn != null && !(_memPrefs[dependsOn] ?? true);
    final on = (_memPrefs[key] ?? true) && !blocked;
    return Opacity(
      opacity: blocked ? 0.5 : 1,
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: on,
        onChanged: blocked ? null : (v) => _setMemPref(key, v),
        title: Text(title, style: theme.textTheme.bodyMedium),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
      ),
    );
  }

  Widget _memEdgeTile(ThemeData theme, Map e) {
    // /api/memory/graph emits `support` (the export uses `support_count`).
    final support = (e['support'] as int?) ?? 1;
    final id = e['id'] as int?;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: (e['source'] ?? '').toString(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            TextSpan(text: '  ${(e['relation'] ?? '').toString()}  ',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            TextSpan(text: (e['target'] ?? '').toString(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ])),
        ),
        if (support > 1)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('×$support',
                style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          ),
        // Forget just this fact — the graph can be wrong about you, and the
        // alternative shouldn't be wiping all of it.
        if (id != null)
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            color: muted,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            tooltip: 'Forget this',
            onPressed: () => _forgetEdge(id),
          ),
      ]),
    );
  }

  Future<void> _forgetEdge(int edgeId) async {
    final previous = _memGraphEdges;
    // Optimistic: drop it now, restore if the server disagrees.
    setState(() => _memGraphEdges =
        _memGraphEdges.where((e) => e['id'] != edgeId).toList());
    final ok = await ApiService.deleteMemoryEdge(edgeId);
    if (!mounted) return;
    if (!ok) {
      setState(() => _memGraphEdges = previous);
      showAppMessage(context, 'Could not forget that', isError: true);
      return;
    }
    _loadMemory();   // refresh the connections count
  }

  Widget _memStat(ThemeData theme, String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(value, style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold)),
          Text(label, style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _skillTile(ThemeData theme, Map s) {
    final kind = (s['kind'] ?? 'note').toString();
    final content = (s['content'] ?? '').toString();
    final c = (s['polarity']?.toString() == 'negative')
        ? Colors.orange
        : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 2, right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6)),
          child: Text(kind, style: TextStyle(
              fontSize: 10, color: c, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(content, style: theme.textTheme.bodyMedium)),
      ]),
    );
  }

  Future<void> _loadMemory() async {
    setState(() => _memoryLoading = true);
    final m = await ApiService.getMemorySummary();
    if (!mounted) return;
    setState(() {
      _memory = m;
      _memoryLoading = false;
      final p = m['prefs'];
      if (p is Map) {
        _memPrefs = p.map((k, v) => MapEntry(k.toString(), v == true));
      }
    });
  }

  Future<void> _loadMemoryGraph() async {
    setState(() => _memGraphLoading = true);
    final g = await ApiService.getMemoryGraph();
    if (!mounted) return;
    setState(() {
      _memGraphEdges = ((g['edges'] as List?) ?? const []).cast<Map>();
      _memGraphLoading = false;
      _memGraphLoaded = true;
    });
  }

  /// Flip a memory switch optimistically, reverting if the save fails — a
  /// switch that silently lies about a privacy setting is worse than an error.
  Future<void> _setMemPref(String key, bool value) async {
    final previous = Map<String, bool>.from(_memPrefs);
    setState(() => _memPrefs = {..._memPrefs, key: value});
    final saved = await ApiService.setMemoryPrefs({key: value});
    if (!mounted) return;
    if (saved == null) {
      setState(() => _memPrefs = previous);
      showAppMessage(context, 'Could not save that setting', isError: true);
      return;
    }
    setState(() => _memPrefs = saved);
  }

  Future<void> _exportMemory() async {
    final data = await ApiService.exportMemory();
    if (!mounted) return;
    if (data == null) {
      showAppMessage(context, 'Export failed', isError: true);
      return;
    }
    final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
    await saveExport(context, bytes, 'nexus-memory.json');
  }

  /// What each purge scope actually deletes. Kept in step with the backend's
  /// data_lifecycle.SCOPES — the copy must name every layer a scope removes.
  static const List<({String scope, String label, String detail})> _memScopes = [
    (
      scope: 'all',
      label: 'Everything',
      detail: 'Memories, skills, feedback, your personal graph, and the facts '
          'learned from your chats and projects.',
    ),
    (
      scope: 'episodic',
      label: 'Memories only',
      detail: 'The stored record of past exchanges. Skills already distilled '
          'from them are kept.',
    ),
    (
      scope: 'skills',
      label: 'Skills only',
      detail: 'The preferences and lessons learned about you.',
    ),
    (
      scope: 'feedback',
      label: 'Feedback only',
      detail: 'Your 👍/👎 ratings on replies.',
    ),
    (
      scope: 'graph',
      label: 'Personal graph only',
      detail: 'The people, orgs and tools you mention, and how they connect.',
    ),
    (
      scope: 'knowledge',
      label: 'Learned facts only',
      detail: 'Facts pulled from the content of your chats and projects.',
    ),
  ];

  Future<void> _clearMemory() async {
    var selected = 'all';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Clear memory'),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) => setDialogState(() => selected = v ?? 'all'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose what to delete. This cannot be undone.'),
                const SizedBox(height: 8),
                ..._memScopes.map((s) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: s.scope,
                      title: Text(s.label),
                      subtitle: Text(s.detail,
                          style: Theme.of(ctx).textTheme.bodySmall),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final done = await ApiService.purgeMemory(scope: selected);
    if (!mounted) return;
    if (done) {
      showAppMessage(context, selected == 'all' ? 'Memory cleared' : 'Cleared');
      setState(() {
        _memGraphEdges = const [];
        _memGraphLoaded = false;
      });
      _loadMemory();
    } else {
      showAppMessage(context, 'Failed to clear memory', isError: true);
    }
  }

  // ── Personalization ───────────────────────────────────────────────────────
  Widget _personalizationSection(ThemeData theme) {
    final s = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(theme, 'Personalization', 'Make the chat yours'),
        const SizedBox(height: 6),

        // Live preview — change a slider and watch the real thing move, rather
        // than guessing and backing out to the chat to check.
        _PersonalizationPreview(settings: s),
        const SizedBox(height: 20),

        _sectionLabel(theme, 'Theme'),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system,
                label: Text('System'), icon: Icon(Icons.brightness_auto, size: 16)),
            ButtonSegment(value: ThemeMode.light,
                label: Text('Light'), icon: Icon(Icons.light_mode_outlined, size: 16)),
            ButtonSegment(value: ThemeMode.dark,
                label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined, size: 16)),
          ],
          selected: {s.themeMode},
          showSelectedIcon: false,
          onSelectionChanged: (v) => s.setThemeMode(v.first),
        ),
        const SizedBox(height: 18),

        _sectionLabel(theme, 'Accent colour'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in SettingsProvider.accentChoices)
              _AccentDot(
                color: c,
                selected: c.toARGB32() == s.accent.toARGB32(),
                onTap: () => s.setAccent(c),
              ),
          ],
        ),
        const SizedBox(height: 18),

        _slider(
          theme,
          label: 'Message text size',
          value: s.textSize,
          min: SettingsProvider.minTextSize,
          max: SettingsProvider.maxTextSize,
          onChanged: s.previewTextSize,
          onEnd: (_) => s.commitPreview(),
        ),
        _slider(
          theme,
          label: 'Message corners',
          value: s.cornerRadius,
          min: SettingsProvider.minRadius,
          max: SettingsProvider.maxRadius,
          onChanged: s.previewCornerRadius,
          onEnd: (_) => s.commitPreview(),
        ),
        const SizedBox(height: 6),

        _sectionLabel(theme, 'Chat density'),
        SegmentedButton<ChatDensity>(
          segments: const [
            ButtonSegment(value: ChatDensity.comfortable, label: Text('Comfortable')),
            ButtonSegment(value: ChatDensity.compact, label: Text('Compact')),
          ],
          selected: {s.density},
          showSelectedIcon: false,
          onSelectionChanged: (v) => s.setDensity(v.first),
        ),
        const SizedBox(height: 18),

        _sectionLabel(theme, 'Colour theme'),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Sets the chat wallpaper and a matching bubble colour. Pick an '
            'accent above afterwards to override it.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final w in Wallpaper.values)
              if (w != Wallpaper.custom)
                _WallpaperSwatch(
                  wallpaper: w,
                  selected: s.wallpaper == w,
                  onTap: () => s.setWallpaper(w),
                ),
            _WallpaperSwatch(
              wallpaper: Wallpaper.custom,
              selected: s.wallpaper == Wallpaper.custom,
              imagePath: s.wallpaperPath,
              onTap: _pickWallpaper,
            ),
          ],
        ),
        const SizedBox(height: 18),

        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.reduceAnimations,
          onChanged: s.setReduceAnimations,
          title: Text('Reduce animations', style: theme.textTheme.bodyMedium),
          subtitle: Text(
              'Turn off motion effects like the typing indicator and smooth '
              'scrolling.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        ),
        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: () async {
            await context.read<SettingsProvider>().resetToDefaults();
            if (mounted) showAppMessage(context, 'Reset to defaults');
          },
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Reset to defaults'),
        ),
        const SizedBox(height: 12),
        Text(
          'These settings follow your account, so your phone and desktop match. '
          'A custom wallpaper image stays on this device only.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }

  Widget _slider(ThemeData theme, {
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text('${value.round()}',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min).round(),
          onChanged: onChanged,
          onChangeEnd: onEnd,
        ),
      ],
    );
  }

  /// Pick an image for the chat background. It's copied into the app's own
  /// directory: the picker hands back a cache/temp path the OS is free to
  /// delete, which would leave the wallpaper silently blank later.
  Future<void> _pickWallpaper() async {
    final s = context.read<SettingsProvider>();
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
      if (picked == null) return;
      final dir = await getApplicationSupportDirectory();
      final dest = File('${dir.path}/chat_wallpaper${p.extension(picked.path)}');
      await File(picked.path).copy(dest.path);
      await s.setWallpaper(Wallpaper.custom, path: dest.path);
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, 'Could not set that image', isError: true);
    }
  }

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

  (IconData, Color) _platformIconInfo(String platform) {
    switch (platform) {
      case 'openrouter':
        return (Icons.router, Colors.blue);
      case 'groq':
        return (Icons.flash_on, Colors.orange);
      case 'nvidia':
        return (Icons.memory, Colors.green);
      case 'huggingface':
        return (Icons.pets, Colors.yellow);
      case 'google':
        return (Icons.auto_awesome, Colors.lightBlue);
      case 'mistral':
        return (Icons.air, const Color(0xFFFF7000));
      case 'cerebras':
        return (Icons.speed, const Color(0xFFEF4444));
      case 'sambanova':
        return (Icons.hub, const Color(0xFFA855F7));
      case 'vercel':
        return (Icons.change_history, const Color(0xFF94A3B8));
      case 'zai':
        return (Icons.hexagon, const Color(0xFF6366F1));
      case 'tavily':
        return (Icons.travel_explore, Colors.teal);
      default:
        return (Icons.api, Colors.grey);
    }
  }

  Widget _platformAvatar(String platform, {double size = 34}) {
    final (icon, color) = _platformIconInfo(platform);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }

  Widget _platformIcon(String platform) => _platformAvatar(platform);

  // ─── Dialogs (unchanged behavior) ─────────────────────────────────────
  /// Fixed modal width so dialogs don't grow as you type/paste a long value.
  /// Clamped to the window so it never overflows on a narrow (phone) screen.
  double _dialogWidth(BuildContext context) {
    final available = MediaQuery.of(context).size.width - 80;
    return available < 400 ? available : 400;
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

  void _showAddKeyDialog() {
    final providers = context.read<ChatProvider>().providers;
    // LLM providers from config, plus non-LLM keys the app supports
    // (Tavily powers the web-search tool — provided here, not in the backend).
    final options = <Map<String, String>>[
      for (final p in providers)
        {
          'id': p['id']?.toString() ?? '',
          'name': p['name']?.toString() ?? '',
          'desc': p['description']?.toString() ?? '',
        },
      {
        'id': 'tavily',
        'name': 'Tavily (Web Search)',
        'desc': 'Powers Web Search & Deep Research',
      },
    ];
    // Providers the user already holds a key for → show an "added" check.
    final addedPlatforms = _keys
        .map((k) => (k['platform'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();
    String? selectedPlatform;
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
                  menuMaxHeight: 380,
                  itemHeight: 56,
                  borderRadius: BorderRadius.circular(14),
                  hint: Text('Select provider',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4))),
                  // Compact display once picked: just avatar + name.
                  selectedItemBuilder: (context) => [
                    for (final o in options)
                      Row(children: [
                        _platformAvatar(o['id']!, size: 26),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(o['name'] ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge),
                        ),
                      ]),
                  ],
                  items: [
                    for (final o in options)
                      DropdownMenuItem(
                        value: o['id'],
                        child: Row(children: [
                          _platformAvatar(o['id']!, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(o['name'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                if ((o['desc'] ?? '').isNotEmpty)
                                  Text(o['desc']!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant)),
                              ],
                            ),
                          ),
                          if (addedPlatforms.contains(o['id'])) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_circle,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary),
                          ],
                        ]),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => selectedPlatform = v),
                  decoration: _fieldDecoration(context, 'Provider'),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: keyController,
                  decoration: _fieldDecoration(context, 'API Key', hint: 'sk-…'),
                  obscureText: true,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: labelController,
                  decoration:
                      _fieldDecoration(context, 'Label (optional)', hint: 'My key'),
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
                      if (selectedPlatform == null ||
                          keyController.text.trim().isEmpty) {
                        showAppMessage(this.context,
                            'Pick a provider and paste your key first',
                            isError: true);
                        return;
                      }
                      final navigator = Navigator.of(dialogContext);
                      setDialogState(() => submitting = true);
                      try {
                        final res = await ApiService.addKey(
                          selectedPlatform!,
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
                          final name = selectedPlatform!.toUpperCase();
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

/// A miniature chat, so the sliders can be judged against the real thing
/// instead of a number. Mirrors MessageBubble's geometry (radius + tail, text
/// size, density gap) — if that widget's shape changes, change this too.
class _PersonalizationPreview extends StatelessWidget {
  const _PersonalizationPreview({required this.settings});

  final SettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final r = settings.cornerRadius;
    final tail = r < 4 ? r : 4.0;
    final gradient = SettingsProvider.gradientFor(settings.wallpaper, isDark);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12 - settings.messageGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Assistant
          Padding(
            padding: EdgeInsets.symmetric(vertical: settings.messageGap),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(r),
                    topRight: Radius.circular(r),
                    bottomLeft: Radius.circular(tail),
                    bottomRight: Radius.circular(r),
                  ),
                  border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'Here’s how your messages will look.',
                  style: TextStyle(
                    fontSize: settings.textSize,
                    height: 1.6,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          // User
          Padding(
            padding: EdgeInsets.symmetric(vertical: settings.messageGap),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: settings.accent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(r),
                    topRight: Radius.circular(r),
                    bottomLeft: Radius.circular(r),
                    bottomRight: Radius.circular(tail),
                  ),
                ),
                child: Text(
                  'Looks good \u{1F44B}',
                  style: TextStyle(
                    color: Colors.white,
                    height: 1.5,
                    fontSize: settings.textSize,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            // Ring the selection in the page's own foreground rather than the
            // swatch colour, so it reads on every hue.
            color: selected
                ? theme.colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}

class _WallpaperSwatch extends StatelessWidget {
  const _WallpaperSwatch({
    required this.wallpaper,
    required this.selected,
    required this.onTap,
    this.imagePath,
  });

  final Wallpaper wallpaper;
  final bool selected;
  final VoidCallback onTap;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradient = SettingsProvider.gradientFor(wallpaper, isDark);
    final isCustom = wallpaper == Wallpaper.custom;
    final hasImage = (imagePath ?? '').isNotEmpty && File(imagePath!).existsSync();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 52,
            height: 66,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              gradient: gradient,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.5),
                width: selected ? 2 : 1,
              ),
            ),
            child: isCustom && hasImage
                ? Image.file(File(imagePath!), fit: BoxFit.cover)
                : isCustom
                    ? Icon(Icons.add_photo_alternate_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))
                    // Two mini bubbles in the theme's paired accent, so the
                    // background AND the bubble colour you're choosing are both
                    // visible before you tap — the pairing is the whole point.
                    : _MiniBubbles(accent: SettingsProvider.accentFor(wallpaper)),
          ),
        ),
        const SizedBox(height: 4),
        Text(SettingsProvider.labelFor(wallpaper),
            style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6))),
      ],
    );
  }
}

/// The bubble pair drawn inside a colour-theme swatch: an incoming bubble in
/// the surface colour and an outgoing one in that theme's accent — a tiny
/// version of what the chat will actually look like.
class _MiniBubbles extends StatelessWidget {
  const _MiniBubbles({required this.accent});

  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 9,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  width: 0.5),
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 24,
              height: 9,
              decoration: BoxDecoration(
                color: accent ?? theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
