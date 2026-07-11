import 'dart:io' show Platform, Process;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../utils/app_feedback.dart';
import 'settings_screen.dart';

/// A step-by-step guide to getting an API key from each supported provider and
/// adding it to Nexus AI. Reached from the sidebar (above Profile) and useful on
/// a fresh install with no keys yet.
class GuideScreen extends StatelessWidget {
  final VoidCallback? onBack;
  const GuideScreen({super.key, this.onBack});

  static Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    try {
      if (Platform.isWindows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else {
        // Android / iOS: dart:io Process isn't available in the mobile sandbox,
        // so hand the URL to the OS (opens the browser / provider key page).
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {/* best-effort */}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providers = context.watch<ChatProvider>().providers;

    // LLM providers from the backend config (each carries its real key-page
    // URL), plus Tavily which powers Web Search / Deep Research.
    final entries = <_ProviderGuide>[
      for (final p in providers)
        _ProviderGuide(
          name: (p['name'] ?? '').toString(),
          description: (p['description'] ?? '').toString(),
          keyUrl: (p['key_url'] ?? '').toString(),
        ),
      const _ProviderGuide(
        name: 'Tavily (Web Search)',
        description: 'Powers Web Search and Deep Research web results',
        keyUrl: 'https://app.tavily.com',
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    tooltip: 'Back',
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 2),
                  Text('Add an API Key',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Divider(
                height: 1,
                color: theme.colorScheme.outline.withValues(alpha: 0.2)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _intro(theme),
                        const SizedBox(height: 16),
                        _quickSteps(theme),
                        const SizedBox(height: 22),
                        _sectionLabel(theme, 'PROVIDERS'),
                        const SizedBox(height: 8),
                        for (final e in entries)
                          _providerCard(context, theme, e),
                        const SizedBox(height: 20),
                        Center(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(
                                      initialSection: 2)),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add API Key'),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro(ThemeData theme) {
    return Text(
      'Nexus AI routes your messages across LLM providers, so it needs at least '
      'one provider API key. Most have a free tier — Groq is a fast, free place '
      'to start. Pick any provider below and follow its steps.',
      style: theme.textTheme.bodyMedium?.copyWith(
        height: 1.5,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _quickSteps(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The short version',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _step(theme, 1,
              'Get a key from any provider below (open its site and create one).'),
          _step(theme, 2,
              'Come back here and open Settings → API Keys → Add API Key.'),
          _step(theme, 3,
              'Choose the provider, paste your key, and Save. The chat unlocks instantly.'),
        ],
      ),
    );
  }

  Widget _providerCard(BuildContext context, ThemeData theme, _ProviderGuide e) {
    final initial = e.name.isNotEmpty ? e.name[0].toUpperCase() : '?';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Theme(
        // Hide ExpansionTile's default divider lines.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(initial,
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          title: Text(e.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: e.description.isEmpty
              ? null
              : Text(e.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _step(theme, 1,
                'Open ${e.keyUrl.isEmpty ? "the provider's website" : e.keyUrl} and sign in (create a free account if you don\'t have one).'),
            _step(theme, 2,
                'Open the API keys page, create a new key/token, and copy it.'),
            _step(theme, 3,
                'Back in Nexus AI: Settings → API Keys → Add API Key → choose "${e.name}" → paste the key → Save.'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (e.keyUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _openUrl(e.keyUrl),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Get key'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      side: BorderSide(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.4)),
                    ),
                  ),
                if (e.keyUrl.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: e.keyUrl));
                      showAppMessage(context, 'Link copied');
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy link'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(ThemeData theme, int n, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8))),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Text(text,
        style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)));
  }
}

class _ProviderGuide {
  final String name;
  final String description;
  final String keyUrl;
  const _ProviderGuide(
      {required this.name, required this.description, required this.keyUrl});
}
