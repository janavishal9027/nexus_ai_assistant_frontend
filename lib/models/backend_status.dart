import 'package:flutter/material.dart';

/// Live backend health (chat-module A.6). Distinguishes a truly-down server from
/// one that's merely restarting or running-but-degraded.
enum BackendStatus { unknown, online, degraded, restarting, unreachable }

extension BackendStatusUi on BackendStatus {
  String get label => switch (this) {
        BackendStatus.online => 'Online',
        BackendStatus.degraded => 'Degraded',
        BackendStatus.restarting => 'Restarting',
        BackendStatus.unreachable => 'Offline',
        BackendStatus.unknown => 'Checking…',
      };

  Color get color => switch (this) {
        BackendStatus.online => const Color(0xFF10A37F),   // teal
        BackendStatus.degraded => const Color(0xFFF59E0B), // amber
        BackendStatus.restarting => const Color(0xFFF59E0B),
        BackendStatus.unreachable => const Color(0xFFEF4444), // red
        BackendStatus.unknown => const Color(0xFF9CA3AF),  // grey
      };

  bool get isProblem =>
      this == BackendStatus.degraded ||
      this == BackendStatus.restarting ||
      this == BackendStatus.unreachable;
}
