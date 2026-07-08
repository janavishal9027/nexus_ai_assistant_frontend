import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'message_bubble.dart' show kContentMaxWidth;

class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final bool isLoading;
  final VoidCallback? onStop;
  final bool deepResearch;
  final VoidCallback? onToggleDeepResearch;

  const ChatInput({
    super.key,
    required this.onSend,
    required this.isLoading,
    this.onStop,
    this.deepResearch = false,
    this.onToggleDeepResearch,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _focused = false;

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

  /// A pill toggle that enables Deep Research mode (large 400B+ models + live
  /// web research). Highlighted when active.
  Widget _deepResearchToggle(ThemeData theme) {
    final active = widget.deepResearch;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    return Tooltip(
      message: active
          ? 'Deep Research on — uses large (400B+) models with live web research'
          : 'Deep Research — thorough, cited answers from large (400B+) models',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onToggleDeepResearch,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: active ? primary.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? primary.withValues(alpha: 0.6)
                    : onSurface.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.travel_explore,
                    size: 16,
                    color: active ? primary : onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text(
                  'Deep Research',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: active ? primary : onSurface.withValues(alpha: 0.7),
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    // The frame reacts to focus (typing) and to Deep Research being on.
    final active = _focused || widget.deepResearch;
    final baseFill = theme.inputDecorationTheme.fillColor ??
        (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F3));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: baseFill,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: active
                    ? primary.withValues(alpha: 0.75)
                    : theme.colorScheme.outline.withValues(alpha: 0.35),
                width: active ? 1.5 : 1,
              ),
              boxShadow: [
                // Soft lift off the message list, plus a gentle primary glow
                // when focused or in Deep Research mode.
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Text field
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    cursorColor: primary,
                    decoration: InputDecoration(
                      hintText: widget.deepResearch
                          ? 'Ask for an in-depth, well-sourced answer…'
                          : 'Message Nexus AI…',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                      fillColor: Colors.transparent,
                      filled: true,
                    ),
                  ),
                ),
                // Toolbar: Deep Research toggle (left) + Send/Stop (right)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 8, 8),
                  child: Row(
                    children: [
                      _deepResearchToggle(theme),
                      const Spacer(),
                      _sendButton(theme),
                    ],
                  ),
                ),
              ],
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
            size: widget.isLoading ? 20 : 20,
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
