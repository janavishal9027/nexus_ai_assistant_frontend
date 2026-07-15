import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart' hide XFile;
import 'package:share_plus/share_plus.dart';

import '../utils/app_feedback.dart';

/// Save exported document bytes (chat-module A.4). On desktop the user picks a
/// location + name in the OS Save As dialog. On Android / iOS (no Save As) we
/// first let the user edit the file name, then hand the file to the system share
/// / save sheet (Save to Files, Drive, or send to an app) via share_plus — a raw
/// file:// URI is blocked on Android (FileUriExposedException), so share_plus
/// wraps it in a FileProvider URI. dart:io is only touched off-web (web-safe).
Future<void> saveExport(BuildContext context, Uint8List bytes, String filename) async {
  try {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      // Save As lets the user edit the name + choose the folder. Advertise the
      // format so the dialog shows a "Save as type", and re-append the extension
      // if the user edits the name and drops it — otherwise the file saves with
      // no extension (Windows shows it as a plain "File", not e.g. a PDF).
      final ext = filename.contains('.')
          ? filename.substring(filename.lastIndexOf('.'))
          : '';
      final groups = ext.length > 1
          ? [
              XTypeGroup(
                  label: ext.substring(1).toUpperCase(),
                  extensions: [ext.substring(1)])
            ]
          : const <XTypeGroup>[];
      final location = await getSaveLocation(
          suggestedName: filename, acceptedTypeGroups: groups);
      if (location == null) return; // user cancelled
      var savePath = location.path;
      if (ext.isNotEmpty && !savePath.toLowerCase().endsWith(ext.toLowerCase())) {
        savePath = '$savePath$ext';
      }
      await File(savePath).writeAsBytes(bytes, flush: true);
      if (context.mounted) showAppMessage(context, 'Saved to $savePath');
    } else if (!kIsWeb) {
      // Let the user rename before saving (mobile has no Save As dialog).
      final chosen = await _promptFilename(context, filename);
      if (chosen == null) return; // cancelled
      if (!context.mounted) return;
      // Anchor rect for the iPad share popover (harmless elsewhere).
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box != null ? box.localToGlobal(Offset.zero) & box.size : null;
      final path = '${Directory.systemTemp.path}/$chosen';
      await File(path).writeAsBytes(bytes, flush: true);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(path, name: chosen)],
        sharePositionOrigin: origin,
      ));
      if (context.mounted && result.status == ShareResultStatus.success) {
        showAppMessage(context, 'Saved $chosen');
      }
    }
  } catch (e) {
    if (context.mounted) showAppMessage(context, 'Could not save: $e');
  }
}

/// Ask the user to name the file before saving (mobile). Returns "name.ext" or
/// null if cancelled. The extension is preserved so the format stays valid.
Future<String?> _promptFilename(BuildContext context, String suggested) async {
  final dot = suggested.lastIndexOf('.');
  final ext = dot > 0 ? suggested.substring(dot) : '';
  final base = dot > 0 ? suggested.substring(0, dot) : suggested;
  final ctrl = TextEditingController(text: base);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Save as'),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                  labelText: 'File name', border: OutlineInputBorder()),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ),
          if (ext.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(ext,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save')),
      ],
    ),
  );
  if (ok != true) return null;
  var name = ctrl.text.trim();
  if (name.isEmpty) name = base;
  // Strip path separators / characters that are illegal in file names.
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return '$name$ext';
}
