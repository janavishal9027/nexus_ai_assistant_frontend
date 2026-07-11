import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:provider/provider.dart';

import '../models/knowledge_base.dart';
import '../providers/kb_provider.dart';
import '../utils/app_feedback.dart';
import 'kb_chat_screen.dart';

/// File types the ingestion backend can parse (kept in sync with
/// rag_chunking.SUPPORTED_EXTS on the server).
const _kAllowedExtensions = <String>[
  'pdf', 'docx', 'txt', 'md', 'markdown', 'rst', 'csv', 'tsv', 'json',
  'log', 'yaml', 'yml', 'xml', 'html', 'htm', 'py', 'js', 'ts', 'java',
  'c', 'cpp', 'go', 'rs', 'rb', 'php', 'sh', 'sql', 'dart', 'kt', 'swift',
];

/// Knowledge Base manager: a list of KBs, and — when one is opened — its
/// documents with live ingestion progress and an entry point to grounded chat.
class KnowledgeBaseScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const KnowledgeBaseScreen({super.key, this.onBack});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final kb = context.read<KbProvider>();
      kb.clearSelection();
      kb.loadKnowledgeBases();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kb = context.watch<KbProvider>();
    final inDetail = kb.selected != null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme, kb, inDetail),
            Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.2)),
            Expanded(
              child: inDetail ? _DetailView(kb: kb.selected!) : _listView(theme, kb),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, KbProvider kb, bool inDetail) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: 'Back',
            onPressed: () {
              if (inDetail) {
                kb.clearSelection();
              } else {
                widget.onBack?.call();
              }
            },
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              inDetail ? kb.selected!.name : 'Knowledge Bases',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (!inDetail)
            FilledButton.icon(
              onPressed: () => _createKbDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
            ),
        ],
      ),
    );
  }

  Widget _listView(ThemeData theme, KbProvider kb) {
    if (kb.loading && kb.knowledgeBases.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (kb.knowledgeBases.isEmpty) {
      return _emptyState(theme);
    }
    return RefreshIndicator(
      onRefresh: kb.loadKnowledgeBases,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: kb.knowledgeBases.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _kbCard(theme, kb, kb.knowledgeBases[i]),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_special_outlined, size: 56,
                color: theme.colorScheme.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text('No knowledge bases yet',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Create a knowledge base, upload documents (PDF, DOCX, text, code), '
              'and chat with grounded, cited answers.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _createKbDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create knowledge base'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kbCard(ThemeData theme, KbProvider kb, KnowledgeBase item) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => kb.selectKnowledgeBase(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.folder_special_outlined,
                    color: theme.colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if ((item.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.description!,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${item.documentCount} document${item.documentCount == 1 ? '' : 's'} · '
                      '${item.chunkCount} chunk${item.chunkCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'rename') _createKbDialog(context, existing: item);
                  if (v == 'delete') _deleteKbDialog(context, kb, item);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createKbDialog(BuildContext context, {KnowledgeBase? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final isEdit = existing != null;
    final kb = context.read<KbProvider>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Rename knowledge base' : 'New knowledge base'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isEdit ? 'Save' : 'Create')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      if (isEdit) {
        await kb.renameKnowledgeBase(existing.id,
            name: name, description: descCtrl.text.trim());
      } else {
        final created = await kb.createKnowledgeBase(name, description: descCtrl.text.trim());
        await kb.selectKnowledgeBase(created);
      }
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Failed: $e');
    }
  }

  Future<void> _deleteKbDialog(BuildContext context, KbProvider kb, KnowledgeBase item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete knowledge base?'),
        content: Text('"${item.name}" and all its documents, chunks and grounded '
            'chats will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await kb.deleteKnowledgeBase(item.id);
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Failed to delete: $e');
    }
  }
}

/// The documents view for one open KB.
class _DetailView extends StatelessWidget {
  final KnowledgeBase kb;
  const _DetailView({required this.kb});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<KbProvider>();
    final docs = prov.documents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openChat(context),
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  label: const Text('Chat with this KB'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _upload(context),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload'),
              ),
            ],
          ),
        ),
        if (kb.embeddingLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(children: [
              Icon(Icons.memory, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('Embeddings: ${kb.embeddingLabel}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        Expanded(
          child: prov.documentsLoading && docs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : docs.isEmpty
                  ? _emptyDocs(context, theme)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _DocTile(doc: docs[i]),
                    ),
        ),
      ],
    );
  }

  Widget _emptyDocs(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 48,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text('No documents yet',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Upload a PDF, DOCX, text or code file to index it for grounded chat.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _upload(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload document'),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => KbChatScreen(kb: kb)),
    );
  }

  Future<void> _upload(BuildContext context) async {
    final prov = context.read<KbProvider>();
    XFile? file;
    try {
      // Desktop honours the extension filter; Android rejects extension-only
      // groups, so fall back to an unrestricted picker there (the backend
      // validates the file type regardless).
      try {
        file = await openFile(acceptedTypeGroups: const [
          XTypeGroup(label: 'Documents', extensions: _kAllowedExtensions),
        ]);
      } catch (_) {
        file = await openFile();
      }
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'File picker error: $e');
      return;
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      if (context.mounted) showAppMessage(context, 'Could not read file');
      return;
    }
    try {
      await prov.uploadDocument(file.name, bytes);
      if (context.mounted) showAppMessage(context, '${file.name} uploaded — indexing…');
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Upload failed: $e');
    }
  }
}

class _DocTile extends StatelessWidget {
  final KbDocument doc;
  const _DocTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<KbProvider>();
    final job = prov.jobFor(doc.id);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _statusIcon(theme),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.filename,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                _subtitle(theme, job),
                if (doc.isBusy) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (job?.progress ?? 0) > 0 ? (job!.progress / 100.0) : null,
                      minHeight: 5,
                      backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.15),
                    ),
                  ),
                ],
                if (doc.isFailed && (doc.error ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(doc.error!,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.red.shade300)),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'reingest') {
                try {
                  await prov.reingestDocument(doc.id);
                } catch (e) {
                  if (context.mounted) showAppMessage(context, 'Failed: $e');
                }
              } else if (v == 'delete') {
                try {
                  await prov.deleteDocument(doc.id);
                } catch (e) {
                  if (context.mounted) showAppMessage(context, 'Failed: $e');
                }
              }
            },
            itemBuilder: (_) => [
              if (doc.isFailed || doc.isDone)
                const PopupMenuItem(value: 'reingest', child: Text('Re-index')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(ThemeData theme) {
    if (doc.isBusy) {
      return SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: theme.colorScheme.primary),
      );
    }
    if (doc.isFailed) {
      return Icon(Icons.error_outline, color: Colors.red.shade400, size: 22);
    }
    return Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 22);
  }

  Widget _subtitle(ThemeData theme, IngestionJob? job) {
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (doc.isBusy) {
      final stage = job?.stage ?? 'Queued';
      final chunks = (job?.totalChunks ?? 0) > 0
          ? ' · ${job!.embeddedChunks}/${job.totalChunks} chunks'
          : '';
      return Text('$stage$chunks', style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    if (doc.isFailed) {
      return Text('Failed to index', style: style);
    }
    final size = doc.sizeBytes != null ? '${_fmtSize(doc.sizeBytes!)} · ' : '';
    return Text('$size${doc.chunkCount} chunk${doc.chunkCount == 1 ? '' : 's'} indexed', style: style);
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
