import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';

/// Edit account details — name, email, and password.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  bool _savingProfile = false;
  String? _profileError;
  bool _savingPassword = false;
  String? _passwordError;
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    final acct = context.read<AuthProvider>().account;
    _nameCtrl.text = acct?.name ?? '';
    _emailCtrl.text = acct?.email ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _profileError = 'Email is required');
      return;
    }
    if (!_emailRe.hasMatch(email)) {
      setState(() => _profileError = 'Enter a valid email address');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      await context.read<AuthProvider>().updateProfile(name: _nameCtrl.text.trim(), email: email);
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
    } catch (e) {
      setState(() => _profileError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePassword() async {
    if (_newPwCtrl.text.length < 6) {
      setState(() => _passwordError = 'New password must be at least 6 characters');
      return;
    }
    if (_newPwCtrl.text != _confirmPwCtrl.text) {
      setState(() => _passwordError = 'Passwords do not match');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _savingPassword = true;
      _passwordError = null;
    });
    try {
      await ApiService.changePassword(_currentPwCtrl.text, _newPwCtrl.text);
      _currentPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Password updated')));
    } catch (e) {
      setState(() => _passwordError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  void _logout() {
    final navigator = Navigator.of(context);
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();
    navigator.pop(); // close Profile → back to chat (home)
    chat.reset();
    auth.logout(); // AuthGate swaps the home route to the auth screen
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acct = context.watch<AuthProvider>().account;
    final initial = (acct != null && acct.displayName.isNotEmpty)
        ? acct.displayName[0].toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Avatar header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                      child: Text(initial,
                          style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(acct?.displayName ?? 'Account',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text(acct?.email ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Profile details
                _card(theme, 'Profile details', [
                  TextField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: _dec('Name', Icons.person_outline),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _dec('Email', Icons.email_outlined),
                  ),
                  if (_profileError != null) _errorText(theme, _profileError!),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _savingProfile ? null : _saveProfile,
                      icon: _savingProfile
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save changes'),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // Password
                _card(theme, 'Password', [
                  TextField(
                    controller: _currentPwCtrl,
                    obscureText: _obscureCurrent,
                    decoration: _dec('Current password', Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility,
                              size: 18),
                          onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                        )),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _newPwCtrl,
                    obscureText: _obscureNew,
                    decoration: _dec('New password (min 6)', Icons.lock_reset,
                        suffix: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        )),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmPwCtrl,
                    obscureText: _obscureNew,
                    decoration: _dec('Confirm new password', Icons.lock_reset),
                  ),
                  if (_passwordError != null) _errorText(theme, _passwordError!),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _savingPassword ? null : _savePassword,
                      icon: _savingPassword
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check, size: 18),
                      label: const Text('Update password'),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                // Log out — sits directly under the Password card, bottom-right.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: _logout,
                      icon: Icon(Icons.logout, size: 16, color: theme.colorScheme.error),
                      label: Text('Log out', style: TextStyle(color: theme.colorScheme.error)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(ThemeData theme, String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  /// Soft, filled field styling (no harsh outlined box) with a gentle focus ring.
  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) {
    final theme = Theme.of(context);
    final fill = theme.brightness == Brightness.dark
        ? const Color(0xFF212121)
        : const Color(0xFFF0F0F1);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
      suffixIcon: suffix,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.85), width: 1.4),
      ),
    );
  }

  Widget _errorText(ThemeData theme, String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(msg, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
