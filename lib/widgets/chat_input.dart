import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'message_bubble.dart' show kContentMaxWidth;

class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final bool isLoading;

  const ChatInput({super.key, required this.onSend, required this.isLoading});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    // Handle Enter on the field's own focus node so we can consume the event
    // (return handled) and stop the TextField from also inserting a newline.
    _focusNode.onKeyEvent = _handleKeyEvent;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: Container(
            decoration: BoxDecoration(
          color: theme.inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Text field
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  style: theme.textTheme.bodyMedium,
                  decoration: const InputDecoration(
                    hintText: 'Message ChatApp...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    fillColor: Colors.transparent,
                    filled: true,
                  ),
                ),
              ),
            ),
            // Send button
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _hasText && !widget.isLoading
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: IconButton(
                  icon: widget.isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: theme.colorScheme.onPrimary,
                        ),
                  onPressed: _hasText && !widget.isLoading ? _handleSend : null,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }
}
