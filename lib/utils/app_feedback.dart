import 'package:flutter/material.dart';

/// Shows a consistent "alert box" toast across the app: an icon + message in a
/// dark, rounded, centered floating card that auto-dismisses after 3 seconds.
///
/// Defaults to a success/info style (teal check); pass [isError] for a red
/// error icon. Replaces ad-hoc `SnackBar(content: Text(...))` calls so every
/// notification looks the same.
void showAppMessage(BuildContext context, String message, {bool isError = false}) {
  final theme = Theme.of(context);
  final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;
  final icon = isError ? Icons.error_outline_rounded : Icons.check_circle_rounded;
  final screenW = MediaQuery.of(context).size.width;
  final boxWidth = screenW < 460 ? screenW - 40 : 400.0;

  ScaffoldMessenger.of(context)
    ..clearSnackBars() // don't stack toasts
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: theme.colorScheme.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        width: boxWidth,
      ),
    );
}
