import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>> _keys = [];
  bool _loading = true;
  final _serverUrlController = TextEditingController(text: ApiService.baseUrl);

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() => _loading = true);
    try {
      _keys = await ApiService.getKeys();
      // Reload config to get updated active status
      final chatProvider = context.read<ChatProvider>();
      await chatProvider.loadConfig();
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account
          _buildSection(
            theme,
            title: 'Account',
            icon: Icons.account_circle_outlined,
            children: [
              Builder(builder: (context) {
                final acct = context.watch<AuthProvider>().account;
                return Row(
                  children: [
                    Icon(Icons.person_outline, size: 18,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(acct?.displayName ?? 'Account',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          if (acct?.email != null)
                            Text(acct!.email,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
            ],
          ),
          const SizedBox(height: 24),
          // Server URL
          _buildSection(
            theme,
            title: 'Server Connection',
            icon: Icons.dns_outlined,
            children: [
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'http://localhost:8080',
                ),
                onSubmitted: (value) {
                  ApiService.setBaseUrl(value.trim());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Server URL updated')),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Press Enter to save. The backend handles LLM routing and fallback.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // API Keys
          _buildSection(
            theme,
            title: 'API Keys',
            icon: Icons.key_outlined,
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddKeyDialog,
              tooltip: 'Add API Key',
            ),
            children: [
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_keys.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.vpn_key_outlined,
                        size: 32,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No API keys configured',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add LLM keys (OpenRouter, Groq, NVIDIA, HuggingFace, Google) '
                        'or a Tavily key for web search',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ..._keys.map((key) => _buildKeyTile(theme, key)),
            ],
          ),
          const SizedBox(height: 24),
          // Supported Providers (dynamic from config)
          _buildSection(
            theme,
            title: 'Supported Providers',
            icon: Icons.hub_outlined,
            children: [
              ...context.watch<ChatProvider>().providers.map((p) => _providerInfo(
                theme,
                p['name'] ?? '',
                p['description'] ?? '',
                p['active'] == true,
                p['key_count'] ?? 0,
              )),
            ],
          ),
          const SizedBox(height: 24),
          // About
          _buildSection(
            theme,
            title: 'About',
            icon: Icons.info_outline,
            children: [
              Text(
                'Nexus AI uses a fallback routing system inspired by FreeLLMAPI. '
                'When a model reaches its rate limit, the system automatically '
                'tries the next available free model — ensuring you always get a response.',
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(ThemeData theme, {
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyTile(ThemeData theme, Map<String, dynamic> key) {
    final platform = key['platform'] ?? '';
    final maskedKey = key['maskedKey'] ?? '****';
    final enabled = key['enabled'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _platformIcon(platform),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform.toUpperCase(),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  maskedKey,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: enabled ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              enabled ? 'Active' : 'Disabled',
              style: TextStyle(
                fontSize: 10,
                color: enabled ? Colors.green : Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            onPressed: () async {
              await ApiService.deleteKey(key['id']);
              _loadKeys();
            },
          ),
        ],
      ),
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
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Widget _providerInfo(ThemeData theme, String name, String description, bool active, int keyCount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: active ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$keyCount key${keyCount > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedPlatform,
                items: options.map((o) => DropdownMenuItem(
                  value: o['id'],
                  child: Text(o['name'] ?? ''),
                )).toList(),
                // Rebuild the dialog so the picked provider is actually shown.
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
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (keyController.text.trim().isEmpty) return;
                      // Capture before the await so we don't use a BuildContext
                      // across the async gap.
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
                          SnackBar(
                            content: Text(
                                '${selectedPlatform.toUpperCase()} key added'),
                          ),
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
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
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
          content: Column(
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
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
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
                        messenger.showSnackBar(const SnackBar(content: Text('Password updated')));
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          error = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                        Navigator.of(dialogContext).pop();   // close dialog
                        settingsNavigator.pop();             // close settings → back to gate
                        chat.reset();
                        await auth.logout();                 // gate shows the auth screen
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
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }
}
