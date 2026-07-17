import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Device connectivity chip (shown on every platform, in the top bar): a green
/// dot + "Online" when connected to Wi-Fi / mobile data / ethernet, a red dot +
/// "Offline" when there's no connection. Reacts live to network changes.
class ConnectivityIndicator extends StatefulWidget {
  const ConnectivityIndicator({super.key});

  @override
  State<ConnectivityIndicator> createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends State<ConnectivityIndicator> {
  static const _green = Color(0xFF10A37F); // app accent
  static const _red = Color(0xFFEF4444);

  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _apply(await Connectivity().checkConnectivity());
      _sub = Connectivity().onConnectivityChanged.listen(_apply);
    } catch (_) {
      // Plugin unavailable (e.g. some desktop/test contexts) — assume online.
      if (mounted) setState(() => _online = true);
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!mounted) return;
    if (online != _online) setState(() => _online = online);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _online ? _green : _red;
    final label = _online ? 'Online' : 'Offline';
    return Tooltip(
      message: _online ? 'Connected to the internet' : 'No internet connection',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
