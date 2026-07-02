import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
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
                        'Add keys from OpenRouter, Groq, NVIDIA, HuggingFace, or Google',
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
                'ChatApp uses a fallback routing system inspired by FreeLLMAPI. '
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
    String selectedPlatform = providers.isNotEmpty ? providers[0]['id'] : 'openrouter';
    final keyController = TextEditingController();
    final labelController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedPlatform,
              items: providers.map((p) => DropdownMenuItem(
                value: p['id']?.toString() ?? '',
                child: Text(p['name']?.toString() ?? ''),
              )).toList(),
              onChanged: (v) => selectedPlatform = v!,
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (keyController.text.trim().isEmpty) return;
              await ApiService.addKey(
                selectedPlatform,
                keyController.text.trim(),
                label: labelController.text.trim().isNotEmpty
                    ? labelController.text.trim()
                    : null,
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              _loadKeys();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }
}
