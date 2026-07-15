import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_feedback.dart';

/// Save exported document bytes (chat-module A.4). On desktop the user picks a
/// location (file_selector); on mobile the file is written to a temp path and
/// handed to the OS to view/share. dart:io is only touched off-web (web-safe).
Future<void> saveExport(BuildContext context, Uint8List bytes, String filename) async {
  try {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      final location = await getSaveLocation(suggestedName: filename);
      if (location == null) return; // user cancelled
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (context.mounted) showAppMessage(context, 'Saved to ${location.path}');
    } else if (!kIsWeb) {
      final path = '${Directory.systemTemp.path}/$filename';
      await File(path).writeAsBytes(bytes, flush: true);
      final opened =
          await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
      if (context.mounted) {
        showAppMessage(context, opened ? 'Exported $filename' : 'Saved: $path');
      }
    }
  } catch (e) {
    if (context.mounted) showAppMessage(context, 'Could not save: $e');
  }
}
