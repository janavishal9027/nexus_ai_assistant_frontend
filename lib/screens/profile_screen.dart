import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../utils/app_feedback.dart';

/// Edit account details — name, email, and password.
///
/// When [onBack] is provided the screen is embedded in the main content area
/// (master-detail): the back button returns to chat via the callback instead of
/// popping a route.
class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ProfileScreen({super.key, this.onBack});

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
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      await context.read<AuthProvider>().updateProfile(name: _nameCtrl.text.trim(), email: email);
      if (mounted) showAppMessage(context, 'Profile updated');
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
    setState(() {
      _savingPassword = true;
      _passwordError = null;
    });
    try {
      await ApiService.changePassword(_currentPwCtrl.text, _newPwCtrl.text);
      _currentPwCtrl.clear();
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
      if (mounted) showAppMessage(context, 'Password updated');
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
    if (widget.onBack == null) navigator.pop();
    chat.reset();
    auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    final acct = context.watch<AuthProvider>().account;
    final initial = (acct != null && acct.displayName.isNotEmpty)
        ? acct.displayName[0].toUpperCase()
        : '?';

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Profile'),
        prefixes: [
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: widget.onBack ?? () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Avatar header
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(initial,
                          style: typography.display.lg.copyWith(
                              color: colors.primary, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(acct?.displayName ?? 'Account',
                              style: typography.body.lg.copyWith(fontWeight: FontWeight.w600)),
                          Text(acct?.email ?? '',
                              style: typography.body.sm
                                  .copyWith(color: colors.mutedForeground)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Profile details
                FCard(
                  title: const Text('Profile details'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      FTextField(
                        control: FTextFieldControl.managed(controller: _nameCtrl),
                        label: const Text('Name'),
                        hint: 'Your name',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      FTextField.email(
                        control: FTextFieldControl.managed(controller: _emailCtrl),
                        label: const Text('Email'),
                        hint: 'you@example.com',
                      ),
                      if (_profileError != null) _errorText(colors, typography, _profileError!),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FButton(
                          onPress: _savingProfile ? null : _saveProfile,
                          prefix: _savingProfile
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: colors.primaryForeground))
                              : const Icon(Icons.save_outlined, size: 18),
                          child: const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Password
                FCard(
                  title: const Text('Password'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      FTextField.password(
                        control: FTextFieldControl.managed(controller: _currentPwCtrl),
                        label: const Text('Current password'),
                      ),
                      const SizedBox(height: 12),
                      FTextField.password(
                        control: FTextFieldControl.managed(controller: _newPwCtrl),
                        label: const Text('New password (min 6)'),
                      ),
                      const SizedBox(height: 12),
                      FTextField.password(
                        control: FTextFieldControl.managed(controller: _confirmPwCtrl),
                        label: const Text('Confirm new password'),
                      ),
                      if (_passwordError != null) _errorText(colors, typography, _passwordError!),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FButton(
                          onPress: _savingPassword ? null : _savePassword,
                          prefix: _savingPassword
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: colors.primaryForeground))
                              : const Icon(Icons.check, size: 18),
                          child: const Text('Update password'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Log out — bottom-right, subtle destructive.
                Align(
                  alignment: Alignment.centerRight,
                  child: FButton(
                    variant: FButtonVariant.ghost,
                    onPress: _logout,
                    prefix: Icon(Icons.logout, size: 16, color: colors.destructive),
                    child: Text('Log out', style: TextStyle(color: colors.destructive)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorText(FColors colors, FTypography typography, String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colors.destructive),
          const SizedBox(width: 6),
          Expanded(
            child: Text(msg,
                style: typography.body.sm.copyWith(color: colors.destructive)),
          ),
        ],
      ),
    );
  }
}
