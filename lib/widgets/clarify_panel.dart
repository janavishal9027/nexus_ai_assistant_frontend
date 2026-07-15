import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/clarify.dart';
import '../providers/chat_provider.dart';
import 'message_bubble.dart' show kContentMaxWidth;

/// Docked AskUserQuestion panel (chat-module A.2). While it's shown it REPLACES
/// the chat composer: pick an option (single = radio, multi = checkboxes) and/or
/// type your own answer, then send with the inline "→". "Skip" answers the
/// original message anyway.
///
/// Reliability/UX: guards against double-submit, gives keyboard support
/// (Esc = skip, Enter = send) on desktop, haptic feedback on mobile, a smooth
/// entrance, and copes with questions that ship no preset options.
class ClarifyPanel extends StatefulWidget {
  final ClarifyQuestion question;

  /// Hard height cap, measured by the parent's LayoutBuilder from the REAL
  /// available space (body height already reduced by the keyboard). We can't
  /// derive this from MediaQuery inside a Scaffold body: resizeToAvoidBottomInset
  /// shrinks the body but zeroes viewInsets.bottom for descendants, so a
  /// MediaQuery-based cap would size against the full screen and overflow.
  final double maxHeight;

  const ClarifyPanel(
      {super.key, required this.question, this.maxHeight = 480});

  @override
  State<ClarifyPanel> createState() => _ClarifyPanelState();
}

class _ClarifyPanelState extends State<ClarifyPanel> {
  final Set<int> _selected = {};
  final _otherCtrl = TextEditingController();
  final _fieldFocus = FocusNode();
  // Once we've handed an answer to the provider, lock the panel so a second tap
  // (or Enter + arrow together) can't fire a duplicate turn before the panel is
  // torn down and replaced by the composer.
  bool _submitting = false;

  @override
  void dispose() {
    _otherCtrl.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      (_selected.isNotEmpty || _otherCtrl.text.trim().isNotEmpty);

  void _send(String answer) {
    if (_submitting || answer.trim().isEmpty) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    context.read<ChatProvider>().submitClarification(answer.trim());
  }

  /// Send the typed answer if present, otherwise the selected option(s).
  void _doSubmit() {
    if (_submitting) return;
    final other = _otherCtrl.text.trim();
    if (other.isNotEmpty) {
      _send(other);
      return;
    }
    if (_selected.isEmpty) return;
    final labels =
        _selected.map((i) => widget.question.options[i].label).toList();
    _send(labels.join(', '));
  }

  void _skip() {
    if (_submitting) return;
    setState(() => _submitting = true);
    context.read<ChatProvider>().dismissClarification();
  }

  void _onTapOption(int index, bool multi) {
    if (_submitting) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (multi) {
        _selected.contains(index)
            ? _selected.remove(index)
            : _selected.add(index);
      } else {
        _selected
          ..clear()
          ..add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final q = widget.question;
    final hasOptions = q.options.isNotEmpty;
    // Cap to the real height the parent measured, and scroll the body — so it
    // never overflows the keyboard and always leaves the messages region above
    // it room to shrink into. A low floor is safe: the options scroll inside.
    final maxPanelHeight = widget.maxHeight.clamp(140.0, 560.0);

    // Desktop keyboard support: Esc dismisses, Enter sends. The text field
    // consumes Enter itself when focused (via onSubmitted), so these only fire
    // when focus is elsewhere — and _submitting guards any overlap.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _skip,
        const SingleActivator(LogicalKeyboardKey.enter): _doSubmit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _doSubmit,
      },
      child: Focus(
        autofocus: true,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
                offset: Offset(0, (1 - t) * 10), child: child),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: kContentMaxWidth, maxHeight: maxPanelHeight),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: primary.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(theme, primary, q),
                    const SizedBox(height: 8),
                    // ── Scrollable: question + guidance + options ───────────
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(q.question,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600, height: 1.3)),
                            if (hasOptions) ...[
                              const SizedBox(height: 4),
                              Text(
                                q.multiSelect
                                    ? 'Select all that apply — or type your own'
                                    : 'Choose one — or type your own',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 12),
                              ...List.generate(q.options.length,
                                  (i) => _optionCard(theme, q.options[i], i)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // ── Type-your-own field + inline "→" (fixed at bottom) ──
                    const SizedBox(height: 10),
                    _otherField(theme, autofocus: !hasOptions),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, Color primary, ClarifyQuestion q) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.help_outline_rounded, size: 13, color: primary),
            const SizedBox(width: 4),
            Text(q.header.toUpperCase(),
                style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.4)),
          ]),
        ),
        const Spacer(),
        // Skip = answer the original message without clarifying.
        Tooltip(
          message: 'Answer without clarifying',
          child: TextButton(
            onPressed: _submitting ? null : _skip,
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Skip'),
          ),
        ),
      ],
    );
  }

  Widget _optionCard(ThemeData theme, ClarifyOption o, int index) {
    final primary = theme.colorScheme.primary;
    final multi = widget.question.multiSelect;
    final selected = _selected.contains(index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _onTapOption(index, multi),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.12)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? primary
                    : theme.colorScheme.outline.withValues(alpha: 0.25),
                width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                    multi
                        ? (selected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank)
                        : (selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                    size: 18,
                    color:
                        selected ? primary : theme.colorScheme.onSurfaceVariant),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.label,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if ((o.description ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(o.description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _otherField(ThemeData theme, {bool autofocus = false}) {
    final primary = theme.colorScheme.primary;
    final enabled = _canSubmit;
    return TextField(
      controller: _otherCtrl,
      focusNode: _fieldFocus,
      autofocus: autofocus,
      enabled: !_submitting,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _doSubmit(),
      textInputAction: TextInputAction.send,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: widget.question.options.isEmpty
            ? 'Type your answer…'
            : 'Or type your own answer…',
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        // Inline "→" send button — sends the typed text, or the selected
        // option(s) if the field is empty. Compact; spins while submitting.
        suffixIconConstraints:
            const BoxConstraints(minWidth: 36, minHeight: 36),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Tooltip(
            message: 'Send',
            child: Material(
              color: enabled ? primary : primary.withValues(alpha: 0.25),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? _doSubmit : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _submitting
                      ? SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary),
                        )
                      : Icon(Icons.arrow_forward_rounded,
                          size: 15, color: theme.colorScheme.onPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
