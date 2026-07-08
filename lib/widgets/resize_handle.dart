import 'package:flutter/material.dart';

/// A thin, draggable vertical divider used to resize an adjacent panel.
///
/// It reports horizontal drag deltas (in logical pixels) via [onDrag] so the
/// parent can adjust a panel width, and calls [onDragEnd] when the drag
/// finishes (a good place to persist the new width). Shows a left-right resize
/// cursor on hover and highlights while hovered or dragging.
class ResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  const ResizeHandle({super.key, required this.onDrag, this.onDragEnd});

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _hovering || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        // Wide-ish hit target with a slim visible line in the middle.
        child: SizedBox(
          width: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 2 : 1,
              color: active
                  ? theme.colorScheme.primary.withValues(alpha: 0.7)
                  : theme.colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
        ),
      ),
    );
  }
}
