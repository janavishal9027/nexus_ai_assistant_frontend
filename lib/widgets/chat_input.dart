import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_attachment.dart';
import '../utils/app_feedback.dart';
import 'message_bubble.dart' show kContentMaxWidth;

class ChatInput extends StatefulWidget {
  final void Function(String text, List<ChatAttachment> attachments) onSend;
  final bool isLoading;
  final VoidCallback? onStop;
  final bool deepResearch;
  final VoidCallback? onToggleDeepResearch;
  final bool webSearch;
  final VoidCallback? onToggleWebSearch;
  // When true the composer is locked (no provider API key yet) and tapping it
  // guides the user to add one.
  final bool locked;
  final VoidCallback? onLockedTap;

  const ChatInput({
    super.key,
    required this.onSend,
    required this.isLoading,
    this.onStop,
    this.deepResearch = false,
    this.onToggleDeepResearch,
    this.webSearch = false,
    this.onToggleWebSearch,
    this.locked = false,
    this.onLockedTap,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _focused = false;

  // Files staged for the next message (images + documents).
  final List<ChatAttachment> _attachments = [];
  static const _maxAttachments = 8;
  static const _maxBytesEach = 20 * 1024 * 1024; // 20 MB

  // Per-mode accent colours (chip + menu icon).
  static const _deepColor = Color(0xFF10A37F); // teal — the app's accent
  static const _webColor = Color(0xFF3B82F6); // blue — web search

  bool get _anyMode => widget.deepResearch || widget.webSearch;

  // Camera capture is only meaningful on mobile.
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get _canSend => _hasText || _attachments.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Handle Enter on the field's own focus node so we can consume the event
    // (return handled) and stop the TextField from also inserting a newline.
    _focusNode.onKeyEvent = _handleKeyEvent;
    // Light up the input frame while it holds focus.
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _handleSend();
      return KeyEventResult.handled; // consume: no trailing newline
    }
    return KeyEventResult.ignored; // Shift+Enter etc. → default newline
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) || widget.isLoading) return;
    widget.onSend(text, List.of(_attachments));
    _controller.clear();
    setState(() => _attachments.clear());
    _focusNode.requestFocus();
  }

  Future<void> _addAttachment(XFile? file) async {
    if (file == null) return;
    if (_attachments.length >= _maxAttachments) {
      if (mounted) showAppMessage(context, 'You can attach up to $_maxAttachments files');
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxBytesEach) {
      if (mounted) showAppMessage(context, '${file.name} is too large (max 20 MB)');
      return;
    }
    setState(() {
      _attachments.add(ChatAttachment(
        name: file.name,
        mimeType: file.mimeType,
        bytes: bytes,
      ));
    });
    _focusNode.requestFocus();
  }

  /// Attach any file (all platforms).
  Future<void> _pickFile() async {
    try {
      final file = await openFile();
      await _addAttachment(file);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not pick file: $e');
    }
  }

  /// Attach a photo from the gallery. Uses image_picker on mobile/web and the
  /// file dialog (image filter) on desktop.
  Future<void> _pickPhoto() async {
    try {
      if (_isMobile || kIsWeb) {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery);
        await _addAttachment(x);
      } else {
        const group = XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
        );
        XFile? file;
        try {
          file = await openFile(acceptedTypeGroups: const [group]);
        } catch (_) {
          file = await openFile();
        }
        await _addAttachment(file);
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not pick photo: $e');
    }
  }

  /// Capture a photo with the camera (mobile only).
  Future<void> _takePhoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera);
      await _addAttachment(x);
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not open camera: $e');
    }
  }

  /// The "+" tools menu: pick Deep research or Web search. Selecting a tool
  /// activates it (mutually exclusive) and refocuses the field so the user can
  /// keep typing. The active tool shows a check.
  Widget _plusMenu() {
    final colors = context.theme.colors;
    return PopupMenuButton<String>(
      tooltip: 'Tools',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.over,
      color: colors.background,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border),
      ),
      onSelected: (v) {
        switch (v) {
          case 'deep':
            widget.onToggleDeepResearch?.call();
            _focusNode.requestFocus();
            break;
          case 'web':
            widget.onToggleWebSearch?.call();
            _focusNode.requestFocus();
            break;
          case 'file':
            _pickFile();
            break;
          case 'photo':
            _pickPhoto();
            break;
          case 'camera':
            _takePhoto();
            break;
        }
      },
      itemBuilder: (_) => [
        // On mobile the camera leads the menu (above Attach file).
        if (_isMobile)
          _actionItem('camera', Icons.photo_camera_outlined, 'Camera'),
        _actionItem('file', Icons.attach_file_rounded, 'Attach file'),
        _actionItem('photo', Icons.image_outlined, 'Photo'),
        _toolItem('deep', Icons.travel_explore, 'Deep research',
            widget.deepResearch, _deepColor),
        _toolItem('web', Icons.public, 'Web search', widget.webSearch,
            _webColor),
      ],
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _anyMode
              ? colors.primary.withValues(alpha: 0.14)
              : colors.foreground.withValues(alpha: 0.06),
        ),
        child: Icon(Icons.add_rounded,
            size: 22,
            color: _anyMode ? colors.primary : colors.mutedForeground),
      ),
    );
  }

  PopupMenuItem<String> _toolItem(
      String value, IconData icon, String label, bool active, Color accent) {
    final colors = context.theme.colors;
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                color: colors.foreground,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              )),
          const Spacer(),
          if (active) Icon(Icons.check_rounded, size: 16, color: accent),
        ],
      ),
    );
  }

  /// A non-toggle action row in the "+" menu (attach file / photo / camera).
  PopupMenuItem<String> _actionItem(String value, IconData icon, String label) {
    final colors = context.theme.colors;
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.mutedForeground),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: colors.foreground, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// Horizontal strip of staged attachments shown above the input row. Images
  /// render as thumbnails; other files as labelled chips. Each has a ✕ to remove.
  Widget _attachmentStrip() {
    final theme = Theme.of(context);
    final colors = context.theme.colors;
    return Container(
      height: 66,
      margin: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = _attachments[i];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: a.isImage ? 58 : 150,
                height: 58,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: a.isImage
                    ? Image.memory(a.bytes, fit: BoxFit.cover)
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined,
                                size: 20, color: colors.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(a.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall),
                            ),
                          ],
                        ),
                      ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _attachments.removeAt(i)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The active-mode chip shown at the start of the field (icon + label + a
  /// small ✕ to turn the mode off), styled in the mode's accent colour.
  Widget _modeChip() {
    final isDeep = widget.deepResearch;
    final accent = isDeep ? _deepColor : _webColor;
    final icon = isDeep ? Icons.travel_explore : Icons.public;
    final label = isDeep ? 'Deep research' : 'Web search';
    final clear =
        isDeep ? widget.onToggleDeepResearch : widget.onToggleWebSearch;

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              )),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: clear,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close_rounded,
                  size: 14, color: accent.withValues(alpha: 0.85)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    // The frame reacts to focus (typing) and to any mode being on.
    final active = _focused || _anyMode || _attachments.isNotEmpty;
    final baseFill = theme.inputDecorationTheme.fillColor ??
        (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F3));

    if (widget.locked) return _lockedBar(theme, primary, baseFill);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: baseFill,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                // Subtle teal frame at rest (matches the locked bar), a
                // stronger teal when focused or a mode is on.
                color: active
                    ? primary.withValues(alpha: 0.75)
                    : primary.withValues(alpha: 0.45),
                width: active ? 1.5 : 1.2,
              ),
              boxShadow: [
                // Soft lift off the message list, plus a gentle primary glow
                // when focused or a mode is on.
                BoxShadow(
                  color: active
                      ? primary.withValues(alpha: 0.16)
                      : Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                  blurRadius: active ? 20 : 14,
                  spreadRadius: active ? 1 : 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_attachments.isNotEmpty) _attachmentStrip(),
                // Single row: [+ tools] [mode chip?] [text field] [send]
                Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _plusMenu(),
                const SizedBox(width: 4),
                if (_anyMode) ...[
                  _modeChip(),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                      cursorColor: primary,
                      decoration: InputDecoration(
                        hintText: widget.deepResearch
                            ? 'Ask for an in-depth, well-sourced answer…'
                            : widget.webSearch
                                ? 'Search the web and answer…'
                                : 'Message Nexus AI…',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        // No fill → Material paints no hover/focus highlight box
                        // over the field when you click or hover it.
                        filled: false,
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _sendButton(theme),
              ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Replaces the composer when there are no provider keys: a tappable bar
  /// that guides the user to Settings → API Keys.
  Widget _lockedBar(ThemeData theme, Color primary, Color baseFill) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onLockedTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: baseFill,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: primary.withValues(alpha: 0.45), width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 20, color: primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add a provider API key in Settings to start chatting',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'Add Key',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Circular send button that becomes a Stop control while generating and
  /// dims when there's nothing to send.
  Widget _sendButton(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final enabled = widget.isLoading || _canSend;
    return AnimatedScale(
      scale: enabled ? 1.0 : 0.9,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: enabled ? primary : primary.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(19),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: IconButton(
          // While generating, this becomes a Stop button that cancels the
          // in-flight request (works even before the first token).
          icon: Icon(
            widget.isLoading ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            size: 20,
            color: theme.colorScheme.onPrimary,
          ),
          tooltip: widget.isLoading ? 'Stop' : 'Send',
          onPressed: widget.isLoading
              ? widget.onStop
              : (_canSend ? _handleSend : null),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
