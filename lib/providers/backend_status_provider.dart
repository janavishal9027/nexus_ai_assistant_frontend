import 'dart:async';
import 'package:flutter/widgets.dart';

import '../models/backend_status.dart';
import '../services/api_service.dart';

/// Live backend-status probe (chat-module A.6). Polls `/api/health` on a cadence
/// that backs off while there's a problem, and — on returning to the foreground
/// (idle → in-use) — resets the backoff and re-checks immediately so it never
/// shows a stale "offline".
class BackendStatusProvider extends ChangeNotifier with WidgetsBindingObserver {
  BackendStatus _status = BackendStatus.unknown;
  String? _detail;
  Timer? _timer;
  int _failStreak = 0;
  bool _started = false;

  BackendStatus get status => _status;
  String? get detail => _detail;

  // Online: relaxed cadence. Problem: escalating backoff.
  static const _onlineInterval = Duration(seconds: 20);
  static const _backoff = [5, 10, 20, 30]; // seconds

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _probe();
  }

  /// Force an immediate re-check (e.g. user tapped the indicator, or changed the
  /// server URL).
  Future<void> recheck() async {
    _failStreak = 0;
    await _probe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _failStreak = 0;
      _probe();
    }
  }

  Future<void> _probe() async {
    _timer?.cancel();
    final res = await ApiService.probeHealth();
    if (_status != res.status || _detail != res.detail) {
      _status = res.status;
      _detail = res.detail;
      notifyListeners();
    }
    _failStreak = res.status == BackendStatus.online ? 0 : _failStreak + 1;
    _schedule();
  }

  void _schedule() {
    final Duration next;
    if (_status == BackendStatus.online) {
      next = _onlineInterval;
    } else {
      final i = (_failStreak - 1).clamp(0, _backoff.length - 1);
      next = Duration(seconds: _backoff[i]);
    }
    _timer = Timer(next, _probe);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
