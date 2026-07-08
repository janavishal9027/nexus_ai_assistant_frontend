import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/api_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  Account? _account;
  String? _error;
  bool _busy = false;

  AuthStatus get status => _status;
  Account? get account => _account;
  String? get error => _error;
  bool get busy => _busy;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// Called once at startup: if a stored token validates, go straight to chat.
  Future<void> tryAutoLogin() async {
    await ApiService.loadTokenFromPrefs();
    if (!ApiService.isAuthenticated) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    final me = await ApiService.getMe();
    if (me != null) {
      _account = Account.fromJson(me);
      _status = AuthStatus.authenticated;
    } else {
      await ApiService.clearAuthToken(); // expired/invalid
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) =>
      _run(() => ApiService.login(email.trim(), password));

  Future<bool> signup(String email, String password, {String? name}) =>
      _run(() => ApiService.signup(email.trim(), password, name: name));

  Future<bool> _run(Future<Map<String, dynamic>> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final res = await action();
      _account = Account.fromJson(res['account'] as Map<String, dynamic>);
      _status = AuthStatus.authenticated;
      _busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Persist name/email changes and refresh the cached account. Throws on error
  /// so the caller can show an inline message.
  Future<void> updateProfile({String? name, String? email}) async {
    final res = await ApiService.updateProfile(name: name, email: email);
    _account = Account.fromJson(res);
    notifyListeners();
  }

  Future<void> logout() async {
    await ApiService.logout();
    _account = null;
    _error = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }
}
