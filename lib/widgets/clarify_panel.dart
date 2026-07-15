import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/clarify.dart';
import '../providers/chat_provider.dart';
import 'message_bubble.dart' show kContentMaxWidth;

/// Docked AskUserQuestion panel (chat-module A.2). A request can be ambiguous in
/// several ways, so the clarifier may ask more than one question — they're shown
/// ONE AT A TIME (paginated) with Back / Next, and Send on the last. For each,
/// pick an option (single = radio, multi = checkboxes) and/or type your own.
/// "Skip" answers the original message anyway.
///
/// While it's shown it REPLACES the composer. It guards against double-submit,
/// supports Esc = skip on desktop, animates in, and scrolls within the height
/// the parent measured so it never overflows the keyboard.
class ClarifyPanel extends StatefulWidget {
  final List<ClarifyQuestion> questions;

  /// Hard height cap, measured by the parent from the REAL available space.
  final double maxHeight;

  const ClarifyPanel({super.key, required this.questions, this.maxHeight = 480});

  @override
  State<ClarifyPanel> createState() => _ClarifyPanelState();
}

class _ClarifyPanelState extends State<ClarifyPanel> {
  // Per-question selected option indices + per-question free-text answer.
  final Map<int, Set<int>> _selected = {};
  final Map<int, TextEditingController> _other = {};
  // The question currently on screen (paginated).
  int _page = 0;
  // Once we've handed the answers to the provider, lock the panel so a second
  // tap can't fire a duplicate turn before it's torn down.
  bool _submitting = false;

  int get _count => widget.questions.length;
  bool get _isLast => _page >= _count - 1;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _count; i++) {
      _selected[i] = {};
      _other[i] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _other.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The answer for question [qi]: typed text if present, else selected label(s).
  String _answerFor(int qi) {
    final typed = _other[qi]?.text.trim() ?? '';
    if (typed.isNotEmpty) return typed;
    final sel = _selected[qi] ?? const <int>{};
    if (sel.isEmpty) return '';
    return sel.map((i) => widget.questions[qi].options[i].label).join(', ');
  }

  bool get _anyAnswered =>
      List.generate(_count, _answerFor).any((a) => a.isNotEmpty);

  void _next() {
    if (_submitting) return;
    if (_isLast) {
      _submit();
    } else {
      setState(() => _page++);
    }
  }

  void _back() {
    if (_submitting || _page == 0) return;
    setState(() => _page--);
  }

  void _submit() {
    if (_submitting || !_anyAnswered) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    context
        .read<ChatProvider>()
        .submitClarifications(List.generate(_count, _answerFor));
  }

  void _skip() {
    if (_submitting) return;
    setState(() => _submitting = true);
    context.read<ChatProvider>().dismissClarification();
  }

  void _tapOption(int qi, int oi, bool multi) {
    if (_submitting) return;
    HapticFeedback.selectionClick();
    setState(() {
      final sel = _selected[qi]!;
      if (multi) {
        sel.contains(oi) ? sel.remove(oi) : sel.add(oi);
      } else {
        sel
          ..clear()
          ..add(oi);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final maxPanelHeight = widget.maxHeight.clamp(140.0, 560.0);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _skip},
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
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(theme, primary),
                    if (_count > 1) ...[
                      const SizedBox(height: 8),
                      _progress(theme, primary),
                    ],
                    const SizedBox(height: 10),
                    // Only the current question — keyed so its field/animation
                    // resets cleanly when the page changes.
                    Flexible(
                      child: SingleChildScrollView(
                        key: ValueKey(_page),
                        child: _questionBlock(theme, primary, _page),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _navRow(theme, primary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, Color primary) {
    final multi = _count > 1;
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
            Text(multi ? 'A FEW QUICK QUESTIONS' : 'QUICK QUESTION',
                style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.4)),
          ]),
        ),
        if (multi) ...[
          const SizedBox(width: 8),
          Text('${_page + 1} of $_count',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const Spacer(),
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

  /// A thin progress bar of segments — one per question, filled up to the
  /// current page (green = answered, lighter = current/pending).
  Widget _progress(ThemeData theme, Color primary) {
    return Row(
      children: [
        for (var i = 0; i < _count; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == _count - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: _answerFor(i).isNotEmpty
                    ? primary
                    : (i == _page
                        ? primary.withValues(alpha: 0.5)
                        : theme.colorScheme.outline.withValues(alpha: 0.25)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _questionBlock(ThemeData theme, Color primary, int qi) {
    final q = widget.questions[qi];
    final hasOptions = q.options.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(q.question,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
        if (hasOptions) ...[
          const SizedBox(height: 4),
          Text(
            q.multiSelect
                ? 'Select all that apply — or type your own'
                : 'Choose one — or type your own',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          ...List.generate(
              q.options.length, (oi) => _optionCard(theme, primary, qi, oi)),
        ],
        const SizedBox(height: 6),
        _otherField(theme, primary, qi, autofocus: !hasOptions),
      ],
    );
  }

  Widget _optionCard(ThemeData theme, Color primary, int qi, int oi) {
    final o = widget.questions[qi].options[oi];
    final multi = widget.questions[qi].multiSelect;
    final selected = _selected[qi]?.contains(oi) ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _tapOption(qi, oi, multi),
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

  Widget _otherField(ThemeData theme, Color primary, int qi,
      {bool autofocus = false}) {
    final hasOptions = widget.questions[qi].options.isNotEmpty;
    return TextField(
      controller: _other[qi],
      autofocus: autofocus,
      enabled: !_submitting,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _next(),
      textInputAction:
          _isLast ? TextInputAction.done : TextInputAction.next,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hasOptions ? 'Or type your own…' : 'Type your answer…',
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _navRow(ThemeData theme, Color primary) {
    return Row(
      children: [
        if (_page > 0)
          TextButton.icon(
            onPressed: _submitting ? null : _back,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant),
          ),
        const Spacer(),
        if (!_isLast)
          FilledButton.icon(
            onPressed: _submitting ? null : _next,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Next'),
            style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: theme.colorScheme.onPrimary),
          )
        else
          FilledButton.icon(
            onPressed: _anyAnswered && !_submitting ? _submit : null,
            icon: _submitting
                ? SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: theme.colorScheme.onPrimary))
                : const Icon(Icons.check_rounded, size: 16),
            label: const Text('Send'),
            style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: theme.colorScheme.onPrimary),
          ),
      ],
    );
  }
}
