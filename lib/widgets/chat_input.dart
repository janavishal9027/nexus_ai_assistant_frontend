import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'message_bubble.dart' show kContentMaxWidth;

class ChatInput extends StatefulWidget {
  final Function(String) onSend;
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

  // Per-mode accent colours (chip + menu icon).
  static const _deepColor = Color(0xFF10A37F); // teal — the app's accent
  static const _webColor = Color(0xFF3B82F6); // blue — web search

  bool get _anyMode => widget.deepResearch || widget.webSearch;

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
    if (text.isEmpty || widget.isLoading) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
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
        if (v == 'deep') widget.onToggleDeepResearch?.call();
        if (v == 'web') widget.onToggleWebSearch?.call();
        _focusNode.requestFocus();
      },
      itemBuilder: (_) => [
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
    final active = _focused || _anyMode;
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
            // Single row: [+ tools] [mode chip?] [text field] [send]
            child: Row(
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
    final enabled = widget.isLoading || _hasText;
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
              : (_hasText ? _handleSend : null),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
