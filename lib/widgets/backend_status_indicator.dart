import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/backend_status.dart';
import '../providers/backend_status_provider.dart';

/// Header backend-status chip (chat-module A.6). A compact coloured dot when
/// online; a clearly-labelled pill when there's a problem. Tap to re-check.
class BackendStatusIndicator extends StatelessWidget {
  const BackendStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prov = context.watch<BackendStatusProvider>();
    final status = prov.status;
    // Stay quiet when healthy; speak up (label) when something's wrong.
    final showLabel = status.isProblem || status == BackendStatus.unknown;

    return Tooltip(
      message: prov.detail ?? status.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.read<BackendStatusProvider>().recheck(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 10 : 7, vertical: 5),
          decoration: BoxDecoration(
            color: status.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: status.color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
              ),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Text(status.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: status.color, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
