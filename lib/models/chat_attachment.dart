import 'dart:convert';
import 'package:flutter/foundation.dart';

/// A file the user attaches to a chat turn (image or document). Held in memory
/// as raw bytes and base64-encoded when sent to the backend.
class ChatAttachment {
  final String name;
  final String? mimeType;
  final Uint8List bytes;

  ChatAttachment({required this.name, this.mimeType, required this.bytes});

  static const _imageExts = [
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.heif',
  ];

  bool get isImage {
    if ((mimeType ?? '').toLowerCase().startsWith('image/')) return true;
    final n = name.toLowerCase();
    return _imageExts.any(n.endsWith);
  }

  int get sizeBytes => bytes.length;

  Map<String, dynamic> toJson() => {
        'filename': name,
        if (mimeType != null) 'mime_type': mimeType,
        'data': base64Encode(bytes),
      };
}
