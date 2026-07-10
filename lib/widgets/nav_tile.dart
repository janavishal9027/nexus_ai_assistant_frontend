import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// A clean, borderless navigation pill: icon + label (+ optional subtitle /
/// trailing), with a subtle hover highlight and a teal-tinted selected state.
/// Uses Forui colors so it matches the rest of the app, and a plain
/// GestureDetector/MouseRegion so it works anywhere (no Material ancestor
/// needed) — unlike Forui's bordered `FItem`.
class NavTile extends StatefulWidget {
  final IconData? icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;

  const NavTile({
    super.key,
    this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.selected = false,
    required this.onTap,
    this.dense = false,
  });

  @override
  State<NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final selected = widget.selected;
    final fg = selected ? colors.primary : colors.foreground;
    final bg = selected
        ? colors.primary.withValues(alpha: 0.14)
        : (_hover ? colors.foreground.withValues(alpha: 0.06) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.dense ? 9 : 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 19, color: fg),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.body.sm.copyWith(
                        color: fg,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.body.xs.copyWith(color: colors.mutedForeground),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
